import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypchat/core/encrypchat_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// F-10: the bridge wipes its native staging buffers before freeing them.
///
/// Freed memory cannot be inspected from Dart, so what is tested here is the
/// property that makes the wiping safe — it must clear the **copy** the bridge
/// made, never the caller's list. A `_freeSecret` pointed at the wrong buffer
/// would destroy the identity on the first inbound message, and the only way to
/// see that is to keep using the same key afterwards.
void main() {
  late EncrypchatCore core;

  setUp(() => core = EncrypchatCore.open());

  test('an identity survives being used as a key over and over', () {
    final generated = core.identityGenerate();
    final secret = generated.secret;
    final pristine = Uint8List.fromList(secret);
    final publicKey = core.identityPublicKey(secret);

    for (var i = 0; i < 5; i++) {
      final ciphertext = core.encryptUtf8(
        recipientPublicKey: publicKey,
        plaintext: 'mensaje $i',
      );
      expect(
        core.decryptUtf8(secret: secret, ciphertext: ciphertext),
        'mensaje $i',
      );
      // Every call stages the secret on the native heap and wipes it there.
      expect(secret, pristine);
      expect(core.identityToken(secret), generated.token);
    }
  });

  test('a db_key still opens what it sealed after repeated use', () {
    final dbKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
    final pristine = Uint8List.fromList(dbKey);
    final body = Uint8List.fromList(utf8.encode('cuerpo del mensaje'));
    final bodyPristine = Uint8List.fromList(body);

    for (var i = 0; i < 3; i++) {
      final sealed = core.localSeal(dbKey: dbKey, plaintext: body);
      expect(core.localOpen(dbKey: dbKey, sealed: sealed), body);
      // The plaintext is staged natively too, and the caller's copy is not the
      // one that gets cleared.
      expect(dbKey, pristine);
      expect(body, bodyPristine);
    }
  });

  test('sealing and opening leave the sender secret intact', () {
    final sender = core.identityGenerate();
    final recipient = core.identityGenerate();
    final senderPristine = Uint8List.fromList(sender.secret);
    final recipientPristine = Uint8List.fromList(recipient.secret);

    final sealed = core.sealedSeal(
      senderSecret: sender.secret,
      recipientPublicKey: core.identityPublicKey(recipient.secret),
      plaintext: Uint8List.fromList(utf8.encode('hola')),
    );
    final opened = core.sealedOpen(
      recipientSecret: recipient.secret,
      blob: sealed.blob,
      nowUnixSecs: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
    );

    expect(opened.senderToken, sender.token);
    expect(utf8.decode(opened.plaintext), 'hola');
    expect(sender.secret, senderPristine);
    expect(recipient.secret, recipientPristine);
  });

  test('the relay proof is reproducible from the same secret', () {
    final generated = core.identityGenerate();
    final eph = Uint8List.fromList(List<int>.generate(32, (i) => 32 - i));
    final nonce = Uint8List.fromList(List<int>.generate(16, (i) => i));

    final first = core.popProof(
      secret: generated.secret,
      ephPubkey: eph,
      nonce: nonce,
      destToken: generated.token,
    );
    final second = core.popProof(
      secret: generated.secret,
      ephPubkey: eph,
      nonce: nonce,
      destToken: generated.token,
    );

    // Same inputs, same proof: the out buffer is wiped after the value is
    // copied out, not before, and the secret is untouched by the first call.
    expect(second, first);
    expect(first, hasLength(32));
  });
}
