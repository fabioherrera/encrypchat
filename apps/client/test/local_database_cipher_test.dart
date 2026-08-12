import 'dart:io';
import 'dart:math';

import 'package:encrypchat/core/encrypchat_core.dart';
import 'package:encrypchat/models/chat_message.dart';
import 'package:encrypchat/models/contact.dart';
import 'package:encrypchat/services/local_database.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The database file used to be plain SQLite: anyone with the disk could read
/// who the user talks to, when, and where the media went, even though bodies
/// were sealed. These tests pin the file being SQLCipher now, and — the part
/// that can actually cost data — that converting an existing plaintext database
/// never loses a row, however badly the process dies while doing it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// First bytes of any unencrypted SQLite file.
  const plaintextMagic = 'SQLite format 3';

  late Directory tempDir;
  late Map<String, String> secureValues;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('encrypchat_cipher');
    _mockPathProvider(tempDir);
    secureValues = _mockSecureStorage();
    dbPath = p.join(tempDir.path, 'encrypchat_v1.db');
    LocalDatabase.ensureFfiInitialized();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<LocalDatabase> openLocal() async {
    final db = LocalDatabase(storage: const FlutterSecureStorage());
    await db.open();
    return db;
  }

  Future<String> fileMagic(String path) async {
    final head = await File(path).openRead(0, plaintextMagic.length).first;
    return String.fromCharCodes(head);
  }

  test(
    'a fresh database is a SQLCipher file, not a readable SQLite one',
    () async {
      final db = await openLocal();
      await db.upsertContact(_contact('Bruja'));
      await db.close();

      expect(await fileMagic(dbPath), isNot(plaintextMagic));
      // What `sqlite3 encrypchat_v1.db` would do: open it and read the schema.
      await expectLater(_readWithoutKey(dbPath), throwsA(isA<Exception>()));
    },
  );

  test('the file key is not the key that seals message bodies', () async {
    final db = await openLocal();
    await db.close();

    // `db_key` still opens the bodies, so it must not also open the file:
    // one compromised layer should not hand over the other.
    final bodyKey = secureValues['local_db_key_v1']!;
    await expectLater(_readWithKey(dbPath, bodyKey), throwsA(isA<Exception>()));
  });

  test(
    'an existing plaintext database is migrated with every row intact',
    () async {
      final core = EncrypchatCore.open();
      // The key that sealed the bodies before this phase existed.
      secureValues['local_db_key_v1'] = _randomHex();
      final bodyKey = _hexToBytes(secureValues['local_db_key_v1']!);
      final sealed = core.localSeal(
        dbKey: bodyKey,
        plaintext: Uint8List.fromList('hola desde antes de F10'.codeUnits),
      );
      final ana = _contact('Ana');
      final beto = _contact('Beto');

      await _seedPlaintextV4(
        dbPath,
        contacts: [ana, beto],
        messages: [
          _messageRow(id: 'm1', peer: ana.token, sealed: sealed),
          _messageRow(id: 'm2', peer: ana.token, sealed: sealed),
          _messageRow(
            id: 'm3',
            peer: beto.token,
            sealed: sealed,
            kind: 'media',
          ),
        ],
        blocked: [beto.token],
      );
      expect(await fileMagic(dbPath), plaintextMagic);

      final db = await openLocal();

      expect(await fileMagic(dbPath), isNot(plaintextMagic));
      expect(
        (await db.listContacts()).map((c) => c.displayName),
        unorderedEquals(['Ana', 'Beto']),
      );
      expect(await db.messageCount(), 3);
      expect((await db.listMessages(ana.token)).map((m) => m.id), ['m1', 'm2']);
      expect(await db.listBlockedTokens(), [beto.token]);
      expect((await db.db.query('profile')).single['token'], 'ec_perfil');
      final media = (await db.listMessages(beto.token)).single;
      expect(media.kind, MessageKind.media);
      expect(media.mediaRelPath, 'media/m3.bin');

      // The inner layer still opens with the same `db_key`: the file key is
      // derived from it, so nothing had to be re-sealed.
      expect(
        core.openUtf8(dbKey: db.dbKey, sealed: media.bodySealed),
        'hola desde antes de F10',
      );

      await db.close();
      expect(await _leftovers(dbPath), isEmpty);
    },
  );

  test(
    'a plaintext database on an older schema still runs its upgrades',
    () async {
      final ana = _contact('Ana');
      await _seedPlaintextV2(dbPath, contacts: [ana], messageIds: ['m1', 'm2']);

      final db = await openLocal();

      // Converted first, then upgraded v2 → v8 on the encrypted file.
      expect(await db.db.getVersion(), 8);
      expect(await db.messageCount(), 2);
      // v8 is the index a conversation is paged through. A database that
      // arrives from an older version without it reads every page by scanning
      // the whole table.
      expect(
        await db.db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name = 'idx_messages_peer_created'",
        ),
        hasLength(1),
      );
      expect((await db.listMessages(ana.token)).first.kind, MessageKind.text);
      expect(await db.listBlockedTokens(), isEmpty);
      expect(await db.listRequests(), isEmpty);
      await db.blockToken(ana.token);
      expect(await db.listBlockedTokens(), [ana.token]);
      await db.close();
    },
  );

  test('a swap interrupted between the two renames keeps the data', () async {
    final ana = _contact('Ana');
    await _seedPlaintextV4(
      dbPath,
      contacts: [ana],
      messages: [_messageRow(id: 'm1', peer: ana.token)],
    );
    // Exactly what the process leaves behind if it dies after parking the
    // plaintext file and before the encrypted copy takes its place.
    await File(dbPath).rename('$dbPath.plaintext-backup');
    await File('$dbPath.encrypting').writeAsBytes(_garbage());
    expect(File(dbPath).existsSync(), isFalse);

    final db = await openLocal();

    expect(await fileMagic(dbPath), isNot(plaintextMagic));
    expect(await db.messageCount(), 1);
    expect((await db.listContacts()).single.displayName, 'Ana');
    await db.close();
    expect(await _leftovers(dbPath), isEmpty);
  });

  test(
    'a crash during the export leaves the plaintext database usable',
    () async {
      final ana = _contact('Ana');
      await _seedPlaintextV4(
        dbPath,
        contacts: [ana],
        messages: [_messageRow(id: 'm1', peer: ana.token)],
      );
      // A half-written encrypted copy: unverified, so it must be thrown away
      // rather than trusted.
      await File('$dbPath.encrypting').writeAsBytes(_garbage());

      final db = await openLocal();

      expect(await db.messageCount(), 1);
      expect(await fileMagic(dbPath), isNot(plaintextMagic));
      await db.close();
      expect(await _leftovers(dbPath), isEmpty);
    },
  );

  test('a crash after the swap removes the parked plaintext copy', () async {
    final ana = _contact('Ana');
    await _seedPlaintextV4(
      dbPath,
      contacts: [ana],
      messages: [_messageRow(id: 'm1', peer: ana.token)],
    );
    var db = await openLocal();
    await db.close();
    // Died before deleting the parked file: a full plaintext database sitting
    // next to the encrypted one is the exact leak this phase closes.
    await _seedPlaintextV4('$dbPath.plaintext-backup', contacts: [ana]);

    db = await openLocal();

    expect(await db.messageCount(), 1);
    await db.close();
    expect(await _leftovers(dbPath), isEmpty);
  });

  test('the wrong key fails with a clear error, not a SQLite one', () async {
    final db = await openLocal();
    await db.close();

    // The secure store lost the key and handed out a fresh one: restored
    // backup, reinstall, cleared credentials.
    secureValues['local_db_key_v1'] = _randomHex();

    await expectLater(
      openLocal(),
      throwsA(
        isA<LocalDatabaseKeyException>().having(
          (e) => e.message,
          'message',
          contains('otra clave'),
        ),
      ),
    );
    // And it did not "fix" the problem by starting over on top of the data.
    expect(await fileMagic(dbPath), isNot(plaintextMagic));
  });
}

/// Reads the schema the way any plain SQLite tool would: no key at all.
Future<void> _readWithoutKey(String path) async {
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(singleInstance: false, readOnly: true),
  );
  try {
    await db.rawQuery('SELECT name FROM sqlite_master');
  } finally {
    await db.close();
  }
}

Future<void> _readWithKey(String path, String keyHex) async {
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      singleInstance: false,
      onConfigure: (db) => db.execute('PRAGMA key = "x\'$keyHex\'"'),
    ),
  );
  try {
    await db.rawQuery('SELECT name FROM sqlite_master');
  } finally {
    await db.close();
  }
}

/// Files left around the database. After a successful open there must be none:
/// a forgotten `.plaintext-backup` would keep the metadata readable on disk.
Future<List<String>> _leftovers(String dbPath) async {
  final dir = Directory(p.dirname(dbPath));
  final name = p.basename(dbPath);
  return [
    for (final entry in dir.listSync())
      if (p.basename(entry.path).startsWith('$name.')) p.basename(entry.path),
  ];
}

/// A pre-F10 database: plain SQLite, schema v4, written without any key.
Future<void> _seedPlaintextV4(
  String path, {
  List<Contact> contacts = const [],
  List<Map<String, Object?>> messages = const [],
  List<String> blocked = const [],
}) async {
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(singleInstance: false),
  );
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
      created_at TEXT NOT NULL,
      kind TEXT NOT NULL DEFAULT 'text',
      mime TEXT,
      media_relpath TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE meta (
      key TEXT PRIMARY KEY NOT NULL,
      value TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE blocked (
      token TEXT PRIMARY KEY NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');
  await db.insert('profile', {
    'id': 1,
    'token': 'ec_perfil',
    'public_key': Uint8List(32),
    'created_at': '2026-08-01T00:00:00.000Z',
  });
  for (final contact in contacts) {
    await db.insert('contacts', contact.toMap());
  }
  for (final message in messages) {
    await db.insert('messages', message);
  }
  for (final token in blocked) {
    await db.insert('blocked', {
      'token': token,
      'created_at': '2026-08-01T00:00:00.000Z',
    });
  }
  await db.setVersion(4);
  await db.close();
}

/// A database from before media landed: no `kind` / `mime` / `media_relpath`
/// columns and no `blocked` table, so the schema upgrades still have work to do
/// after the conversion.
Future<void> _seedPlaintextV2(
  String path, {
  List<Contact> contacts = const [],
  List<String> messageIds = const [],
}) async {
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(singleInstance: false),
  );
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
  for (final contact in contacts) {
    await db.insert('contacts', contact.toMap());
  }
  for (final id in messageIds) {
    final row = _messageRow(id: id, peer: contacts.first.token);
    row.removeWhere(
      (key, _) => const ['kind', 'mime', 'media_relpath'].contains(key),
    );
    await db.insert('messages', row);
  }
  await db.setVersion(2);
  await db.close();
}

Map<String, Object?> _messageRow({
  required String id,
  required String peer,
  Uint8List? sealed,
  String kind = 'text',
}) {
  return {
    'id': id,
    'peer_token': peer,
    'direction': 'inbound',
    'body_sealed': sealed ?? Uint8List.fromList([1, 2, 3]),
    'status': 'sent',
    'created_at': '2026-08-0${id.substring(1)}T10:00:00.000Z',
    'kind': kind,
    'mime': kind == 'media' ? 'image/jpeg' : null,
    'media_relpath': kind == 'media' ? 'media/$id.bin' : null,
  };
}

Contact _contact(String name) {
  final rnd = Random(name.hashCode);
  final key = Uint8List.fromList(
    List<int>.generate(32, (_) => rnd.nextInt(256)),
  );
  return Contact(
    token: 'ec_${name.toLowerCase()}',
    publicKey: key,
    displayName: name,
    createdAt: DateTime.utc(2026, 8, 1),
  );
}

Uint8List _garbage() {
  final rnd = Random(7);
  return Uint8List.fromList(List<int>.generate(4096, (_) => rnd.nextInt(256)));
}

String _randomHex() {
  final rnd = Random.secure();
  return List<int>.generate(
    32,
    (_) => rnd.nextInt(256),
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

void _mockPathProvider(Directory dir) {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async => dir.path);
}

Map<String, String> _mockSecureStorage() {
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final values = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
        final key = args['key'] as String?;
        switch (call.method) {
          case 'write':
            if (key != null) values[key] = args['value'] as String? ?? '';
            return null;
          case 'read':
            return key == null ? null : values[key];
          case 'readAll':
            return values;
          case 'delete':
            values.remove(key);
            return null;
          case 'deleteAll':
            values.clear();
            return null;
          case 'containsKey':
            return values.containsKey(key);
          default:
            return null;
        }
      });
  return values;
}
