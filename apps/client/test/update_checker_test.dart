import 'dart:io';

import 'package:encrypchat/core/app_version.dart';
import 'package:encrypchat/services/update_checker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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
      expect(request.url.path, '/latest.json');
      return http.Response(
        '{"version":"1.0.1","download":"https://encrypchat.com/es/download"}',
        200,
      );
    });
    final checker = UpdateChecker(
      client: client,
      currentVersion: '1.0.0',
      catalogUri: Uri.parse('https://encrypchat.com/latest.json'),
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
    final client = MockClient((_) async => http.Response(body, 200));
    final checker = UpdateChecker(
      client: client,
      currentVersion: '1.0.0',
      catalogUri: Uri.parse('https://encrypchat.com/latest.json'),
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
          'sha256': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'file': 'encrypchat.rpm',
        },
      },
    }, UpdateChannel.linuxRpm);
    expect(pkg, isNull);
  });

  test('matching catalog version is current', () async {
    final client = MockClient((request) async {
      return http.Response('{"version":"1.0.0"}', 200);
    });
    final checker = UpdateChecker(
      client: client,
      currentVersion: '1.0.0',
      catalogUri: Uri.parse('https://encrypchat.com/latest.json'),
    );
    await checker.check();
    expect(checker.info.status, UpdateStatus.current);
    expect(checker.info.hasUpdate, isFalse);
    checker.dispose();
  });

  test('a failed catalog fetch does not claim an update', () async {
    final client = MockClient((request) async {
      return http.Response('nope', 500);
    });
    final checker = UpdateChecker(
      client: client,
      currentVersion: '1.0.0',
      catalogUri: Uri.parse('https://encrypchat.com/latest.json'),
    );
    await checker.check();
    expect(checker.info.status, UpdateStatus.failed);
    expect(checker.info.hasUpdate, isFalse);
    checker.dispose();
  });
}
