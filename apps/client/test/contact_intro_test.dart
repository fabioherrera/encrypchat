import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypchat/core/call_signal.dart';
import 'package:encrypchat/core/contact_intro.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Uint8List pub([int seed = 1]) =>
      Uint8List.fromList(List<int>.generate(32, (i) => (i + seed) & 0xff));

  test('roundtrip and token binding', () {
    final key = pub();
    final token = 'ec_${sha256.convert(key)}';
    final intro = ContactIntro(token: token, publicKey: key);
    expect(intro.keyMatchesToken, isTrue);
    expect(ContactIntro.looksLike(intro.encode()), isTrue);

    final parsed = ContactIntro.tryDecode(intro.encode());
    expect(parsed, isNotNull);
    expect(parsed!.token, token);
    expect(parsed.publicKey, key);
    expect(parsed.matchesSender(token), isTrue);
    expect(parsed.matchesSender('ec_${'a' * 64}'), isFalse);
  });

  test('a call signal is not an intro', () {
    final call = CallSignal(
      type: CallSignalType.hangup,
      callId: 'c1',
      media: CallMediaMode.audio,
    ).stamped(1);
    expect(ContactIntro.looksLike(call.encode()), isFalse);
  });

  test('a swapped key is refused', () {
    final a = pub(1);
    final b = pub(2);
    final raw = ContactIntro(
      token: 'ec_${sha256.convert(a)}',
      publicKey: a,
    ).encode();
    // Flip the published key without changing the token.
    final swapped = ContactIntro(
      token: 'ec_${sha256.convert(a)}',
      publicKey: b,
    );
    expect(swapped.keyMatchesToken, isFalse);
    expect(() => swapped.encode(), throwsStateError);
    expect(ContactIntro.tryDecode(raw)!.publicKey, a);
  });
}
