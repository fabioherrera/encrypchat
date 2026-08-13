import 'dart:io';

import 'package:encrypchat/core/update_copy.dart';
import 'package:encrypchat/services/update_applier.dart';
import 'package:encrypchat/services/update_checker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

void main() {
  const helloSha =
      '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';

  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('encrypchat-update-');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  UpdatePackage pkg(String sha) => UpdatePackage(
    url: Uri.parse('https://encrypchat.com/encrypchat.rpm'),
    sha256: sha,
    fileName: 'encrypchat.rpm',
    channel: UpdateChannel.linuxRpm,
  );

  test('a matching hash is installed, not skipped', () async {
    File? installed;
    final client = MockClient((_) async => http.Response('hello', 200));
    final applier = UpdateApplier(
      client: client,
      tempDirectory: () => tmp,
      installHook: (file, channel) async {
        installed = file;
        expect(channel, UpdateChannel.linuxRpm);
      },
    );
    await applier.apply(pkg(helloSha));
    expect(applier.phase, UpdateApplyPhase.done);
    expect(installed, isNotNull);
    expect(installed!.readAsStringSync(), 'hello');
    applier.dispose();
  });

  test('a mismatched hash is not installed', () async {
    var called = false;
    final client = MockClient((_) async => http.Response('hello', 200));
    final applier = UpdateApplier(
      client: client,
      tempDirectory: () => tmp,
      installHook: (file, channel) async {
        called = true;
      },
    );
    await applier.apply(
      pkg('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
    );
    expect(applier.phase, UpdateApplyPhase.failed);
    expect(applier.error, UpdateCopy.hashMismatch);
    expect(called, isFalse);
    expect(File(p.join(tmp.path, 'encrypchat.rpm')).existsSync(), isFalse);
    applier.dispose();
  });
}
