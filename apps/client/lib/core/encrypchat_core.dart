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

typedef _BufOutC = Int32 Function(
  Pointer<Uint8> a,
  Pointer<Uint8> data,
  Size dataLen,
  Pointer<Pointer<Uint8>> out,
  Pointer<Size> outLen,
);
typedef _BufOutDart = int Function(
  Pointer<Uint8> a,
  Pointer<Uint8> data,
  int dataLen,
  Pointer<Pointer<Uint8>> out,
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

typedef _NodeStartC = Int32 Function(
  Pointer<Uint8> secret,
  Uint16 listenPort,
  Pointer<Pointer<Void>> outHandle,
);
typedef _NodeStartDart = int Function(
  Pointer<Uint8> secret,
  int listenPort,
  Pointer<Pointer<Void>> outHandle,
);

typedef _NodeStopC = Void Function(Pointer<Void> handle);
typedef _NodeStopDart = void Function(Pointer<Void> handle);

typedef _NodeTokenC = Int32 Function(
  Pointer<Void> handle,
  Pointer<Char> out,
  Size cap,
);
typedef _NodeTokenDart = int Function(
  Pointer<Void> handle,
  Pointer<Char> out,
  int cap,
);

typedef _NodeSendC = Int32 Function(
  Pointer<Void> handle,
  Pointer<Char> token,
  Pointer<Uint8> frame,
  Size frameLen,
);
typedef _NodeSendDart = int Function(
  Pointer<Void> handle,
  Pointer<Char> token,
  Pointer<Uint8> frame,
  int frameLen,
);

typedef _NodeTryRecvC = Int32 Function(
  Pointer<Void> handle,
  Pointer<Pointer<Uint8>> out,
  Pointer<Size> outLen,
);
typedef _NodeTryRecvDart = int Function(
  Pointer<Void> handle,
  Pointer<Pointer<Uint8>> out,
  Pointer<Size> outLen,
);

typedef _NodePeerCountC = Int32 Function(
  Pointer<Void> handle,
  Pointer<Size> outCount,
);
typedef _NodePeerCountDart = int Function(
  Pointer<Void> handle,
  Pointer<Size> outCount,
);

typedef _NodeConnectC = Int32 Function(
  Pointer<Void> handle,
  Pointer<Char> multiaddr,
);
typedef _NodeConnectDart = int Function(
  Pointer<Void> handle,
  Pointer<Char> multiaddr,
);

typedef _FreeC = Void Function(Pointer<Void> ptr);
typedef _FreeDart = void Function(Pointer<Void> ptr);

/// Dart wrapper for Phase 4 C ABI (`docs/ffi-contract.md`).
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
        _encrypt = lib.lookupFunction<_BufOutC, _BufOutDart>('encrypchat_encrypt'),
        _decrypt = lib.lookupFunction<_DecryptC, _DecryptDart>('encrypchat_decrypt'),
        _localSeal =
            lib.lookupFunction<_BufOutC, _BufOutDart>('encrypchat_local_seal'),
        _localOpen =
            lib.lookupFunction<_BufOutC, _BufOutDart>('encrypchat_local_open'),
        _nodeStart =
            lib.lookupFunction<_NodeStartC, _NodeStartDart>('encrypchat_node_start'),
        _nodeStop =
            lib.lookupFunction<_NodeStopC, _NodeStopDart>('encrypchat_node_stop'),
        _nodeLocalToken =
            lib.lookupFunction<_NodeTokenC, _NodeTokenDart>(
          'encrypchat_node_local_token',
        ),
        _nodeListenAddr =
            lib.lookupFunction<_NodeTokenC, _NodeTokenDart>(
          'encrypchat_node_listen_addr',
        ),
        _nodeSend =
            lib.lookupFunction<_NodeSendC, _NodeSendDart>('encrypchat_node_send'),
        _nodeTryRecv = lib.lookupFunction<_NodeTryRecvC, _NodeTryRecvDart>(
          'encrypchat_node_try_recv',
        ),
        _nodePeerCount = lib.lookupFunction<_NodePeerCountC, _NodePeerCountDart>(
          'encrypchat_node_peer_count',
        ),
        _nodeConnect = lib.lookupFunction<_NodeConnectC, _NodeConnectDart>(
          'encrypchat_node_connect',
        ),
        _free = lib.lookupFunction<_FreeC, _FreeDart>('encrypchat_free');

  factory EncrypchatCore.open() => EncrypchatCore(loadEncrypchatCore());

  static const int tokenCap = 68;
  static const int addrCap = 128;

  final _ApiVersionDart _apiVersion;
  final _IdentityGenerateDart _identityGenerate;
  final _IdentityTokenDart _identityToken;
  final _IdentityPublicKeyDart _identityPublicKey;
  final _BufOutDart _encrypt;
  final _DecryptDart _decrypt;
  final _BufOutDart _localSeal;
  final _BufOutDart _localOpen;
  final _NodeStartDart _nodeStart;
  final _NodeStopDart _nodeStop;
  final _NodeTokenDart _nodeLocalToken;
  final _NodeTokenDart _nodeListenAddr;
  final _NodeSendDart _nodeSend;
  final _NodeTryRecvDart _nodeTryRecv;
  final _NodePeerCountDart _nodePeerCount;
  final _NodeConnectDart _nodeConnect;
  final _FreeDart _free;

  Pointer<Void>? _node;

  bool get isNodeRunning => _node != null;

  String apiVersion() {
    final out = calloc<Uint8>(16);
    try {
      _check(_apiVersion(out.cast<Char>(), 16));
      return out.cast<Utf8>().toDartString();
    } finally {
      calloc.free(out);
    }
  }

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
    _require32(secret);
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
    _require32(secret);
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
    _require32(recipientPublicKey);
    return _bufOut(_encrypt, recipientPublicKey, plaintext);
  }

  Uint8List decrypt({
    required Uint8List secret,
    required Uint8List ciphertext,
  }) {
    _require32(secret);
    final secretPtr = _copyBytes(secret);
    final ct = ciphertext.isEmpty ? nullptr : _copyBytes(ciphertext);
    final outPtr = calloc<Pointer<Uint8>>();
    final outLen = calloc<Size>();
    try {
      _check(_decrypt(secretPtr, ct, ciphertext.length, outPtr, outLen));
      return _takeBuffer(outPtr.value, outLen.value);
    } finally {
      calloc.free(secretPtr);
      if (ct != nullptr) calloc.free(ct);
      calloc.free(outPtr);
      calloc.free(outLen);
    }
  }

  Uint8List localSeal({
    required Uint8List dbKey,
    required Uint8List plaintext,
  }) {
    _require32(dbKey);
    return _bufOut(_localSeal, dbKey, plaintext);
  }

  Uint8List localOpen({
    required Uint8List dbKey,
    required Uint8List sealed,
  }) {
    _require32(dbKey);
    return _bufOut(_localOpen, dbKey, sealed);
  }

  String sealUtf8({required Uint8List dbKey, required String text}) {
    final sealed = localSeal(
      dbKey: dbKey,
      plaintext: Uint8List.fromList(utf8.encode(text)),
    );
    return base64Encode(sealed);
  }

  String openUtf8({required Uint8List dbKey, required Uint8List sealed}) {
    return utf8.decode(localOpen(dbKey: dbKey, sealed: sealed));
  }

  void nodeStart({required Uint8List secret, int listenPort = 0}) {
    if (_node != null) return;
    _require32(secret);
    final secretPtr = _copyBytes(secret);
    final out = calloc<Pointer<Void>>();
    try {
      _check(_nodeStart(secretPtr, listenPort, out));
      _node = out.value;
    } finally {
      calloc.free(secretPtr);
      calloc.free(out);
    }
  }

  void nodeStop() {
    final h = _node;
    if (h == null) return;
    _nodeStop(h);
    _node = null;
  }

  String nodeLocalToken() {
    final h = _requireNode();
    final out = calloc<Uint8>(tokenCap);
    try {
      _check(_nodeLocalToken(h, out.cast<Char>(), tokenCap));
      return out.cast<Utf8>().toDartString();
    } finally {
      calloc.free(out);
    }
  }

  String nodeListenAddr() {
    final h = _requireNode();
    final out = calloc<Uint8>(addrCap);
    try {
      _check(_nodeListenAddr(h, out.cast<Char>(), addrCap));
      return out.cast<Utf8>().toDartString();
    } finally {
      calloc.free(out);
    }
  }

  void nodeConnect(String multiaddr) {
    final h = _requireNode();
    final cstr = multiaddr.toNativeUtf8();
    try {
      _check(_nodeConnect(h, cstr.cast<Char>()));
    } finally {
      malloc.free(cstr);
    }
  }

  /// Convenience: `/ip4/$host/tcp/$port`
  void nodeConnectHostPort(String host, int port) {
    nodeConnect('/ip4/$host/tcp/$port');
  }

  void nodeSend({required String peerToken, required Uint8List frame}) {
    final h = _requireNode();
    final token = peerToken.toNativeUtf8();
    final framePtr = frame.isEmpty ? nullptr : _copyBytes(frame);
    try {
      _check(_nodeSend(h, token.cast<Char>(), framePtr, frame.length));
    } finally {
      malloc.free(token);
      if (framePtr != nullptr) calloc.free(framePtr);
    }
  }

  /// Returns null when queue is empty (code 9).
  Uint8List? nodeTryRecv() {
    final h = _requireNode();
    final outPtr = calloc<Pointer<Uint8>>();
    final outLen = calloc<Size>();
    try {
      final code = _nodeTryRecv(h, outPtr, outLen);
      if (code == CoreException.empty) return null;
      _check(code);
      return _takeBuffer(outPtr.value, outLen.value);
    } finally {
      calloc.free(outPtr);
      calloc.free(outLen);
    }
  }

  int nodePeerCount() {
    final h = _requireNode();
    final out = calloc<Size>();
    try {
      _check(_nodePeerCount(h, out));
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

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

  Uint8List _bufOut(
    _BufOutDart fn,
    Uint8List keyOrPub,
    Uint8List data,
  ) {
    final a = _copyBytes(keyOrPub);
    final dataPtr = data.isEmpty ? nullptr : _copyBytes(data);
    final outPtr = calloc<Pointer<Uint8>>();
    final outLen = calloc<Size>();
    try {
      _check(fn(a, dataPtr, data.length, outPtr, outLen));
      return _takeBuffer(outPtr.value, outLen.value);
    } finally {
      calloc.free(a);
      if (dataPtr != nullptr) calloc.free(dataPtr);
      calloc.free(outPtr);
      calloc.free(outLen);
    }
  }

  Uint8List _takeBuffer(Pointer<Uint8> ptr, int len) {
    final bytes = Uint8List.fromList(ptr.asTypedList(len));
    _free(ptr.cast());
    return bytes;
  }

  Pointer<Void> _requireNode() {
    final h = _node;
    if (h == null) {
      throw StateError('P2P node not started');
    }
    return h;
  }

  void _check(int code) {
    if (code != 0) throw CoreException(code);
  }

  void _require32(Uint8List bytes) {
    if (bytes.length != 32) {
      throw CoreException(CoreException.invalidPublicKey, 'expected 32 bytes');
    }
  }

  Pointer<Uint8> _copyBytes(Uint8List bytes) {
    final ptr = calloc<Uint8>(bytes.length);
    ptr.asTypedList(bytes.length).setAll(0, bytes);
    return ptr;
  }
}
