import 'dart:convert';
import 'dart:io';

import 'package:encrypchat/core/encrypchat_core.dart';
import 'package:encrypchat/models/chat_message.dart';
import 'package:encrypchat/models/contact.dart';
import 'package:encrypchat/services/identity_service.dart';
import 'package:encrypchat/services/identity_wipe.dart';
import 'package:encrypchat/services/local_database.dart';
import 'package:encrypchat/services/media_store.dart';
import 'package:encrypchat/services/messaging_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Leaving the app for good.
///
/// The failure this guards against is not "the wipe crashed" — it is a wipe
/// that *looks* done and is not: an identity secret still in the keychain, a
/// sealed attachment nobody counted, a `db_key` that outlives the database it
/// opens. So the tests check the device from the outside afterwards (what is
/// left in the secure store, what is left on the disk, what a fresh start
/// finds) rather than trusting the steps to have run.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Map<String, String> stored;
  late EncrypchatCore core;
  const storage = FlutterSecureStorage();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('encrypchat_wipe');
    _mockPathProvider(tempDir);
    stored = _mockSecureStorage();
    core = EncrypchatCore.open();
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// A device that has been used: identity, an encrypted database with a
  /// conversation in it, a sealed attachment, a relay configured.
  Future<void> useTheApp() async {
    final database = LocalDatabase(storage: storage);
    await database.open();
    final identity = IdentityService(core: core, storage: storage);
    await identity.create();

    final generated = core.identityGenerate();
    final friend = Contact(
      token: generated.token,
      publicKey: core.identityPublicKey(generated.secret),
    );
    await database.upsertContact(friend);
    await database.upsertMessage(
      ChatMessage(
        id: 'mensaje-1',
        peerToken: friend.token,
        direction: MessageDirection.inbound,
        bodySealed: core.localSeal(
          dbKey: database.dbKey,
          plaintext: Uint8List.fromList(utf8.encode('hola')),
        ),
        status: MessageStatus.delivered,
        createdAt: DateTime.now().toUtc(),
      ),
    );
    final media = MediaStore(core: core, database: database);
    await media.writeSealed(id: 'adjunto-1', plaintextBytes: Uint8List(2048));

    final messaging = MessagingService(
      core: core,
      identity: identity,
      database: database,
    );
    await messaging.setRelayBaseUrl('https://relay.example');
    messaging.dispose();
    await database.close();
  }

  List<File> filesOnDisk() =>
      tempDir.listSync(recursive: true).whereType<File>().toList();

  test('a used device writes nothing the wipe does not know about', () async {
    await useTheApp();

    // The check that survives the next feature: every entry any service put in
    // the OS secure store has to be in the deletion list. A key added later and
    // forgotten here is an identity that outlives its own deletion.
    expect(stored.keys, isNotEmpty);
    expect(stored.keys, everyElement(isIn(IdentityWipe.storageKeys)));
  });

  test('wiping leaves no key, no database and no attachment', () async {
    await useTheApp();
    expect(filesOnDisk(), isNotEmpty);

    final report = await IdentityWipe.run(storage);

    expect(report.isClean, isTrue);
    expect(stored, isEmpty);
    expect(filesOnDisk(), isEmpty);
    expect(MediaStore.directoryIn(tempDir).existsSync(), isFalse);
    for (final path in LocalDatabase.filePathsIn(tempDir)) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
  });

  test('after a wipe the device starts as a new one', () async {
    await useTheApp();
    await IdentityWipe.run(storage);

    final identity = IdentityService(core: core, storage: storage);
    expect(await identity.load(), isFalse);

    final database = LocalDatabase(storage: storage);
    await database.open();
    addTearDown(database.close);
    expect(await database.messageCount(), 0);
    expect(await database.listContacts(), isEmpty);
  });

  test(
    'a wipe interrupted after the key is finished on the next start',
    () async {
      await useTheApp();
      // Where a crash hurts most: the key that opens the database is already
      // gone, so opening it would fail and there would be nothing left to fix it
      // with. The mark is what turns that into a wipe that simply resumes.
      await IdentityWipe.markPending(storage);
      await storage.delete(key: LocalDatabase.dbKeyStorageKey);
      expect(filesOnDisk(), isNotEmpty);

      final report = await IdentityWipe.resumeIfPending(storage);

      expect(report, isNotNull);
      expect(report!.isClean, isTrue);
      expect(stored, isEmpty);
      expect(filesOnDisk(), isEmpty);
    },
  );

  test('a wipe interrupted before the keys is also finished', () async {
    await useTheApp();
    await IdentityWipe.markPending(storage);

    await IdentityWipe.resumeIfPending(storage);

    expect(stored, isEmpty);
    expect(filesOnDisk(), isEmpty);
  });

  test('with no wipe pending nothing is touched', () async {
    await useTheApp();
    final before = filesOnDisk().length;
    final keysBefore = stored.length;

    expect(await IdentityWipe.resumeIfPending(storage), isNull);

    expect(filesOnDisk(), hasLength(before));
    expect(stored, hasLength(keysBefore));
  });

  test('the mark outlives every step it guards', () async {
    await useTheApp();
    await IdentityWipe.markPending(storage);
    expect(await IdentityWipe.isPending(storage), isTrue);

    // Deleting the identity's own entries must not take the mark with them:
    // it is the only reason an interrupted wipe is recoverable.
    for (final key in IdentityWipe.storageKeys) {
      await storage.delete(key: key);
    }
    expect(await IdentityWipe.isPending(storage), isTrue);

    await IdentityWipe.run(storage);
    expect(await IdentityWipe.isPending(storage), isFalse);
  });
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
