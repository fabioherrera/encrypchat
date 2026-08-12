import 'dart:io';

import 'package:encrypchat/core/call_signal.dart';
import 'package:encrypchat/core/encrypchat_core.dart';
import 'package:encrypchat/core/wire_frame.dart';
import 'package:encrypchat/models/contact.dart';
import 'package:encrypchat/services/call_service.dart';
import 'package:encrypchat/services/identity_service.dart';
import 'package:encrypchat/services/local_database.dart';
import 'package:encrypchat/services/messaging_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// F-4: blocking someone has to end the call you are on with them.
///
/// The media path is direct UDP, so nothing in the node can stop it, and after
/// the block the peer's own `hangup` is discarded too — the call would stay up
/// until the person being harassed hung up by hand.
///
/// `getUserMedia` and `RTCPeerConnection` need the platform plugin, which
/// `flutter test` does not load, so the call state is staged and what is checked
/// is the teardown: the phase, the peer, and the local stream being released.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late EncrypchatCore core;
  late LocalDatabase database;
  late IdentityService identity;
  late MessagingService messaging;
  late CallService calls;
  late Contact bob;
  late Contact carla;

  Uint8List inviteFrom(Contact peer, {int? stampedAt}) {
    var invite = CallSignal(
      type: CallSignalType.invite,
      callId: 'call-1',
      media: CallMediaMode.audio,
    );
    if (stampedAt != null) invite = invite.stamped(stampedAt);
    return WireFrame.create(
      senderToken: peer.token,
      ciphertext: core.encrypt(
        recipientPublicKey: identity.publicKey!,
        plaintext: invite.encode(),
      ),
    ).encode();
  }

  Contact newContact(String name) {
    final generated = core.identityGenerate();
    return Contact(
      token: generated.token,
      publicKey: core.identityPublicKey(generated.secret),
      displayName: name,
    );
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('encrypchat_call_block');
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

    bob = newContact('Bob');
    carla = newContact('Carla');

    messaging = MessagingService(
      core: core,
      identity: identity,
      database: database,
    );
    messaging.setContacts([bob, carla]);
    await messaging.loadBlocked();
    calls = CallService(messaging: messaging);
  });

  tearDown(() async {
    calls.dispose();
    messaging.dispose();
    await database.close();
    await tempDir.delete(recursive: true);
  });

  test('blocking mid-call ends it and releases the local stream', () async {
    final stream = _FakeMediaStream();
    calls.simulateActiveCall(peer: bob, localStream: stream);
    expect(calls.phase, CallPhase.active);

    await messaging.block(bob.token);

    expect(calls.phase, CallPhase.ended);
    expect(calls.peer, isNull);
    expect(calls.callId, isNull);
    expect(
      stream.disposed,
      isTrue,
      reason: 'mic and camera keep transmitting until the stream is released',
    );
    expect(messaging.isBlocked(bob.token), isTrue);
  });

  test('a ringing call from the peer being blocked stops ringing', () async {
    await messaging.handleInboundFrame(inviteFrom(bob));
    // The signal is dispatched without awaiting, so let the handler settle.
    await Future<void>.delayed(Duration.zero);
    expect(calls.phase, CallPhase.incoming);
    expect(calls.peer?.token, bob.token);

    await messaging.block(bob.token);

    expect(calls.phase, CallPhase.ended);
    expect(calls.peer, isNull);
  });

  test('blocking someone else leaves the call alone', () async {
    final stream = _FakeMediaStream();
    calls.simulateActiveCall(peer: bob, localStream: stream);

    await messaging.block(carla.token);

    expect(calls.phase, CallPhase.active);
    expect(calls.peer?.token, bob.token);
    expect(stream.disposed, isFalse);
    expect(messaging.isBlocked(carla.token), isTrue);
  });

  test('casing cannot save a call from the block', () async {
    final stream = _FakeMediaStream();
    calls.simulateActiveCall(peer: bob, localStream: stream);

    await messaging.block(bob.token.toUpperCase());

    expect(calls.phase, CallPhase.ended);
    expect(stream.disposed, isTrue);
  });

  test('a teardown that throws still applies the block', () async {
    // The block is the control the user asked for: a call that refuses to hang
    // up cannot be allowed to keep the peer unblocked.
    messaging.onBlockPeer = (_) async => throw StateError('teardown roto');

    await messaging.block(bob.token);

    expect(messaging.isBlocked(bob.token), isTrue);
    expect(await database.listBlockedTokens(), [
      LocalDatabase.normalizeToken(bob.token),
    ]);
  });

  test('a stale invite does not ring the phone', () async {
    // A phone ringing for a call the caller gave up on minutes ago is at best
    // confusing and at worst a way to make it ring on someone else's schedule.
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await messaging.handleInboundFrame(inviteFrom(bob, stampedAt: now - 600));
    await Future<void>.delayed(Duration.zero);

    expect(calls.phase, CallPhase.idle);
    expect(calls.peer, isNull);
  });

  test('an invite stamped in the future does not ring either', () async {
    // A clock ahead by seconds is ordinary; ahead by an hour is either broken or
    // an attempt to buy the invite a longer life than the window allows.
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await messaging.handleInboundFrame(inviteFrom(bob, stampedAt: now + 3600));
    await Future<void>.delayed(Duration.zero);

    expect(calls.phase, CallPhase.idle);
  });

  test('a fresh stamped invite rings', () async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await messaging.handleInboundFrame(inviteFrom(bob, stampedAt: now));
    await Future<void>.delayed(Duration.zero);

    expect(calls.phase, CallPhase.incoming);
    expect(calls.peer?.token, bob.token);
  });

  test('an unstamped invite still rings', () async {
    // Older builds do not stamp. Refusing them would drop calls from peers who
    // simply have not updated, which is a worse failure than the delay this
    // window is meant to bound.
    await messaging.handleInboundFrame(inviteFrom(bob));
    await Future<void>.delayed(Duration.zero);

    expect(calls.phase, CallPhase.incoming);
  });

  test('a call torn down before it was displayed does not throw', () async {
    // The renderers are only initialized when the call reaches the screen, and
    // rejecting a ringing call happens before that.
    await messaging.handleInboundFrame(inviteFrom(bob));
    await Future<void>.delayed(Duration.zero);

    await calls.rejectIncoming();

    expect(calls.phase, CallPhase.ended);
  });
}

/// Minimal stand-in for the stream `getUserMedia` hands over: the teardown only
/// has to dispose it, and that is what the test watches.
class _FakeMediaStream extends MediaStream {
  _FakeMediaStream() : super('fake-stream', 'fake-owner');

  bool disposed = false;

  @override
  bool? get active => !disposed;

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Future<void> addTrack(MediaStreamTrack track, {bool addToNative = true}) =>
      Future.value();

  @override
  Future<void> removeTrack(
    MediaStreamTrack track, {
    bool removeFromNative = true,
  }) => Future.value();

  @override
  List<MediaStreamTrack> getTracks() => const [];

  @override
  List<MediaStreamTrack> getAudioTracks() => const [];

  @override
  List<MediaStreamTrack> getVideoTracks() => const [];

  @override
  Future<void> getMediaTracks() => Future.value();
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
