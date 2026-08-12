import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

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
      case 429:
        return StateError('Relay saturado ($op): reintentá en un momento');
      case 507:
        return StateError(
          'Buzón del destinatario lleno en el relay: esperá a que lo vacíe o conectá P2P',
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

  Future<({Uint8List nonce, Uint8List ephPubkey})> challenge({
    required String destToken,
  }) async {
    final res = await _http
        .post(
          _uri('/v1/challenge'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'dest_token': destToken}),
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw _httpError('challenge', res.statusCode);
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    return (
      nonce: base64Decode(map['nonce_b64'] as String),
      ephPubkey: base64Decode(map['eph_pubkey_b64'] as String),
    );
  }

  Future<List<Uint8List>> pull({
    required String destToken,
    required Uint8List publicKey,
    required Uint8List proof,
  }) async {
    final res = await _http
        .post(
          _uri('/v1/pull'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'dest_token': destToken,
            'pubkey_b64': base64Encode(publicKey),
            'proof_b64': base64Encode(proof),
          }),
        )
        .timeout(const Duration(seconds: 20));
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
