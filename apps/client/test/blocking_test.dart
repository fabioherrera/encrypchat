import 'dart:convert';
import 'dart:io';

import 'package:encrypchat/core/call_signal.dart';
import 'package:encrypchat/core/encrypchat_core.dart';
import 'package:encrypchat/core/media_envelope.dart';
import 'package:encrypchat/core/wire_frame.dart';
import 'package:encrypchat/models/contact.dart';
import 'package:encrypchat/services/identity_service.dart';
import 'package:encrypchat/services/local_database.dart';
import 'package:encrypchat/services/messaging_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// End-to-end block enforcement against the real FFI core and a real SQLite
/// file: what the stores ask for is that traffic from a blocked identity never
/// reaches the user, so the test drives the same entry points the P2P poller
/// and the relay pull use.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late EncrypchatCore core;
  late LocalDatabase database;
  late IdentityService identity;
  late MessagingService messaging;

  /// Bob is the peer that gets blocked; his identity only exists to produce
  /// frames addressed to the local user.
  late Contact bob;
  late Uint8List bobSecret;

  Uint8List frameFromBob(Uint8List plaintext) {
    return WireFrame.create(
      senderToken: bob.token,
      ciphertext: core.encrypt(
        recipientPublicKey: identity.publicKey!,
        plaintext: plaintext,
      ),
    ).encode();
  }

  Future<LocalDatabase> openDatabase() async {
    final db = LocalDatabase(storage: const FlutterSecureStorage());
    await db.open();
    return db;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('encrypchat_block_test');
    _mockPathProvider(tempDir);
    _mockSecureStorage();

    core = EncrypchatCore.open();
    database = await openDatabase();
    identity = IdentityService(
      core: core,
      storage: const FlutterSecureStorage(),
    );
    await identity.create();

    final bobIdentity = core.identityGenerate();
    bobSecret = bobIdentity.secret;
    bob = Contact(
      token: bobIdentity.token,
      publicKey: core.identityPublicKey(bobSecret),
      displayName: 'Bob',
    );

    messaging = MessagingService(
      core: core,
      identity: identity,
      database: database,
    );
    messaging.setContacts([bob]);
    await messaging.loadBlocked();
  });

  tearDown(() async {
    messaging.dispose();
    await database.close();
    await tempDir.delete(recursive: true);
  });

  test('a text message from a blocked peer is dropped, not stored', () async {
    await messaging.block(bob.token);

    await messaging.handleInboundFrame(
      frameFromBob(Uint8List.fromList(utf8.encode('hola'))),
    );

    expect(await database.messageCount(), 0);
    expect(await messaging.messagesFor(bob.token), isEmpty);

    // Same frame after unblocking: proves the drop was the block, not a decode
    // failure, and that unblocking restores delivery.
    await messaging.unblock(bob.token);
    await messaging.handleInboundFrame(
      frameFromBob(Uint8List.fromList(utf8.encode('hola'))),
    );
    expect(await database.messageCount(), 1);
  });

  test(
    'media from a blocked peer is dropped and nothing hits the disk',
    () async {
      await messaging.block(bob.token);
      final envelope = MediaEnvelope(
        mime: 'image/jpeg',
        name: 'foto.jpg',
        data: Uint8List.fromList(List<int>.generate(64, (i) => i)),
      );

      await messaging.handleInboundFrame(frameFromBob(envelope.encode()));

      expect(await database.messageCount(), 0);
      final mediaDir = Directory(p.join(tempDir.path, 'media'));
      expect(mediaDir.existsSync(), isFalse);
    },
  );

  test('call signaling from a blocked peer never rings', () async {
    final rung = <String>[];
    messaging.onCallSignal = (from, signal) => rung.add(from);
    await messaging.block(bob.token);

    final invite = CallSignal(
      type: CallSignalType.invite,
      callId: 'call-1',
      media: CallMediaMode.audio,
    );
    await messaging.handleInboundFrame(frameFromBob(invite.encode()));

    expect(rung, isEmpty);

    await messaging.unblock(bob.token);
    await messaging.handleInboundFrame(frameFromBob(invite.encode()));
    expect(rung, [bob.token]);
  });

  test('relay-delivered messages from a blocked peer are dropped', () async {
    await messaging.block(bob.token);
    // Sealed by Bob himself: the token the block acts on comes out of the
    // ciphertext, so there is no declared sender to swap for a trusted one.
    final blob = core
        .sealedSeal(
          senderSecret: bobSecret,
          recipientPublicKey: identity.publicKey!,
          plaintext: Uint8List.fromList(utf8.encode('hola')),
        )
        .blob;

    await messaging.handleRelayBlob(blob);

    expect(await database.messageCount(), 0);

    // Unblocking lets the same identity through, which is what proves the drop
    // was the block and not a format failure.
    await messaging.unblock(bob.token);
    await messaging.handleRelayBlob(blob);
    expect(await database.messageCount(), 1);
  });

  test(
    'sending to a blocked peer is refused before touching the node',
    () async {
      await messaging.block(bob.token);

      await expectLater(
        messaging.sendText(peer: bob, text: 'hola'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('bloqueado'),
          ),
        ),
      );
      await expectLater(
        messaging.sendCallSignal(
          peer: bob,
          signal: CallSignal(
            type: CallSignalType.invite,
            callId: 'call-1',
            media: CallMediaMode.audio,
          ),
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('the block survives closing and reopening the database', () async {
    await messaging.block(bob.token);
    await database.close();

    final reopened = await openDatabase();
    final restored = MessagingService(
      core: core,
      identity: identity,
      database: reopened,
    );
    await restored.loadBlocked();

    expect(restored.isBlocked(bob.token), isTrue);
    // Casing must not be a bypass: tokens are hex and compared normalized.
    expect(restored.isBlocked(bob.token.toUpperCase()), isTrue);
    expect(restored.blockedTokens, [bob.token]);

    restored.dispose();
    database = reopened;
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
