import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:encrypchat/core/core_error.dart';
import 'package:encrypchat/core/encrypchat_core.dart';
import 'package:encrypchat/models/contact.dart';
import 'package:encrypchat/services/identity_service.dart';
import 'package:encrypchat/services/local_database.dart';
import 'package:encrypchat/services/session_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Importing a contact card, against the real FFI core.
///
/// Since `0.8.1` the core names one key with exactly one encoding: `S` and
/// `S | 0x80` are the same X25519 key with two different SHA-256 hashes, so
/// accepting an alias would hand the same peer a second token — and a way back
/// past a block (F-10). The card is where that key enters the app, so this is
/// where the refusal has to be visible and final. Nothing here ever repairs an
/// encoding: invariant 14 of `docs/ffi-contract.md`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late EncrypchatCore core;
  late LocalDatabase database;
  late IdentityService identity;
  late SessionController session;

  String cardFor(Uint8List publicKey, {String? name}) {
    final token = 'ec_${sha256.convert(publicKey)}';
    return Contact(
      token: token,
      publicKey: publicKey,
      displayName: name,
    ).exportLine();
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('encrypchat_card_test');
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
    session = SessionController(
      core: core,
      identity: identity,
      database: database,
    );
  });

  tearDown(() async {
    await database.close();
    await tempDir.delete(recursive: true);
  });

  test('a good card is stored with the bytes it arrived with', () async {
    final peer = core.identityGenerate();
    final pub = core.identityPublicKey(peer.secret);

    await session.importContact(cardFor(pub, name: 'Ada'));

    final stored = session.contacts.single;
    // Byte-identical, not "equivalent": the token is only a stable identity
    // because the encoding is fixed, so re-encoding here would be the bug.
    expect(stored.publicKey, pub);
    expect(stored.token, 'ec_${sha256.convert(pub)}');
    expect(stored.displayName, 'Ada');
  });

  test('a degenerate key reads as a malformed card', () async {
    // All zeros: canonically encoded, and still a key whose shared secret is
    // all-zero and computable by anyone. The card is internally consistent — the
    // token really is its SHA-256 — so nothing but the core can tell it apart
    // from a real one, which is why the check is a question and not a rule
    // rewritten here.
    final card = cardFor(Uint8List(32));

    await expectLater(
      session.importContact(card),
      throwsA(
        isA<ContactCardException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('mal codificada'),
            contains('No es un problema de red'),
          ),
        ),
      ),
    );
    // Nothing was stored: a contact that looks fine and cannot be written to is
    // worse than a refused import.
    expect(session.contacts, isEmpty);
    expect(await database.listContacts(), isEmpty);
  });

  test('a token that does not match its key is refused', () async {
    final peer = core.identityGenerate();
    final pub = core.identityPublicKey(peer.secret);
    final other = core.identityGenerate();

    await expectLater(
      session.importContact(
        'encrypchat:contact:v1:${other.token}:'
        '${Contact(token: other.token, publicKey: pub).publicKeyHex}:',
      ),
      throwsA(
        isA<ContactCardException>().having(
          (e) => e.message,
          'message',
          contains('no corresponde a su clave pública'),
        ),
      ),
    );
    expect(session.contacts, isEmpty);
  });

  test(
    'something that is not a card at all is refused as unreadable',
    () async {
      for (final raw in [
        'hola',
        'encrypchat:contact:v2:ec_abc:00:',
        'encrypchat:contact:v1:ec_abc:not-hex:',
      ]) {
        await expectLater(
          session.importContact(raw),
          throwsA(isA<ContactCardException>()),
          reason: raw,
        );
      }
    },
  );

  test('an alias of a real key is refused, and never quietly fixed', () async {
    final peer = core.identityGenerate();
    final pub = core.identityPublicKey(peer.secret);
    // The F-10 card: bit 255 set. RFC 7748 masks it away before every
    // Diffie-Hellman, so this is the *same* key — with a different token.
    final alias = Uint8List.fromList(pub);
    alias[31] |= 0x80;
    final card = cardFor(alias);

    if (!_rejectsAliases(core, identity.requireSecret(), alias)) {
      // Said out loud rather than passed: the library in `apps/client/native/`
      // is a 0.8.0 build, and the canonicality check landed in 0.8.1. The
      // mapping this test exercises is in place; the core behind it is not yet.
      markTestSkipped(
        'core on disk reports ${core.apiVersion()} and still accepts an alias '
        '(canonical encoding is enforced from 0.8.1)',
      );
      return;
    }

    await expectLater(
      session.importContact(card),
      throwsA(isA<ContactCardException>()),
    );
    expect(session.contacts, isEmpty);
    // And the alias did not sneak in under the real key's token either.
    expect(session.contactByToken('ec_${sha256.convert(pub)}'), isNull);
  });
}

/// Whether this core enforces canonical public-key encodings (`0.8.1`).
///
/// Asked of the library instead of parsed out of its version string: the version
/// says what it should do, this says what it does.
bool _rejectsAliases(
  EncrypchatCore core,
  Uint8List senderSecret,
  Uint8List alias,
) {
  try {
    core.assertUsablePublicKey(senderSecret: senderSecret, publicKey: alias);
    return false;
  } on CoreException catch (e) {
    return e.code == CoreException.invalidPublicKey;
  }
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
