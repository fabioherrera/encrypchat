import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/chat_message.dart';
import '../models/contact.dart';

/// Local SQLite for profile / contacts / messages.
///
/// Message bodies are stored as AEAD blobs (`local_seal` with [dbKey]), never plaintext.
class LocalDatabase {
  LocalDatabase({FlutterSecureStorage? storage, DatabaseFactory? factory})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          ),
      _factory = factory;

  static const _dbKeyStorage = 'local_db_key_v1';
  static const _dbName = 'encrypchat_v1.db';

  final FlutterSecureStorage _storage;
  final DatabaseFactory? _factory;
  Database? _db;
  Uint8List? _dbKey;

  Database get db {
    final d = _db;
    if (d == null) throw StateError('LocalDatabase not open');
    return d;
  }

  Uint8List get dbKey {
    final k = _dbKey;
    if (k == null) throw StateError('LocalDatabase not open');
    return k;
  }

  static void ensureFfiInitialized() {
    if (Platform.isLinux || Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  Future<void> open() async {
    ensureFfiInitialized();
    final factory = _factory ?? databaseFactory;
    _dbKey = await _loadOrCreateDbKey();

    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final path = p.join(dir.path, _dbName);

    _db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, version) async {
          await _createV2(db);
          await _upgradeToV3(db);
          await _upgradeToV4(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await _upgradeToV2(db);
          if (oldVersion < 3) await _upgradeToV3(db);
          if (oldVersion < 4) await _upgradeToV4(db);
        },
      ),
    );
  }

  Future<void> _createV2(Database db) async {
    await db.execute('''
      CREATE TABLE profile (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        token TEXT NOT NULL,
        public_key BLOB NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE contacts (
        token TEXT PRIMARY KEY NOT NULL,
        public_key BLOB NOT NULL,
        display_name TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY NOT NULL,
        peer_token TEXT NOT NULL,
        direction TEXT NOT NULL,
        body_sealed BLOB NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE meta (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL
      )
    ''');
    await db.insert('meta', {
      'key': 'encryption',
      'value': 'local_aead_db_key_v1',
    });
  }

  Future<void> _upgradeToV2(Database db) async {
    await db.execute('ALTER TABLE messages RENAME TO messages_old');
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY NOT NULL,
        peer_token TEXT NOT NULL,
        direction TEXT NOT NULL,
        body_sealed BLOB NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    var copied = true;
    try {
      await db.execute('''
        INSERT INTO messages (id, peer_token, direction, body_sealed, status, created_at)
        SELECT id, peer_token, direction, ciphertext, 'sent', created_at FROM messages_old
      ''');
    } catch (e) {
      copied = false;
      debugPrint('db v1→v2 copy failed: ${e.runtimeType}');
    }
    // Keep `messages_old` when the copy failed: dropping it would silently
    // destroy the only remaining copy of those message bodies.
    if (copied) {
      await db.execute('DROP TABLE IF EXISTS messages_old');
    }
    await db.insert('meta', {
      'key': 'encryption',
      'value': 'local_aead_db_key_v1',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _upgradeToV3(Database db) async {
    await db.execute(
      "ALTER TABLE messages ADD COLUMN kind TEXT NOT NULL DEFAULT 'text'",
    );
    await db.execute('ALTER TABLE messages ADD COLUMN mime TEXT');
    await db.execute('ALTER TABLE messages ADD COLUMN media_relpath TEXT');
  }

  /// Blocklist keyed by token, not by contact row: a peer can send frames
  /// without ever being imported as a contact, and deleting the contact must
  /// not silently lift the block.
  Future<void> _upgradeToV4(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS blocked (
        token TEXT PRIMARY KEY NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> upsertProfile({
    required String token,
    required Uint8List publicKey,
  }) async {
    await db.insert('profile', {
      'id': 1,
      'token': token,
      'public_key': publicKey,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Contact>> listContacts() async {
    final rows = await db.query('contacts', orderBy: 'created_at DESC');
    return rows.map((r) => Contact.fromMap(r)).toList();
  }

  Future<void> upsertContact(Contact contact) async {
    await db.insert(
      'contacts',
      contact.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteContact(String token) async {
    await db.delete('contacts', where: 'token = ?', whereArgs: [token]);
  }

  Future<List<String>> listBlockedTokens() async {
    final rows = await db.query('blocked', orderBy: 'created_at DESC');
    return [for (final r in rows) r['token']! as String];
  }

  Future<void> blockToken(String token) async {
    await db.insert('blocked', {
      'token': normalizeToken(token),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> unblockToken(String token) async {
    await db.delete(
      'blocked',
      where: 'token = ?',
      whereArgs: [normalizeToken(token)],
    );
  }

  /// Tokens are case-insensitive hex; store and compare one canonical form so a
  /// block cannot be bypassed by changing the casing of the same identity.
  static String normalizeToken(String token) => token.trim().toLowerCase();

  Future<void> upsertMessage(ChatMessage message) async {
    await db.insert(
      'messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateMessageStatus(String id, MessageStatus status) async {
    await db.update(
      'messages',
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Oldest-first. With [limit] set, returns the newest `limit` messages
  /// (still oldest-first) so callers can bound what they hold in memory.
  Future<List<ChatMessage>> listMessages(String peerToken, {int? limit}) async {
    final rows = await db.query(
      'messages',
      where: 'peer_token = ?',
      whereArgs: [peerToken],
      orderBy: limit == null ? 'created_at ASC' : 'created_at DESC',
      limit: limit,
    );
    final messages = rows.map((r) => ChatMessage.fromMap(r)).toList();
    if (limit != null) {
      return messages.reversed.toList();
    }
    return messages;
  }

  Future<List<({String peerToken, DateTime? lastAt})>> listChatPeers() async {
    final rows = await db.rawQuery('''
      SELECT peer_token, MAX(created_at) AS last_at
      FROM messages
      GROUP BY peer_token
      ORDER BY last_at DESC
    ''');
    return [
      for (final r in rows)
        (
          peerToken: r['peer_token']! as String,
          lastAt: r['last_at'] != null
              ? DateTime.tryParse(r['last_at']! as String)
              : null,
        ),
    ];
  }

  Future<int> messageCount() async {
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM messages');
    if (result.isEmpty) return 0;
    final value = result.first['c'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _dbKey?.fillRange(0, _dbKey!.length, 0);
    _dbKey = null;
  }

  Future<Uint8List> _loadOrCreateDbKey() async {
    final existing = await _storage.read(key: _dbKeyStorage);
    if (existing != null && existing.isNotEmpty) {
      final bytes = _hexToBytes(existing);
      if (bytes.length == 32) return bytes;
    }
    final key = _randomKey();
    await _storage.write(key: _dbKeyStorage, value: _toHex(key));
    return key;
  }

  static Uint8List _randomKey() {
    final rnd = Random.secure();
    return Uint8List.fromList(List<int>.generate(32, (_) => rnd.nextInt(256)));
  }

  static String _toHex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
