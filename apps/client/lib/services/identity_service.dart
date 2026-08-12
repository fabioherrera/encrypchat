import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/encrypchat_core.dart';

/// Persists the 32-byte identity secret in OS secure storage.
///
/// Never logs secret bytes. [toString] only exposes the token.
class IdentityService {
  IdentityService({required EncrypchatCore core, FlutterSecureStorage? storage})
    : _core = core,
      _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  /// Where the identity lives in the OS secure store. Public because deleting
  /// the identity has to remove both entries, and the order in which every
  /// stored secret goes is decided in one place — see `IdentityWipe`.
  static const secretStorageKey = 'identity_secret_v1';
  static const tokenStorageKey = 'identity_token_v1';

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
    final b64 = await _storage.read(key: secretStorageKey);
    if (b64 == null || b64.isEmpty) {
      _clearMemory();
      return false;
    }
    final secret = base64Decode(b64);
    if (secret.length != 32) {
      secret.fillRange(0, secret.length, 0);
      await wipe();
      return false;
    }
    _secret = Uint8List.fromList(secret);
    // The intermediate copy is reachable garbage otherwise. What cannot be
    // cleared is `b64` itself: a Dart `String` is immutable and GC-managed, so
    // the base64 of the secret stays in the heap until it is collected. That
    // residue belongs to the storage API's shape, not to this class.
    secret.fillRange(0, secret.length, 0);
    _token = _core.identityToken(_secret!);
    _publicKey = _core.identityPublicKey(_secret!);
    await _storage.write(key: tokenStorageKey, value: _token);
    return true;
  }

  /// Create a new identity and persist it.
  Future<String> create() async {
    final generated = _core.identityGenerate();
    _secret = generated.secret;
    _token = generated.token;
    _publicKey = _core.identityPublicKey(_secret!);
    await _storage.write(key: secretStorageKey, value: base64Encode(_secret!));
    await _storage.write(key: tokenStorageKey, value: _token);
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
    await _storage.delete(key: secretStorageKey);
    await _storage.delete(key: tokenStorageKey);
    _clearMemory();
  }

  /// Zeroes the copy of the secret this object is holding, without touching the
  /// secure store. Deleting an identity needs the two apart: the stored entries
  /// are removed in an order that matters (`IdentityWipe`), and this is the
  /// copy in this process, which has to go before anything can be retried.
  void forget() => _clearMemory();

  void _clearMemory() {
    _secret?.fillRange(0, _secret!.length, 0);
    _secret = null;
    _token = null;
    _publicKey = null;
  }

  @override
  String toString() => 'IdentityService(token: $_token, secret: <redacted>)';
}
