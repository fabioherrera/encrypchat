import 'dart:convert';
import 'dart:io';

import 'package:encrypchat/core/call_signal.dart';
import 'package:encrypchat/core/contact_intro.dart';
import 'package:encrypchat/core/encrypchat_core.dart';
import 'package:encrypchat/core/media_envelope.dart';
import 'package:encrypchat/core/wire_frame.dart';
import 'package:encrypchat/models/contact.dart';
import 'package:encrypchat/services/identity_service.dart';
import 'package:encrypchat/services/local_database.dart';
import 'package:encrypchat/services/media_store.dart';
import 'package:encrypchat/services/messaging_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// F-6: what an identity that is **not** a contact can leave on this device.
///
/// Before the policy, anything that decrypted was persisted — a row, and for
/// media a sealed file of up to 12 MiB — while the chat list only walked
/// contacts, so a stranger's traffic was invisible: impossible to read, delete,
/// or answer with a block. These tests pin the policy that replaced it, on both
/// routes, and the fact that the messages that *are* kept are reachable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late EncrypchatCore core;
  late LocalDatabase database;
  late IdentityService identity;
  late MessagingService messaging;

  late Contact friend;
  late Contact stranger;
  late Uint8List strangerSecret;

  Contact freshIdentity(String name) {
    final generated = core.identityGenerate();
    return Contact(
      token: generated.token,
      publicKey: core.identityPublicKey(generated.secret),
      displayName: name,
    );
  }

  /// A P2P frame: authenticated by the session, so it carries a token and no
  /// public key. That is what makes a P2P request unanswerable until the peer's
  /// contact card arrives.
  Uint8List frameFrom(Contact from, Uint8List plaintext) {
    return WireFrame.create(
      senderToken: from.token,
      ciphertext: core.encrypt(
        recipientPublicKey: identity.publicKey!,
        plaintext: plaintext,
      ),
    ).encode();
  }

  Uint8List textFrame(Contact from, String text) =>
      frameFrom(from, Uint8List.fromList(utf8.encode(text)));

  /// A relay blob: the sender comes out of the ciphertext, public key included.
  Uint8List sealedFrom(Uint8List secret, Uint8List plaintext) => core
      .sealedSeal(
        senderSecret: secret,
        recipientPublicKey: identity.publicKey!,
        plaintext: plaintext,
      )
      .blob;

  Uint8List mediaEnvelope({int bytes = 64}) => MediaEnvelope(
    mime: 'image/png',
    name: 'foto.png',
    data: Uint8List(bytes),
  ).encode();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('encrypchat_stranger');
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

    friend = freshIdentity('Amiga');
    final generated = core.identityGenerate();
    strangerSecret = generated.secret;
    stranger = Contact(
      token: generated.token,
      publicKey: core.identityPublicKey(strangerSecret),
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

  Future<int> mediaFileCount() async {
    final dir = Directory('${tempDir.path}/media');
    if (!dir.existsSync()) return 0;
    return dir.listSync().whereType<File>().length;
  }

  test('a stranger writing lands in a request, not in the chat list', () async {
    await messaging.handleInboundFrame(textFrame(stranger, 'hola, soy Ana'));

    // Stored — and now findable, which is the whole difference from F-6.
    final request = messaging.requests.single;
    expect(request.peerToken, stranger.token);
    expect(request.messageCount, 1);
    final messages = await messaging.messagesFor(stranger.token);
    expect(messages.single.plaintext, 'hola, soy Ana');
    // Not promoted to a contact by writing.
    expect(messaging.isContact(stranger.token), isFalse);
  });

  test('a stranger cannot put an attachment on the disk', () async {
    await messaging.handleInboundFrame(
      frameFrom(stranger, mediaEnvelope(bytes: 512)),
    );

    expect(await mediaFileCount(), 0);
    expect(await database.messageCount(), 0);
    expect(messaging.requests, isEmpty);
    expect(messaging.inboundDrops, {InboundDropReason.strangerMedia: 1});
  });

  test('a stranger cannot make the app ring', () async {
    final rung = <String>[];
    messaging.onCallSignal = (from, signal) => rung.add(from);
    final invite = CallSignal(
      type: CallSignalType.invite,
      callId: 'call-1',
      media: CallMediaMode.av,
    );

    await messaging.handleInboundFrame(frameFrom(stranger, invite.encode()));

    expect(rung, isEmpty);
    expect(await database.messageCount(), 0);
    expect(messaging.inboundDrops, {InboundDropReason.strangerCall: 1});
  });

  test('a stranger runs out of messages instead of the disk', () async {
    for (var i = 0; i < MessagingService.maxRequestMessagesPerPeer + 3; i++) {
      await messaging.handleInboundFrame(textFrame(stranger, 'mensaje $i'));
    }

    expect(
      await database.messageCount(),
      MessagingService.maxRequestMessagesPerPeer,
    );
    expect(
      messaging.requests.single.messageCount,
      MessagingService.maxRequestMessagesPerPeer,
    );
    expect(messaging.inboundDrops, {InboundDropReason.senderFull: 3});
  });

  test('a long message from a stranger is refused', () async {
    final long = 'x' * (MessagingService.maxRequestTextBytes + 1);

    await messaging.handleInboundFrame(textFrame(stranger, long));

    expect(await database.messageCount(), 0);
    expect(messaging.inboundDrops, {InboundDropReason.strangerTooLong: 1});
  });

  group('what a stranger can make this isolate decrypt (B-5)', () {
    /// A frame with a body that is not a ciphertext at all. If anything ever
    /// hands it to `decrypt`, the call throws `CoreException` and the test says
    /// so — which is what makes it a probe for *where* the size check runs.
    Uint8List oversizedFrameFrom(Contact from, {required int bytes}) {
      return WireFrame.create(
        senderToken: from.token,
        ciphertext: Uint8List(bytes),
      ).encode();
    }

    test('a big frame from an unknown identity is refused before it is '
        'decrypted', () async {
      // A frame may carry up to `MAX_FRAME_LEN` (16 MiB) and sending moved off
      // this isolate in F-11, but receiving did not: `decrypt` is a DH plus an
      // AEAD open over the whole body, on the isolate drawing the interface.
      // Until the ceiling, the 4 KiB a stranger is allowed was only applied
      // afterwards, so a throwaway identity could make the app open one 16 MiB
      // frame after another before deciding it wanted none of them.
      await messaging.handleInboundFrame(
        oversizedFrameFrom(stranger, bytes: 1024 * 1024),
      );

      expect(messaging.inboundDrops, {InboundDropReason.strangerTooLong: 1});
      expect(await database.messageCount(), 0);
      expect(messaging.requests, isEmpty);
    });

    test('the ceiling clears what the policy would have accepted', () async {
      // The longest text a request may carry, sealed: it has to pass, or the
      // check has taken something the policy allows.
      final atCeiling = 'x' * MessagingService.maxRequestTextBytes;

      await messaging.handleInboundFrame(textFrame(stranger, atCeiling));

      expect(messaging.inboundDrops, isEmpty);
      expect(
        (await messaging.messagesFor(stranger.token)).single.plaintext,
        atCeiling,
      );
    });

    test('a contact is not held to it', () async {
      // Attachments from an agended contact are large by design, and they are
      // the reason the ceiling is not a global one.
      await messaging.handleInboundFrame(
        frameFrom(friend, mediaEnvelope(bytes: 256 * 1024)),
      );

      expect(await mediaFileCount(), 1);
      expect(messaging.inboundDrops, isEmpty);
    });
  });

  group('a full inbox is a moment, not a state (B-4)', () {
    /// Fills every slot and returns the tokens, oldest activity first.
    Future<List<String>> fillInbox() async {
      final tokens = <String>[];
      for (var i = 0; i < MessagingService.maxPendingRequests; i++) {
        final peer = freshIdentity('desconocido $i');
        await messaging.handleInboundFrame(textFrame(peer, 'hola'));
        tokens.add(peer.token);
      }
      expect(
        messaging.requests,
        hasLength(MessagingService.maxPendingRequests),
      );
      return tokens;
    }

    test('the oldest request makes way instead of the newest being '
        'turned away', () async {
      final filled = await fillInbox();

      await messaging.handleInboundFrame(textFrame(stranger, 'hola, soy Ana'));

      // The whole point: twenty throwaway identities cost nothing, and before
      // this they owned the twenty slots for good — nobody genuine could reach
      // the user again, and neither end was told.
      expect(
        messaging.requests,
        hasLength(MessagingService.maxPendingRequests),
      );
      expect(
        messaging.requests.map((r) => r.peerToken),
        contains(stranger.token),
      );
      expect(
        messaging.requests.map((r) => r.peerToken),
        isNot(contains(filled.first)),
      );
      expect(
        (await messaging.messagesFor(stranger.token)).single.plaintext,
        'hola, soy Ana',
      );
      expect(messaging.inboundDrops, isEmpty);
    });

    test('what is displaced takes its messages and files with it', () async {
      // The displaced one is chosen by last activity, so it is the peer that
      // wrote first and never came back.
      final oldest = freshIdentity('el primero');
      await messaging.handleInboundFrame(textFrame(oldest, 'hola'));
      for (var i = 1; i < MessagingService.maxPendingRequests; i++) {
        await messaging.handleInboundFrame(
          textFrame(freshIdentity('desconocido $i'), 'hola'),
        );
      }

      await messaging.handleInboundFrame(textFrame(stranger, 'hola'));

      // A row left behind under a token with no request and no contact is the
      // invisible conversation of F-6, reached from the other end.
      expect(await messaging.messagesFor(oldest.token), isEmpty);
      expect(messaging.displacedRequests, 1);
      expect(
        await database.messageCount(),
        MessagingService.maxPendingRequests,
      );
    });

    test('a sender that is already pending is not displaced by its own '
        'message', () async {
      await messaging.handleInboundFrame(textFrame(stranger, 'primera'));
      for (var i = 0; i < MessagingService.maxPendingRequests - 1; i++) {
        await messaging.handleInboundFrame(
          textFrame(freshIdentity('desconocido $i'), 'hola'),
        );
      }

      await messaging.handleInboundFrame(textFrame(stranger, 'segunda'));

      // Full, but this one already has a slot: nothing is evicted to hold a
      // message from somebody who is already in the list.
      expect(messaging.displacedRequests, 0);
      expect(messaging.requests.length, MessagingService.maxPendingRequests);
      expect(
        (await messaging.messagesFor(stranger.token)).map((m) => m.plaintext),
        ['primera', 'segunda'],
      );
    });
  });

  test('a contact is not subject to the request ceilings', () async {
    for (var i = 0; i < MessagingService.maxRequestMessagesPerPeer + 5; i++) {
      await messaging.handleInboundFrame(textFrame(friend, 'mensaje $i'));
    }
    await messaging.handleInboundFrame(
      frameFrom(friend, mediaEnvelope(bytes: 2048)),
    );

    expect(
      await database.messageCount(),
      MessagingService.maxRequestMessagesPerPeer + 6,
    );
    expect(await mediaFileCount(), 1);
    expect(messaging.requests, isEmpty);
    expect(messaging.inboundDrops, isEmpty);
  });

  test('accepting a request keeps the history and lifts the limits', () async {
    // By relay, so the blob carries the sender's authenticated public key.
    await messaging.handleRelayBlob(
      sealedFrom(strangerSecret, Uint8List.fromList(utf8.encode('hola'))),
    );
    final request = messaging.requests.single;
    expect(request.canAccept, isTrue);

    final contact = await messaging.acceptRequest(request, displayName: 'Ana');

    expect(contact.publicKey, stranger.publicKey);
    expect(messaging.requests, isEmpty);
    expect(await database.listContacts(), hasLength(1));
    // The conversation is the same one, still readable.
    expect(
      (await messaging.messagesFor(stranger.token)).single.plaintext,
      'hola',
    );

    // And what the policy withheld is now allowed.
    await messaging.handleInboundFrame(
      frameFrom(stranger, mediaEnvelope(bytes: 1024)),
    );
    expect(await mediaFileCount(), 1);
  });

  test('a P2P intro from a stranger is an acceptable request', () async {
    final intro = ContactIntro(
      token: stranger.token,
      publicKey: stranger.publicKey,
    );
    await messaging.handleInboundFrame(frameFrom(stranger, intro.encode()));

    final request = messaging.requests.single;
    expect(request.canAccept, isTrue);
    expect(request.publicKey, stranger.publicKey);
    expect(
      (await messaging.messagesFor(stranger.token)).single.plaintext,
      ContactIntro.preview,
    );

    final contact = await messaging.acceptRequest(request, displayName: 'Ana');
    expect(contact.publicKey, stranger.publicKey);
    expect(messaging.requests, isEmpty);
  });

  test('a request that only arrived by P2P cannot be accepted yet', () async {
    await messaging.handleInboundFrame(textFrame(stranger, 'hola'));

    final request = messaging.requests.single;
    // An `EC04` frame carries a token, not a key, so there is nothing to reply
    // with. The UI says so instead of offering a button that cannot work.
    expect(request.canAccept, isFalse);
    await expectLater(
      messaging.acceptRequest(request),
      throwsA(isA<StateError>()),
    );
  });

  test('the same sender by relay makes a P2P request answerable', () async {
    await messaging.handleInboundFrame(textFrame(stranger, 'hola'));
    expect(messaging.requests.single.canAccept, isFalse);

    await messaging.handleRelayBlob(
      sealedFrom(strangerSecret, Uint8List.fromList(utf8.encode('¿me leés?'))),
    );

    expect(messaging.requests.single.canAccept, isTrue);
    expect(messaging.requests.single.messageCount, 2);
  });

  test('discarding a request removes what it left behind', () async {
    await messaging.handleInboundFrame(textFrame(stranger, 'hola'));

    await messaging.discardRequest(stranger.token);

    expect(messaging.requests, isEmpty);
    expect(await database.messageCount(), 0);
    expect(messaging.isBlocked(stranger.token), isFalse);
  });

  test('blocking from the inbox stops the identity for good', () async {
    await messaging.handleInboundFrame(textFrame(stranger, 'hola'));

    await messaging.discardRequest(stranger.token, alsoBlock: true);
    // Whatever they send next is cut before it is decrypted.
    await messaging.handleInboundFrame(textFrame(stranger, 'y otra'));

    expect(messaging.isBlocked(stranger.token), isTrue);
    expect(messaging.requests, isEmpty);
    expect(await database.messageCount(), 0);
  });

  test('an attachment over the peer ceiling is refused, not stored', () async {
    // A store with a tiny budget: the ceiling is what is being tested, not the
    // number of megabytes it takes to reach the real one.
    final metered = MessagingService(
      core: core,
      identity: identity,
      database: database,
      mediaStore: MediaStore(
        core: core,
        database: database,
        maxInboundBytesPerPeer: 4096,
      ),
    );
    addTearDown(metered.dispose);
    metered.setContacts([friend]);
    await metered.loadBlocked();

    await metered.handleInboundFrame(
      frameFrom(friend, mediaEnvelope(bytes: 3072)),
    );
    await metered.handleInboundFrame(
      frameFrom(friend, mediaEnvelope(bytes: 3072)),
    );

    expect(await mediaFileCount(), 1);
    expect(metered.inboundDrops, {InboundDropReason.mediaQuota: 1});
    // Text from the same contact still arrives: the ceiling is on attachments.
    await metered.handleInboundFrame(textFrame(friend, 'y esto sí'));
    expect(await database.messageCount(), 2);
  });

  test('deleting a conversation takes its media files with it', () async {
    await messaging.handleInboundFrame(
      frameFrom(friend, mediaEnvelope(bytes: 1024)),
    );
    expect(await mediaFileCount(), 1);

    await messaging.deleteConversation(friend.token);

    expect(await mediaFileCount(), 0);
    expect(await database.messageCount(), 0);
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
