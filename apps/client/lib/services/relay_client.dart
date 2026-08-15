import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// A PoP challenge in flight.
///
/// [id] is the whole reason this type exists: since F-8 the challenge is not
/// issued *for* a destination, so the relay has nothing to look it up by except
/// the id it handed out. Losing it between the two calls is what made every pull
/// fail with `422`.
typedef RelayChallenge = ({String id, Uint8List nonce, Uint8List ephPubkey});

/// The relay refused the proof (HTTP 401).
///
/// One code covers three cases on purpose — unknown id, expired id, proof that
/// does not verify — and none of them is retryable with the same challenge: the
/// relay consumes a challenge only when the proof verifies, so an id that failed
/// once will keep failing. The caller must ask for a new one.
class RelayAuthException implements Exception {
  const RelayAuthException();

  String get message =>
      'El relay rechazó la prueba de posesión: el desafío caducó o la clave no '
      'corresponde al token. Se pedirá uno nuevo.';

  @override
  String toString() => 'RelayAuthException: $message';
}

/// The relay is rate-limiting this address (HTTP 429).
///
/// Kept apart from the other refusals because it is the one that passes on its
/// own: the budget is per client IP and shared by every device behind the same
/// NAT, so a household polling one relay reaches it without anybody misbehaving.
/// The answer is to poll less for a while, not to tell the user the relay is
/// broken.
class RelayBusyException implements Exception {
  const RelayBusyException();

  @override
  String toString() => 'RelayBusyException';
}

/// Blind relay HTTP client (Phase 5). Never sends plaintext.
class RelayClient {
  RelayClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;
  String? baseUrl;

  bool get isConfigured => baseUrl != null && baseUrl!.trim().isNotEmpty;

  /// Configured without TLS: blobs stay E2EE, but `dest_token`, pubkey and the
  /// PoP proof are readable by anyone on the path. Allowed for LAN demos.
  bool get isInsecure => isConfigured && !isSecureUrl(baseUrl!);

  static bool isSecureUrl(String url) =>
      url.trim().toLowerCase().startsWith('https://');

  Uri _uri(String path) {
    final base = baseUrl!.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }

  /// Server text is not echoed: known codes get an actionable message instead.
  StateError _httpError(String op, int status) {
    switch (status) {
      case 422:
        // The relay parsed the JSON and rejected its *shape*: this client and
        // that relay do not agree on the contract. Said out loud because the
        // alternative is what F-8 produced — a pull failing every 8 s forever
        // with nothing on screen.
        return StateError(
          'El relay no acepta la forma de esta petición ($op): la app y el '
          'relay hablan versiones distintas del protocolo. Actualiza alguno '
          'de los dos.',
        );
      case 429:
        return StateError('Relay saturado ($op): reintenta en un momento');
      case 507:
        // No longer anything to do with the recipient. A mailbox over quota is
        // answered like an acceptance now — telling those two apart is what let
        // anyone holding a token learn whether that person was online — so what
        // is left here is the relay's own disk, and the answer is a different
        // relay, not waiting for somebody to read their messages.
        return StateError(
          'El relay se quedó sin espacio ($op). No depende del destinatario: '
          'usa otro relay, o espera a que los dos estén en línea para ir por P2P.',
        );
      default:
        return StateError('Relay $op falló (HTTP $status)');
    }
  }

  Future<bool> healthz() async {
    if (!isConfigured) return false;
    final res = await _http
        .get(_uri('/healthz'))
        .timeout(const Duration(seconds: 5));
    return res.statusCode == 200;
  }

  Future<String> enqueue({
    required String destToken,
    required Uint8List blob,
    int ttlSecs = 86400,
  }) async {
    final res = await _http
        .post(
          _uri('/v1/enqueue'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'dest_token': destToken,
            'ttl_secs': ttlSecs,
            'blob_b64': base64Encode(blob),
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw _httpError('enqueue', res.statusCode);
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    return map['id'] as String;
  }

  /// Asks for a challenge. **No destination is sent**: the mailbox to read is
  /// named only in the pull, and the proof binds it inside the transcript
  /// (`pop_verify` hashes the token), so telling the relay here would hand a
  /// blind relay "who is about to read" for nothing — and it is what let a
  /// stranger overwrite somebody else's pending challenge (F-8).
  ///
  /// The body is ignored server-side; `{}` is sent so the request stays a
  /// well-formed JSON POST for proxies that insist on one.
  Future<RelayChallenge> challenge() async {
    final res = await _http
        .post(
          _uri('/v1/challenge'),
          headers: {'content-type': 'application/json'},
          body: '{}',
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 429) throw const RelayBusyException();
    if (res.statusCode != 200) {
      throw _httpError('challenge', res.statusCode);
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final id = map['challenge_id'] as String?;
    if (id == null || id.isEmpty) {
      // A relay that answers 200 without an id is pre-F-8: pulling with an
      // empty id would earn a 401 on every attempt and read as "bad proof".
      throw StateError(
        'El relay respondió un desafío sin challenge_id: es una versión '
        'anterior a F-8 y esta app no puede recoger de ahí.',
      );
    }
    return (
      id: id,
      nonce: base64Decode(map['nonce_b64'] as String),
      ephPubkey: base64Decode(map['eph_pubkey_b64'] as String),
    );
  }

  /// Drains the mailbox with the proof built over [challengeId]'s nonce.
  ///
  /// Throws [RelayAuthException] on 401 — see there for why the same challenge
  /// must not be retried.
  Future<List<Uint8List>> pull({
    required String challengeId,
    required String destToken,
    required Uint8List publicKey,
    required Uint8List proof,
  }) async {
    final res = await _http
        .post(
          _uri('/v1/pull'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'challenge_id': challengeId,
            'dest_token': destToken,
            'pubkey_b64': base64Encode(publicKey),
            'proof_b64': base64Encode(proof),
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 401) {
      throw const RelayAuthException();
    }
    if (res.statusCode == 429) throw const RelayBusyException();
    if (res.statusCode != 200) {
      throw _httpError('pull', res.statusCode);
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final messages = map['messages'] as List<dynamic>? ?? const [];
    return [
      for (final m in messages)
        base64Decode((m as Map<String, dynamic>)['blob_b64'] as String),
    ];
  }

  void close() => _http.close();
}
