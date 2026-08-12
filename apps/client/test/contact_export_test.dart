import 'dart:typed_data';

import 'package:encrypchat/models/contact.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';

void main() {
  test('contact export roundtrip validates token/pubkey', () {
    final pub = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
    final digest = sha256.convert(pub);
    final token = 'ec_${digest.toString()}';
    final contact = Contact(
      token: token,
      publicKey: pub,
      displayName: 'Ada',
    );
    final parsed = Contact.parseExport(contact.exportLine());
    expect(parsed.token, token);
    expect(parsed.publicKey, pub);
    expect(parsed.displayName, 'Ada');
  });

  test('isValidToken accepts ec_ + 64 hex', () {
    expect(
      isValidToken(
        'ec_${List.filled(64, 'a').join()}',
      ),
      isTrue,
    );
    expect(isValidToken('bad'), isFalse);
  });
}
