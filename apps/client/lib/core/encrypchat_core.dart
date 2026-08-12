import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'core_error.dart';
import 'native_library.dart';

typedef _ApiVersionC = Int32 Function(Pointer<Char> out, Size cap);
typedef _ApiVersionDart = int Function(Pointer<Char> out, int cap);

typedef _IdentityGenerateC =
    Int32 Function(
      Pointer<Uint8> outSecret,
      Pointer<Char> outToken,
      Size tokenCap,
    );
typedef _IdentityGenerateDart =
    int Function(
      Pointer<Uint8> outSecret,
      Pointer<Char> outToken,
      int tokenCap,
    );

typedef _IdentityTokenC =
    Int32 Function(
      Pointer<Uint8> secret,
      Pointer<Char> outToken,
      Size tokenCap,
    );
typedef _IdentityTokenDart =
    int Function(Pointer<Uint8> secret, Pointer<Char> outToken, int tokenCap);

typedef _IdentityPublicKeyC =
    Int32 Function(Pointer<Uint8> secret, Pointer<Uint8> outPub);
typedef _IdentityPublicKeyDart =
    int Function(Pointer<Uint8> secret, Pointer<Uint8> outPub);

typedef _BufOutC =
    Int32 Function(
      Pointer<Uint8> a,
      Pointer<Uint8> data,
      Size dataLen,
      Pointer<Pointer<Uint8>> out,
      Pointer<Size> outLen,
    );
typedef _BufOutDart =
    int Function(
      Pointer<Uint8> a,
      Pointer<Uint8> data,
      int dataLen,
      Pointer<Pointer<Uint8>> out,
      Pointer<Size> outLen,
    );

typedef _DecryptC =
    Int32 Function(
      Pointer<Uint8> secret,
      Pointer<Uint8> ciphertext,
      Size ciphertextLen,
      Pointer<Pointer<Uint8>> outPlaintext,
      Pointer<Size> outLen,
    );
typedef _DecryptDart =
    int Function(
      Pointer<Uint8> secret,
      Pointer<Uint8> ciphertext,
      int ciphertextLen,
      Pointer<Pointer<Uint8>> outPlaintext,
      Pointer<Size> outLen,
    );

typedef _NodeStartC =
    Int32 Function(
      Pointer<Uint8> secret,
      Uint16 listenPort,
      Pointer<Pointer<Void>> outHandle,
    );
typedef _NodeStartDart =
    int Function(
      Pointer<Uint8> secret,
      int listenPort,
      Pointer<Pointer<Void>> outHandle,
    );

typedef _NodeStopC = Void Function(Pointer<Void> handle);
typedef _NodeStopDart = void Function(Pointer<Void> handle);

typedef _NodeTokenC =
    Int32 Function(Pointer<Void> handle, Pointer<Char> out, Size cap);
typedef _NodeTokenDart =
    int Function(Pointer<Void> handle, Pointer<Char> out, int cap);

typedef _NodeSendC =
    Int32 Function(
      Pointer<Void> handle,
      Pointer<Char> token,
      Pointer<Uint8> frame,
      Size frameLen,
    );
typedef _NodeSendDart =
    int Function(
      Pointer<Void> handle,
      Pointer<Char> token,
      Pointer<Uint8> frame,
      int frameLen,
    );

typedef _NodeTryRecvC =
    Int32 Function(
      Pointer<Void> handle,
      Pointer<Pointer<Uint8>> out,
      Pointer<Size> outLen,
    );
typedef _NodeTryRecvDart =
    int Function(
      Pointer<Void> handle,
      Pointer<Pointer<Uint8>> out,
      Pointer<Size> outLen,
    );

typedef _NodePeerCountC =
    Int32 Function(Pointer<Void> handle, Pointer<Size> outCount);
typedef _NodePeerCountDart =
    int Function(Pointer<Void> handle, Pointer<Size> outCount);

typedef _NodeConnectC =
    Int32 Function(Pointer<Void> handle, Pointer<Char> multiaddr);
typedef _NodeConnectDart =
    int Function(Pointer<Void> handle, Pointer<Char> multiaddr);

typedef _NodeSetBlockedC =
    Int32 Function(
      Pointer<Void> handle,
      Pointer<Pointer<Char>> tokens,
      Size count,
    );
typedef _NodeSetBlockedDart =
    int Function(
      Pointer<Void> handle,
      Pointer<Pointer<Char>> tokens,
      int count,
    );

typedef _PopProofC =
    Int32 Function(
      Pointer<Uint8> secret,
      Pointer<Uint8> ephPub,
      Pointer<Uint8> nonce,
      Size nonceLen,
      Pointer<Char> token,
      Pointer<Uint8> outProof,
    );
typedef _PopProofDart =
    int Function(
      Pointer<Uint8> secret,
      Pointer<Uint8> ephPub,
      Pointer<Uint8> nonce,
      int nonceLen,
      Pointer<Char> token,
      Pointer<Uint8> outProof,
    );

typedef _SealedSealC =
    Int32 Function(
      Pointer<Uint8> senderSecret,
      Pointer<Uint8> recipientPub,
      Pointer<Uint8> plaintext,
      Size plaintextLen,
      Pointer<Pointer<Uint8>> outBlob,
      Pointer<Size> outLen,
      Pointer<Uint8> outMsgId,
      Pointer<Uint64> outSentAt,
    );
typedef _SealedSealDart =
    int Function(
      Pointer<Uint8> senderSecret,
      Pointer<Uint8> recipientPub,
      Pointer<Uint8> plaintext,
      int plaintextLen,
      Pointer<Pointer<Uint8>> outBlob,
      Pointer<Size> outLen,
      Pointer<Uint8> outMsgId,
      Pointer<Uint64> outSentAt,
    );

typedef _SealedOpenC =
    Int32 Function(
      Pointer<Uint8> recipientSecret,
      Pointer<Uint8> blob,
      Size blobLen,
      Uint64 nowUnixSecs,
      Pointer<Uint8> outSenderPub,
      Pointer<Char> outSenderToken,
      Size tokenCap,
      Pointer<Uint8> outMsgId,
      Pointer<Uint64> outSentAt,
      Pointer<Pointer<Uint8>> outPlaintext,
      Pointer<Size> outLen,
    );
typedef _SealedOpenDart =
    int Function(
      Pointer<Uint8> recipientSecret,
      Pointer<Uint8> blob,
      int blobLen,
      int nowUnixSecs,
      Pointer<Uint8> outSenderPub,
      Pointer<Char> outSenderToken,
      int tokenCap,
      Pointer<Uint8> outMsgId,
      Pointer<Uint64> outSentAt,
      Pointer<Pointer<Uint8>> outPlaintext,
      Pointer<Size> outLen,
    );

typedef _FreeC = Void Function(Pointer<Void> ptr);
typedef _FreeDart = void Function(Pointer<Void> ptr);

/// What comes out of an opened `ECS1` blob. [senderToken] and [senderPublicKey]
/// are **authenticated**: they were recovered from the ciphertext, not read from
/// a field the sender could write.
typedef SealedInbound = ({
  Uint8List senderPublicKey,
  String senderToken,
  Uint8List msgId,
  int sentAtUnix,
  Uint8List plaintext,
});

/// Dart wrapper for Phase 4 C ABI (`docs/ffi-contract.md`).
class EncrypchatCore {
  EncrypchatCore(DynamicLibrary lib)
    : _apiVersion = lib.lookupFunction<_ApiVersionC, _ApiVersionDart>(
        'encrypchat_api_version',
      ),
      _identityGenerate = lib
          .lookupFunction<_IdentityGenerateC, _IdentityGenerateDart>(
            'encrypchat_identity_generate',
          ),
      _identityToken = lib.lookupFunction<_IdentityTokenC, _IdentityTokenDart>(
        'encrypchat_identity_token',
      ),
      _identityPublicKey = lib
          .lookupFunction<_IdentityPublicKeyC, _IdentityPublicKeyDart>(
            'encrypchat_identity_public_key',
          ),
      _encrypt = lib.lookupFunction<_BufOutC, _BufOutDart>(
        'encrypchat_encrypt',
      ),
      _decrypt = lib.lookupFunction<_DecryptC, _DecryptDart>(
        'encrypchat_decrypt',
      ),
      _localSeal = lib.lookupFunction<_BufOutC, _BufOutDart>(
        'encrypchat_local_seal',
      ),
      _localOpen = lib.lookupFunction<_BufOutC, _BufOutDart>(
        'encrypchat_local_open',
      ),
      _nodeStart = lib.lookupFunction<_NodeStartC, _NodeStartDart>(
        'encrypchat_node_start',
      ),
      _nodeStop = lib.lookupFunction<_NodeStopC, _NodeStopDart>(
        'encrypchat_node_stop',
      ),
      _nodeLocalToken = lib.lookupFunction<_NodeTokenC, _NodeTokenDart>(
        'encrypchat_node_local_token',
      ),
      _nodeListenAddr = lib.lookupFunction<_NodeTokenC, _NodeTokenDart>(
        'encrypchat_node_listen_addr',
      ),
      _nodeSend = lib.lookupFunction<_NodeSendC, _NodeSendDart>(
        'encrypchat_node_send',
      ),
      _nodeTryRecv = lib.lookupFunction<_NodeTryRecvC, _NodeTryRecvDart>(
        'encrypchat_node_try_recv',
      ),
      _nodePeerCount = lib.lookupFunction<_NodePeerCountC, _NodePeerCountDart>(
        'encrypchat_node_peer_count',
      ),
      _nodeConnect = lib.lookupFunction<_NodeConnectC, _NodeConnectDart>(
        'encrypchat_node_connect',
      ),
      _nodeSetBlocked = lib
          .lookupFunction<_NodeSetBlockedC, _NodeSetBlockedDart>(
            'encrypchat_node_set_blocked_tokens',
          ),
      _popProof = lib.lookupFunction<_PopProofC, _PopProofDart>(
        'encrypchat_pop_proof',
      ),
      _sealedSeal = lib.lookupFunction<_SealedSealC, _SealedSealDart>(
        'encrypchat_sealed_seal',
      ),
      _sealedOpen = lib.lookupFunction<_SealedOpenC, _SealedOpenDart>(
        'encrypchat_sealed_open',
      ),
      _free = lib.lookupFunction<_FreeC, _FreeDart>('encrypchat_free');

  factory EncrypchatCore.open() {
    final lib = loadEncrypchatCore();
    assertSupportedApiVersion(lib);
    return EncrypchatCore(lib);
  }

  static const int tokenCap = 68;
  static const int addrCap = 128;

  /// Size of the sealed-sender message id (`ECS1`), stable across replays.
  static const int sealedMsgIdLen = 16;

  /// Fixed overhead of an `ECS1` blob over its plaintext.
  static const int sealedOverheadBytes = 136;

  /// Fixed overhead of an [encrypt] ciphertext over its plaintext: the
  /// ephemeral public key (32), the nonce (12) and the Poly1305 tag (16). What
  /// makes a ceiling on the P2P wire a ceiling on the payload inside it.
  static const int encryptOverheadBytes = 60;

  /// Lowest core ABI this client can drive: the sealed-sender pair
  /// (`encrypchat_sealed_seal` / `encrypchat_sealed_open`) arrived in 0.8.0 and
  /// the relay path has no fallback without it.
  static const String minApiVersion = '0.8.0';

  /// Fails loudly on a stale library **before** the constructor looks up its
  /// symbols, because a missing symbol surfaces as `Invalid argument(s): Failed
  /// to lookup symbol …`, which reads like a client bug instead of "rebuild the
  /// core".
  static void assertSupportedApiVersion(DynamicLibrary lib) {
    String? found;
    try {
      final read = lib.lookupFunction<_ApiVersionC, _ApiVersionDart>(
        'encrypchat_api_version',
      );
      final out = calloc<Uint8>(16);
      try {
        if (read(out.cast<Char>(), 16) == 0) {
          found = out.cast<Utf8>().toDartString();
        }
      } finally {
        calloc.free(out);
      }
    } on ArgumentError {
      // Older than the version symbol itself: report it as unknown, not as a
      // lookup failure.
      found = null;
    }
    if (found == null || !isApiCompatible(found)) {
      throw CoreVersionException(found: found, required: minApiVersion);
    }
  }

  /// The core is pre-1.0, so the minor is what moves when the ABI grows: an
  /// older minor is missing symbols this build looks up, a newer one only adds.
  static bool isApiCompatible(String version) {
    final found = _parseVersion(version);
    final wanted = _parseVersion(minApiVersion);
    if (found == null || wanted == null) return false;
    if (found.major != wanted.major) return false;
    return found.minor >= wanted.minor;
  }

  static ({int major, int minor})? _parseVersion(String version) {
    final parts = version.trim().split('.');
    if (parts.length < 2) return null;
    final major = int.tryParse(parts[0]);
    final minor = int.tryParse(parts[1]);
    if (major == null || minor == null) return null;
    return (major: major, minor: minor);
  }

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
  final _NodeSetBlockedDart _nodeSetBlocked;
  final _PopProofDart _popProof;
  final _SealedSealDart _sealedSeal;
  final _SealedOpenDart _sealedOpen;
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
      // The identity of this device, freshly minted: the one buffer that must
      // not survive the call it was created in.
      _freeSecret(secret, 32);
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
      _freeSecret(secretPtr, secret.length);
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
      _freeSecret(secretPtr, secret.length);
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

  /// Throws `CoreException` with [CoreException.invalidPublicKey] when the core
  /// will not accept this key as a peer identity.
  ///
  /// Two independent refusals, and neither implies the other: a **non-canonical
  /// encoding** of a real key, which is the same key under a second token and so
  /// a way around a block (F-10, core `0.8.1`), and a **degenerate** key, whose
  /// shared secret is all-zero and computable by a stranger.
  ///
  /// The ABI exports no validator, and writing one here is exactly what
  /// invariant 14 of `docs/ffi-contract.md` forbids: the canonical form is the
  /// core's to define, and a second implementation in Dart would be one bug away
  /// from accepting an alias the core rejects — or refusing a key it accepts. So
  /// the question is asked the only way the ABI allows, by sealing one byte and
  /// throwing the result away, and only the verdict is used. `sealed_seal` is the
  /// probe because it is the strictest door: it checks the encoding *and* the
  /// shared secret, while `encrypt` only checks the encoding. Never a step
  /// towards "fixing" a key — there is nothing to fix, the card is wrong.
  void assertUsablePublicKey({
    required Uint8List senderSecret,
    required Uint8List publicKey,
  }) {
    final probe = sealedSeal(
      senderSecret: senderSecret,
      recipientPublicKey: publicKey,
      plaintext: Uint8List.fromList(const [0]),
    );
    probe.blob.fillRange(0, probe.blob.length, 0);
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
      // Once per inbound message, which is what makes this the hottest copy of
      // the identity secret in the client.
      _freeSecret(secretPtr, secret.length);
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

  Uint8List localOpen({required Uint8List dbKey, required Uint8List sealed}) {
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
      _freeSecret(secretPtr, secret.length);
      calloc.free(out);
    }
  }

  void nodeStop() {
    final h = _node;
    if (h == null) return;
    _nodeStop(h);
    _node = null;
  }

  /// The node handle as an integer, for handing to the worker isolate: a
  /// `Pointer` cannot cross an isolate boundary, its address can.
  int? get nodeHandleAddress => _node?.address;

  /// Gives up ownership of the handle without stopping it, so whoever holds the
  /// address can stop it later. After this call nothing in this isolate
  /// dereferences the node, which is what makes a stop from elsewhere safe.
  int? detachNode() {
    final address = _node?.address;
    _node = null;
    return address;
  }

  /// Stops a node by address (see [detachNode]). A zero address is a no-op, not
  /// a crash: teardown paths call this without knowing whether a node ever ran.
  void nodeStopAt(int handleAddress) {
    if (handleAddress == 0) return;
    _nodeStop(Pointer<Void>.fromAddress(handleAddress));
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

  /// [handleAddress] lets the worker isolate drive a node started elsewhere in
  /// the process; without it the call uses this isolate's own handle.
  void nodeConnect(String multiaddr, {int? handleAddress}) {
    final h = _handleOr(handleAddress);
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

  /// Replaces the core-side blocklist (it never merges, and it starts empty on
  /// every [nodeStart]). The core normalizes and copies the tokens before
  /// returning, so the array and the strings are freed right here.
  ///
  /// A rejected list (code 1 for a malformed token) leaves the previous one in
  /// place core-side; nothing is applied halfway.
  void nodeSetBlockedTokens(List<String> tokens) {
    final h = _requireNode();
    if (tokens.isEmpty) {
      _check(_nodeSetBlocked(h, nullptr, 0));
      return;
    }
    final array = calloc<Pointer<Char>>(tokens.length);
    final strings = <Pointer<Utf8>>[];
    try {
      for (var i = 0; i < tokens.length; i++) {
        final cstr = tokens[i].toNativeUtf8();
        // Registered before the array write so a throw mid-loop still frees it.
        strings.add(cstr);
        array[i] = cstr.cast<Char>();
      }
      _check(_nodeSetBlocked(h, array, tokens.length));
    } finally {
      for (final cstr in strings) {
        malloc.free(cstr);
      }
      calloc.free(array);
    }
  }

  /// Blocks up to 15 s waiting for the peer's ACK, so callers on the UI isolate
  /// go through `CoreWorker` and pass [handleAddress] (F-11).
  void nodeSend({
    required String peerToken,
    required Uint8List frame,
    int? handleAddress,
  }) {
    final h = _handleOr(handleAddress);
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

  /// Relay PoP proof (32 bytes) for `POST /v1/pull`.
  Uint8List popProof({
    required Uint8List secret,
    required Uint8List ephPubkey,
    required Uint8List nonce,
    required String destToken,
  }) {
    _require32(secret);
    _require32(ephPubkey);
    final secretPtr = _copyBytes(secret);
    final ephPtr = _copyBytes(ephPubkey);
    final noncePtr = nonce.isEmpty ? nullptr : _copyBytes(nonce);
    final token = destToken.toNativeUtf8();
    final out = calloc<Uint8>(32);
    try {
      _check(
        _popProof(
          secretPtr,
          ephPtr,
          noncePtr,
          nonce.length,
          token.cast<Char>(),
          out,
        ),
      );
      return Uint8List.fromList(out.asTypedList(32));
    } finally {
      // Every 8 s while the relay poll runs, so this one is not a rare path.
      _freeSecret(secretPtr, secret.length);
      calloc.free(ephPtr);
      if (noncePtr != nullptr) calloc.free(noncePtr);
      malloc.free(token);
      // The proof authorises emptying this mailbox until the challenge rolls.
      _freeSecret(out, 32);
    }
  }

  /// Seals `plaintext` for the relay: the sender is bound to the content, so
  /// the payload must not declare a `from` of its own.
  ///
  /// The returned `msgId` is what the recipient sees too, and is stable across
  /// replays — it is the de-duplication key on the other side.
  ({Uint8List blob, Uint8List msgId, int sentAtUnix}) sealedSeal({
    required Uint8List senderSecret,
    required Uint8List recipientPublicKey,
    required Uint8List plaintext,
  }) {
    _require32(senderSecret);
    _require32(recipientPublicKey);
    final secretPtr = _copyBytes(senderSecret);
    final pubPtr = _copyBytes(recipientPublicKey);
    final dataPtr = plaintext.isEmpty ? nullptr : _copyBytes(plaintext);
    final outBlob = calloc<Pointer<Uint8>>();
    final outLen = calloc<Size>();
    final outMsgId = calloc<Uint8>(sealedMsgIdLen);
    final outSentAt = calloc<Uint64>();
    try {
      _check(
        _sealedSeal(
          secretPtr,
          pubPtr,
          dataPtr,
          plaintext.length,
          outBlob,
          outLen,
          outMsgId,
          outSentAt,
        ),
      );
      return (
        blob: _takeBuffer(outBlob.value, outLen.value),
        msgId: Uint8List.fromList(outMsgId.asTypedList(sealedMsgIdLen)),
        sentAtUnix: outSentAt.value,
      );
    } finally {
      _freeSecret(secretPtr, senderSecret.length);
      calloc.free(pubPtr);
      if (dataPtr != nullptr) _freeSecret(dataPtr, plaintext.length);
      calloc.free(outBlob);
      calloc.free(outLen);
      calloc.free(outMsgId);
      calloc.free(outSentAt);
    }
  }

  /// Opens an `ECS1` blob and returns the **authenticated** sender.
  ///
  /// [nowUnixSecs] is wall-clock seconds; `0` disables the freshness window.
  /// Out of the window the core throws `Expired` (13) *after* authenticating,
  /// so "old" is never confused with "forged" — and on `AuthFailed` (11) there
  /// is nothing to fall back to, because the blob carries no declared sender.
  SealedInbound sealedOpen({
    required Uint8List recipientSecret,
    required Uint8List blob,
    required int nowUnixSecs,
  }) {
    _require32(recipientSecret);
    final secretPtr = _copyBytes(recipientSecret);
    final blobPtr = blob.isEmpty ? nullptr : _copyBytes(blob);
    final outPub = calloc<Uint8>(32);
    final outToken = calloc<Uint8>(tokenCap);
    final outMsgId = calloc<Uint8>(sealedMsgIdLen);
    final outSentAt = calloc<Uint64>();
    final outPlain = calloc<Pointer<Uint8>>();
    final outLen = calloc<Size>();
    try {
      _check(
        _sealedOpen(
          secretPtr,
          blobPtr,
          blob.length,
          nowUnixSecs,
          outPub,
          outToken.cast<Char>(),
          tokenCap,
          outMsgId,
          outSentAt,
          outPlain,
          outLen,
        ),
      );
      return (
        senderPublicKey: Uint8List.fromList(outPub.asTypedList(32)),
        senderToken: outToken.cast<Utf8>().toDartString(),
        msgId: Uint8List.fromList(outMsgId.asTypedList(sealedMsgIdLen)),
        sentAtUnix: outSentAt.value,
        plaintext: _takeBuffer(outPlain.value, outLen.value),
      );
    } finally {
      _freeSecret(secretPtr, recipientSecret.length);
      if (blobPtr != nullptr) calloc.free(blobPtr);
      calloc.free(outPub);
      calloc.free(outToken);
      calloc.free(outMsgId);
      calloc.free(outSentAt);
      calloc.free(outPlain);
      calloc.free(outLen);
    }
  }

  /// Shared shape of `encrypt` / `local_seal` / `local_open`.
  ///
  /// Both staging buffers are wiped without asking which call this is: the key
  /// slot is `db_key` for the local pair (the key to the whole store on this
  /// device) and a public key for `encrypt`, and the data slot is the message
  /// body — up to a whole attachment — for two of the three. Branching on which
  /// one is sensitive would be one refactor away from being wrong.
  Uint8List _bufOut(_BufOutDart fn, Uint8List keyOrPub, Uint8List data) {
    final a = _copyBytes(keyOrPub);
    final dataPtr = data.isEmpty ? nullptr : _copyBytes(data);
    final outPtr = calloc<Pointer<Uint8>>();
    final outLen = calloc<Size>();
    try {
      _check(fn(a, dataPtr, data.length, outPtr, outLen));
      return _takeBuffer(outPtr.value, outLen.value);
    } finally {
      _freeSecret(a, keyOrPub.length);
      if (dataPtr != nullptr) _freeSecret(dataPtr, data.length);
      calloc.free(outPtr);
      calloc.free(outLen);
    }
  }

  /// Copies a core-allocated buffer out and wipes the original before freeing.
  ///
  /// Every one of these holds plaintext or key-adjacent material: a decrypted
  /// message, a sealed body, an inbound frame. The allocation is the core's, but
  /// the moment to wipe it is here — `encrypchat_free` is a plain free, so
  /// whatever is still in those pages goes back to the allocator readable.
  Uint8List _takeBuffer(Pointer<Uint8> ptr, int len) {
    final bytes = Uint8List.fromList(ptr.asTypedList(len));
    if (len > 0) ptr.asTypedList(len).fillRange(0, len, 0);
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

  Pointer<Void> _handleOr(int? handleAddress) {
    if (handleAddress == null) return _requireNode();
    if (handleAddress == 0) {
      throw StateError('P2P node not started');
    }
    return Pointer<Void>.fromAddress(handleAddress);
  }

  void _check(int code) {
    if (code != 0) throw CoreException(code);
  }

  void _require32(Uint8List bytes) {
    if (bytes.length != 32) {
      throw CoreException(CoreException.invalidPublicKey, 'expected 32 bytes');
    }
  }

  /// Stages Dart bytes on the native heap for a call.
  ///
  /// The copy is unavoidable — the ABI takes pointers — but its lifetime is not:
  /// anything that held a secret or a plaintext is freed through [_freeSecret].
  /// The *Dart* original is beyond reach: a `Uint8List` lives on the GC heap,
  /// which can move and copy it, so the language offers no way to promise it is
  /// gone. That is the residue [_freeSecret] cannot cover.
  Pointer<Uint8> _copyBytes(Uint8List bytes) {
    final ptr = calloc<Uint8>(bytes.length);
    ptr.asTypedList(bytes.length).setAll(0, bytes);
    return ptr;
  }

  /// `docs/ffi-contract.md`: buffers the caller allocates are the caller's to
  /// wipe. The core zeroizes its own copy of an identity secret; leaving ours
  /// on the native heap would undo that.
  ///
  /// Used for **every** staging buffer that held a secret or a plaintext, not
  /// just the obvious identity secrets: `db_key` opens the whole local store,
  /// and the `data` side of a seal is the message body itself. What this cannot
  /// do is reach the Dart-side copy the caller passed in — see [_copyBytes].
  void _freeSecret(Pointer<Uint8> ptr, int len) {
    if (len > 0) ptr.asTypedList(len).fillRange(0, len, 0);
    calloc.free(ptr);
  }
}
