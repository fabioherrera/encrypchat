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
}
