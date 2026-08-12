import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:encrypchat/core/call_signal.dart';
import 'package:encrypchat/core/encrypchat_core.dart';
import 'package:encrypchat/core/media_envelope.dart';
import 'package:encrypchat/models/chat_message.dart';
import 'package:encrypchat/models/contact.dart';
import 'package:encrypchat/services/identity_service.dart';
import 'package:encrypchat/services/local_database.dart';
import 'package:encrypchat/services/media_store.dart';
import 'package:encrypchat/services/messaging_service.dart';
import 'package:encrypchat/services/relay_client.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Sealed sender (`ECS1`) over the relay, against the real FFI core.
///
/// The point of the format is that the sender is not a field anybody can write:
/// these tests drive the two ends the app actually uses — the enqueue on send
/// and [MessagingService.handleRelayBlob] on pull — and check that every failure
/// mode the core distinguishes stays distinguishable here, with nothing stored
/// and nobody attributed when the binding does not hold.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late EncrypchatCore core;
  late LocalDatabase database;
  late IdentityService identity;
  late MessagingService messaging;
  late List<Uint8List> enqueued;

  /// Bob is a real peer: the test holds his secret so it can seal towards the
  /// local user and open what the local user sealed towards him.
  late Contact bob;
  late Uint8List bobSecret;

  Uint8List sealFromBob(Uint8List plaintext, {Uint8List? recipientPublicKey}) {
    return core
        .sealedSeal(
          senderSecret: bobSecret,
          recipientPublicKey: recipientPublicKey ?? identity.publicKey!,
          plaintext: plaintext,
        )
        .blob;
  }

  Uint8List sealTextFromBob(String text) =>
      sealFromBob(Uint8List.fromList(utf8.encode(text)));

  late FakeRelay relay;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('encrypchat_sealed_test');
    _mockPathProvider(tempDir);
    _mockSecureStorage();

    core = EncrypchatCore.open();
    relay = FakeRelay(core);
    enqueued = relay.enqueued;
    database = LocalDatabase(storage: const FlutterSecureStorage());
    await database.open();
    identity = IdentityService(
      core: core,
      storage: const FlutterSecureStorage(),
    );
    await identity.create();

    final generated = core.identityGenerate();
    bobSecret = generated.secret;
    bob = Contact(
      token: generated.token,
      publicKey: core.identityPublicKey(bobSecret),
      displayName: 'Bob',
    );

    messaging = MessagingService(
      core: core,
      identity: identity,
      database: database,
      relay: relay.client(),
    );
    messaging.setContacts([bob]);
    await messaging.loadBlocked();
  });

  tearDown(() async {
    messaging.dispose();
    await database.close();
    await tempDir.delete(recursive: true);
  });

  test('the core is new enough to seal', () {
    // The relay path has no fallback: a core without the sealed pair must fail
    // at load, not at the first send.
    expect(EncrypchatCore.minApiVersion, '0.8.0');
    expect(EncrypchatCore.isApiCompatible(core.apiVersion()), isTrue);
  });

  test('an enqueued text blob is ECS1 and names no sender', () async {
    // `startNode` reloads the relay URL from secure storage, so it has to be
    // stored and not just set on the client.
    await messaging.setRelayBaseUrl('https://relay.test');
    await messaging.startNode();

    // No P2P session with Bob, so the send falls through to the relay.
    final message = await messaging.sendText(peer: bob, text: 'hola por relay');

    expect(message.status, MessageStatus.viaRelay);
    expect(enqueued, hasLength(1));
    final blob = enqueued.single;
    expect(
      utf8.decode(blob.sublist(0, 4)),
      'ECS1',
      reason: 'the relay must get the sealed format, not an EC01 payload',
    );
    expect(blob.length, EncrypchatCore.sealedOverheadBytes + 14);

    // Nothing in the blob says who wrote it: not the token, not the pubkey.
    expect(_contains(blob, utf8.encode(identity.token!)), isFalse);
    expect(_contains(blob, identity.publicKey!), isFalse);

    // Bob, and only Bob, gets the authenticated sender out of the ciphertext.
    final opened = core.sealedOpen(
      recipientSecret: bobSecret,
      blob: blob,
      nowUnixSecs: _nowUnix(),
    );
    expect(opened.senderToken, identity.token);
    expect(opened.senderPublicKey, identity.publicKey);
    expect(utf8.decode(opened.plaintext), 'hola por relay');
  });

  test('a blob the relay accepted and dropped is still reported as sent '
      'to the relay', () async {
    // What an over-quota mailbox looks like from here: `200`, a body of the
    // usual shape, an id that names no stored row. Indistinguishable from an
    // acceptance on purpose — the honest sender and somebody probing for
    // presence send the very same request — so there is nothing to detect and
    // nothing to report as an error. `viaRelay` is the truthful answer because
    // it is named after the one thing that did happen; what must not promise
    // more is the copy around it, which `outbound_status_test` pins.
    final silent = MessagingService(
      core: core,
      identity: identity,
      database: database,
      relay: RelayClient(
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode({'id': 'no-such-row'}), 200),
        ),
      )..baseUrl = 'https://relay.test',
    )..setContacts([bob]);
    addTearDown(silent.dispose);
    await silent.loadBlocked();
    // `startNode` reloads the address from secure storage, so it has to be
    // stored and not just set on the client.
    await silent.setRelayBaseUrl('https://relay.test');
    await silent.startNode();

    final message = await silent.sendText(peer: bob, text: 'quizá llegue');

    expect(message.status, MessageStatus.viaRelay);
    expect(message.error, isNull);
    await silent.stopNode();
  });

  group('the pull handshake', () {
    test('a blob waiting in the mailbox reaches the conversation', () async {
      relay.deposit(identity.token!, sealTextFromBob('hola por relay'));

      await messaging.pullFromRelay();

      // The fake verifies the proof, so arriving here means the challenge id was
      // carried between the two calls and the proof covered this destination.
      expect(relay.pullsServed, 1);
      expect(relay.challengesIssued, 1);
      final message = (await messaging.messagesFor(bob.token)).single;
      expect(message.plaintext, 'hola por relay');
      expect(message.status, MessageStatus.viaRelay);
      // The fake hands a blob over once and forgets it. The real relay keeps it
      // leased for another 60 s, which is why one bad blob must never abort the
      // loop: the rest of the batch has to be drained before it comes back.
      expect(relay.waitingFor(identity.token!), isEmpty);
    });

    test('the challenge asks for nothing and names no destination', () async {
      relay.deposit(identity.token!, sealTextFromBob('hola'));

      await messaging.pullFromRelay();

      expect(relay.challengeBodies, ['{}']);
      // The whole point of F-8: a blind relay is not told whose mailbox is about
      // to be read, and the destination rides inside the proof's transcript.
      expect(relay.challengeBodies.single, isNot(contains(identity.token!)));
    });

    test('the pre-F-8 shape is refused, so the contract cannot drift '
        'back quietly', () async {
      // Byte-for-byte what `RelayClient` used to send, straight at the fake: no
      // `challenge_id`, because the challenge used to be bound to the
      // destination server-side.
      final res = await relay.rawClient().post(
        Uri.parse('https://relay.test/v1/pull'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'dest_token': identity.token,
          'pubkey_b64': base64Encode(identity.publicKey!),
          'proof_b64': base64Encode(Uint8List(32)),
        }),
      );

      expect(res.statusCode, 422);
    });

    test('a 507 is explained as the relay running out of disk, not as the '
        "recipient's mailbox", () async {
      // The mailbox-full refusal is gone from the wire: it was distinguishable
      // from an acceptance, so anybody holding a token could fill a mailbox and
      // then probe it to learn when its owner came online to empty it. What is
      // left under this code is the relay's own storage, and the remedy is a
      // different relay — not waiting for somebody to read their messages.
      final full = RelayClient(
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode({'error': 'full'}), 507),
        ),
      )..baseUrl = 'https://relay.test';

      await expectLater(
        full.enqueue(destToken: identity.token!, blob: Uint8List(8)),
        throwsA(
          isA<StateError>()
              .having((e) => e.message, 'message', contains('sin espacio'))
              .having(
                (e) => e.message,
                'message',
                isNot(contains('destinatario lleno')),
              ),
        ),
      );
    });

    test('a 422 is reported as a protocol mismatch, not swallowed', () async {
      final stubborn = RelayClient(
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode({'error': 'nope'}), 422),
        ),
      )..baseUrl = 'https://relay.test';

      await expectLater(
        stubborn.challenge(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('versiones distintas del protocolo'),
          ),
        ),
      );
    });

    test('a contract mismatch reaches the interface and then goes away', () async {
      // The bug this whole batch starts from was invisible: a pull failing every
      // 8 s with nothing on screen. A protocol mismatch has to be visible, and
      // stop being visible once it is fixed.
      relay.refusePullShape = true;

      await messaging.pullFromRelay();

      expect(
        messaging.relayPullFault,
        contains('versiones distintas del protocolo'),
      );

      relay
        ..refusePullShape = false
        ..deposit(identity.token!, sealTextFromBob('hola'));
      await messaging.pullFromRelay();

      expect(messaging.relayPullFault, isNull);
      expect((await messaging.messagesFor(bob.token)).single.plaintext, 'hola');
    });

    test('a rate-limited address backs off instead of hammering', () async {
      var pulls = 0;
      final throttled = MessagingService(
        core: core,
        identity: identity,
        database: database,
        relay: RelayClient(
          httpClient: MockClient((request) async {
            if (request.url.path == '/v1/pull') {
              pulls++;
              return http.Response('{"error":"rate limit exceeded"}', 429);
            }
            return http.Response(
              jsonEncode({
                'challenge_id': 'ch-1',
                'nonce_b64': base64Encode(_randomBytes(16)),
                'eph_pubkey_b64': base64Encode(
                  core.identityPublicKey(core.identityGenerate().secret),
                ),
              }),
              200,
            );
          }),
        )..baseUrl = 'https://relay.test',
      );
      await throttled.loadBlocked();
      var now = DateTime.utc(2026, 8, 12, 12);
      throttled.clock = () => now;

      await throttled.pullFromRelay();
      // The 8 s timer keeps firing; the budget is per IP and shared with every
      // other device on this network, so the next cycles must not spend it.
      await throttled.pullFromRelay();
      await throttled.pullFromRelay();

      expect(pulls, 1);
      // Being throttled is not the relay being broken, and a banner that comes
      // and goes on its own is one people stop reading.
      expect(throttled.relayPullFault, isNull);

      now = now.add(MessagingService.relayBackoff);
      await throttled.pullFromRelay();

      expect(pulls, 2);
      throttled.dispose();
    });

    test('being unreachable is not shown as a broken relay', () async {
      // Offline is ordinary and passes on its own; a banner for it would be a
      // banner people learn to ignore before the real one arrives.
      final offline = MessagingService(
        core: core,
        identity: identity,
        database: database,
        relay: RelayClient(
          httpClient: MockClient(
            (_) async => throw const SocketException('sin red'),
          ),
        )..baseUrl = 'https://relay.test',
      );
      await offline.loadBlocked();

      await offline.pullFromRelay();

      expect(offline.relayPullFault, isNull);
      offline.dispose();
    });

    test('a challenge that vanished is not retried, a new one is asked '
        'for', () async {
      relay
        ..deposit(identity.token!, sealTextFromBob('hola'))
        ..loseNextChallenge = true;

      await messaging.pullFromRelay();

      // First attempt got a 401 for a challenge that no longer existed; the
      // second asked for a fresh one instead of replaying the same id, which the
      // relay would refuse forever (it only consumes one on success).
      expect(relay.challengesIssued, 2);
      expect(relay.pullsServed, 1);
      expect((await messaging.messagesFor(bob.token)).single.plaintext, 'hola');
    });

    test('a proof built for another mailbox is refused', () async {
      final client = relay.client();
      final challenge = await client.challenge();
      final stranger = core.identityGenerate();

      // Our key, our proof, somebody else's mailbox: the pubkey does not hash to
      // that token, and the proof would not cover it either.
      await expectLater(
        client.pull(
          challengeId: challenge.id,
          destToken: stranger.token,
          publicKey: identity.publicKey!,
          proof: core.popProof(
            secret: identity.requireSecret(),
            ephPubkey: challenge.ephPubkey,
            nonce: challenge.nonce,
            destToken: stranger.token,
          ),
        ),
        throwsA(isA<RelayAuthException>()),
      );
    });

    test('a proof over the wrong nonce is refused', () async {
      final client = relay.client();
      final challenge = await client.challenge();

      await expectLater(
        client.pull(
          challengeId: challenge.id,
          destToken: identity.token!,
          publicKey: identity.publicKey!,
          proof: core.popProof(
            secret: identity.requireSecret(),
            ephPubkey: challenge.ephPubkey,
            nonce: _randomBytes(16),
            destToken: identity.token!,
          ),
        ),
        throwsA(isA<RelayAuthException>()),
      );
    });
  });

  test('an inbound blob is filed under its authenticated sender', () async {
    await messaging.handleRelayBlob(sealTextFromBob('hola'));

    final messages = await messaging.messagesFor(bob.token);
    expect(messages.single.plaintext, 'hola');
    expect(messages.single.status, MessageStatus.viaRelay);
    expect(messages.single.direction, MessageDirection.inbound);
    expect(messaging.inboundDrops, isEmpty);
  });

  test('media travels sealed and lands as an attachment', () async {
    final envelope = MediaEnvelope(
      mime: 'image/jpeg',
      name: 'foto.jpg',
      data: Uint8List.fromList(List<int>.generate(512, (i) => i % 256)),
    );

    await messaging.handleRelayBlob(sealFromBob(envelope.encode()));

    final media = (await messaging.messagesFor(bob.token)).single;
    expect(media.kind, MessageKind.media);
    expect(media.mime, 'image/jpeg');
    expect(media.status, MessageStatus.viaRelay);
    expect(await messaging.mediaBytesFor(media), envelope.data);
  });

  test('the same blob twice is stored once', () async {
    final blob = sealTextFromBob('hola');

    await messaging.handleRelayBlob(blob);
    await messaging.handleRelayBlob(blob);

    expect(await database.messageCount(), 1);
    expect(messaging.inboundDrops, {InboundDropReason.replay: 1});
    expect(messaging.lastDrop, InboundDropReason.replay);
    // One id per delivered blob, and the replay did not add a second row.
    expect(await database.seenSealedCount(), 1);
  });

  test('a replay is still refused after a restart', () async {
    final blob = sealTextFromBob('hola');
    await messaging.handleRelayBlob(blob);
    await database.close();

    // Same device, new process: the seen-id set lives in the database, so the
    // window is not a fresh start for an attacker who kept the blob.
    final reopened = LocalDatabase(storage: const FlutterSecureStorage());
    await reopened.open();
    final restarted = MessagingService(
      core: core,
      identity: identity,
      database: reopened,
      relay: relay.client(),
    );
    await restarted.loadBlocked();

    await restarted.handleRelayBlob(blob);

    expect(await reopened.messageCount(), 1);
    expect(restarted.inboundDrops, {InboundDropReason.replay: 1});
    restarted.dispose();
    database = reopened;
  });

  /// B-1: the relay stopped deleting a blob when it hands it over. It leases it
  /// for 60 s and delivers it a second and last time if the client comes back,
  /// and the only failure that covers is a client killed between the `200` and
  /// its own write. Recording the `msg_id` — a durable commit — *before* the
  /// message was inserted turned that redelivery into a replay and lost the
  /// message in silence, in exactly the case the lease was built for.
  ///
  /// So the id goes in last, and these pin what that costs and what it does not.
  group('the seen id is written after the message, not before', () {
    test('a write that dies before it lands leaves the id free, and the '
        'second delivery arrives', () async {
      final blob = sealTextFromBob('la que no se puede perder');

      // Same database file, an insert that dies inside the write.
      await database.close();
      final dying = _DyingDatabase(storage: const FlutterSecureStorage());
      await dying.open();
      final doomed = MessagingService(
        core: core,
        identity: identity,
        database: dying,
        relay: relay.client(),
      )..setContacts([bob]);
      await doomed.loadBlocked();

      await expectLater(
        doomed.handleRelayBlob(blob),
        throwsA(isA<StateError>()),
      );

      expect(await dying.messageCount(), 0);
      // The assertion the whole finding is about. An id here with no message to
      // show for it is a message that can never arrive again.
      expect(await dying.seenSealedCount(), 0);
      doomed.dispose();
      await dying.close();

      // New process on the same device, and the blob is still under lease.
      final reopened = LocalDatabase(storage: const FlutterSecureStorage());
      await reopened.open();
      final restarted = MessagingService(
        core: core,
        identity: identity,
        database: reopened,
        relay: relay.client(),
      )..setContacts([bob]);
      await restarted.loadBlocked();

      await restarted.handleRelayBlob(blob);

      expect(
        (await restarted.messagesFor(bob.token)).single.plaintext,
        'la que no se puede perder',
      );
      // Not a replay: nothing had been written under this id.
      expect(restarted.inboundDrops, isEmpty);
      expect(await reopened.seenSealedCount(), 1);
      restarted.dispose();
      // tearDown closes whatever `database` points at.
      database = reopened;
    });

    test('a delivery that did land is refused by the message table, not by '
        'the id', () async {
      final blob = sealTextFromBob('hola');
      await messaging.handleRelayBlob(blob);
      // The window the other way round: the message is in, the id write is the
      // one that never happened. `insertMessageIfNew` is what has to hold.
      await database.db.delete('seen_sealed');

      await messaging.handleRelayBlob(blob);

      expect(await database.messageCount(), 1);
      expect(messaging.inboundDrops, {InboundDropReason.replay: 1});
    });

    test('a payload that will never parse does burn its id', () async {
      // Not UTF-8, not a media envelope, not a call signal: a `FormatException`
      // on the way in, and a verdict a second copy cannot change. This one is
      // remembered on purpose, so the redelivery costs a lookup instead of a
      // second decode.
      final blob = sealFromBob(Uint8List.fromList([0xff, 0xfe, 0xff, 0xfe]));

      await messaging.handleRelayBlob(blob);
      await messaging.handleRelayBlob(blob);

      expect(await database.seenSealedCount(), 1);
      expect(messaging.inboundDrops, {
        InboundDropReason.unreadable: 1,
        InboundDropReason.replay: 1,
      });
    });

    test('an attachment refused for space is left re-deliverable', () async {
      // A ceiling this device owns, not a verdict on the blob: the user frees
      // room and the lease's second delivery is what makes that worth anything.
      final metered = MessagingService(
        core: core,
        identity: identity,
        database: database,
        relay: relay.client(),
        mediaStore: MediaStore(
          core: core,
          database: database,
          maxInboundBytesPerPeer: 4096,
        ),
      )..setContacts([bob]);
      addTearDown(metered.dispose);
      await metered.loadBlocked();
      final first = sealFromBob(_envelope(3072));
      final second = sealFromBob(_envelope(3072));

      await metered.handleRelayBlob(first);
      await metered.handleRelayBlob(second);

      expect(metered.inboundDrops, {InboundDropReason.mediaQuota: 1});
      // One id, not two.
      expect(await database.seenSealedCount(), 1);

      await metered.deleteConversation(bob.token);
      await metered.handleRelayBlob(second);

      expect(await database.listMediaRelPaths(), hasLength(1));
      expect(await database.seenSealedCount(), 2);
    });
  });

  test('a tampered blob is forged, not attributed to anyone', () async {
    final mallory = core.identityGenerate();
    final blob = core
        .sealedSeal(
          senderSecret: mallory.secret,
          recipientPublicKey: identity.publicKey!,
          plaintext: Uint8List.fromList(utf8.encode('soy Bob, mandame plata')),
        )
        .blob;
    // The body is authenticated: flipping a bit breaks the sender binding.
    blob[blob.length - 1] ^= 0xff;

    await messaging.handleRelayBlob(blob);

    expect(await database.messageCount(), 0);
    expect(messaging.inboundDrops, {InboundDropReason.forged: 1});
    expect(messaging.sawForgedSender, isTrue);
    // Nothing was written under the real sender either: there is no declared
    // sender to fall back to, which is the whole point of the format.
    expect(await messaging.messagesFor(bob.token), isEmpty);
    expect(await messaging.messagesFor(mallory.token), isEmpty);
  });

  test('a pre-0.8.0 payload is refused, declared sender and all', () async {
    // Exactly what an older client used to enqueue: an EC01 blob whose JSON
    // claimed a sender. It opens with `decrypt`, which is why it had to stop
    // being the format the relay path accepts.
    final legacy = core.encryptUtf8(
      recipientPublicKey: identity.publicKey!,
      plaintext: jsonEncode({'v': 1, 'from': bob.token, 'body': 'hola'}),
    );

    await messaging.handleRelayBlob(legacy);

    expect(await database.messageCount(), 0);
    expect(messaging.inboundDrops, {InboundDropReason.legacyFormat: 1});
  });

  test('a truncated blob reads as truncated, not as forged', () async {
    final blob = sealTextFromBob('hola');

    await messaging.handleRelayBlob(blob.sublist(0, 120));

    expect(messaging.inboundDrops, {InboundDropReason.truncated: 1});
    expect(messaging.sawForgedSender, isFalse);
  });

  test('a blob for another identity reads as not ours', () async {
    // Sealed towards Bob, so it is authentic but undecryptable here.
    final other = core.identityGenerate();
    final blob = sealFromBob(
      Uint8List.fromList(utf8.encode('para otro')),
      recipientPublicKey: core.identityPublicKey(other.secret),
    );

    await messaging.handleRelayBlob(blob);

    expect(messaging.inboundDrops, {InboundDropReason.notForUs: 1});
    expect(messaging.sawForgedSender, isFalse);
  });

  test('an authentic blob outside the window reads as expired', () async {
    final blob = sealTextFromBob('hola');
    // The `sent_at` is bound inside the ciphertext, so the only way past the
    // window is time itself: eight days after it was sealed.
    messaging.clock = () => DateTime.now().toUtc().add(const Duration(days: 8));

    await messaging.handleRelayBlob(blob);

    expect(await database.messageCount(), 0);
    expect(messaging.inboundDrops, {InboundDropReason.expired: 1});
    // Authenticated first: an old message is never reported as an attack.
    expect(messaging.sawForgedSender, isFalse);
  });

  test('a blocked sender cannot get through by sealing', () async {
    await messaging.block(bob.token);

    await messaging.handleRelayBlob(sealTextFromBob('hola'));

    expect(await database.messageCount(), 0);
    // The blocklist now decides on the authenticated token, so a blocked peer
    // has nothing left to declare.
    expect(await database.seenSealedCount(), 0);
  });

  test('call signaling by relay does not ring', () async {
    final rung = <String>[];
    messaging.onCallSignal = (from, signal) => rung.add(from);
    final invite = CallSignal(
      type: CallSignalType.invite,
      callId: 'call-1',
      media: CallMediaMode.av,
    );

    await messaging.handleRelayBlob(sealFromBob(invite.encode()));

    expect(rung, isEmpty);
    expect(messaging.inboundDrops, {InboundDropReason.callSignal: 1});
  });

  test('seen ids are pruned once the window has passed', () async {
    await messaging.handleRelayBlob(sealTextFromBob('hola'));
    expect(await database.seenSealedCount(), 1);

    // Inside the window a pull must not forget anything.
    await messaging.pullFromRelay();
    expect(await database.seenSealedCount(), 1);

    // Past it, the blob would be rejected as `Expired` anyway, so the id is
    // dead weight and the table gives it back.
    messaging.clock = () => DateTime.now().toUtc().add(const Duration(days: 8));
    await messaging.pullFromRelay();
    expect(await database.seenSealedCount(), 0);
  });

  group('the seen-id table cannot be emptied on demand', () {
    /// The horizon `MessagingService` prunes with: the freshness window plus the
    /// skew, behind the local clock.
    int horizonFor(int nowUnix) =>
        nowUnix -
        MessagingService.sealedFreshnessPast.inSeconds -
        MessagingService.sealedFreshnessSkew.inSeconds;

    test('retention follows when a blob arrived, not what its sender '
        'claims', () async {
      final now = _nowUnix();
      // A blob this device has held past the window: replaying it now earns
      // `Expired` from the core, so the id is genuinely dead weight — even
      // though its sender stamped it "just now".
      await database.recordSeenSealedId(
        'held-too-long',
        sentAtUnix: now,
        receivedAtUnix: now - const Duration(days: 8).inSeconds,
      );
      // And one that just landed claiming to be six days old: still replayable,
      // so the id has to stay. Under the old rule these two were inverted, which
      // is the whole bug — the sender picked which ids got forgotten.
      await database.recordSeenSealedId(
        'just-arrived',
        sentAtUnix: now - const Duration(days: 6).inSeconds,
        receivedAtUnix: now,
      );

      await database.pruneSeenSealedIds(
        receivedBeforeUnix: horizonFor(now),
        hardCap: MessagingService.seenSealedHardCap,
      );

      expect(await _seenIds(database), ['just-arrived']);
    });

    test('a flood of fresh blobs evicts nothing inside the window', () async {
      final now = _nowUnix();
      for (var i = 0; i < 40; i++) {
        await database.recordSeenSealedId(
          'flood-$i',
          sentAtUnix: now,
          receivedAtUnix: now,
        );
      }
      await database.recordSeenSealedId(
        'genuine',
        sentAtUnix: now - const Duration(days: 5).inSeconds,
        receivedAtUnix: now - const Duration(days: 5).inSeconds,
      );

      final result = await database.pruneSeenSealedIds(
        receivedBeforeUnix: horizonFor(now),
        hardCap: MessagingService.seenSealedHardCap,
      );

      // Nothing was evicted to make room. The old ceiling did exactly that, and
      // since relay deposits are not authenticated it was reachable by anyone:
      // 20 000 blobs bought a replay of a genuine message.
      expect(result.removed, 0);
      expect(result.held, 41);
      expect(await _seenIds(database), contains('genuine'));
    });

    test('the hard cap keeps the newest arrivals, and only there', () async {
      final now = _nowUnix();
      for (var i = 0; i < 5; i++) {
        await database.recordSeenSealedId(
          'id-$i',
          sentAtUnix: now,
          // Distinct arrival seconds, so which two go is not a coin toss.
          receivedAtUnix: now - (5 - i),
        );
      }

      final result = await database.pruneSeenSealedIds(
        receivedBeforeUnix: horizonFor(now),
        hardCap: 3,
      );

      expect(result.held, 3);
      expect(await _seenIds(database), ['id-2', 'id-3', 'id-4']);
    });

    test('a forgotten id cannot move an old message back to the top', () async {
      final blob = sealTextFromBob('hola de hace días');
      await messaging.handleRelayBlob(blob);
      final original = (await messaging.messagesFor(bob.token)).single;

      // The eviction the attack was aiming for, done by hand: the id is gone, so
      // the blob opens and passes the replay check.
      await database.db.delete('seen_sealed');
      await messaging.refreshPeer(bob.token);
      await messaging.handleRelayBlob(blob);

      // It got no further: inbound rows are inserted, never replaced, so the
      // message keeps its place and its timestamp instead of surfacing as new.
      expect(await database.messageCount(), 1);
      final stored = (await messaging.messagesFor(bob.token)).single;
      expect(stored.createdAt, original.createdAt);
      expect(messaging.inboundDrops, {InboundDropReason.replay: 1});
    });

    test('a forgotten media id does not rewrite the attachment', () async {
      final envelope = MediaEnvelope(
        mime: 'image/jpeg',
        name: 'foto.jpg',
        data: Uint8List.fromList(List<int>.generate(256, (i) => i)),
      );
      final blob = sealFromBob(envelope.encode());
      await messaging.handleRelayBlob(blob);
      final stored = (await messaging.messagesFor(bob.token)).single;

      await database.db.delete('seen_sealed');
      await messaging.refreshPeer(bob.token);
      await messaging.handleRelayBlob(blob);

      expect(await database.messageCount(), 1);
      expect(
        await database.listMediaRelPaths(),
        [stored.mediaRelPath],
        reason: 'a second sealed copy would be a byte nobody can reach',
      );
      expect(messaging.inboundDrops, {InboundDropReason.replay: 1});
    });
  });

  test('the drop tally is dismissable', () async {
    await messaging.handleRelayBlob(sealTextFromBob('hola').sublist(0, 120));
    expect(messaging.dropCount, 1);

    messaging.clearDrops();

    expect(messaging.inboundDrops, isEmpty);
    expect(messaging.lastDrop, isNull);
    expect(messaging.sawForgedSender, isFalse);
  });
}

int _nowUnix() => DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

Uint8List _envelope(int bytes) => MediaEnvelope(
  mime: 'image/png',
  name: 'foto.png',
  data: Uint8List(bytes),
).encode();

/// A database whose message insert never completes — the app killed by the OS
/// with the write half done, which is the one thing the relay's lease exists to
/// survive and the one thing the old write order turned into a lost message.
class _DyingDatabase extends LocalDatabase {
  _DyingDatabase({super.storage});

  @override
  Future<bool> insertMessageIfNew(ChatMessage message) async {
    throw StateError('el proceso murió acá');
  }
}

/// Remembered ids, oldest arrival first.
Future<List<String>> _seenIds(LocalDatabase database) async {
  final rows = await database.db.query(
    'seen_sealed',
    columns: ['msg_id'],
    orderBy: 'received_at_unix ASC',
  );
  return [for (final r in rows) r['msg_id']! as String];
}

Uint8List _randomBytes(int length) {
  final rnd = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(length, (_) => rnd.nextInt(256)),
  );
}

/// Stands in for the relay: a mailbox per destination and the **post-F-8** HTTP
/// contract, enforced the way the server enforces it.
///
/// Being strict is the point. The previous version of this fake answered any
/// pull with `200 {"messages": []}`, so the whole relay suite stayed green while
/// `RelayClient` was still speaking the pre-F-8 shape and no client could
/// actually pull from a relay — the `422` went straight into the poll loop's
/// `catch`, every 8 s, forever. A permissive fake is worse than no test.
///
/// What it does not do is re-implement the relay. The proof of possession is
/// *verified*, using the same FFI the client uses — the ECDH is symmetric, so the
/// ephemeral side recomputes the same proof — and so is the `pubkey ↔ dest_token`
/// binding, because without it a proof over somebody else's token would open
/// their mailbox. TTL, quotas, rate limits and storage are the relay's own tests.
class FakeRelay {
  FakeRelay(this._core);

  final EncrypchatCore _core;

  /// Blobs waiting per destination token, oldest first.
  final Map<String, List<Uint8List>> mailboxes = {};

  /// Everything this client enqueued, in order, whoever it was for.
  final List<Uint8List> enqueued = [];

  /// Raw bodies posted to `/v1/challenge`: a test reads them to check that the
  /// destination never travels there.
  final List<String> challengeBodies = [];

  final Map<String, _LiveChallenge> _live = {};
  int challengesIssued = 0;
  int pullsServed = 0;

  /// Drops the next issued challenge before it can be spent — what an expiry or
  /// the relay's global trim looks like from the client's side.
  bool loseNextChallenge = false;

  /// Refuses every pull body as unparseable: a relay on a contract this client
  /// does not speak, whatever the direction of the drift.
  bool refusePullShape = false;

  void deposit(String destToken, Uint8List blob) =>
      mailboxes.putIfAbsent(destToken.trim().toLowerCase(), () => []).add(blob);

  List<Uint8List> waitingFor(String destToken) =>
      mailboxes[destToken.trim().toLowerCase()] ?? const [];

  RelayClient client() =>
      RelayClient(httpClient: MockClient(_handle))
        ..baseUrl = 'https://relay.test';

  /// The bare HTTP client, for tests that post a body `RelayClient` can no
  /// longer produce — the old pull shape, for one.
  http.Client rawClient() => MockClient(_handle);

  /// The proof the relay expects for [challengeId] from the holder of
  /// [publicKey], reading [destToken] out of the transcript.
  Uint8List expectedProof({
    required String challengeId,
    required String destToken,
    required Uint8List publicKey,
  }) {
    final ch = _live[challengeId]!;
    return _core.popProof(
      secret: ch.ephSecret,
      ephPubkey: publicKey,
      nonce: ch.nonce,
      destToken: destToken,
    );
  }

  /// The id of the challenge issued last and not yet spent.
  String get lastChallengeId => _live.keys.last;

  Future<http.Response> _handle(http.Request request) async {
    switch (request.url.path) {
      case '/v1/enqueue':
        return _enqueue(request);
      case '/v1/challenge':
        return _challenge(request);
      case '/v1/pull':
        return _pull(request);
      default:
        return http.Response('not found', 404);
    }
  }

  http.Response _enqueue(http.Request request) {
    final body = jsonDecode(request.body);
    if (body is! Map<String, dynamic>) return _error(400, 'invalid json');
    final dest = body['dest_token'];
    final blobB64 = body['blob_b64'];
    if (dest is! String || blobB64 is! String) {
      return _error(422, 'missing field');
    }
    final blob = base64Decode(blobB64);
    enqueued.add(blob);
    deposit(dest, blob);
    return _json({'id': 'relay-${enqueued.length}'});
  }

  http.Response _challenge(http.Request request) {
    // Recorded, not read: the handler takes no body extractor at all, which is
    // exactly what stops it from learning which mailbox is about to be read.
    challengeBodies.add(request.body);
    final eph = _core.identityGenerate();
    final id = 'ch-${++challengesIssued}';
    final nonce = _randomBytes(16);
    if (!loseNextChallenge) {
      _live[id] = _LiveChallenge(ephSecret: eph.secret, nonce: nonce);
    }
    loseNextChallenge = false;
    return _json({
      'challenge_id': id,
      'nonce_b64': base64Encode(nonce),
      'eph_pubkey_b64': base64Encode(_core.identityPublicKey(eph.secret)),
    });
  }

  http.Response _pull(http.Request request) {
    if (refusePullShape) return _error(422, 'unknown field');
    final body = jsonDecode(request.body);
    if (body is! Map<String, dynamic>) return _error(400, 'invalid json');
    final id = body['challenge_id'];
    final dest = body['dest_token'];
    final pubB64 = body['pubkey_b64'];
    final proofB64 = body['proof_b64'];
    if (id is! String ||
        dest is! String ||
        pubB64 is! String ||
        proofB64 is! String) {
      // What axum answers for a body it parsed but cannot deserialize, and what
      // the pre-F-8 shape (no `challenge_id`) gets.
      return _error(422, 'missing field');
    }
    final pubkey = base64Decode(pubB64);
    if (pubkey.length != 32) return _error(400, 'invalid pubkey');
    final token = dest.trim().toLowerCase();
    if ('ec_${sha256.convert(pubkey)}' != token) {
      // Without this a proof anybody can build over a stranger's token would
      // empty that stranger's mailbox.
      return _error(401, 'pubkey does not match dest_token');
    }
    final ch = _live[id];
    if (ch == null) return _error(401, 'no valid challenge');
    final expected = _core.popProof(
      secret: ch.ephSecret,
      ephPubkey: pubkey,
      nonce: ch.nonce,
      destToken: token,
    );
    if (!_sameBytes(expected, base64Decode(proofB64))) {
      // Not consumed: the relay only spends a challenge whose proof verified.
      return _error(401, 'pop failed');
    }
    _live.remove(id);
    pullsServed++;
    final waiting = mailboxes.remove(token) ?? const <Uint8List>[];
    return _json({
      'messages': [
        for (var i = 0; i < waiting.length; i++)
          {'id': 'msg-$i', 'blob_b64': base64Encode(waiting[i])},
      ],
    });
  }

  http.Response _json(Map<String, Object?> body) =>
      http.Response(jsonEncode(body), 200);

  http.Response _error(int status, String message) =>
      http.Response(jsonEncode({'error': message}), status);
}

class _LiveChallenge {
  _LiveChallenge({required this.ephSecret, required this.nonce});

  final Uint8List ephSecret;
  final Uint8List nonce;
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _contains(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
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
