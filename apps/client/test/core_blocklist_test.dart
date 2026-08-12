import 'dart:ffi';
import 'dart:io';

import 'package:encrypchat/core/core_error.dart';
import 'package:encrypchat/core/encrypchat_core.dart';
import 'package:encrypchat/core/native_library.dart';
import 'package:encrypchat/core/wire_frame.dart';
import 'package:encrypchat/models/chat_message.dart';
import 'package:encrypchat/models/contact.dart';
import 'package:encrypchat/services/identity_service.dart';
import 'package:encrypchat/services/local_database.dart';
import 'package:encrypchat/services/messaging_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// The core keeps its own blocklist as defence in depth (it refuses a blocked
/// token at the handshake), but it starts empty on every `node_start` and never
/// merges. These tests pin the moments the client has to (re)push it, and that
/// the Dart cut keeps working when the push fails.
///
/// The spy calls through to the real FFI, so the binding — array of C strings,
/// allocation and free — is exercised against the actual `.so`.
class _SpyCore extends EncrypchatCore {
  _SpyCore(super.lib);

  final List<List<String>> pushes = [];
  bool failNextPushes = false;

  @override
  void nodeSetBlockedTokens(List<String> tokens) {
    pushes.add(List.of(tokens));
    if (failNextPushes) {
      throw CoreException(CoreException.internal, 'spy failure');
    }
    super.nodeSetBlockedTokens(tokens);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _SpyCore core;
  late LocalDatabase database;
  late IdentityService identity;
  late MessagingService messaging;
  late Contact bob;
  late Contact carol;

  Contact freshContact(String name) {
    final generated = core.identityGenerate();
    return Contact(
      token: generated.token,
      publicKey: core.identityPublicKey(generated.secret),
      displayName: name,
    );
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('encrypchat_core_block');
    _mockPathProvider(tempDir);
    _mockSecureStorage();

    core = _SpyCore(loadEncrypchatCore());
    database = LocalDatabase(storage: const FlutterSecureStorage());
    await database.open();
    identity = IdentityService(
      core: core,
      storage: const FlutterSecureStorage(),
    );
    await identity.create();

    bob = freshContact('Bob');
    carol = freshContact('Carol');

    messaging = MessagingService(
      core: core,
      identity: identity,
      database: database,
    );
    messaging.setContacts([bob, carol]);
    await messaging.loadBlocked();
  });

  tearDown(() async {
    messaging.dispose();
    await database.close();
    await tempDir.delete(recursive: true);
  });

  test('starting the node pushes the list the core lost', () async {
    // Blocked while the node is down: there is nothing to mirror yet.
    await messaging.block(bob.token);
    expect(core.pushes, isEmpty);

    await messaging.startNode();

    expect(core.pushes, [
      [bob.token],
    ]);
    await messaging.stopNode();
  });

  test('blocking and unblocking re-push the whole set', () async {
    await messaging.startNode();
    core.pushes.clear();

    await messaging.block(bob.token);
    await messaging.block(carol.token);
    await messaging.unblock(bob.token);

    // The core replaces, never merges: every push carries the full set.
    expect(core.pushes.length, 3);
    expect(core.pushes[0], [bob.token]);
    expect(core.pushes[1], unorderedEquals([bob.token, carol.token]));
    expect(core.pushes[2], [carol.token]);

    await messaging.stopNode();
  });

  test('a core that refuses the mirror does not weaken the block', () async {
    await messaging.startNode();
    core.failNextPushes = true;
    var notified = 0;
    messaging.addListener(() => notified++);

    await messaging.block(bob.token);

    // The user's action completed: stored, in memory, and the UI was told.
    expect(messaging.isBlocked(bob.token), isTrue);
    expect(await database.listBlockedTokens(), [bob.token]);
    expect(notified, greaterThan(0));

    // And the layer that actually enforces still cuts on its own.
    await messaging.handleInboundFrame(
      WireFrame.create(
        senderToken: bob.token,
        ciphertext: core.encryptUtf8(
          recipientPublicKey: identity.publicKey!,
          plaintext: 'hola',
        ),
      ).encode(),
    );
    expect(await database.messageCount(), 0);

    await messaging.stopNode();
  });

  test('a malformed stored token never reaches the core', () async {
    await database.blockToken('no-es-un-token');
    await messaging.loadBlocked();
    await messaging.block(bob.token);
    core.pushes.clear();

    await messaging.startNode();

    // The core rejects a whole list that carries one bad entry, which would
    // leave it with a stale set; Dart keeps blocking the junk token anyway.
    expect(core.pushes, [
      [bob.token],
    ]);
    expect(messaging.isBlocked('no-es-un-token'), isTrue);

    await messaging.stopNode();
  });

  test('a send the core refuses reads as a block, not an error code', () async {
    await messaging.startNode();
    await messaging.messagesFor(bob.token);
    // Pushed behind the service's back so the core knows about the block and
    // Dart does not: the only way to reach code 12, which is a safety net.
    core.nodeSetBlockedTokens([bob.token]);

    await expectLater(
      messaging.sendText(peer: bob, text: 'hola'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          MessagingService.blockedMessage,
        ),
      ),
    );

    final stored = await messaging.messagesFor(bob.token);
    expect(stored.single.status, MessageStatus.error);
    expect(stored.single.error, MessagingService.blockedMessage);

    await messaging.stopNode();
  });

  test('the loaded core satisfies the ABI this client needs', () {
    expect(EncrypchatCore.isApiCompatible(core.apiVersion()), isTrue);
  });

  test('the ABI floor rejects an older core and accepts a newer one', () {
    expect(EncrypchatCore.isApiCompatible('0.7.0'), isTrue);
    expect(EncrypchatCore.isApiCompatible('0.7.3'), isTrue);
    expect(EncrypchatCore.isApiCompatible('0.8.0'), isTrue);
    expect(EncrypchatCore.isApiCompatible('0.6.9'), isFalse);
    // A major bump is not assumed compatible either way.
    expect(EncrypchatCore.isApiCompatible('1.0.0'), isFalse);
    expect(EncrypchatCore.isApiCompatible('viejo'), isFalse);
  });

  test('a stale library fails with a sentence, not a symbol error', () {
    expect(
      () => EncrypchatCore.assertSupportedApiVersion(_emptyLibrary()),
      throwsA(
        isA<CoreVersionException>().having(
          (e) => e.message,
          'message',
          allOf(contains('make build-ffi'), contains('0.7.0')),
        ),
      ),
    );
  });
}

/// The process itself: has no Encrypchat symbol, so it stands in for a `.so`
/// too old to even report a version.
DynamicLibrary _emptyLibrary() => DynamicLibrary.executable();

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
