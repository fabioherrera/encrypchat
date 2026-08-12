import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/core_error.dart';
import '../core/encrypchat_core.dart';
import '../core/call_signal.dart';
import '../core/media_envelope.dart';
import '../core/wire_frame.dart';
import '../models/chat_message.dart';
import '../models/contact.dart';
import 'identity_service.dart';
import 'local_database.dart';
import 'media_store.dart';
import 'relay_client.dart';

/// Encrypt → P2P send (prefer); on PeerOffline → blind relay; poll inbound + relay pull.
class MessagingService extends ChangeNotifier {
  MessagingService({
    required EncrypchatCore core,
    required IdentityService identity,
    required LocalDatabase database,
    RelayClient? relay,
    MediaStore? mediaStore,
    FlutterSecureStorage? storage,
  }) : _core = core,
       _identity = identity,
       _database = database,
       _relay = relay ?? RelayClient(),
       _media = mediaStore ?? MediaStore(core: core, database: database),
       _storage =
           storage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(encryptedSharedPreferences: true),
           );

  static const _relayUrlKey = 'relay_base_url_v1';

  /// Must stay under relay `MAX_BLOB_BYTES` (256 KiB).
  static const relayMaxBlobBytes = 256 * 1024;

  /// Cache ceilings: plaintext in RAM is bounded, media never is (read on demand).
  static const maxCachedMessagesPerPeer = 200;
  static const maxCachedPeers = 3;

  final EncrypchatCore _core;
  final IdentityService _identity;
  final LocalDatabase _database;
  final RelayClient _relay;
  final MediaStore _media;
  final FlutterSecureStorage _storage;

  Timer? _poll;
  Timer? _relayPoll;
  bool _draining = false;
  bool _pulling = false;
  String? listenAddr;
  String? lastError;
  final Map<String, List<ChatMessage>> _cache = {};

  /// Cached peers, least recently used first.
  final List<String> _cacheLru = [];
  final Map<String, Contact> _contacts = {};

  /// Mirror of the `blocked` table, kept in memory so the inbound hot path can
  /// decide before decrypting. Loaded by [loadBlocked] on every session start.
  final Set<String> _blocked = {};

  /// Demux for call signaling (not persisted as chat).
  void Function(String fromToken, CallSignal signal)? onCallSignal;

  bool get nodeRunning => _core.isNodeRunning;
  bool get relayConfigured => _relay.isConfigured;
  String? get relayBaseUrl => _relay.baseUrl;

  /// Relay configured over plain HTTP: blobs stay E2EE but token/pubkey/proof
  /// travel in the clear. Surfaced in the UI, not blocked (LAN demos need it).
  bool get relayIsInsecure => _relay.isInsecure;

  void setContacts(List<Contact> contacts) {
    _contacts
      ..clear()
      ..addEntries(contacts.map((c) => MapEntry(c.token, c)));
  }

  Contact? contactForToken(String token) => _contacts[token];

  /// Tokens blocked on this device, newest first.
  List<String> get blockedTokens => List.unmodifiable(_blocked);

  bool isBlocked(String token) =>
      _blocked.contains(LocalDatabase.normalizeToken(token));

  Future<void> loadBlocked() async {
    final tokens = await _database.listBlockedTokens();
    _blocked
      ..clear()
      ..addAll(tokens.map(LocalDatabase.normalizeToken));
    _syncBlockedToCore();
    notifyListeners();
  }

  /// Mirrors the list into the core, which refuses a blocked token at the
  /// handshake and on send (defence in depth).
  ///
  /// Best effort **on purpose**: the enforcing layer is this class — see the
  /// cut in [handleInboundFrame] — and a core that refuses the update must not
  /// stop the user from blocking someone, so a failure is logged and swallowed.
  void _syncBlockedToCore() {
    if (!_core.isNodeRunning) return;
    // One malformed entry makes the core reject the whole list and keep the
    // previous (stale) one, so a junk row cannot be allowed to disable the
    // mirror for every other token. Dart-side blocking still covers it.
    final tokens = _blocked.where(isValidToken).toList(growable: false);
    if (tokens.length != _blocked.length) {
      debugPrint(
        'core blocklist: ${_blocked.length - tokens.length} token(s) skipped',
      );
    }
    try {
      _core.nodeSetBlockedTokens(tokens);
    } catch (e) {
      debugPrint('core blocklist sync failed: ${e.runtimeType}');
    }
  }

  /// Blocking is local and unilateral: the peer is never told. It drops
  /// everything that identity sends — text, media and call signaling — and
  /// stops this device from sending to it.
  Future<void> block(String token) async {
    final normalized = LocalDatabase.normalizeToken(token);
    await _database.blockToken(normalized);
    _blocked.add(normalized);
    _syncBlockedToCore();
    notifyListeners();
  }

  Future<void> unblock(String token) async {
    final normalized = LocalDatabase.normalizeToken(token);
    await _database.unblockToken(normalized);
    _blocked.remove(normalized);
    _syncBlockedToCore();
    notifyListeners();
  }

  Future<void> loadRelayUrl() async {
    final url = await _storage.read(key: _relayUrlKey);
    _relay.baseUrl = (url != null && url.trim().isNotEmpty) ? url.trim() : null;
    notifyListeners();
  }

  Future<void> setRelayBaseUrl(String? url) async {
    final trimmed = url?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await _storage.delete(key: _relayUrlKey);
      _relay.baseUrl = null;
    } else {
      await _storage.write(key: _relayUrlKey, value: trimmed);
      _relay.baseUrl = trimmed;
    }
    notifyListeners();
  }

  Future<void> startNode({int listenPort = 0}) async {
    await loadRelayUrl();
    if (_core.isNodeRunning) return;
    _core.nodeStart(secret: _identity.requireSecret(), listenPort: listenPort);
    // The core-side list is empty after every start, so this is the one sync
    // that cannot be skipped: without it a restart silently drops the mirror.
    _syncBlockedToCore();
    listenAddr = _core.nodeListenAddr();
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 400), (_) {
      unawaited(_drainInbound());
    });
    _relayPoll?.cancel();
    _relayPoll = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(pullFromRelay());
    });
    unawaited(pullFromRelay());
    notifyListeners();
  }

  Future<void> stopNode() async {
    _poll?.cancel();
    _poll = null;
    _relayPoll?.cancel();
    _relayPoll = null;
    _core.nodeStop();
    listenAddr = null;
    notifyListeners();
  }

  Future<void> connectHostPort(String host, int port) async {
    lastError = null;
    try {
      _core.nodeConnectHostPort(host.trim(), port);
      notifyListeners();
    } catch (e) {
      lastError = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> connectMultiaddr(String multiaddr) async {
    lastError = null;
    try {
      _core.nodeConnect(multiaddr.trim());
      notifyListeners();
    } catch (e) {
      lastError = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<List<ChatMessage>> messagesFor(String peerToken) async {
    final cached = _cache[peerToken];
    if (cached != null) {
      _touchCache(peerToken);
      return List.unmodifiable(cached);
    }
    final rows = await _database.listMessages(
      peerToken,
      limit: maxCachedMessagesPerPeer,
    );
    final opened = <ChatMessage>[];
    for (final m in rows) {
      try {
        if (m.isMedia) {
          String? caption;
          try {
            caption = _openCaption(m);
          } catch (e) {
            // Distinct from "no caption": the sealed body exists but did not open.
            debugPrint('open caption failed: ${e.runtimeType}');
            opened.add(
              m.copyWith(
                plaintext: '«adjunto: nombre ilegible»',
                status: MessageStatus.error,
              ),
            );
            continue;
          }
          opened.add(m.copyWith(plaintext: caption ?? m.mime));
        } else {
          final text = _core.openUtf8(
            dbKey: _database.dbKey,
            sealed: m.bodySealed,
          );
          opened.add(m.copyWith(plaintext: text));
        }
      } catch (e) {
        debugPrint('open message failed: ${e.runtimeType}');
        opened.add(
          m.copyWith(
            plaintext: '«no se pudo abrir»',
            status: MessageStatus.error,
          ),
        );
      }
    }
    _cache[peerToken] = opened;
    _touchCache(peerToken);
    return List.unmodifiable(opened);
  }

  /// Sealed media read on demand for the UI. Bytes are never cached here.
  Future<Uint8List> mediaBytesFor(ChatMessage message) {
    final rel = message.mediaRelPath;
    if (!message.isMedia || rel == null) {
      throw StateError('El mensaje no tiene adjunto');
    }
    return _media.readSealed(rel);
  }

  Future<void> refreshPeer(String peerToken) async {
    _cache.remove(peerToken);
    _cacheLru.remove(peerToken);
    await messagesFor(peerToken);
    notifyListeners();
  }

  /// Caption is optional: `null` means "no caption", a throw means the sealed
  /// body could not be opened (rotated `db_key`, corrupt row) and must surface.
  String? _openCaption(ChatMessage message) {
    final caption = _core.openUtf8(
      dbKey: _database.dbKey,
      sealed: message.bodySealed,
    );
    return caption.isEmpty ? null : caption;
  }

  void _touchCache(String peerToken) {
    _cacheLru
      ..remove(peerToken)
      ..add(peerToken);
    while (_cacheLru.length > maxCachedPeers) {
      _cache.remove(_cacheLru.removeAt(0));
    }
  }

  Future<ChatMessage> sendText({
    required Contact peer,
    required String text,
  }) async {
    _assertNotBlocked(peer.token);
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw CoreException(CoreException.emptyPlaintext);
    }
    if (!_core.isNodeRunning) {
      throw StateError('Nodo P2P no iniciado');
    }

    final id = _newId();
    final sealed = _core.localSeal(
      dbKey: _database.dbKey,
      plaintext: Uint8List.fromList(utf8.encode(trimmed)),
    );
    var message = ChatMessage(
      id: id,
      peerToken: peer.token,
      direction: MessageDirection.outbound,
      bodySealed: sealed,
      status: MessageStatus.sending,
      createdAt: DateTime.now().toUtc(),
      plaintext: trimmed,
    );
    await _database.upsertMessage(message);
    _pushCache(message);
    notifyListeners();

    final ciphertext = _core.encryptUtf8(
      recipientPublicKey: peer.publicKey,
      plaintext: trimmed,
    );
    final frame = WireFrame.create(
      senderToken: _identity.token!,
      ciphertext: ciphertext,
      msgId: _idToBytes(id),
    );
    final encoded = frame.encode();

    try {
      _core.nodeSend(peerToken: peer.token, frame: encoded);
      message = message.copyWith(status: MessageStatus.delivered);
      await _database.updateMessageStatus(id, MessageStatus.delivered);
      _pushCache(message);
      notifyListeners();
      return message;
    } on CoreException catch (e) {
      if (e.code == CoreException.peerOffline && _relay.isConfigured) {
        try {
          // Relay blob = E2EE only (no cleartext sender_token on wire to relay).
          final relayPayload = jsonEncode({
            'v': 1,
            'from': _identity.token,
            'body': trimmed,
          });
          final blob = _core.encryptUtf8(
            recipientPublicKey: peer.publicKey,
            plaintext: relayPayload,
          );
          await _relay.enqueue(destToken: peer.token, blob: blob);
          message = message.copyWith(status: MessageStatus.viaRelay);
          await _database.updateMessageStatus(id, MessageStatus.viaRelay);
          _pushCache(message);
          notifyListeners();
          return message;
        } catch (re) {
          message = message.copyWith(
            status: MessageStatus.error,
            error: 'P2P offline y relay falló: $re',
          );
          await _database.updateMessageStatus(id, MessageStatus.error);
          _pushCache(message);
          notifyListeners();
          throw StateError(message.error!);
        }
      }
      message = message.copyWith(
        status: MessageStatus.error,
        error: switch (e.code) {
          CoreException.peerOffline =>
            'Peer offline (configurá relay en Chats → ☁)',
          CoreException.peerBlocked => blockedMessage,
          _ => e.toString(),
        },
      );
      await _database.updateMessageStatus(id, MessageStatus.error);
      _pushCache(message);
      notifyListeners();
      if (e.code == CoreException.peerBlocked) {
        // The core caught what this class should have caught first: report it
        // as the block it is, not as a raw error code.
        throw StateError(blockedMessage);
      }
      rethrow;
    }
  }

  /// Send an image/file (E2EE). Prefers P2P; relay only if ciphertext ≤ 256 KiB.
  Future<ChatMessage> sendMedia({
    required Contact peer,
    required Uint8List bytes,
    required String mime,
    required String name,
  }) async {
    _assertNotBlocked(peer.token);
    if (!_core.isNodeRunning) {
      throw StateError('Nodo P2P no iniciado');
    }
    if (bytes.isEmpty) {
      throw CoreException(CoreException.emptyPlaintext);
    }
    final envelope = MediaEnvelope(mime: mime, name: name, data: bytes);
    final plain = envelope.encode();

    final id = _newId();
    final rel = await _media.writeSealed(id: id, plaintextBytes: bytes);
    final captionSealed = _core.localSeal(
      dbKey: _database.dbKey,
      plaintext: Uint8List.fromList(utf8.encode(name)),
    );
    var message = ChatMessage(
      id: id,
      peerToken: peer.token,
      direction: MessageDirection.outbound,
      bodySealed: captionSealed,
      status: MessageStatus.sending,
      createdAt: DateTime.now().toUtc(),
      kind: MessageKind.media,
      mime: mime,
      mediaRelPath: rel,
      plaintext: name,
    );
    await _database.upsertMessage(message);
    _pushCache(message);
    notifyListeners();

    final ciphertext = _core.encrypt(
      recipientPublicKey: peer.publicKey,
      plaintext: plain,
    );
    final frame = WireFrame.create(
      senderToken: _identity.token!,
      ciphertext: ciphertext,
      msgId: _idToBytes(id),
    );

    try {
      _core.nodeSend(peerToken: peer.token, frame: frame.encode());
      message = message.copyWith(status: MessageStatus.delivered);
      await _database.updateMessageStatus(id, MessageStatus.delivered);
      _pushCache(message);
      notifyListeners();
      return message;
    } on CoreException catch (e) {
      if (e.code == CoreException.peerOffline && _relay.isConfigured) {
        final relayPayload = utf8.encode(
          jsonEncode({
            'v': 2,
            'from': _identity.token,
            'kind': 'media',
            'mime': mime,
            'name': name,
            'data_b64': base64Encode(bytes),
          }),
        );
        final blob = _core.encrypt(
          recipientPublicKey: peer.publicKey,
          plaintext: Uint8List.fromList(relayPayload),
        );
        if (blob.length > relayMaxBlobBytes) {
          message = message.copyWith(
            status: MessageStatus.error,
            error:
                'Adjunto (${blob.length} B cifrado) supera el límite del relay '
                '(${relayMaxBlobBytes} B). Conectá P2P o comprimí la imagen.',
          );
          await _database.updateMessageStatus(id, MessageStatus.error);
          _pushCache(message);
          notifyListeners();
          throw StateError(message.error!);
        }
        try {
          await _relay.enqueue(destToken: peer.token, blob: blob);
          message = message.copyWith(status: MessageStatus.viaRelay);
          await _database.updateMessageStatus(id, MessageStatus.viaRelay);
          _pushCache(message);
          notifyListeners();
          return message;
        } catch (re) {
          message = message.copyWith(
            status: MessageStatus.error,
            error: 'Relay falló: $re',
          );
          await _database.updateMessageStatus(id, MessageStatus.error);
          _pushCache(message);
          notifyListeners();
          rethrow;
        }
      }
      message = message.copyWith(
        status: MessageStatus.error,
        error: switch (e.code) {
          CoreException.peerOffline =>
            'Peer offline — adjuntos grandes requieren P2P o relay ≤256KiB',
          CoreException.peerBlocked => blockedMessage,
          _ => e.toString(),
        },
      );
      await _database.updateMessageStatus(id, MessageStatus.error);
      _pushCache(message);
      notifyListeners();
      if (e.code == CoreException.peerBlocked) {
        throw StateError(blockedMessage);
      }
      rethrow;
    }
  }

  /// E2EE call signaling (not stored in chat DB).
  ///
  /// **P2P-only, both directions.** The relay does not authenticate the sender,
  /// so a relayed `invite`/`sdp-offer` could impersonate a contact and obtain
  /// mic/camera on accept. Re-enable only after relay sender-auth (F5 P0);
  /// [_handleRelayBlob] drops inbound call signals for the same reason.
  Future<void> sendCallSignal({
    required Contact peer,
    required CallSignal signal,
  }) async {
    _assertNotBlocked(peer.token);
    if (!_core.isNodeRunning) {
      throw StateError('Nodo P2P no iniciado');
    }
    final plain = signal.encode();
    final ciphertext = _core.encrypt(
      recipientPublicKey: peer.publicKey,
      plaintext: plain,
    );
    final frame = WireFrame.create(
      senderToken: _identity.token!,
      ciphertext: ciphertext,
      msgId: _idToBytes(_newId()),
    );
    try {
      _core.nodeSend(peerToken: peer.token, frame: frame.encode());
    } on CoreException catch (e) {
      if (e.code == CoreException.peerBlocked) throw StateError(blockedMessage);
      if (e.code != CoreException.peerOffline) rethrow;
      throw StateError(
        'Llamadas requieren peer P2P online (relay diferido hasta auth de remitente)',
      );
    }
  }

  Future<void> pullFromRelay() async {
    if (!_relay.isConfigured || _pulling) return;
    _pulling = true;
    try {
      final token = _identity.token!;
      final ch = await _relay.challenge(destToken: token);
      final proof = _core.popProof(
        secret: _identity.requireSecret(),
        ephPubkey: ch.ephPubkey,
        nonce: ch.nonce,
        destToken: token,
      );
      final blobs = await _relay.pull(
        destToken: token,
        publicKey: _identity.publicKey!,
        proof: proof,
      );
      for (final blob in blobs) {
        try {
          await handleRelayBlob(blob);
        } catch (e) {
          // Blobs are already deleted relay-side: one bad blob must not drop the rest.
          debugPrint('relay blob dropped: ${e.runtimeType}');
        }
      }
    } catch (e) {
      // Never interpolate the exception: FormatException embeds a fragment of the
      // decrypted source, and debugPrint survives release builds.
      debugPrint('relay pull failed: ${e.runtimeType}');
    } finally {
      _pulling = false;
    }
  }

  @visibleForTesting
  Future<void> handleRelayBlob(Uint8List blob) async {
    final plaintext = _core.decrypt(
      secret: _identity.requireSecret(),
      ciphertext: blob,
    );
    if (MediaEnvelope.looksLike(plaintext)) {
      // Relay payloads are always the JSON v1/v2 envelope, which carries `from`.
      // A bare EM01 has no sender, and inventing one would create a phantom chat.
      throw const FormatException('EM01 crudo por relay: sin remitente');
    }
    final map = jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
    final from = map['from'] as String? ?? '';
    if (from.isEmpty) throw const FormatException('from vacío');
    if (isBlocked(from)) {
      // The relay already dropped the blob on pull, so discarding it here is
      // the end of the line: nothing is persisted and nothing is shown.
      debugPrint('relay blob dropped: blocked sender');
      return;
    }
    if (map['kind'] == 'call') {
      // Relay does not authenticate the sender: a forged `from` would ring as a
      // known contact and hand over mic/camera on accept. Drop until F5 P0.
      debugPrint('relay: call signal dropped (P2P-only policy)');
      return;
    }
    if (map['kind'] == 'media') {
      final mime = map['mime'] as String? ?? 'application/octet-stream';
      final name = map['name'] as String? ?? 'file';
      final data = base64Decode(map['data_b64'] as String);
      await _persistInboundMedia(
        peerToken: from,
        mime: mime,
        name: name,
        bytes: data,
        viaRelay: true,
      );
      return;
    }
    final body = map['body'] as String? ?? '';
    if (body.isEmpty) throw const FormatException('body vacío');
    final sealed = _core.localSeal(
      dbKey: _database.dbKey,
      plaintext: Uint8List.fromList(utf8.encode(body)),
    );
    final message = ChatMessage(
      id: _newId(),
      peerToken: from,
      direction: MessageDirection.inbound,
      bodySealed: sealed,
      status: MessageStatus.viaRelay,
      createdAt: DateTime.now().toUtc(),
      plaintext: body,
    );
    await _database.upsertMessage(message);
    _pushCache(message);
    notifyListeners();
  }

  Future<void> _drainInbound() async {
    if (!_core.isNodeRunning || _draining) return;
    _draining = true;
    try {
      while (true) {
        Uint8List? raw;
        try {
          raw = _core.nodeTryRecv();
        } catch (e) {
          debugPrint('inbound poll failed: ${e.runtimeType}');
          return;
        }
        if (raw == null) break;
        try {
          await handleInboundFrame(raw);
        } catch (e) {
          // One malformed frame must not stop the queue from draining.
          debugPrint('inbound frame dropped: ${e.runtimeType}');
        }
      }
    } finally {
      _draining = false;
    }
  }

  @visibleForTesting
  Future<void> handleInboundFrame(Uint8List raw) async {
    final frame = WireFrame.decode(raw);
    if (isBlocked(frame.senderToken)) {
      // Single cut for every payload type: text, media (EM01) and call
      // signaling all arrive as one frame, and the sender is known before the
      // ciphertext is opened. Nothing is decrypted, stored or rung.
      debugPrint('inbound frame dropped: blocked sender');
      return;
    }
    final plain = _core.decrypt(
      secret: _identity.requireSecret(),
      ciphertext: frame.ciphertext,
    );
    if (MediaEnvelope.looksLike(plain)) {
      final env = MediaEnvelope.decode(plain);
      await _persistInboundMedia(
        peerToken: frame.senderToken,
        mime: env.mime,
        name: env.name,
        bytes: env.data,
        viaRelay: false,
        msgId: _bytesToId(frame.msgId),
      );
      return;
    }
    if (CallSignal.looksLike(plain)) {
      final signal = CallSignal.decode(plain);
      onCallSignal?.call(frame.senderToken, signal);
      return;
    }
    final text = utf8.decode(plain);
    final sealed = _core.localSeal(
      dbKey: _database.dbKey,
      plaintext: Uint8List.fromList(utf8.encode(text)),
    );
    final id = _bytesToId(frame.msgId);
    final message = ChatMessage(
      id: id,
      peerToken: frame.senderToken,
      direction: MessageDirection.inbound,
      bodySealed: sealed,
      status: MessageStatus.delivered,
      createdAt: DateTime.now().toUtc(),
      plaintext: text,
    );
    await _database.upsertMessage(message);
    _pushCache(message);
    notifyListeners();
  }

  Future<void> _persistInboundMedia({
    required String peerToken,
    required String mime,
    required String name,
    required Uint8List bytes,
    required bool viaRelay,
    String? msgId,
  }) async {
    final id = msgId ?? _newId();
    final rel = await _media.writeSealed(id: id, plaintextBytes: bytes);
    final captionSealed = _core.localSeal(
      dbKey: _database.dbKey,
      plaintext: Uint8List.fromList(utf8.encode(name)),
    );
    final message = ChatMessage(
      id: id,
      peerToken: peerToken,
      direction: MessageDirection.inbound,
      bodySealed: captionSealed,
      status: viaRelay ? MessageStatus.viaRelay : MessageStatus.delivered,
      createdAt: DateTime.now().toUtc(),
      kind: MessageKind.media,
      mime: mime,
      mediaRelPath: rel,
      plaintext: name,
    );
    await _database.upsertMessage(message);
    _pushCache(message);
    notifyListeners();
  }

  /// Updates an already-cached conversation. A cold conversation is left alone:
  /// seeding it with a single message would make a partial list look complete.
  void _pushCache(ChatMessage message) {
    final list = _cache[message.peerToken];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == message.id);
    if (idx >= 0) {
      list[idx] = message;
    } else {
      list.add(message);
    }
    if (list.length > maxCachedMessagesPerPeer) {
      list.removeRange(0, list.length - maxCachedMessagesPerPeer);
    }
    _touchCache(message.peerToken);
  }

  /// Shown wherever a send is refused for a blocked peer, no matter which of
  /// the two layers cut it: this class up front, or the core with `PeerBlocked`.
  static const blockedMessage =
      'Contacto bloqueado: desbloqueálo para volver a escribirle o llamarlo.';

  void _assertNotBlocked(String token) {
    if (isBlocked(token)) {
      throw StateError(blockedMessage);
    }
  }

  static String _newId() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static Uint8List _idToBytes(String id) {
    try {
      final decoded = base64Url.decode(base64Url.normalize(id));
      if (decoded.length >= 16) {
        return Uint8List.fromList(decoded.sublist(0, 16));
      }
    } catch (_) {}
    final out = Uint8List(16);
    final src = utf8.encode(id);
    for (var i = 0; i < 16; i++) {
      out[i] = i < src.length ? src[i] : 0;
    }
    return out;
  }

  static String _bytesToId(Uint8List bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  @override
  void dispose() {
    _poll?.cancel();
    _relayPoll?.cancel();
    _relay.close();
    if (_core.isNodeRunning) {
      _core.nodeStop();
    }
    super.dispose();
  }
}
