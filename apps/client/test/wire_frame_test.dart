import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypchat/core/wire_frame.dart';
import 'package:encrypchat/models/contact.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EC04 wire frame roundtrip', () {
    final pub = Uint8List.fromList(List<int>.generate(32, (i) => i + 3));
    final digest = sha256.convert(pub);
    final token = 'ec_${digest.toString()}';
    expect(isValidToken(token), isTrue);

    final frame = WireFrame.create(
      senderToken: token,
      ciphertext: Uint8List.fromList([1, 2, 3, 4, 5]),
    );
    final decoded = WireFrame.decode(frame.encode());
    expect(decoded.senderToken, token);
    expect(decoded.ciphertext, frame.ciphertext);
    expect(decoded.msgId, frame.msgId);
  });
}
