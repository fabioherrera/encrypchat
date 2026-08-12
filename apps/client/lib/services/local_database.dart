import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/contact.dart';

/// Local SQLite for profile / contacts / messages.
///
/// **F3 interim at-rest model (pre-SQLCipher):**
/// - Identity secret lives only in OS secure storage.
/// - SQLite file is in the app-private directory and is **not** SQLCipher-encrypted yet.
/// - Message bodies must be ciphertext BLOBs when F4 writes them (never plaintext columns).
/// - A `db_key` is reserved in secure storage for upcoming SQLCipher / AEAD; unused for
///   `PRAGMA key` until vendored libs land (see docs/phase-3.md).
///
/// Do not claim SQLCipher equivalence until `PRAGMA key` (or equivalent AEAD) is wired.
class LocalDatabase {
  LocalDatabase({
    FlutterSecureStorage? storage,
    DatabaseFactory? factory,
  })  : _storage = storage ??
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
        version: 1,
        onCreate: (db, version) async {
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
              ciphertext BLOB NOT NULL,
              created_at TEXT NOT NULL,
              FOREIGN KEY(peer_token) REFERENCES contacts(token)
            )
          ''');
          // Bind metadata proving a db_key exists (not the key itself).
          await db.execute('''
            CREATE TABLE meta (
              key TEXT PRIMARY KEY NOT NULL,
              value TEXT NOT NULL
            )
          ''');
          await db.insert('meta', {
            'key': 'encryption',
            'value': 'interim_secure_storage_identity+app_sandbox_db',
          });
          await db.insert('meta', {
            'key': 'db_key_fingerprint',
            'value': _fingerprint(_dbKey!),
          });
        },
      ),
    );
  }

  Future<void> upsertProfile({
    required String token,
    required Uint8List publicKey,
  }) async {
    await db.insert(
      'profile',
      {
        'id': 1,
        'token': token,
        'public_key': publicKey,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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

  static String _fingerprint(Uint8List key) {
    // One-way tag — never store raw key prefix.
    final digest = sha256.convert(key);
    return digest.toString().substring(0, 16);
  }
}
