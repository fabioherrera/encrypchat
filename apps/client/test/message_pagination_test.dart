import 'dart:convert';
import 'dart:io';

import 'package:encrypchat/core/encrypchat_core.dart';
import 'package:encrypchat/core/media_envelope.dart';
import 'package:encrypchat/core/wire_frame.dart';
import 'package:encrypchat/models/chat_message.dart';
import 'package:encrypchat/models/contact.dart';
import 'package:encrypchat/services/identity_service.dart';
import 'package:encrypchat/services/local_database.dart';
import 'package:encrypchat/services/media_store.dart';
import 'package:encrypchat/services/messaging_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reading a conversation one page at a time.
///
/// Opening a chat used to decrypt the newest two hundred messages in one go on
/// the UI isolate, and anything older than that was simply unreachable. These
/// tests pin the two things the replacement has to get right: the pages fit
/// together into exactly the stored history — no gap, no repeat, including when
/// a message arrives mid-scrollback — and everything that counts what is on the
/// device still counts it, whether or not it happens to be in the window.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late EncrypchatCore core;
  late LocalDatabase database;
  late IdentityService identity;
  late MessagingService messaging;
  late Contact friend;

  /// Fixed base so ordering is decided by the test, not by how fast it runs.
  final base = DateTime.utc(2026, 1, 1);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('encrypchat_paging');
    _mockPathProvider(tempDir);
    _mockSecureStorage();

    core = EncrypchatCore.open();
    database = LocalDatabase(storage: const FlutterSecureStorage());
    await database.open();
    identity = IdentityService(
      core: core,
      storage: const FlutterSecureStorage(),
    );
    await identity.create();

    final generated = core.identityGenerate();
    friend = Contact(
      token: generated.token,
      publicKey: core.identityPublicKey(generated.secret),
      displayName: 'Amiga',
    );

    messaging = MessagingService(
      core: core,
      identity: identity,
      database: database,
    );
    messaging.setContacts([friend]);
    await messaging.loadBlocked();
    await messaging.loadRequests();
  });

  tearDown(() async {
    messaging.dispose();
    await database.close();
    await tempDir.delete(recursive: true);
  });

  /// Writes a stored message straight to the database — the history a device
  /// arrives with, without replaying a year of traffic through the node.
  Future<void> store(int i, {DateTime? at}) async {
    await database.upsertMessage(
      ChatMessage(
        id: 'm${i.toString().padLeft(4, '0')}',
        peerToken: friend.token,
        direction: MessageDirection.inbound,
        bodySealed: core.localSeal(
          dbKey: database.dbKey,
          plaintext: Uint8List.fromList(utf8.encode('mensaje $i')),
        ),
        status: MessageStatus.delivered,
        createdAt: at ?? base.add(Duration(seconds: i)),
      ),
    );
  }

  Future<void> storeHistory(int count, {DateTime? from}) async {
    for (var i = 0; i < count; i++) {
      await store(i, at: from?.add(Duration(seconds: i)));
    }
  }

  Uint8List frameFrom(Contact from, Uint8List plaintext) => WireFrame.create(
    senderToken: from.token,
    ciphertext: core.encrypt(
      recipientPublicKey: identity.publicKey!,
      plaintext: plaintext,
    ),
  ).encode();

  List<String?> texts(List<ChatMessage> messages) => [
    for (final m in messages) m.plaintext,
  ];

  const page = MessagingService.messagesPageSize;

  test('opening a chat reads one page, and it is the newest one', () async {
    await storeHistory(page * 3);

    final window = await messaging.messagesFor(friend.token);

    expect(window, hasLength(page));
    expect(window.first.plaintext, 'mensaje ${page * 2}');
    expect(window.last.plaintext, 'mensaje ${page * 3 - 1}');
    expect(messaging.hasOlderMessages(friend.token), isTrue);
  });

  test('a conversation shorter than a page has nothing older', () async {
    await storeHistory(3);

    final window = await messaging.messagesFor(friend.token);

    expect(texts(window), ['mensaje 0', 'mensaje 1', 'mensaje 2']);
    expect(messaging.hasOlderMessages(friend.token), isFalse);
    expect(await messaging.loadOlderMessages(friend.token), 0);
  });

  test('the pages walk back to exactly the stored history', () async {
    // Deliberately not a multiple of the page size: the last page is short and
    // that is where an off-by-one hides.
    const total = page * 2 + 7;
    await storeHistory(total);

    await messaging.messagesFor(friend.token);
    var steps = 0;
    while (await messaging.loadOlderMessages(friend.token) > 0) {
      steps++;
      expect(steps, lessThan(10), reason: 'paging back should terminate');
    }

    final window = await messaging.messagesFor(friend.token);
    expect(texts(window), [for (var i = 0; i < total; i++) 'mensaje $i']);
    expect(messaging.hasOlderMessages(friend.token), isFalse);
  });

  test('messages stamped at the same instant are not skipped', () async {
    // A relay pull files a batch in one go, so a page boundary landing inside a
    // group that shares a timestamp is ordinary. A cursor on the timestamp
    // alone would ask for "older than this instant" and step over the rest of
    // the group; the id is what breaks the tie.
    const total = page + 10;
    final sameInstant = base.add(const Duration(hours: 1));
    for (var i = 0; i < total; i++) {
      await store(i, at: sameInstant);
    }

    await messaging.messagesFor(friend.token);
    expect(await messaging.loadOlderMessages(friend.token), 10);

    final window = await messaging.messagesFor(friend.token);
    expect(texts(window), [for (var i = 0; i < total; i++) 'mensaje $i']);
  });

  test('a message arriving mid-scrollback does not shift the pages', () async {
    const total = page * 2;
    await storeHistory(total);
    await messaging.messagesFor(friend.token);

    await messaging.handleInboundFrame(
      frameFrom(friend, Uint8List.fromList(utf8.encode('recién llegado'))),
    );
    final afterArrival = await messaging.messagesFor(friend.token);
    // Appended at the newest end, where the screen expects it — the window
    // still ends at the newest message.
    expect(afterArrival, hasLength(page + 1));
    expect(afterArrival.last.plaintext, 'recién llegado');

    expect(await messaging.loadOlderMessages(friend.token), page);

    final window = await messaging.messagesFor(friend.token);
    expect(texts(window), [
      for (var i = 0; i < total; i++) 'mensaje $i',
      'recién llegado',
    ]);
    // The check that says it plainly: an offset would have counted the new
    // message as one of the fifty it skipped.
    expect(window.map((m) => m.id).toSet(), hasLength(window.length));
  });

  test('closing a conversation collapses it back to one page', () async {
    await storeHistory(page * 3);
    await messaging.messagesFor(friend.token);
    while (await messaging.loadOlderMessages(friend.token) > 0) {}
    expect(await messaging.messagesFor(friend.token), hasLength(page * 3));

    messaging.releaseWindow(friend.token);

    final window = await messaging.messagesFor(friend.token);
    expect(window, hasLength(page));
    expect(window.last.plaintext, 'mensaje ${page * 3 - 1}');
    // Collapsing is not forgetting: the rest is on disk and reachable again.
    expect(messaging.hasOlderMessages(friend.token), isTrue);
    expect(await messaging.loadOlderMessages(friend.token), page);
  });

  test('a window that keeps receiving stays bounded', () async {
    await messaging.messagesFor(friend.token);
    for (var i = 0; i < MessagingService.maxWindowMessages + 20; i++) {
      await messaging.handleInboundFrame(
        frameFrom(friend, Uint8List.fromList(utf8.encode('flood $i'))),
      );
    }

    final window = await messaging.messagesFor(friend.token);
    expect(window, hasLength(MessagingService.maxWindowMessages));
    expect(
      window.last.plaintext,
      'flood ${MessagingService.maxWindowMessages + 19}',
    );
    // What was dropped is a page the window knows how to read back, which is
    // the only kind of trimming that keeps it honest.
    expect(messaging.hasOlderMessages(friend.token), isTrue);
    expect(
      await database.messageCount(),
      MessagingService.maxWindowMessages + 20,
    );
  });

  test('an attachment outside the window still counts, and still goes '
      'when the conversation does', () async {
    // The coherence check between paging and the media ceilings: the quota is
    // measured from the database and the disk, never from what happens to be
    // loaded, so scrolling cannot conjure free space — nor orphan a file.
    final store = MediaStore(core: core, database: database);
    await messaging.handleInboundFrame(
      frameFrom(
        friend,
        MediaEnvelope(
          mime: 'image/png',
          name: 'foto.png',
          data: Uint8List(4096),
        ).encode(),
      ),
    );
    expect(await store.bytesForPeer(friend.token), greaterThan(0));

    // Newer than the attachment, so a page of them pushes it out of the window.
    await storeHistory(
      page + 5,
      from: DateTime.now().toUtc().add(const Duration(seconds: 1)),
    );
    await messaging.refreshPeer(friend.token);
    final window = await messaging.messagesFor(friend.token);
    expect(
      window.where((m) => m.isMedia),
      isEmpty,
      reason: 'the attachment is older than the newest page',
    );

    expect(await store.bytesForPeer(friend.token), greaterThan(0));
    expect(
      await database.listMediaRelPaths(peerToken: friend.token),
      hasLength(1),
    );

    await messaging.deleteConversation(friend.token);

    expect(await store.bytesForPeer(friend.token), 0);
    expect(
      Directory('${tempDir.path}/media').listSync().whereType<File>(),
      isEmpty,
    );
  });
}

void _mockPathProvider(Directory dir) {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async => dir.path);
}

void _mockSecureStorage() {
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
}
