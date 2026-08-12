import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypchat/core/call_signal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('call signal invite roundtrip', () {
    final s = CallSignal(
      type: CallSignalType.invite,
      callId: 'abc123',
      media: CallMediaMode.av,
    );
    final bytes = s.encode();
    expect(CallSignal.looksLike(bytes), isTrue);
    final d = CallSignal.decode(bytes);
    expect(d.type, CallSignalType.invite);
    expect(d.callId, 'abc123');
    expect(d.media, CallMediaMode.av);
  });

  test('call signal ice with candidate', () {
    final s = CallSignal(
      type: CallSignalType.ice,
      callId: 'c1',
      media: CallMediaMode.audio,
      candidate: {
        'candidate': 'candidate:1 1 udp 1 1.2.3.4 9 typ host',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      },
    );
    final d = CallSignal.decode(s.encode());
    expect(d.type, CallSignalType.ice);
    expect(d.candidate?['sdpMid'], '0');
  });

  test('looksLike rejects plain text', () {
    expect(
      CallSignal.looksLike(Uint8List.fromList(utf8.encode('hola'))),
      isFalse,
    );
  });

  test('the stamp survives the round trip', () {
    final stamped = CallSignal(
      type: CallSignalType.invite,
      callId: 'abc123',
      media: CallMediaMode.audio,
    ).stamped(1786000000);

    final decoded = CallSignal.decode(stamped.encode());

    expect(decoded.sentAtUnix, 1786000000);
    expect(decoded.callId, 'abc123');
  });

  test('a signal from before the field existed reads as unstamped', () {
    // Not as zero: 1970 would be judged stale, and refusing to ring is a louder
    // decision than the missing field justifies on its own.
    final legacy = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'v': 1,
          'kind': 'call',
          'type': 'invite',
          'callId': 'c1',
          'media': 'audio',
        }),
      ),
    );

    expect(CallSignal.decode(legacy).sentAtUnix, isNull);
  });

  test('a junk stamp reads as unstamped', () {
    for (final ts in ['ayer', 0, -1, 3.5]) {
      final raw = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'v': 1,
            'kind': 'call',
            'type': 'invite',
            'callId': 'c1',
            'media': 'audio',
            'ts': ts,
          }),
        ),
      );
      expect(CallSignal.decode(raw).sentAtUnix, isNull, reason: '$ts');
    }
  });
}
