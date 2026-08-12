import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../core/core_error.dart';
import '../core/encrypchat_core.dart';
import '../core/wire_frame.dart';
import '../models/chat_message.dart';
import '../models/contact.dart';
import 'identity_service.dart';
import 'local_database.dart';

/// Encrypt → frame → P2P send; poll inbound; seal bodies with db_key.
class MessagingService extends ChangeNotifier {
  MessagingService({
    required EncrypchatCore core,
    required IdentityService identity,
    required LocalDatabase database,
  })  : _core = core,
        _identity = identity,
        _database = database;

  final EncrypchatCore _core;
  final IdentityService _identity;
  final LocalDatabase _database;

  Timer? _poll;
  String? listenAddr;
  String? lastError;
  final Map<String, List<ChatMessage>> _cache = {};

  bool get nodeRunning => _core.isNodeRunning;

  Future<void> startNode({int listenPort = 0}) async {
    if (_core.isNodeRunning) return;
    _core.nodeStart(
      secret: _identity.requireSecret(),
      listenPort: listenPort,
    );
    listenAddr = _core.nodeListenAddr();
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 400), (_) {
      unawaited(_drainInbound());
    });
    notifyListeners();
  }

  Future<void> stopNode() async {
    _poll?.cancel();
    _poll = null;
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
    if (_cache.containsKey(peerToken)) {
      return List.unmodifiable(_cache[peerToken]!);
    }
    final rows = await _database.listMessages(peerToken);
    final opened = <ChatMessage>[];
    for (final m in rows) {
      try {
        final text = _core.openUtf8(dbKey: _database.dbKey, sealed: m.bodySealed);
        opened.add(m.copyWith(plaintext: text));
      } catch (_) {
        opened.add(m.copyWith(plaintext: '«no se pudo abrir»', status: MessageStatus.error));
      }
    }
    _cache[peerToken] = opened;
    return List.unmodifiable(opened);
  }

  Future<void> refreshPeer(String peerToken) async {
    _cache.remove(peerToken);
    await messagesFor(peerToken);
    notifyListeners();
  }

  Future<ChatMessage> sendText({
    required Contact peer,
    required String text,
  }) async {
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

    try {
      final ciphertext = _core.encryptUtf8(
        recipientPublicKey: peer.publicKey,
        plaintext: trimmed,
      );
      final frame = WireFrame.create(
        senderToken: _identity.token!,
        ciphertext: ciphertext,
        msgId: _idToBytes(id),
      );
      _core.nodeSend(peerToken: peer.token, frame: frame.encode());
      message = message.copyWith(status: MessageStatus.delivered);
      await _database.updateMessageStatus(id, MessageStatus.delivered);
      _replaceCache(message);
      notifyListeners();
      return message;
    } on CoreException catch (e) {
      final status =
          e.code == CoreException.peerOffline ? MessageStatus.error : MessageStatus.error;
      message = message.copyWith(
        status: status,
        error: e.code == CoreException.peerOffline
            ? 'Peer offline o no conectado'
            : e.toString(),
      );
      await _database.updateMessageStatus(id, MessageStatus.error);
      _replaceCache(message);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _drainInbound() async {
    if (!_core.isNodeRunning) return;
    try {
      while (true) {
        final raw = _core.nodeTryRecv();
        if (raw == null) break;
        await _handleInboundFrame(raw);
      }
    } catch (e, st) {
      debugPrint('inbound poll error: $e\n$st');
    }
  }

  Future<void> _handleInboundFrame(Uint8List raw) async {
    final frame = WireFrame.decode(raw);
    final plaintext = _core.decryptUtf8(
      secret: _identity.requireSecret(),
      ciphertext: frame.ciphertext,
    );
    final sealed = _core.localSeal(
      dbKey: _database.dbKey,
      plaintext: Uint8List.fromList(utf8.encode(plaintext)),
    );
    final id = _bytesToId(frame.msgId);
    final message = ChatMessage(
      id: id,
      peerToken: frame.senderToken,
      direction: MessageDirection.inbound,
      bodySealed: sealed,
      status: MessageStatus.delivered,
      createdAt: DateTime.now().toUtc(),
      plaintext: plaintext,
    );
    await _database.upsertMessage(message);
    _pushCache(message);
    notifyListeners();
  }

  void _pushCache(ChatMessage message) {
    final list = _cache.putIfAbsent(message.peerToken, () => []);
    final idx = list.indexWhere((m) => m.id == message.id);
    if (idx >= 0) {
      list[idx] = message;
    } else {
      list.add(message);
    }
  }

  void _replaceCache(ChatMessage message) => _pushCache(message);

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
    if (_core.isNodeRunning) {
      _core.nodeStop();
    }
    super.dispose();
  }
}
