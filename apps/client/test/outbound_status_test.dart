import 'dart:convert';
import 'dart:io';

import 'package:encrypchat/core/encrypchat_core.dart';
import 'package:encrypchat/models/chat_message.dart';
import 'package:encrypchat/models/contact.dart';
import 'package:encrypchat/screens/chat_page.dart';
import 'package:encrypchat/services/call_service.dart';
import 'package:encrypchat/services/identity_service.dart';
import 'package:encrypchat/services/local_database.dart';
import 'package:encrypchat/services/messaging_service.dart';
import 'package:encrypchat/services/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the mark under an outbound message tells the user.
///
/// It is a test about copy because the bug is about copy. The relay stopped
/// distinguishing a mailbox over quota from an acceptance — that difference let
/// anyone holding a token learn when its owner came online — so a successful
/// enqueue no longer means the message is waiting for anybody. The client
/// cannot recover that bit and must not imply it: what is asserted here is that
/// the relay mark claims delivery to the relay and nothing past it, while the
/// P2P mark, which really is an acknowledgement, still says so.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late EncrypchatCore core;
  late LocalDatabase database;
  late IdentityService identity;
  late MessagingService messaging;
  late Contact friend;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('encrypchat_status');
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

  /// Opens the chat with one outbound message in [status].
  Future<void> openWith(WidgetTester tester, MessageStatus status) async {
    await tester.runAsync(() async {
      await database.upsertMessage(
        ChatMessage(
          id: 'm1',
          peerToken: friend.token,
          direction: MessageDirection.outbound,
          bodySealed: core.localSeal(
            dbKey: database.dbKey,
            plaintext: Uint8List.fromList(utf8.encode('hola')),
          ),
          status: status,
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await messaging.messagesFor(friend.token);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(session: _TestSession(messaging), peer: friend),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Scoped to the message list: the app bar and the composer have tooltips of
  /// their own, and they are not what this is about.
  final tick = find.descendant(
    of: find.byType(ListView),
    matching: find.byType(Tooltip),
  );

  String tickLabel(WidgetTester tester) =>
      tester.widget<Tooltip>(tick).message!;

  IconData? tickIcon(WidgetTester tester) => tester
      .widget<Icon>(find.descendant(of: tick, matching: find.byType(Icon)))
      .icon;

  testWidgets('a message left at the relay does not claim to have '
      'arrived', (tester) async {
    await openWith(tester, MessageStatus.viaRelay);

    final label = tickLabel(tester);
    expect(label, contains('relay'));
    // The whole finding in one line: the relay answers an enqueue the same way
    // whether it kept the blob or dropped it for space, so anything the user
    // could read as "it is waiting for them" is invented.
    expect(label, contains('No hay confirmación de entrega'));
    // And the tick is an upload, not the `cloud_done` that used to read as a
    // finished delivery.
    expect(tickIcon(tester), Icons.cloud_upload_outlined);
  });

  testWidgets('a P2P delivery still says so, because that one is real', (
    tester,
  ) async {
    await openWith(tester, MessageStatus.delivered);

    // `node_send` waits for the peer's own ACK: this is the only confirmation
    // the app has, and dropping it to be cautious would be its own lie.
    expect(tickLabel(tester), contains('P2P'));
    expect(tickIcon(tester), Icons.done_all);
  });

  testWidgets('a send that failed is not a mark to hover over and '
      'guess', (tester) async {
    await openWith(tester, MessageStatus.error);

    expect(tickLabel(tester), 'No se pudo enviar');
  });
}

/// A session that is only the messaging this screen reads. Bootstrapping a real
/// one would start a libp2p node, which has nothing to do with a tick.
class _TestSession extends SessionController {
  _TestSession(this._messaging) {
    phase = AppPhase.ready;
  }

  final MessagingService _messaging;

  @override
  MessagingService get messaging => _messaging;

  @override
  bool get hasMessaging => true;

  @override
  CallService? get calls => null;

  @override
  bool isBlocked(String token) => false;
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
