import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Builds the same proof of possession a pull uses, for the socket's challenge.
typedef RelaySocketProof =
    Uint8List Function(Uint8List ephPubkey, Uint8List nonce);

/// Opens the transport. Tests hand in a fake one.
typedef RelaySocketConnector = Future<RelaySocketChannel> Function(Uri uri);

/// The small part of a WebSocket this class uses.
abstract class RelaySocketChannel {
  Stream<dynamic> get stream;
  void add(String text);
  Future<void> close();
}

class _IoChannel implements RelaySocketChannel {
  _IoChannel(this._socket);

  final WebSocket _socket;

  @override
  Stream<dynamic> get stream => _socket;

  @override
  void add(String text) => _socket.add(text);

  @override
  Future<void> close() => _socket.close();
}

Future<RelaySocketChannel> _connectIo(Uri uri) async {
  final socket = await WebSocket.connect(
    uri.toString(),
  ).timeout(const Duration(seconds: 15));
  // Answers the relay's silence too: a phone that changed networks has a socket
  // that looks open until a ping goes unanswered.
  socket.pingInterval = const Duration(seconds: 25);
  return _IoChannel(socket);
}

/// Keeps one authenticated doorbell open to the relay.
///
/// A wake carries nothing: the mail still goes through the normal pull, so this
/// class holds no ciphertext and no contact. A restart on the relay or at
/// Cloudflare drops the socket, so losing it is routine and reconnecting is
/// silent, with growing delays so a relay outage is not hammered by every client.
class RelaySocket {
  RelaySocket({
    required this.baseUrl,
    required this.token,
    required this.publicKey,
    required this.proof,
    required this.onWake,
    required this.onStateChanged,
    RelaySocketConnector? connector,
    Random? random,
  }) : _connector = connector ?? _connectIo,
       _random = random ?? Random();

  final String baseUrl;
  final String token;
  final Uint8List publicKey;
  final RelaySocketProof proof;
  final void Function() onWake;
  final void Function() onStateChanged;
  final RelaySocketConnector _connector;
  final Random _random;

  static const minDelay = Duration(seconds: 1);
  static const maxDelay = Duration(seconds: 60);
  static const turnTimeout = Duration(seconds: 6);

  RelaySocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  bool _closed = false;
  bool _connecting = false;
  int _failures = 0;
  Completer<List<Map<String, dynamic>>?>? _turnWaiter;

  /// Authenticated and listening, which is what "the relay is reachable" means.
  bool get isConnected => _ready;
  bool _ready = false;

  /// The relay said it can issue TURN credentials.
  bool get turnAvailable => _ready && _turnOffered;
  bool _turnOffered = false;

  /// `ws(s)://` for an `http(s)://` relay URL, or null for anything else.
  static Uri? socketUri(String baseUrl) {
    final base = Uri.tryParse(baseUrl.trim().replaceAll(RegExp(r'/+$'), ''));
    if (base == null || !base.hasAuthority) return null;
    final scheme = switch (base.scheme) {
      'https' => 'wss',
      'http' => 'ws',
      _ => null,
    };
    if (scheme == null) return null;
    return base.replace(scheme: scheme, path: '${base.path}/v1/ws');
  }

  /// Delay before retry number [failures], with jitter so that a relay restart
  /// does not bring every client back in the same second.
  @visibleForTesting
  Duration delayFor(int failures) {
    final capped = min(failures, 6);
    final seconds = min(
      minDelay.inSeconds * (1 << capped),
      maxDelay.inSeconds,
    );
    return Duration(milliseconds: seconds * 750 + _random.nextInt(seconds * 500));
  }

  void start() {
    if (_closed) return;
    unawaited(_connect());
  }

  /// Retries now instead of waiting out the delay: the network just came back
  /// or the app just returned to the foreground.
  void nudge() {
    if (_closed || _ready || _connecting) return;
    _retry?.cancel();
    _retry = null;
    _failures = 0;
    unawaited(_connect());
  }

  Future<void> _connect() async {
    if (_closed || _connecting || _ready) return;
    final uri = socketUri(baseUrl);
    if (uri == null) return;
    _connecting = true;
    try {
      final channel = await _connector(uri);
      if (_closed) {
        await channel.close();
        return;
      }
      _channel = channel;
      _sub = channel.stream.listen(
        _onFrame,
        onDone: _onLost,
        onError: (Object _) => _onLost(),
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('relay socket: connect failed (${e.runtimeType})');
      _scheduleRetry();
    } finally {
      _connecting = false;
    }
  }

  void _onFrame(dynamic raw) {
    if (raw is! String) return;
    final Map<String, dynamic> frame;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      frame = decoded;
    } on FormatException {
      return;
    }
    switch (frame['type']) {
      case 'challenge':
        _answerChallenge(frame);
      case 'ready':
        _ready = true;
        _turnOffered = frame['turn'] == true;
        _failures = 0;
        onStateChanged();
        // Whatever landed while the socket was down rang nobody.
        onWake();
      case 'wake':
        onWake();
      case 'turn':
        final servers = frame['ice_servers'];
        _finishTurn(
          servers is List
              ? [
                  for (final s in servers)
                    if (s is Map) Map<String, dynamic>.from(s),
                ]
              : null,
        );
      case 'turn_unavailable':
        _finishTurn(null);
    }
  }

  void _answerChallenge(Map<String, dynamic> frame) {
    try {
      final proofBytes = proof(
        base64Decode(frame['eph_pubkey_b64'] as String),
        base64Decode(frame['nonce_b64'] as String),
      );
      _channel?.add(
        jsonEncode({
          'type': 'auth',
          'challenge_id': frame['challenge_id'],
          'dest_token': token,
          'pubkey_b64': base64Encode(publicKey),
          'proof_b64': base64Encode(proofBytes),
        }),
      );
    } catch (e) {
      debugPrint('relay socket: auth failed (${e.runtimeType})');
      unawaited(_channel?.close());
    }
  }

  /// ICE servers with fresh TURN credentials, or null to call with STUN alone.
  Future<List<Map<String, dynamic>>?> requestTurn() async {
    final channel = _channel;
    if (!turnAvailable || channel == null) return null;
    final existing = _turnWaiter;
    if (existing != null) return existing.future;
    final waiter = Completer<List<Map<String, dynamic>>?>();
    _turnWaiter = waiter;
    try {
      channel.add(jsonEncode({'type': 'turn'}));
    } catch (_) {
      _finishTurn(null);
    }
    return waiter.future.timeout(
      turnTimeout,
      onTimeout: () {
        _finishTurn(null);
        return null;
      },
    );
  }

  void _finishTurn(List<Map<String, dynamic>>? servers) {
    final waiter = _turnWaiter;
    _turnWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete(servers);
  }

  void _onLost() {
    final wasReady = _ready;
    _ready = false;
    _turnOffered = false;
    _channel = null;
    unawaited(_sub?.cancel());
    _sub = null;
    _finishTurn(null);
    if (wasReady) onStateChanged();
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_closed) return;
    _retry?.cancel();
    _retry = Timer(delayFor(_failures), () {
      _retry = null;
      unawaited(_connect());
    });
    _failures++;
  }

  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
    _retry = null;
    _ready = false;
    _finishTurn(null);
    await _sub?.cancel();
    _sub = null;
    final channel = _channel;
    _channel = null;
    await channel?.close();
  }
}
