import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:encrypchat/core/app_version.dart';
import 'package:encrypchat/core/update_key.dart';
import 'package:encrypchat/services/update_checker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late SimpleKeyPair keyPair;
  late String publicKey;

  Future<String> signedWith(SimpleKeyPair key, String catalog) async {
    final payload = utf8.encode(catalog);
    final signature = await Ed25519().sign(payload, keyPair: key);
    return jsonEncode({
      'payload': base64Encode(payload),
      'signature': base64Encode(signature.bytes),
    });
  }

  Future<String> signed(String catalog) => signedWith(keyPair, catalog);

  setUpAll(() async {
    keyPair = await Ed25519().newKeyPair();
    publicKey = base64Encode((await keyPair.extractPublicKey()).bytes);
  });

  test('encrypchatVersion matches pubspec without the build number', () {
    final yaml = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)',
      multiLine: true,
    ).firstMatch(yaml);
    expect(match, isNotNull);
    expect(match!.group(1), encrypchatVersion);
  });

  test('compareSemver ignores build metadata', () {
    expect(UpdateChecker.compareSemver('1.0.0+2', '1.0.0'), 0);
    expect(UpdateChecker.compareSemver('1.0.1', '1.0.0'), 1);
    expect(UpdateChecker.compareSemver('1.0.0', '1.2.0'), -1);
  });

  test('a newer catalog version is available, not installed', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/update-manifest.json');
      return http.Response(
        await signed(
          '{"version":"1.0.1","download":"https://encrypchat.com/es/download"}',
        ),
        200,
      );
    });
    final checker = UpdateChecker(
      publicKeyBase64: publicKey,
      client: client,
      currentVersion: '1.0.0',
      catalogUri: Uri.parse('https://encrypchat.com/update-manifest.json'),
      channel: UpdateChannel.linuxRpm,
    );
    await checker.check();
    expect(checker.info.hasUpdate, isTrue);
    expect(checker.info.latestVersion, '1.0.1');
    expect(checker.info.canApply, isFalse);
    checker.dispose();
  });

  test('a hashed https package can be applied', () async {
    const body = '''
{
  "version": "1.0.1",
  "packages": {
    "linux-rpm": {
      "url": "https://encrypchat.com/encrypchat.rpm",
      "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "file": "encrypchat.rpm"
    }
  }
}
''';
    final response = await signed(body);
    final client = MockClient((_) async => http.Response(response, 200));
    final checker = UpdateChecker(
      publicKeyBase64: publicKey,
      client: client,
      currentVersion: '1.0.0',
      catalogUri: Uri.parse('https://encrypchat.com/update-manifest.json'),
      channel: UpdateChannel.linuxRpm,
    );
    await checker.check();
    expect(checker.info.canApply, isTrue);
    expect(checker.info.package!.fileName, 'encrypchat.rpm');
    checker.dispose();
  });

  test('an http package URL is refused', () {
    final pkg = UpdateChecker.packageFromCatalog({
      'packages': {
        'linux-rpm': {
          'url': 'http://evil.example/encrypchat.rpm',
          'sha256':
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'file': 'encrypchat.rpm',
        },
      },
    }, UpdateChannel.linuxRpm);
    expect(pkg, isNull);
  });

  test('matching catalog version is current', () async {
    final client = MockClient((request) async {
      return http.Response(await signed('{"version":"1.0.0"}'), 200);
    });
    final checker = UpdateChecker(
      publicKeyBase64: publicKey,
      client: client,
      currentVersion: '1.0.0',
      catalogUri: Uri.parse('https://encrypchat.com/update-manifest.json'),
    );
    await checker.check();
    expect(checker.info.status, UpdateStatus.current);
    expect(checker.info.hasUpdate, isFalse);
    checker.dispose();
  });

  group('catalog signature', () {
    const evil = '''
{
  "version": "9.9.9",
  "packages": {
    "linux-rpm": {
      "url": "https://evil.example/encrypchat.rpm",
      "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "file": "encrypchat.rpm"
    }
  }
}
''';

    Future<UpdateInfo> check(String body) async {
      final checker = UpdateChecker(
        publicKeyBase64: publicKey,
        client: MockClient((_) async => http.Response(body, 200)),
        currentVersion: '1.0.0',
        catalogUri: Uri.parse('https://encrypchat.com/update-manifest.json'),
        channel: UpdateChannel.linuxRpm,
      );
      addTearDown(checker.dispose);
      await checker.check();
      return checker.info;
    }

    test('an unsigned catalog offers nothing', () async {
      final info = await check(evil);
      expect(info.status, UpdateStatus.failed);
      expect(info.package, isNull);
    });

    test('a catalog signed by another key offers nothing', () async {
      final attacker = await Ed25519().newKeyPair();
      final info = await check(await signedWith(attacker, evil));
      expect(info.status, UpdateStatus.failed);
      expect(info.package, isNull);
    });

    test('a signed catalog with a swapped payload offers nothing', () async {
      final good = jsonDecode(await signed('{"version":"1.0.1"}')) as Map;
      final info = await check(
        jsonEncode({
          'payload': base64Encode(utf8.encode(evil)),
          'signature': good['signature'],
        }),
      );
      expect(info.status, UpdateStatus.failed);
      expect(info.package, isNull);
    });

    test('the published catalog verifies with the pinned key', () async {
      final checker = UpdateChecker(currentVersion: '1.0.0');
      addTearDown(checker.dispose);
      final file = File('../web/public/update-manifest.json');
      final catalog = await checker.verifiedCatalog(file.readAsBytesSync());
      expect(catalog, isNotNull);
      expect(catalog!['version'], encrypchatVersion);
    });

    test('the pinned key is a real Ed25519 public key', () {
      expect(base64Decode(updateSigningPublicKey), hasLength(32));
    });
  });

  test('a failed catalog fetch does not claim an update', () async {
    final client = MockClient((request) async {
      return http.Response('nope', 500);
    });
    final checker = UpdateChecker(
      publicKeyBase64: publicKey,
      client: client,
      currentVersion: '1.0.0',
      catalogUri: Uri.parse('https://encrypchat.com/update-manifest.json'),
    );
    await checker.check();
    expect(checker.info.status, UpdateStatus.failed);
    expect(checker.info.hasUpdate, isFalse);
    checker.dispose();
  });
}
