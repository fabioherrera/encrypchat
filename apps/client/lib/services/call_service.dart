import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/call_signal.dart';
import '../models/contact.dart';
import 'messaging_service.dart';

enum CallPhase { idle, outgoing, incoming, connecting, active, ended }

/// 1:1 WebRTC over Encrypchat E2EE signaling. Media is P2P (STUN only; no SFU).
class CallService extends ChangeNotifier {
  CallService({required MessagingService messaging}) : _messaging = messaging {
    _messaging.onCallSignal = _onInboundSignal;
  }

  static const stunServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ];

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
  bool _resetting = false;
  bool _disposed = false;

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
    if (phase != CallPhase.idle && phase != CallPhase.ended) {
      throw StateError('Ya hay una llamada en curso');
    }
    if (_messaging.isBlocked(peer.token)) {
      throw StateError('Contacto bloqueado: desbloqueálo para llamarlo.');
    }
    await ensureRenderers();
    // OS prompts via getUserMedia (mic/camera manifests declared).
    this.peer = peer;
    this.media = media;
    isCaller = true;
    callId = _newCallId();
    phase = CallPhase.outgoing;
    lastError = null;
    notifyListeners();

    try {
      await _setupPeerConnection();
      await _messaging.sendCallSignal(
        peer: peer,
        signal: CallSignal(
          type: CallSignalType.invite,
          callId: callId!,
          media: media,
        ),
      );
      final offer = await _pc!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': media == CallMediaMode.av,
      });
      await _pc!.setLocalDescription(offer);
      await _messaging.sendCallSignal(
        peer: peer,
        signal: CallSignal(
          type: CallSignalType.sdpOffer,
          callId: callId!,
          media: media,
          sdp: offer.sdp,
        ),
      );
      phase = CallPhase.connecting;
      notifyListeners();
    } catch (e) {
      lastError = e.toString();
      await hangup(sendSignal: true);
      rethrow;
    }
  }

  Future<void> acceptIncoming() async {
    if (phase != CallPhase.incoming || peer == null || callId == null) return;
    await ensureRenderers();
    isCaller = false;
    phase = CallPhase.connecting;
    notifyListeners();
    try {
      await _setupPeerConnection();
      await _messaging.sendCallSignal(
        peer: peer!,
        signal: CallSignal(
          type: CallSignalType.accept,
          callId: callId!,
          media: media,
        ),
      );
    } catch (e) {
      lastError = e.toString();
      await hangup(sendSignal: true);
      rethrow;
    }
  }

  Future<void> rejectIncoming() async {
    if (phase != CallPhase.incoming || peer == null || callId == null) return;
    final p = peer!;
    final id = callId!;
    final m = media;
    try {
      await _messaging.sendCallSignal(
        peer: p,
        signal: CallSignal(type: CallSignalType.reject, callId: id, media: m),
      );
    } catch (_) {}
    await _reset();
  }

  Future<void> hangup({bool sendSignal = true}) async {
    final p = peer;
    final id = callId;
    final m = media;
    if (sendSignal && p != null && id != null) {
      try {
        await _messaging.sendCallSignal(
          peer: p,
          signal: CallSignal(type: CallSignalType.hangup, callId: id, media: m),
        );
      } catch (_) {}
    }
    await _reset();
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

  Future<void> _onInboundSignal(String fromToken, CallSignal signal) async {
    // MessagingService already drops frames from blocked peers before
    // decrypting; this second check keeps the mic/camera path safe if a future
    // transport ever dispatches signaling from somewhere else.
    if (_messaging.isBlocked(fromToken)) return;
    try {
      await _handleInboundSignal(fromToken, signal);
    } catch (e) {
      // SDP/candidates are call content: log the type only, never the exception.
      debugPrint('call signal failed: ${e.runtimeType}');
      lastError = e.toString();
      await hangup(sendSignal: true);
    }
  }

  Future<void> _handleInboundSignal(String fromToken, CallSignal signal) async {
    switch (signal.type) {
      case CallSignalType.invite:
        if (phase != CallPhase.idle && phase != CallPhase.ended) {
          final contact = _messaging.contactForToken(fromToken);
          if (contact != null) {
            try {
              await _messaging.sendCallSignal(
                peer: contact,
                signal: CallSignal(
                  type: CallSignalType.reject,
                  callId: signal.callId,
                  media: signal.media,
                ),
              );
            } catch (_) {}
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
        phase = CallPhase.active;
        notifyListeners();
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

  Future<void> _applyRemoteOffer(String sdp) async {
    if (_pc == null) {
      _pendingOfferSdp = sdp;
      return;
    }
    await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    await _flushPendingIce();
    final answer = await _pc!.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': media == CallMediaMode.av,
    });
    await _pc!.setLocalDescription(answer);
    await _messaging.sendCallSignal(
      peer: peer!,
      signal: CallSignal(
        type: CallSignalType.sdpAnswer,
        callId: callId!,
        media: media,
        sdp: answer.sdp,
      ),
    );
    phase = CallPhase.active;
    notifyListeners();
  }

  Future<void> _flushPendingIce() async {
    if (_pc == null) return;
    for (final ice in _pendingRemoteIce) {
      await _pc!.addCandidate(ice);
    }
    _pendingRemoteIce.clear();
  }

  Future<void> _setupPeerConnection() async {
    _pc = await createPeerConnection({
      'iceServers': stunServers,
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
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        phase = CallPhase.active;
        notifyListeners();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        if (phase == CallPhase.active || phase == CallPhase.connecting) {
          lastError = 'Conexión WebRTC perdida';
          unawaited(_reset(keepError: true));
        }
      }
    };

    _pc!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams[0];
        notifyListeners();
      }
    };

    final constraints = <String, dynamic>{
      'audio': true,
      'video': media == CallMediaMode.av
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
    for (final track in _local!.getTracks()) {
      await _pc!.addTrack(track, _local!);
    }

    if (_pendingOfferSdp != null) {
      final sdp = _pendingOfferSdp!;
      _pendingOfferSdp = null;
      await _applyRemoteOffer(sdp);
    }
    notifyListeners();
  }

  Future<void> _reset({bool keepError = false}) async {
    // `onConnectionState` fires while closing; without this guard it re-enters.
    if (_resetting) return;
    _resetting = true;
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
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
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

  @override
  void dispose() {
    _disposed = true;
    _messaging.onCallSignal = null;
    _idleTimer?.cancel();
    _idleTimer = null;
    unawaited(localRenderer.dispose());
    unawaited(remoteRenderer.dispose());
    unawaited(_reset());
    super.dispose();
  }
}
