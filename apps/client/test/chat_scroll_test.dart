import 'dart:convert';
import 'dart:io';

import 'package:encrypchat/core/encrypchat_core.dart';
import 'package:encrypchat/core/wire_frame.dart';
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

/// How a long conversation behaves on screen.
///
/// Two things are easy to break and hard to notice in a screenshot: the reading
/// position must not move when the page before it is spliced in, and a message
/// arriving while somebody is reading old history must not drag them to the end
/// of the conversation. Both are asserted here through the widget, not through
/// the service, because both are properties of the scroll.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late EncrypchatCore core;
  late LocalDatabase database;
  late IdentityService identity;
  late MessagingService messaging;
  late Contact friend;

  final base = DateTime.utc(2026, 1, 1);
  const page = MessagingService.messagesPageSize;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('encrypchat_chatscroll');
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

  Future<void> seed(int count) async {
    for (var i = 0; i < count; i++) {
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
          createdAt: base.add(Duration(seconds: i)),
        ),
      );
    }
  }

  tearDown(() async {
    messaging.dispose();
    await database.close();
    await tempDir.delete(recursive: true);
  });

  /// Not `pumpAndSettle`: while a page is being fetched the screen shows a
  /// progress indicator, and an indicator never settles.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The database is real: its reads finish on the event loop, which a widget
  /// test's fake clock does not advance. Everything that touches it has to be
  /// handed back to real time, and only then pumped.
  Future<void> offClock(WidgetTester tester, Future<void> Function() body) =>
      tester.runAsync(body).then((_) => settle(tester));

  Future<void> openChat(WidgetTester tester, {required int history}) async {
    await tester.runAsync(() async {
      await seed(history);
      // Warm the first page here so the screen's own load resolves on the
      // microtask queue, which the fake clock does drain.
      await messaging.messagesFor(friend.token);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(session: _TestSession(messaging), peer: friend),
      ),
    );
    await settle(tester);
  }

  Future<void> deliver(WidgetTester tester, String text) => offClock(
    tester,
    () => messaging.handleInboundFrame(
      WireFrame.create(
        senderToken: friend.token,
        ciphertext: core.encrypt(
          recipientPublicKey: identity.publicKey!,
          plaintext: Uint8List.fromList(utf8.encode(text)),
        ),
      ).encode(),
    ),
  );

  /// Scrolls towards the older end. The list is reversed, so dragging the
  /// content downwards is going back in time.
  Future<void> scrollBack(WidgetTester tester, double distance) async {
    await tester.drag(find.byType(ListView), Offset(0, distance));
    await settle(tester);
    // A drag that reached the oldest end started a page read; give it real time
    // to land before asserting on what is drawn.
    await offClock(
      tester,
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
  }

  ScrollPosition positionOf(WidgetTester tester) => tester
      .widget<Scrollable>(find.byType(Scrollable).first)
      .controller!
      .position;

  testWidgets('a chat opens at its newest message', (tester) async {
    await openChat(tester, history: page * 2);

    expect(find.text('mensaje ${page * 2 - 1}'), findsOneWidget);
    // Nothing from the far side of the history was decrypted to get here.
    expect(find.text('mensaje 0'), findsNothing);
  });

  testWidgets('scrolling back reaches the page before it', (tester) async {
    await openChat(tester, history: page * 2);
    expect(find.text('mensaje 0'), findsNothing);

    // Far enough back that the older page is asked for and drawn.
    await scrollBack(tester, 4000);
    await scrollBack(tester, 4000);
    await scrollBack(tester, 4000);

    expect(find.text('mensaje 0'), findsOneWidget);
  });

  testWidgets('a message arriving while reading history announces itself '
      'instead of jumping', (tester) async {
    // One page exactly: nothing older to fetch, so the scroll under test is
    // only a scroll and the assertion on the offset means what it says.
    await openChat(tester, history: page);
    await scrollBack(tester, 400);
    final position = positionOf(tester);
    final before = position.pixels;
    expect(before, greaterThan(0), reason: 'the test must not be at the end');

    await deliver(tester, 'recién llegado');

    expect(find.text('1 mensaje nuevo'), findsOneWidget);
    expect(find.text('recién llegado'), findsNothing);
    expect(position.pixels, before);
  });

  testWidgets('coming back to the end shows what was held', (tester) async {
    await openChat(tester, history: page);
    await scrollBack(tester, 400);
    await deliver(tester, 'recién llegado');

    await tester.tap(find.text('1 mensaje nuevo'));
    await settle(tester);

    expect(find.text('recién llegado'), findsOneWidget);
    expect(find.text('1 mensaje nuevo'), findsNothing);
    expect(positionOf(tester).pixels, 0);
  });

  testWidgets('at the newest message, what arrives is shown', (tester) async {
    await openChat(tester, history: page);

    await deliver(tester, 'recién llegado');

    expect(find.text('recién llegado'), findsOneWidget);
    expect(find.textContaining('mensaje nuevo'), findsNothing);
  });
}

/// A session that is only the messaging this screen reads. Bootstrapping a real
/// one would start a libp2p node, which has nothing to do with scrolling.
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
