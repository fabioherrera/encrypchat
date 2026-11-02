import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypchat/services/relay_socket.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeChannel implements RelaySocketChannel {
  final controller = StreamController<dynamic>();
  final sent = <Map<String, dynamic>>[];
  bool closed = false;

  @override
  Stream<dynamic> get stream => controller.stream;

  @override
  void add(String text) => sent.add(jsonDecode(text) as Map<String, dynamic>);

  @override
  Future<void> close() async {
    closed = true;
    await controller.close();
  }

  void push(Map<String, dynamic> frame) => controller.add(jsonEncode(frame));
}

void main() {
  late List<FakeChannel> channels;
  late int wakes;
  late int changes;
  late RelaySocket socket;

  RelaySocket build() => RelaySocket(
    baseUrl: 'https://relay.example',
    token: 'ec_token',
    publicKey: Uint8List.fromList([1, 2, 3]),
    proof: (eph, nonce) => Uint8List.fromList([...eph, ...nonce]),
    onWake: () => wakes++,
    onStateChanged: () => changes++,
    random: Random(1),
    connector: (uri) async {
      final c = FakeChannel();
      channels.add(c);
      return c;
    },
  );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<FakeChannel> ready({bool turn = false}) async {
    socket.start();
    await settle();
    final c = channels.last;
    c.push({'type': 'ready', 'turn': turn});
    await settle();
    return c;
  }

  setUp(() {
    channels = [];
    wakes = 0;
    changes = 0;
    socket = build();
  });

  tearDown(() => socket.close());

  test('derives the socket address from the relay URL', () {
    expect(
      RelaySocket.socketUri('https://relay.encrypchat.com/').toString(),
      'wss://relay.encrypchat.com/v1/ws',
    );
    expect(
      RelaySocket.socketUri('http://10.0.0.2:8787').toString(),
      'ws://10.0.0.2:8787/v1/ws',
    );
    expect(RelaySocket.socketUri('ftp://nope'), isNull);
  });

  test('answers the challenge with the same proof a pull uses', () async {
    socket.start();
    await settle();
    final c = channels.single;
    c.push({
      'type': 'challenge',
      'challenge_id': 'ch-1',
      'eph_pubkey_b64': base64Encode([9]),
      'nonce_b64': base64Encode([8]),
    });
    await settle();

    expect(c.sent.single, {
      'type': 'auth',
      'challenge_id': 'ch-1',
      'dest_token': 'ec_token',
      'pubkey_b64': base64Encode([1, 2, 3]),
      'proof_b64': base64Encode([9, 8]),
    });
    expect(socket.isConnected, isFalse);
  });

  test('ready catches up, and a wake asks for a pull', () async {
    final c = await ready();
    expect(socket.isConnected, isTrue);
    expect(wakes, 1, reason: 'what landed while down rang nobody');

    c.push({'type': 'wake'});
    await settle();
    expect(wakes, 2);
  });

  test('a lost socket is reported and retried', () async {
    final c = await ready();
    changes = 0;
    await c.controller.close();
    await settle();

    expect(socket.isConnected, isFalse);
    expect(changes, 1);
    socket.nudge();
    await settle();
    expect(channels, hasLength(2));
  });

  test('garbage from the wire is ignored', () async {
    final c = await ready();
    final before = wakes;
    c.controller.add('not json');
    c.controller.add('[1]');
    c.controller.add(Uint8List(3));
    await settle();
    expect(wakes, before);
    expect(socket.isConnected, isTrue);
  });

  test('TURN credentials come back over the socket', () async {
    final c = await ready(turn: true);
    final pending = socket.requestTurn();
    await settle();
    expect(c.sent.last, {'type': 'turn'});

    c.push({
      'type': 'turn',
      'ice_servers': [
        {
          'urls': ['turn:t'],
          'username': 'u',
          'credential': 'c',
        },
      ],
    });
    final servers = await pending;
    expect(servers!.single['credential'], 'c');
  });

  test('no TURN means STUN, and nothing is asked', () async {
    final c = await ready(turn: false);
    expect(await socket.requestTurn(), isNull);
    expect(c.sent, isEmpty);
  });

  test('a refused TURN request resolves to null', () async {
    final c = await ready(turn: true);
    final pending = socket.requestTurn();
    await settle();
    c.push({'type': 'turn_unavailable'});
    expect(await pending, isNull);
  });

  test('losing the socket does not strand a TURN request', () async {
    final c = await ready(turn: true);
    final pending = socket.requestTurn();
    await settle();
    await c.controller.close();
    expect(await pending, isNull);
  });

  test('retry delays grow, stay bounded and are jittered', () {
    final first = socket.delayFor(0);
    final late = socket.delayFor(20);
    expect(first.inMilliseconds, lessThan(2000));
    expect(late, greaterThan(first));
    expect(
      late.inMilliseconds,
      lessThanOrEqualTo(RelaySocket.maxDelay.inMilliseconds * 1.25),
    );
  });
}
