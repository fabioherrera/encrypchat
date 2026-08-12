import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'core_error.dart';
import 'native_library.dart';

typedef _ApiVersionC = Int32 Function(Pointer<Char> out, Size cap);
typedef _ApiVersionDart = int Function(Pointer<Char> out, int cap);

typedef _IdentityGenerateC = Int32 Function(
  Pointer<Uint8> outSecret,
  Pointer<Char> outToken,
  Size tokenCap,
);
typedef _IdentityGenerateDart = int Function(
  Pointer<Uint8> outSecret,
  Pointer<Char> outToken,
  int tokenCap,
);

typedef _IdentityTokenC = Int32 Function(
  Pointer<Uint8> secret,
  Pointer<Char> outToken,
  Size tokenCap,
);
typedef _IdentityTokenDart = int Function(
  Pointer<Uint8> secret,
  Pointer<Char> outToken,
  int tokenCap,
);

typedef _IdentityPublicKeyC = Int32 Function(
  Pointer<Uint8> secret,
  Pointer<Uint8> outPub,
);
typedef _IdentityPublicKeyDart = int Function(
  Pointer<Uint8> secret,
  Pointer<Uint8> outPub,
);

typedef _EncryptC = Int32 Function(
  Pointer<Uint8> recipientPub,
  Pointer<Uint8> plaintext,
  Size plaintextLen,
  Pointer<Pointer<Uint8>> outCiphertext,
  Pointer<Size> outLen,
);
typedef _EncryptDart = int Function(
  Pointer<Uint8> recipientPub,
  Pointer<Uint8> plaintext,
  int plaintextLen,
  Pointer<Pointer<Uint8>> outCiphertext,
  Pointer<Size> outLen,
);

typedef _DecryptC = Int32 Function(
  Pointer<Uint8> secret,
  Pointer<Uint8> ciphertext,
  Size ciphertextLen,
  Pointer<Pointer<Uint8>> outPlaintext,
  Pointer<Size> outLen,
);
typedef _DecryptDart = int Function(
  Pointer<Uint8> secret,
  Pointer<Uint8> ciphertext,
  int ciphertextLen,
  Pointer<Pointer<Uint8>> outPlaintext,
  Pointer<Size> outLen,
);

typedef _FreeC = Void Function(Pointer<Void> ptr);
typedef _FreeDart = void Function(Pointer<Void> ptr);

/// Thin Dart wrapper around the Phase 3 C ABI (`docs/ffi-contract.md`).
class EncrypchatCore {
  EncrypchatCore(DynamicLibrary lib)
      : _apiVersion = lib.lookupFunction<_ApiVersionC, _ApiVersionDart>(
          'encrypchat_api_version',
        ),
        _identityGenerate =
            lib.lookupFunction<_IdentityGenerateC, _IdentityGenerateDart>(
          'encrypchat_identity_generate',
        ),
        _identityToken =
            lib.lookupFunction<_IdentityTokenC, _IdentityTokenDart>(
          'encrypchat_identity_token',
        ),
        _identityPublicKey =
            lib.lookupFunction<_IdentityPublicKeyC, _IdentityPublicKeyDart>(
          'encrypchat_identity_public_key',
        ),
        _encrypt = lib.lookupFunction<_EncryptC, _EncryptDart>(
          'encrypchat_encrypt',
        ),
        _decrypt = lib.lookupFunction<_DecryptC, _DecryptDart>(
          'encrypchat_decrypt',
        ),
        _free = lib.lookupFunction<_FreeC, _FreeDart>('encrypchat_free');

  factory EncrypchatCore.open() => EncrypchatCore(loadEncrypchatCore());

  static const int tokenCap = 68;

  final _ApiVersionDart _apiVersion;
  final _IdentityGenerateDart _identityGenerate;
  final _IdentityTokenDart _identityToken;
  final _IdentityPublicKeyDart _identityPublicKey;
  final _EncryptDart _encrypt;
  final _DecryptDart _decrypt;
  final _FreeDart _free;

  String apiVersion() {
    final out = calloc<Uint8>(16);
    try {
      _check(_apiVersion(out.cast<Char>(), 16));
      return out.cast<Utf8>().toDartString();
    } finally {
      calloc.free(out);
    }
  }

  /// Returns `(secret, token)`. Caller must protect [secret].
  ({Uint8List secret, String token}) identityGenerate() {
    final secret = calloc<Uint8>(32);
    final token = calloc<Uint8>(tokenCap);
    try {
      _check(_identityGenerate(secret, token.cast<Char>(), tokenCap));
      return (
        secret: Uint8List.fromList(secret.asTypedList(32)),
        token: token.cast<Utf8>().toDartString(),
      );
    } finally {
      calloc.free(secret);
      calloc.free(token);
    }
  }

  String identityToken(Uint8List secret) {
    _requireSecret(secret);
    final secretPtr = _copyBytes(secret);
    final token = calloc<Uint8>(tokenCap);
    try {
      _check(_identityToken(secretPtr, token.cast<Char>(), tokenCap));
      return token.cast<Utf8>().toDartString();
    } finally {
      calloc.free(secretPtr);
      calloc.free(token);
    }
  }

  Uint8List identityPublicKey(Uint8List secret) {
    _requireSecret(secret);
    final secretPtr = _copyBytes(secret);
    final out = calloc<Uint8>(32);
    try {
      _check(_identityPublicKey(secretPtr, out));
      return Uint8List.fromList(out.asTypedList(32));
    } finally {
      calloc.free(secretPtr);
      calloc.free(out);
    }
  }

  Uint8List encrypt({
    required Uint8List recipientPublicKey,
    required Uint8List plaintext,
  }) {
    if (recipientPublicKey.length != 32) {
      throw CoreException(CoreException.invalidPublicKey);
    }
    final pub = _copyBytes(recipientPublicKey);
    final pt = plaintext.isEmpty ? nullptr : _copyBytes(plaintext);
    final outPtr = calloc<Pointer<Uint8>>();
    final outLen = calloc<Size>();
    try {
      _check(_encrypt(pub, pt, plaintext.length, outPtr, outLen));
      final len = outLen.value;
      final ptr = outPtr.value;
      final bytes = Uint8List.fromList(ptr.asTypedList(len));
      _free(ptr.cast());
      return bytes;
    } finally {
      calloc.free(pub);
      if (pt != nullptr) calloc.free(pt);
      calloc.free(outPtr);
      calloc.free(outLen);
    }
  }

  Uint8List decrypt({
    required Uint8List secret,
    required Uint8List ciphertext,
  }) {
    _requireSecret(secret);
    final secretPtr = _copyBytes(secret);
    final ct = ciphertext.isEmpty ? nullptr : _copyBytes(ciphertext);
    final outPtr = calloc<Pointer<Uint8>>();
    final outLen = calloc<Size>();
    try {
      _check(_decrypt(secretPtr, ct, ciphertext.length, outPtr, outLen));
      final len = outLen.value;
      final ptr = outPtr.value;
      final bytes = Uint8List.fromList(ptr.asTypedList(len));
      _free(ptr.cast());
      return bytes;
    } finally {
      calloc.free(secretPtr);
      if (ct != nullptr) calloc.free(ct);
      calloc.free(outPtr);
      calloc.free(outLen);
    }
  }

  /// Encrypt UTF-8 for storage (local DB blobs).
  Uint8List encryptUtf8({
    required Uint8List recipientPublicKey,
    required String plaintext,
  }) {
    return encrypt(
      recipientPublicKey: recipientPublicKey,
      plaintext: Uint8List.fromList(utf8.encode(plaintext)),
    );
  }

  String decryptUtf8({
    required Uint8List secret,
    required Uint8List ciphertext,
  }) {
    return utf8.decode(decrypt(secret: secret, ciphertext: ciphertext));
  }

  void _check(int code) {
    if (code != 0) throw CoreException(code);
  }

  void _requireSecret(Uint8List secret) {
    if (secret.length != 32) {
      throw CoreException(CoreException.invalidPublicKey, 'secret must be 32 bytes');
    }
  }

  Pointer<Uint8> _copyBytes(Uint8List bytes) {
    final ptr = calloc<Uint8>(bytes.length);
    ptr.asTypedList(bytes.length).setAll(0, bytes);
    return ptr;
  }
}
