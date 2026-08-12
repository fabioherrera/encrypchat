import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/encrypchat_core.dart';

/// Persists the 32-byte identity secret in OS secure storage.
///
/// Never logs secret bytes. [toString] only exposes the token.
class IdentityService {
  IdentityService({
    required EncrypchatCore core,
    FlutterSecureStorage? storage,
  })  : _core = core,
        _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _secretKey = 'identity_secret_v1';
  static const _tokenKey = 'identity_token_v1';

  final EncrypchatCore _core;
  final FlutterSecureStorage _storage;

  Uint8List? _secret;
  String? _token;
  Uint8List? _publicKey;

  bool get hasIdentity => _secret != null;
  String? get token => _token;
  Uint8List? get publicKey => _publicKey;

  /// Load identity from secure storage if present.
  Future<bool> load() async {
    final b64 = await _storage.read(key: _secretKey);
    if (b64 == null || b64.isEmpty) {
      _clearMemory();
      return false;
    }
    final secret = base64Decode(b64);
    if (secret.length != 32) {
      await wipe();
      return false;
    }
    _secret = Uint8List.fromList(secret);
    _token = _core.identityToken(_secret!);
    _publicKey = _core.identityPublicKey(_secret!);
    await _storage.write(key: _tokenKey, value: _token);
    return true;
  }

  /// Create a new identity and persist it.
  Future<String> create() async {
    final generated = _core.identityGenerate();
    _secret = generated.secret;
    _token = generated.token;
    _publicKey = _core.identityPublicKey(_secret!);
    await _storage.write(
      key: _secretKey,
      value: base64Encode(_secret!),
    );
    await _storage.write(key: _tokenKey, value: _token);
    return _token!;
  }

  Uint8List requireSecret() {
    final s = _secret;
    if (s == null) {
      throw StateError('No identity loaded');
    }
    return s;
  }

  Future<void> wipe() async {
    await _storage.delete(key: _secretKey);
    await _storage.delete(key: _tokenKey);
    _clearMemory();
  }

  void _clearMemory() {
    _secret?.fillRange(0, _secret!.length, 0);
    _secret = null;
    _token = null;
    _publicKey = null;
  }

  @override
  String toString() => 'IdentityService(token: $_token, secret: <redacted>)';
}
