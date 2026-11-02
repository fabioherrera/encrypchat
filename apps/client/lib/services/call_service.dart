import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/call_signal.dart';
import '../models/contact.dart';
import 'local_database.dart';
import 'messaging_service.dart';

enum CallPhase { idle, outgoing, incoming, connecting, active, ended }

/// 1:1 WebRTC over Encrypchat E2EE signaling.
///
/// Media tries a direct path first. When both networks refuse one it goes through
/// Cloudflare TURN, still under WebRTC's own encryption; TURN sees addresses and
/// traffic volume, not the audio or video.
class CallService extends ChangeNotifier {
  CallService({required MessagingService messaging}) : _messaging = messaging {
    _messaging.onCallSignal = _onInboundSignal;
    _messaging.onBlockPeer = hangupIfPeer;
  }

  static const stunServers = <Map<String, dynamic>>[
    {'urls': 'stun:stun.cloudflare.com:3478'},
  ];

  /// How long a dropped path may stay quiet before an ICE restart. Most
  /// interruptions, like walking between access points, recover on their own.
  static const iceGrace = Duration(seconds: 4);

  /// Total time to recover a lost path before giving up on the call.
  @visibleForTesting
  Duration iceRecoveryLimit = const Duration(seconds: 25);

  /// How late a stamped `invite` may be and still ring, and how far ahead the
  /// caller's clock may run.
  ///
  /// Defence in depth: with EH02 encrypting the transport under a counter nonce,
  /// a third party can no longer drop an old signal into a live session, so what
  /// is left is an `invite` that reaches the callee long after the caller gave up
  /// — a phone ringing for a call nobody is on. The forward tolerance matches the
  /// core's sealed-blob skew, so two devices whose clocks are close enough to
  /// exchange messages are close enough to ring each other.
  static const inviteMaxAge = Duration(seconds: 90);
  static const inviteMaxSkewAhead = Duration(seconds: 300);

  final MessagingService _messaging;

  CallPhase phase = CallPhase.idle;
  CallMediaMode media = CallMediaMode.audio;
  String? callId;
  Contact? peer;
  bool muted = false;
  bool cameraOff = false;
  String? lastError;
  bool isCaller = false;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _pc;
  MediaStream? _local;
  bool _renderersReady = false;
  final List<RTCIceCandidate> _pendingRemoteIce = [];
  String? _pendingOfferSdp;
  Timer? _idleTimer;
  Timer? _ringTimer;
  bool _resetting = false;
  bool _disposed = false;

  /// True from the first tap until the call owns the state, which covers the
  /// permission prompt: a second tap or an incoming ring must not race it.
  bool _starting = false;
  Timer? _iceGraceTimer;
  Timer? _iceRecoveryTimer;

  /// Bumped on every teardown so an in-flight `startCall` / `acceptIncoming`
  /// stops touching WebRTC after Colgar already dismissed the overlay.
  int _epoch = 0;

  /// How long "Llamando…" / "Conectando…" may last before we hang up for the
  /// user. Without this, a call that never gets an answer keeps the screen.
  @visibleForTesting
  Duration ringTimeout = const Duration(seconds: 45);

  /// Shown when neither a live session nor the relay can carry the signaling.
  static const noRouteMessage =
      'Sin conexión para llamar. Revisa internet o enciende el relay.';

  Future<void> ensureRenderers() async {
    if (_renderersReady) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;
  }

  Future<void> startCall({
    required Contact peer,
    required CallMediaMode media,
  }) async {
    if (_starting || (phase != CallPhase.idle && phase != CallPhase.ended)) {
      throw StateError('Ya hay una llamada en curso');
    }
    if (_messaging.isBlocked(peer.token)) {
      throw StateError('Contacto bloqueado: desbloquéalo para llamarlo.');
    }
    if (!_messaging.canSignalCall(peer.token)) {
      throw StateError(noRouteMessage);
    }
    _starting = true;
    try {
      await ensureRenderers();
      // Mic/camera prompts must happen *before* CallPage covers the screen:
      // on Linux the portal dialog sits behind the fullscreen route and the
      // user can neither grant permission nor reach Colgar.
      await _openLocalMedia(media);
    } finally {
      _starting = false;
    }
    // A call may have rung during the prompt. It is already on screen, so it
    // wins, and the stream just opened must not stay on.
    if (phase != CallPhase.idle && phase != CallPhase.ended) {
      await _releaseLocal();
      throw StateError('Ya hay una llamada en curso');
    }

    final epoch = ++_epoch;
    this.peer = peer;
    this.media = media;
    isCaller = true;
    callId = _newCallId();
    phase = CallPhase.outgoing;
    lastError = null;
    notifyListeners();
    _armRingTimeout();

    try {
      await _setupPeerConnection();
      if (!_sameEpoch(epoch)) return;
      await _messaging.sendCallSignal(
        peer: peer,
        signal: CallSignal(
          type: CallSignalType.invite,
          callId: callId!,
          media: media,
        ),
      );
      if (!_sameEpoch(epoch)) return;
      final offer = await _pc!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': media == CallMediaMode.av,
      });
      if (!_sameEpoch(epoch)) return;
      await _pc!.setLocalDescription(offer);
      if (!_sameEpoch(epoch)) return;
      await _messaging.sendCallSignal(
        peer: peer,
        signal: CallSignal(
          type: CallSignalType.sdpOffer,
          callId: callId!,
          media: media,
          sdp: offer.sdp,
        ),
      );
      if (!_sameEpoch(epoch)) return;
      phase = CallPhase.connecting;
      notifyListeners();
    } catch (e) {
      if (!_sameEpoch(epoch)) return;
      lastError = e.toString();
      await hangup(sendSignal: true, keepError: true);
      rethrow;
    }
  }

  Future<void> acceptIncoming() async {
    if (phase != CallPhase.incoming || peer == null || callId == null) return;
    if (!_messaging.canSignalCall(peer!.token)) {
      lastError = noRouteMessage;
      await hangup(sendSignal: true, keepError: true);
      throw StateError(noRouteMessage);
    }
    final epoch = _epoch;
    await ensureRenderers();
    if (!_sameEpoch(epoch) || phase != CallPhase.incoming) return;
    try {
      await _openLocalMedia(media);
    } on StateError catch (e) {
      // Without this the caller keeps ringing until its own timeout, and this
      // screen stays on a call that can no longer be answered.
      lastError = e.message;
      if (_sameEpoch(epoch)) await rejectIncoming();
      rethrow;
    }
    if (!_sameEpoch(epoch) || phase != CallPhase.incoming) {
      await _releaseLocal();
      return;
    }
    isCaller = false;
    phase = CallPhase.connecting;
    notifyListeners();
    _armRingTimeout();
    try {
      await _setupPeerConnection();
      if (!_sameEpoch(epoch)) return;
      await _messaging.sendCallSignal(
        peer: peer!,
        signal: CallSignal(
          type: CallSignalType.accept,
          callId: callId!,
          media: media,
        ),
      );
    } catch (e) {
      if (!_sameEpoch(epoch)) return;
      lastError = e.toString();
      await hangup(sendSignal: true, keepError: true);
      rethrow;
    }
  }

  Future<void> rejectIncoming() async {
    if (phase != CallPhase.incoming || peer == null || callId == null) return;
    final p = peer!;
    final id = callId!;
    final m = media;
    // Tear down first: Rechazar used to wait for a P2P send, so a dead
    // session left the banner up and the phone still ringing.
    final signal = _sendControlBestEffort(
      peer: p,
      signal: CallSignal(type: CallSignalType.reject, callId: id, media: m),
    );
    await _reset();
    unawaited(signal);
  }

  Future<void> hangup({bool sendSignal = true, bool keepError = false}) async {
    final p = peer;
    final id = callId;
    final m = media;
    final shouldSignal = sendSignal && p != null && id != null;
    // Start the hangup frame *now* (encrypt + queue) so a mid-call block
    // still has a chance to tell the peer, then drop the overlay without
    // waiting for the ACK. Waiting was what froze Colgar: the worker is
    // single-file and may already be inside a 15 s `node_send`.
    final Future<void>? signal = shouldSignal
        ? _sendControlBestEffort(
            peer: p,
            signal: CallSignal(
              type: CallSignalType.hangup,
              callId: id,
              media: m,
            ),
          )
        : null;
    await _reset(keepError: keepError);
    if (signal != null) unawaited(signal);
  }

  /// Ends the call if [token] is the identity on the other side.
  ///
  /// Wired into [MessagingService.block], which calls it *before* the block
  /// lands: WebRTC media is direct UDP and does not pass through the node, so
  /// nothing else would stop mic and camera — and after the block even the
  /// peer's `hangup` is discarded, so the call would hang until the user hung up
  /// by hand. Someone blocking a harasser mid-call expects the call to end.
  Future<void> hangupIfPeer(String token) async {
    final active = peer?.token;
    if (active == null) return;
    if (LocalDatabase.normalizeToken(active) !=
        LocalDatabase.normalizeToken(token)) {
      return;
    }
    await hangup();
  }

  Future<void> toggleMute() async {
    muted = !muted;
    _local?.getAudioTracks().forEach((t) => t.enabled = !muted);
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    if (media != CallMediaMode.av) return;
    cameraOff = !cameraOff;
    _local?.getVideoTracks().forEach((t) => t.enabled = !cameraOff);
    notifyListeners();
  }

  Future<void> _onInboundSignal(
    String fromToken,
    CallSignal signal, {
    required bool viaRelay,
  }) async {
    // MessagingService already drops frames from blocked peers before
    // decrypting; this second check keeps the mic/camera path safe if a future
    // transport ever dispatches signaling from somewhere else.
    if (_messaging.isBlocked(fromToken)) return;
    try {
      await _handleInboundSignal(fromToken, signal, viaRelay: viaRelay);
    } catch (e) {
      // SDP/candidates are call content: log the type only, never the exception.
      debugPrint('call signal failed: ${e.runtimeType}');
      lastError = e.toString();
      await hangup(sendSignal: true, keepError: true);
    }
  }

  Future<void> _handleInboundSignal(
    String fromToken,
    CallSignal signal, {
    required bool viaRelay,
  }) async {
    switch (signal.type) {
      case CallSignalType.invite:
        if (!_ringworthy(signal, viaRelay: viaRelay)) return;
        if (_starting ||
            (phase != CallPhase.idle && phase != CallPhase.ended)) {
          final contact = _messaging.contactForToken(fromToken);
          if (contact != null) {
            unawaited(
              _sendControlBestEffort(
                peer: contact,
                signal: CallSignal(
                  type: CallSignalType.reject,
                  callId: signal.callId,
                  media: signal.media,
                ),
              ),
            );
          }
          return;
        }
        final contact = _messaging.contactForToken(fromToken);
        if (contact == null) {
          debugPrint('call invite from unknown contact');
          return;
        }
        peer = contact;
        callId = signal.callId;
        media = signal.media;
        isCaller = false;
        phase = CallPhase.incoming;
        notifyListeners();
        _armIncomingTimeout();
        break;

      case CallSignalType.accept:
        if (!_fromActivePeer(fromToken) || callId != signal.callId) return;
        phase = CallPhase.connecting;
        notifyListeners();
        break;

      case CallSignalType.reject:
      case CallSignalType.hangup:
        if (!_fromActivePeer(fromToken)) return;
        if (callId != null && callId != signal.callId) return;
        lastError = signal.type == CallSignalType.reject
            ? 'Llamada rechazada'
            : 'Llamada finalizada';
        await _reset(keepError: true);
        break;

      case CallSignalType.sdpOffer:
        if (!_fromActivePeer(fromToken) ||
            callId != signal.callId ||
            signal.sdp == null) {
          return;
        }
        if (_pc == null) {
          _pendingOfferSdp = signal.sdp;
          return;
        }
        await _applyRemoteOffer(signal.sdp!);
        break;

      case CallSignalType.sdpAnswer:
        if (!_fromActivePeer(fromToken) ||
            callId != signal.callId ||
            signal.sdp == null ||
            _pc == null) {
          return;
        }
        await _pc!.setRemoteDescription(
          RTCSessionDescription(signal.sdp, 'answer'),
        );
        await _flushPendingIce();
        // Active waits for the connection state: an answer only means the other
        // side picked up, and audio may still never find a path.
        break;

      case CallSignalType.ice:
        if (!_fromActivePeer(fromToken) ||
            callId != signal.callId ||
            signal.candidate == null) {
          return;
        }
        final c = signal.candidate!;
        final ice = RTCIceCandidate(
          c['candidate'] as String?,
          c['sdpMid'] as String?,
          c['sdpMLineIndex'] as int?,
        );
        if (_pc == null) {
          _pendingRemoteIce.add(ice);
        } else {
          final remote = await _pc!.getRemoteDescription();
          if (remote == null) {
            _pendingRemoteIce.add(ice);
          } else {
            await _pc!.addCandidate(ice);
          }
        }
        break;
    }
  }

  bool _fromActivePeer(String fromToken) =>
      peer != null && peer!.token == fromToken;

  /// Whether an `invite` is recent enough to ring the phone.
  ///
  /// Only `invite` is gated: it is the one signal that makes noise on its own,
  /// and the rest are already tied to a live call by `callId` and phase.
  ///
  /// Over a live session an **unstamped** invite still rings: refusing one would
  /// mean a peer on an older build silently cannot reach the user, and the
  /// transport itself (EH02) stops a third party from injecting one. Over the
  /// relay it is refused, because there a blob can genuinely arrive late.
  bool _ringworthy(CallSignal signal, {required bool viaRelay}) {
    final ts = signal.sentAtUnix;
    if (ts == null) {
      debugPrint('call invite without timestamp (peer on an older build)');
      return !viaRelay;
    }
    final now = clock().toUtc().millisecondsSinceEpoch ~/ 1000;
    final age = now - ts;
    if (age > inviteMaxAge.inSeconds || -age > inviteMaxSkewAhead.inSeconds) {
      // No `lastError` and no ring: nothing on this device was waiting for it.
      debugPrint('call invite ignored: ${age}s off this clock');
      return false;
    }
    return true;
  }

  /// Wall clock for the invite window. Injectable because the stamp travels
  /// inside the ciphertext and cannot be backdated from the outside.
  @visibleForTesting
  DateTime Function() clock = () => DateTime.now().toUtc();

  Future<void> _applyRemoteOffer(String sdp) async {
    if (_pc == null) {
      _pendingOfferSdp = sdp;
      return;
    }
    final epoch = _epoch;
    await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    if (!_sameEpoch(epoch)) return;
    await _flushPendingIce();
    if (!_sameEpoch(epoch)) return;
    final answer = await _pc!.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': media == CallMediaMode.av,
    });
    if (!_sameEpoch(epoch)) return;
    await _pc!.setLocalDescription(answer);
    if (!_sameEpoch(epoch)) return;
    await _messaging.sendCallSignal(
      peer: peer!,
      signal: CallSignal(
        type: CallSignalType.sdpAnswer,
        callId: callId!,
        media: media,
        sdp: answer.sdp,
      ),
    );
  }

  Future<void> _flushPendingIce() async {
    if (_pc == null) return;
    for (final ice in _pendingRemoteIce) {
      await _pc!.addCandidate(ice);
    }
    _pendingRemoteIce.clear();
  }

  /// STUN alone when the relay cannot issue TURN. Those calls can still connect,
  /// just not across the strictest networks.
  Future<List<Map<String, dynamic>>> _iceServers() async {
    try {
      return await _messaging.requestIceServers() ?? stunServers;
    } catch (e) {
      debugPrint('turn credentials failed: ${e.runtimeType}');
      return stunServers;
    }
  }

  Future<void> _setupPeerConnection() async {
    final iceServers = await _iceServers();
    _pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });

    _pc!.onIceCandidate = (RTCIceCandidate? c) {
      if (c == null || peer == null || callId == null) return;
      unawaited(
        _messaging
            .sendCallSignal(
              peer: peer!,
              signal: CallSignal(
                type: CallSignalType.ice,
                callId: callId!,
                media: media,
                candidate: {
                  'candidate': c.candidate,
                  'sdpMid': c.sdpMid,
                  'sdpMLineIndex': c.sdpMLineIndex,
                },
              ),
            )
            .catchError((_) {}),
      );
    };

    _pc!.onConnectionState = (RTCPeerConnectionState state) {
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _clearIceRecovery();
          _becomeActive();
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          onPathLost();
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          onPathLost(failed: true);
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          if (phase == CallPhase.active || phase == CallPhase.connecting) {
            _loseCall();
          }
        default:
          break;
      }
    };

    _pc!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams[0];
        notifyListeners();
      }
    };

    if (_local != null) {
      for (final track in _local!.getTracks()) {
        await _pc!.addTrack(track, _local!);
      }
    }

    if (_pendingOfferSdp != null) {
      final sdp = _pendingOfferSdp!;
      _pendingOfferSdp = null;
      await _applyRemoteOffer(sdp);
    }
    notifyListeners();
  }

  Future<void> _openLocalMedia(CallMediaMode mode) async {
    final constraints = <String, dynamic>{
      'audio': true,
      'video': mode == CallMediaMode.av
          ? {'facingMode': 'user', 'width': 640, 'height': 480}
          : false,
    };
    try {
      _local = await navigator.mediaDevices.getUserMedia(constraints);
    } catch (e) {
      throw StateError(
        'No se pudo acceder a micrófono/cámara (¿permisos denegados?): $e',
      );
    }
    localRenderer.srcObject = _local;
  }

  Future<void> _releaseLocal() async {
    try {
      await _local?.dispose();
    } catch (_) {}
    _local = null;
    if (_renderersReady) {
      localRenderer.srcObject = null;
    }
  }

  bool _sameEpoch(int epoch) => !_disposed && _epoch == epoch;

  void _armRingTimeout() {
    _ringTimer?.cancel();
    _ringTimer = Timer(ringTimeout, () {
      if (phase == CallPhase.outgoing || phase == CallPhase.connecting) {
        lastError = 'Nadie contestó';
        unawaited(hangup(sendSignal: true, keepError: true));
      }
    });
  }

  /// Keeps a call alive through a dropped path. Changing from Wi‑Fi to mobile
  /// data lands here, so ending the call on the first `disconnected` was hanging
  /// up on anyone who left the house.
  ///
  /// Only the caller restarts ICE, so the two sides cannot send crossing offers.
  /// The callee just waits for that offer under the same limit.
  @visibleForTesting
  void onPathLost({bool failed = false}) {
    if (phase != CallPhase.active && phase != CallPhase.connecting) return;
    _iceRecoveryTimer ??= Timer(iceRecoveryLimit, () {
      _iceRecoveryTimer = null;
      if (phase == CallPhase.active || phase == CallPhase.connecting) {
        _loseCall();
      }
    });
    _iceGraceTimer?.cancel();
    _iceGraceTimer = Timer(failed ? Duration.zero : iceGrace, () {
      _iceGraceTimer = null;
      if (isCaller) unawaited(_restartIce());
    });
  }

  void _clearIceRecovery() {
    _iceGraceTimer?.cancel();
    _iceGraceTimer = null;
    _iceRecoveryTimer?.cancel();
    _iceRecoveryTimer = null;
  }

  void _loseCall() {
    lastError = 'Conexión perdida';
    unawaited(hangup(sendSignal: true, keepError: true));
  }

  Future<void> _restartIce() async {
    final pc = _pc;
    final p = peer;
    final id = callId;
    if (pc == null || p == null || id == null) return;
    final epoch = _epoch;
    try {
      final offer = await pc.createOffer({'iceRestart': true});
      if (!_sameEpoch(epoch)) return;
      await pc.setLocalDescription(offer);
      if (!_sameEpoch(epoch)) return;
      await _messaging.sendCallSignal(
        peer: p,
        signal: CallSignal(
          type: CallSignalType.sdpOffer,
          callId: id,
          media: media,
          sdp: offer.sdp,
        ),
      );
    } catch (e) {
      // The recovery limit still ends the call if nothing else works.
      debugPrint('ice restart failed: ${e.runtimeType}');
    }
  }

  /// Rings stop on their own if the caller's `hangup` never arrives: that signal
  /// is best effort, and the relay can lose it while the caller is offline.
  void _armIncomingTimeout() {
    _ringTimer?.cancel();
    _ringTimer = Timer(ringTimeout + const Duration(seconds: 15), () {
      if (phase == CallPhase.incoming) {
        lastError = 'Llamada perdida';
        unawaited(_reset(keepError: true));
      }
    });
  }

  void _becomeActive() {
    _ringTimer?.cancel();
    _ringTimer = null;
    phase = CallPhase.active;
    notifyListeners();
  }

  Future<void> _sendControlBestEffort({
    required Contact peer,
    required CallSignal signal,
  }) async {
    try {
      await _messaging
          .sendCallSignal(peer: peer, signal: signal)
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  Future<void> _reset({bool keepError = false}) async {
    // `onConnectionState` fires while closing; without this guard it re-enters.
    if (_resetting) return;
    _resetting = true;
    _epoch++;
    _ringTimer?.cancel();
    _ringTimer = null;
    _clearIceRecovery();
    try {
      final pc = _pc;
      _pc = null;
      if (pc != null) {
        pc.onIceCandidate = null;
        pc.onConnectionState = null;
        pc.onTrack = null;
        try {
          await pc.close();
        } catch (_) {}
      }
      try {
        await _local?.dispose();
      } catch (_) {}
      _local = null;
      // Only touch the renderers if they were initialized: their setter throws
      // without a texture, and a call torn down before it was ever displayed
      // (rejected, or the peer blocked while ringing) never initializes them.
      if (_renderersReady) {
        localRenderer.srcObject = null;
        remoteRenderer.srcObject = null;
      }
      _pendingRemoteIce.clear();
      _pendingOfferSdp = null;
      phase = CallPhase.ended;
      callId = null;
      peer = null;
      muted = false;
      cameraOff = false;
      isCaller = false;
      if (!keepError) lastError = null;
      _notify();
      _idleTimer?.cancel();
      if (_disposed) return;
      _idleTimer = Timer(const Duration(milliseconds: 400), () {
        if (phase != CallPhase.ended) return;
        phase = CallPhase.idle;
        _notify();
      });
    } finally {
      _resetting = false;
    }
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  static String _newCallId() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(12, (_) => rnd.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// Puts the service in the state a connected call leaves behind, minus the
  /// WebRTC objects: `getUserMedia` and `RTCPeerConnection` need the platform
  /// plugin, which `flutter test` does not load. Only the teardown path is
  /// exercised through it.
  @visibleForTesting
  void simulateActiveCall({
    required Contact peer,
    required MediaStream localStream,
    String callId = 'test-call',
  }) {
    this.peer = peer;
    this.callId = callId;
    media = CallMediaMode.av;
    phase = CallPhase.active;
    _local = localStream;
    notifyListeners();
  }

  /// Stages an outgoing ring without WebRTC, so the unanswered-call timer
  /// can be tested on `flutter test`.
  @visibleForTesting
  void simulateOutgoingCall({
    required Contact peer,
    String callId = 'test-call',
  }) {
    this.peer = peer;
    this.callId = callId;
    media = CallMediaMode.audio;
    isCaller = true;
    phase = CallPhase.outgoing;
    notifyListeners();
    _armRingTimeout();
  }

  @override
  void dispose() {
    _disposed = true;
    _messaging.onCallSignal = null;
    _messaging.onBlockPeer = null;
    _idleTimer?.cancel();
    _idleTimer = null;
    _ringTimer?.cancel();
    _ringTimer = null;
    _clearIceRecovery();
    unawaited(localRenderer.dispose());
    unawaited(remoteRenderer.dispose());
    unawaited(_reset());
    super.dispose();
  }
}
