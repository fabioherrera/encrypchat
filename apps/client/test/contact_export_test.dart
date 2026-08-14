import 'dart:typed_data';

import 'package:encrypchat/models/contact.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';

void main() {
  test('contact export roundtrip validates token/pubkey', () {
    final pub = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
    final digest = sha256.convert(pub);
    final token = 'ec_${digest.toString()}';
    final contact = Contact(token: token, publicKey: pub, displayName: 'Ada');
    final parsed = Contact.parseExport(contact.exportLine());
    expect(parsed.token, token);
    expect(parsed.publicKey, pub);
    expect(parsed.displayName, 'Ada');
  });

  test('dial hints ride on extra lines and do not change identity', () {
    final pub = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
    final digest = sha256.convert(pub);
    final token = 'ec_${digest.toString()}';
    final contact = Contact(
      token: token,
      publicKey: pub,
      displayName: 'Ada',
      dialHints: const [
        '/ip4/192.168.1.10/tcp/41234',
        '/ip4/10.0.0.2/tcp/41234',
      ],
    );
    final raw = contact.exportLine();
    expect(raw, contains('\n/ip4/192.168.1.10/tcp/41234'));
    expect(Contact.looksLikeCard(raw), isTrue);

    final parsed = Contact.parseExport(raw);
    expect(parsed.token, token);
    expect(parsed.publicKey, pub);
    expect(parsed.displayName, 'Ada');
    expect(parsed.dialHints, [
      '/ip4/192.168.1.10/tcp/41234',
      '/ip4/10.0.0.2/tcp/41234',
    ]);
  });

  test('a junk second line is ignored', () {
    final pub = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
    final base = Contact(
      token: 'ec_${sha256.convert(pub)}',
      publicKey: pub,
      displayName: 'Ada',
    ).exportLine();
    final parsed = Contact.parseExport('$base\nnot-an-addr');
    expect(parsed.displayName, 'Ada');
    expect(parsed.dialHints, isEmpty);
  });

  test('isValidToken accepts ec_ + 64 hex', () {
    expect(isValidToken('ec_${List.filled(64, 'a').join()}'), isTrue);
    expect(isValidToken('bad'), isFalse);
  });
}
