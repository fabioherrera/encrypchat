import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/chat_message.dart';
import '../models/contact.dart';
import '../models/message_request.dart';

/// The file on disk is encrypted with a key this device cannot derive: the OS
/// secure store lost `db_key`, or the database belongs to another install.
///
/// Deleting the database would be the only way forward, so that decision is the
/// user's, not ours.
class LocalDatabaseKeyException implements Exception {
  const LocalDatabaseKeyException(this.message);

  final String message;

  @override
  String toString() => 'LocalDatabaseKeyException: $message';
}

/// The plaintext database could not be converted *and verified*. Nothing was
/// deleted: the plaintext file is still on disk with every row in it, and the
/// next open retries from scratch.
class LocalDatabaseMigrationException implements Exception {
  const LocalDatabaseMigrationException(this.message, this.reason);

  final String message;

  /// What failed, in structural terms (`row counts`, `integrity_check`, …).
  /// Never carries row contents or key material.
  final String reason;

  @override
  String toString() => 'LocalDatabaseMigrationException($reason): $message';
}

/// Local SQLite for profile / contacts / messages.
///
/// Two independent layers protect it at rest:
///
/// - the file itself is a SQLCipher database (AES-256), so peer tokens,
///   contact names, timestamps and media paths are not readable on disk;
/// - message bodies and media are *also* sealed with AEAD (`local_seal` with
///   [dbKey]), which still holds if the file is ever opened.
class LocalDatabase {
  LocalDatabase({FlutterSecureStorage? storage, DatabaseFactory? factory})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          ),
      _factory = factory;

  /// Where `db_key` lives in the OS secure store. Public because deleting the
  /// identity has to remove it, and it is the entry that decides whether the
  /// bytes left on disk are readable at all — see `IdentityWipe`.
  static const dbKeyStorageKey = 'local_db_key_v1';
  static const _dbName = 'encrypchat_v1.db';

  /// Domain separation between the two layers: SQLCipher gets a subkey derived
  /// from `db_key`, `local_seal` keeps using `db_key` itself. Reusing one key
  /// for two primitives buys nothing, and this way bodies sealed before F10
  /// keep opening with the key already in the secure store — no re-sealing, no
  /// second secret to back up.
  static const _cipherKeyLabel = 'encrypchat/sqlcipher/file-key/v1';

  /// First 15 bytes of every unencrypted SQLite file. A SQLCipher file starts
  /// with its random salt instead, which is what tells a pre-F10 database apart
  /// from an already-encrypted one.
  static const _plaintextMagic = 'SQLite format 3';

  /// The encrypted copy while it is being written, and therefore unverified.
  static const _pendingSuffix = '.encrypting';

  /// Where the plaintext file waits during the swap. Removed only once the
  /// encrypted database is in place.
  static const _parkedSuffix = '.plaintext-backup';

  /// Journal files SQLite keeps next to the database.
  static const _sidecarSuffixes = ['-wal', '-shm', '-journal'];

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

  /// The same SQLite on all four platforms: the FFI factory uses the SQLCipher
  /// build bundled through the `sqlite3` hook (see `pubspec.yaml`). The sqflite
  /// native plugin is deliberately not used on Android/iOS — it talks to the OS
  /// SQLite, which cannot open an encrypted file.
  static void ensureFfiInitialized() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  Future<void> open() async {
    ensureFfiInitialized();
    final factory = _factory ?? databaseFactory;
    final key = await _loadOrCreateDbKey();
    _dbKey = key;

    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final path = p.join(dir.path, _dbName);
    final cipherKey = _cipherKeyHex(key);

    await _finishInterruptedMigration(path);
    if (await _isPlaintextFile(path)) {
      await _encryptFile(factory, path, cipherKey);
    }

    try {
      _db = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 8,
          onConfigure: (db) => _applyKey(db, cipherKey),
          onCreate: (db, version) async {
            await _createV2(db);
            await _upgradeToV3(db);
            await _upgradeToV4(db);
            await _upgradeToV5(db);
            await _upgradeToV6(db);
            await _upgradeToV7(db);
            await _upgradeToV8(db);
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 2) await _upgradeToV2(db);
            if (oldVersion < 3) await _upgradeToV3(db);
            if (oldVersion < 4) await _upgradeToV4(db);
            if (oldVersion < 5) await _upgradeToV5(db);
            if (oldVersion < 6) await _upgradeToV6(db);
            if (oldVersion < 7) await _upgradeToV7(db);
            if (oldVersion < 8) await _upgradeToV8(db);
          },
        ),
      );
    } on DatabaseException catch (e) {
      // SQLCipher accepts any key and only fails on the first read, so a wrong
      // key reads as "not a database". Say that instead of the raw SQLite text.
      if (_readsAsWrongKey(e)) {
        throw const LocalDatabaseKeyException(
          'La base local está cifrada con otra clave. El llavero del sistema '
          'ya no tiene la que la abre (reinstalación, restauración de copia o '
          'borrado de credenciales).',
        );
      }
      rethrow;
    }
  }

  /// SQLCipher takes the key as the first statement on the connection. A raw
  /// 32-byte key (`x'…'`) skips its PBKDF2, which exists for passphrases, not
  /// for keys that already come out of the OS secure store with full entropy.
  static Future<void> _applyKey(DatabaseExecutor db, String cipherKeyHex) =>
      db.execute('PRAGMA key = "x\'$cipherKeyHex\'"');

  static String _cipherKeyHex(Uint8List dbKey) {
    final derived = Hmac(sha256, dbKey).convert(utf8.encode(_cipherKeyLabel));
    return _toHex(Uint8List.fromList(derived.bytes));
  }

  /// A wrong key is `SQLITE_NOTADB`. A corrupt-but-readable file reports
  /// "malformed" instead, and blaming the key for that would send the user
  /// looking in the wrong place.
  static bool _readsAsWrongKey(DatabaseException e) {
    final text = e.toString().toLowerCase();
    return text.contains('not a database') ||
        text.contains('file is encrypted');
  }

  static Future<bool> _isPlaintextFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) return false;
    final handle = await file.open();
    try {
      final head = await handle.read(_plaintextMagic.length);
      if (head.length < _plaintextMagic.length) return false;
      return String.fromCharCodes(head) == _plaintextMagic;
    } finally {
      await handle.close();
    }
  }

  /// A conversion killed mid-swap left either the plaintext file parked aside or
  /// an unverified encrypted copy. Both are recoverable and neither may cost a
  /// message, so this runs before anything else touches the database.
  static Future<void> _finishInterruptedMigration(String path) async {
    final parked = '$path$_parkedSuffix';
    if (!File(path).existsSync() && File(parked).existsSync()) {
      // Died between the two renames: the parked file is the only copy of the
      // data. Put it back and let this open convert it again from scratch.
      await _moveWithSidecars(parked, path, sidecarsFirst: true);
      debugPrint('local db: plaintext file restored after interrupted swap');
      return;
    }
    // The database in place is the authoritative one: a pending copy was never
    // verified, and a parked one is plaintext we promised to remove.
    await _deleteWithSidecars('$path$_pendingSuffix');
    await _deleteWithSidecars(parked);
  }

  /// Converts a pre-F10 plaintext database into a SQLCipher one at the same
  /// path. The plaintext file is only ever deleted after the encrypted copy is
  /// on disk, opens with the key and holds the same rows.
  static Future<void> _encryptFile(
    DatabaseFactory factory,
    String path,
    String cipherKeyHex,
  ) async {
    final pending = '$path$_pendingSuffix';
    await _deleteWithSidecars(pending);

    final exported = await _exportEncrypted(
      factory,
      path,
      pending,
      cipherKeyHex,
    );
    await _verifyExport(factory, pending, cipherKeyHex, exported);

    // Verified: from here on the plaintext file is a spare copy, not the
    // original. Both renames create a name that does not exist yet, so they
    // are a single filesystem operation on POSIX and on Windows alike.
    await _moveWithSidecars(path, '$path$_parkedSuffix', sidecarsFirst: false);
    await File(pending).rename(path);
    await _deleteWithSidecars('$path$_parkedSuffix');
    debugPrint('local db: converted to sqlcipher');
  }

  static Future<({int userVersion, Map<String, int> rowCounts})>
  _exportEncrypted(
    DatabaseFactory factory,
    String path,
    String pending,
    String cipherKeyHex,
  ) async {
    // No key on this connection: SQLCipher reads a plaintext database as long
    // as none is set, which is what makes the export possible at all.
    final source = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      final userVersion = await source.getVersion();
      final rowCounts = await _rowCounts(source);
      await source.execute(
        "ATTACH DATABASE '${_sqlLiteral(pending)}' AS encrypted "
        'KEY "x\'$cipherKeyHex\'"',
      );
      // Copies schema and rows into the encrypted file; `user_version` is not
      // part of that, and losing it would re-run the schema migrations.
      await source.rawQuery("SELECT sqlcipher_export('encrypted')");
      await source.execute('PRAGMA encrypted.user_version = $userVersion');
      await source.execute('DETACH DATABASE encrypted');
      return (userVersion: userVersion, rowCounts: rowCounts);
    } finally {
      await source.close();
    }
  }

  static Future<void> _verifyExport(
    DatabaseFactory factory,
    String pending,
    String cipherKeyHex,
    ({int userVersion, Map<String, int> rowCounts}) expected,
  ) async {
    String? failure;
    Database? db;
    try {
      db = await factory.openDatabase(
        pending,
        options: OpenDatabaseOptions(
          singleInstance: false,
          onConfigure: (db) => _applyKey(db, cipherKeyHex),
        ),
      );
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      final counts = await _rowCounts(db);
      final version = await db.getVersion();
      if (integrity.length != 1 || integrity.first.values.first != 'ok') {
        failure = 'integrity_check';
      } else if (version != expected.userVersion) {
        failure = 'user_version';
      } else if (!_sameCounts(expected.rowCounts, counts)) {
        failure = 'row counts';
      }
    } catch (e) {
      failure = e.runtimeType.toString();
    } finally {
      await db?.close();
    }
    if (failure == null) return;

    await _deleteWithSidecars(pending);
    throw LocalDatabaseMigrationException(
      'No se pudo cifrar la base local. Tus mensajes y contactos siguen '
      'intactos; volveremos a intentarlo.',
      failure,
    );
  }

  /// Every user table and how many rows it holds — the check that the export
  /// carried the data over, including tables from older schema versions.
  static Future<Map<String, int>> _rowCounts(DatabaseExecutor db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    final counts = <String, int>{};
    for (final row in tables) {
      final name = row['name']! as String;
      final result = await db.rawQuery('SELECT COUNT(*) AS c FROM "$name"');
      counts[name] = (result.first['c']! as num).toInt();
    }
    return counts;
  }

  static bool _sameCounts(Map<String, int> expected, Map<String, int> actual) {
    if (expected.length != actual.length) return false;
    for (final entry in expected.entries) {
      if (actual[entry.key] != entry.value) return false;
    }
    return true;
  }

  /// Moves a database file together with any journal SQLite left next to it.
  /// [sidecarsFirst] keeps the crash windows pointing the same way: parking the
  /// plaintext file moves the main file first, restoring it moves the main file
  /// last, so an interrupted move always reads as "the parked copy is the one".
  static Future<void> _moveWithSidecars(
    String from,
    String to, {
    required bool sidecarsFirst,
  }) async {
    if (!sidecarsFirst) await File(from).rename(to);
    for (final suffix in _sidecarSuffixes) {
      final sidecar = File('$from$suffix');
      if (sidecar.existsSync()) await sidecar.rename('$to$suffix');
    }
    if (sidecarsFirst) await File(from).rename(to);
  }

  static Future<void> _deleteWithSidecars(String path) async {
    for (final target in [
      path,
      for (final suffix in _sidecarSuffixes) '$path$suffix',
    ]) {
      final file = File(target);
      if (!file.existsSync()) continue;
      try {
        await file.delete();
      } catch (e) {
        debugPrint('local db: leftover not removed (${e.runtimeType})');
      }
    }
  }

  static String _sqlLiteral(String value) => value.replaceAll("'", "''");

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

  /// Seen sealed-sender message ids, so an authentic relay blob that someone
  /// captured and re-enqueued cannot become a second message. `ECS1` stops
  /// forgery and tampering, not duplication.
  ///
  /// `sent_at_unix` is the timestamp bound inside the blob. It is authenticated
  /// but **sender-chosen**, so since v7 it is kept for diagnostics only and
  /// retention is decided by `received_at_unix`.
  Future<void> _upgradeToV5(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS seen_sealed (
        msg_id TEXT PRIMARY KEY NOT NULL,
        sent_at_unix INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_seen_sealed_sent_at '
      'ON seen_sealed (sent_at_unix)',
    );
  }

  /// Message requests: identities that wrote without being contacts.
  ///
  /// Before this table their messages were stored under their token and shown
  /// nowhere, because the chat list walks `contacts` (F-6). A row here is what
  /// makes such a conversation reachable — and countable, which is what bounds
  /// how much a stranger can leave on the disk.
  Future<void> _upgradeToV6(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS requests (
        peer_token TEXT PRIMARY KEY NOT NULL,
        public_key BLOB,
        first_seen_at TEXT NOT NULL,
        last_seen_at TEXT NOT NULL,
        message_count INTEGER NOT NULL DEFAULT 0,
        via_relay INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// Anti-replay retention moves to a clock this device owns.
  ///
  /// `sent_at_unix` comes from inside the sender's ciphertext: authenticated,
  /// but picked by whoever wrote the blob. Ordering the eviction by it let
  /// anyone enqueue blobs stamped "just now" and push genuine ids — still inside
  /// the 7-day window — out of the table, after which a captured blob is
  /// accepted a second time. Nobody but this device can move `received_at_unix`.
  ///
  /// It also fixes the honest case the old column got wrong: a contact whose
  /// clock runs days behind used to have its ids evicted first, while its blobs
  /// were still perfectly replayable.
  Future<void> _upgradeToV7(Database db) async {
    await db.execute(
      'ALTER TABLE seen_sealed '
      'ADD COLUMN received_at_unix INTEGER NOT NULL DEFAULT 0',
    );
    // Best estimate for rows written before the column existed, and no worse
    // than what v5 pruned by. Leaving them at 0 would forget every id on the
    // first prune and reopen the window for blobs still inside it.
    await db.execute('UPDATE seen_sealed SET received_at_unix = sent_at_unix');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_seen_sealed_received_at '
      'ON seen_sealed (received_at_unix)',
    );
    // Nothing orders by the sender's timestamp any more.
    await db.execute('DROP INDEX IF EXISTS idx_seen_sealed_sent_at');
  }

  /// The index a conversation is read through.
  ///
  /// Until now every read of a thread was a full scan of `messages` plus a sort,
  /// which a single query per chat could absorb. Paging cannot: it asks the same
  /// question once per screenful of scrollback, and the cost of each answer grew
  /// with the whole history, not with the page. The columns are exactly the
  /// ordering [listMessages] pages by, tie-break included.
  Future<void> _upgradeToV8(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_messages_peer_created '
      'ON messages (peer_token, created_at, id)',
    );
  }

  /// Every file this class can leave in [directory]: the database, the journals
  /// SQLite keeps beside it, and the two names a conversion in progress uses.
  ///
  /// Deleting the identity has to remove all of them, and the names belong
  /// here — a second list somewhere else is a leftover waiting to happen.
  static List<String> filePathsIn(Directory directory) {
    final base = p.join(directory.path, _dbName);
    return [
      for (final stem in [
        base,
        '$base$_pendingSuffix',
        '$base$_parkedSuffix',
      ]) ...[stem, for (final suffix in _sidecarSuffixes) '$stem$suffix'],
    ];
  }

  /// Admits one message from a non-contact, or refuses it with the reason.
  ///
  /// The whole decision runs in one transaction: the inbound P2P poll (400 ms)
  /// and the relay pull (8 s) can both be in flight, and two of them reading a
  /// count before either writes would let a flood past the ceiling.
  ///
  /// [publicKey] is only known on the relay route (`sealed_open` returns it). It
  /// is filled in on the first message that carries it and never overwritten
  /// with `null`, so a P2P request that later arrives sealed becomes acceptable.
  Future<RequestAdmission> admitRequestMessage(
    String peerToken, {
    Uint8List? publicKey,
    required bool viaRelay,
    required int maxPeers,
    required int maxPerPeer,
  }) async {
    final token = normalizeToken(peerToken);
    return db.transaction<RequestAdmission>((txn) async {
      final existing = await txn.query(
        'requests',
        where: 'peer_token = ?',
        whereArgs: [token],
        limit: 1,
      );
      final now = DateTime.now().toUtc().toIso8601String();
      if (existing.isEmpty) {
        final counted = await txn.rawQuery(
          'SELECT COUNT(*) AS c FROM requests',
        );
        final pending = (counted.first['c']! as num).toInt();
        if (pending >= maxPeers) return RequestAdmission.inboxFull;
        await txn.insert('requests', {
          'peer_token': token,
          'public_key': publicKey,
          'first_seen_at': now,
          'last_seen_at': now,
          'message_count': 1,
          'via_relay': viaRelay ? 1 : 0,
        });
        return RequestAdmission.admitted;
      }
      final row = existing.first;
      final count = (row['message_count'] as num?)?.toInt() ?? 0;
      if (count >= maxPerPeer) return RequestAdmission.senderFull;
      await txn.update(
        'requests',
        {
          'last_seen_at': now,
          'message_count': count + 1,
          // Null-aware: a route that does not carry the key leaves the column
          // alone instead of clearing one we already learned.
          'public_key': ?publicKey,
          if (viaRelay) 'via_relay': 1,
        },
        where: 'peer_token = ?',
        whereArgs: [token],
      );
      return RequestAdmission.admitted;
    });
  }

  Future<List<MessageRequest>> listRequests() async {
    final rows = await db.query('requests', orderBy: 'last_seen_at DESC');
    return [for (final r in rows) MessageRequest.fromMap(r)];
  }

  /// The pending request whose sender has been quiet the longest, or `null` if
  /// there are none. What gets displaced when a new stranger needs a slot.
  ///
  /// The tie-break is the token, so two requests recorded in the same
  /// millisecond still have one answer and not a coin toss.
  Future<String?> oldestRequestToken() async {
    final rows = await db.query(
      'requests',
      columns: ['peer_token'],
      orderBy: 'last_seen_at ASC, peer_token ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['peer_token']! as String;
  }

  Future<MessageRequest?> requestFor(String peerToken) async {
    final rows = await db.query(
      'requests',
      where: 'peer_token = ?',
      whereArgs: [normalizeToken(peerToken)],
      limit: 1,
    );
    return rows.isEmpty ? null : MessageRequest.fromMap(rows.first);
  }

  Future<void> deleteRequest(String peerToken) async {
    await db.delete(
      'requests',
      where: 'peer_token = ?',
      whereArgs: [normalizeToken(peerToken)],
    );
  }

  /// Sealed media paths, for quota accounting and for deleting a conversation
  /// without leaving orphan files behind.
  Future<List<String>> listMediaRelPaths({String? peerToken}) async {
    final rows = await db.query(
      'messages',
      columns: ['media_relpath'],
      where: peerToken == null
          ? 'media_relpath IS NOT NULL'
          : 'media_relpath IS NOT NULL AND peer_token = ?',
      whereArgs: peerToken == null ? null : [peerToken],
    );
    return [
      for (final r in rows)
        if (r['media_relpath'] != null) r['media_relpath']! as String,
    ];
  }

  Future<int> deleteMessagesFor(String peerToken) async {
    return db.delete(
      'messages',
      where: 'peer_token = ?',
      whereArgs: [peerToken],
    );
  }

  /// Whether this sealed-sender id has already been dealt with.
  ///
  /// Asked **before** the payload is processed; the id itself is written after,
  /// by [recordSeenSealedId] — see `MessagingService.handleRelayBlob` for why
  /// that order is the one that survives a process killed mid-delivery.
  Future<bool> seenSealedId(String msgId) async {
    final rows = await db.query(
      'seen_sealed',
      columns: ['msg_id'],
      where: 'msg_id = ?',
      whereArgs: [msgId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Remembers a sealed-sender id, so the same blob is discarded next time.
  ///
  /// Written once the blob has been **disposed of**: filed as a message, or
  /// refused by a verdict a second delivery cannot change. `false` means the id
  /// was already there, which the caller normally knows from [seenSealedId].
  /// [receivedAtUnix] is this device's clock, and it is what retention is keyed
  /// on; [sentAtUnix] is the sender's claim, stored for diagnostics only.
  Future<bool> recordSeenSealedId(
    String msgId, {
    required int sentAtUnix,
    required int receivedAtUnix,
  }) async {
    final rowId = await db.insert('seen_sealed', {
      'msg_id': msgId,
      'sent_at_unix': sentAtUnix,
      'received_at_unix': receivedAtUnix,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return rowId != 0;
  }

  /// Forgets ids that can no longer be replayed and reports what is left.
  ///
  /// Only one eviction rule is free of consequence: a row whose blob arrived
  /// before [receivedBeforeUnix] is past the freshness window, so the core would
  /// refuse that blob as `Expired` anyway and the id is dead weight.
  ///
  /// Anything **inside** the window is kept, even past the caller's watermark.
  /// Evicting there was the bug: the eviction is reachable by anyone — relay
  /// deposits are not authenticated — so a flood of blobs would push genuine ids
  /// out and hand back a replay. [hardCap] is the last resort so the table
  /// cannot grow without bound; crossing it is a deliberate trade of the window
  /// for bounded disk, it takes an order of magnitude more work than the
  /// watermark did, and [held] is what lets the caller say it happened.
  Future<({int removed, int held})> pruneSeenSealedIds({
    required int receivedBeforeUnix,
    required int hardCap,
  }) async {
    var removed = await db.delete(
      'seen_sealed',
      where: 'received_at_unix < ?',
      whereArgs: [receivedBeforeUnix],
    );
    var held = await seenSealedCount();
    if (held > hardCap) {
      final overflow = await db.rawDelete(
        'DELETE FROM seen_sealed WHERE msg_id IN ('
        'SELECT msg_id FROM seen_sealed '
        'ORDER BY received_at_unix DESC LIMIT -1 OFFSET ?)',
        [hardCap],
      );
      removed += overflow;
      held -= overflow;
    }
    return (removed: removed, held: held);
  }

  Future<int> seenSealedCount() async {
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM seen_sealed');
    return (result.first['c']! as num).toInt();
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

  /// Files an inbound message unless that id is already stored. `false` means
  /// the caller has it already, which is a replay.
  ///
  /// Inbound rows are never *replaced*, and that is a second line of defence
  /// behind `seen_sealed`: `msg_id` is stable across replays and chosen by the
  /// sender, so `REPLACE` gave away two things at once. A replayed blob whose id
  /// the seen-id table had been made to forget would rewrite the row with a
  /// fresh `created_at` and shove an old message to the top of the conversation
  /// (with media, rewriting the file), and a connected peer could overwrite an
  /// earlier message's body — even one in somebody else's thread — just by
  /// reusing its id.
  Future<bool> insertMessageIfNew(ChatMessage message) async {
    final rowId = await db.insert(
      'messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return rowId != 0;
  }

  Future<bool> messageExists(String id) async {
    final rows = await db.query(
      'messages',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> updateMessageStatus(String id, MessageStatus status) async {
    await db.update(
      'messages',
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Oldest-first. With [limit] set, returns the newest `limit` messages (still
  /// oldest-first) so callers can bound what they hold in memory; with [before]
  /// it returns the `limit` messages immediately *older* than that one, which is
  /// what lets a conversation be read one page at a time.
  ///
  /// The cursor is the pair `(created_at, id)` and not an `OFFSET`. An offset is
  /// counted from the newest row, so a message arriving between two pages shifts
  /// every boundary by one and the next page silently repeats a message or skips
  /// one — and messages arriving while the user reads backwards is the normal
  /// case here, not an edge one. The same pair is what the `ORDER BY` uses, so
  /// the cursor and the ordering agree on ties inside the same instant.
  Future<List<ChatMessage>> listMessages(
    String peerToken, {
    int? limit,
    ChatMessage? before,
  }) async {
    if (limit == null && before == null) {
      final rows = await db.query(
        'messages',
        where: 'peer_token = ?',
        whereArgs: [peerToken],
        orderBy: 'created_at ASC, id ASC',
      );
      return [for (final r in rows) ChatMessage.fromMap(r)];
    }
    final cursor = before?.createdAt.toUtc().toIso8601String();
    final rows = await db.query(
      'messages',
      where: cursor == null
          ? 'peer_token = ?'
          : 'peer_token = ? AND (created_at < ? OR (created_at = ? AND id < ?))',
      whereArgs: cursor == null
          ? [peerToken]
          : [peerToken, cursor, cursor, before!.id],
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return [for (final r in rows.reversed) ChatMessage.fromMap(r)];
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
    final existing = await _storage.read(key: dbKeyStorageKey);
    if (existing != null && existing.isNotEmpty) {
      final bytes = _hexToBytes(existing);
      if (bytes.length == 32) return bytes;
    }
    final key = _randomKey();
    await _storage.write(key: dbKeyStorageKey, value: _toHex(key));
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
