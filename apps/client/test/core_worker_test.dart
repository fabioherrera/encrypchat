import 'dart:io';

import 'package:encrypchat/core/core_error.dart';
import 'package:encrypchat/core/encrypchat_core.dart';
import 'package:encrypchat/core/native_library.dart';
import 'package:encrypchat/models/chat_message.dart';
import 'package:encrypchat/models/contact.dart';
import 'package:encrypchat/services/identity_service.dart';
import 'package:encrypchat/services/local_database.dart';
import 'package:encrypchat/services/messaging_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// F-11: the node calls with a blocking budget run off the UI isolate.
///
/// `node_send` waits up to 15 s for the peer's ACK and `node_connect` up to 10 s
/// for the dial plus handshake; on the main isolate that is a frozen interface
/// and, on Android, an ANR. The spy is what makes the move observable: it counts
/// the calls that reach **this** isolate's core object, so a send that still
/// comes back with a real `CoreError` while the spy stays at zero can only have
/// happened somewhere else.
class _SpyCore extends EncrypchatCore {
  _SpyCore(super.lib);

  int sendsHere = 0;
  int connectsHere = 0;

  @override
  void nodeSend({
    required String peerToken,
    required Uint8List frame,
    int? handleAddress,
  }) {
    sendsHere++;
    super.nodeSend(
      peerToken: peerToken,
      frame: frame,
      handleAddress: handleAddress,
    );
  }

  @override
  void nodeConnect(String multiaddr, {int? handleAddress}) {
    connectsHere++;
    super.nodeConnect(multiaddr, handleAddress: handleAddress);
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

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('encrypchat_worker');
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

    final generated = core.identityGenerate();
    bob = Contact(
      token: generated.token,
      publicKey: core.identityPublicKey(generated.secret),
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

  test('starting the node brings up the worker', () async {
    expect(messaging.sendsOffIsolate, isFalse);

    await messaging.startNode();

    expect(messaging.sendsOffIsolate, isTrue);
    await messaging.stopNode();
    // Stopping takes the worker with it: a stale one would hold a freed handle.
    expect(messaging.sendsOffIsolate, isFalse);
  });

  test('a send does not run on this isolate and still reports the core '
      'verdict', () async {
    await messaging.startNode();

    // Bob has no session, so the core answers `PeerOffline` (8) — and with no
    // relay configured that becomes the message's error.
    await expectLater(
      messaging.sendText(peer: bob, text: 'hola'),
      throwsA(isA<CoreException>().having((e) => e.code, 'code', 8)),
    );

    expect(
      core.sendsHere,
      0,
      reason: 'the blocking call must not happen on the UI isolate',
    );
    final stored = await messaging.messagesFor(bob.token);
    expect(stored.single.status, MessageStatus.error);
    await messaging.stopNode();
  });

  test('dialing does not run on this isolate either', () async {
    await messaging.startNode();

    // Nothing is listening on that port, so the dial fails — the point is where
    // it fails from.
    await expectLater(
      messaging.connectHostPort('127.0.0.1', 1),
      throwsA(anything),
    );

    expect(core.connectsHere, 0);
    expect(messaging.lastError, isNotNull);
    await messaging.stopNode();
  });

  test('sends keep their order and all finish before the node stops', () async {
    await messaging.startNode();

    // Queued together: the worker processes them in order, and the stop is
    // queued behind them, which is what keeps the shared handle safe.
    final sends = [
      for (var i = 0; i < 5; i++)
        messaging
            .sendText(peer: bob, text: 'mensaje $i')
            .catchError(
              (Object _) => ChatMessage(
                id: 'x$i',
                peerToken: bob.token,
                direction: MessageDirection.outbound,
                bodySealed: Uint8List(0),
                status: MessageStatus.error,
                createdAt: DateTime.now().toUtc(),
              ),
            ),
    ];
    await Future.wait(sends);
    await messaging.stopNode();

    expect(core.sendsHere, 0);
    final stored = await messaging.messagesFor(bob.token);
    expect(stored.map((m) => m.plaintext), [
      for (var i = 0; i < 5; i++) 'mensaje $i',
    ]);
    expect(messaging.nodeRunning, isFalse);
  });

  test('a stopped node refuses further sends instead of using a freed '
      'handle', () async {
    await messaging.startNode();
    await messaging.stopNode();

    await expectLater(
      messaging.sendText(peer: bob, text: 'hola'),
      throwsA(isA<StateError>()),
    );
  });

  test('the core drives a node by address exactly as by handle', () async {
    // The equivalence the worker depends on: same node, reached through an
    // integer instead of a pointer.
    core.nodeStart(secret: identity.requireSecret());
    final address = core.nodeHandleAddress;
    expect(address, isNotNull);

    expect(
      () => core.nodeSend(
        peerToken: bob.token,
        frame: Uint8List.fromList([1, 2, 3]),
        handleAddress: address,
      ),
      throwsA(isA<CoreException>().having((e) => e.code, 'code', 8)),
    );

    core.nodeStopAt(core.detachNode()!);
    expect(core.isNodeRunning, isFalse);
    // A zero address is the teardown case, not a crash.
    core.nodeStopAt(0);
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
