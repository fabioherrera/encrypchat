import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:encrypchat/services/auto_updater.dart';
import 'package:encrypchat/services/update_applier.dart';
import 'package:encrypchat/services/update_checker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _RecordingApplier extends UpdateApplier {
  final applied = <UpdatePackage>[];

  @override
  Future<void> apply(UpdatePackage package) async => applied.add(package);
}

void main() {
  late _RecordingApplier applier;
  late UpdateChecker checker;

  Future<UpdateChecker> checkerFor(UpdateChannel channel) async {
    final key = await Ed25519().newKeyPair();
    final payload = utf8.encode(
      jsonEncode({
        'version': '2.0.0',
        'packages': {
          for (final name in ['android-apk', 'windows-setup', 'linux-rpm'])
            name: {
              'url': 'https://encrypchat.com/$name',
              'sha256': 'a' * 64,
              'file': name,
            },
        },
      }),
    );
    final signature = await Ed25519().sign(payload, keyPair: key);
    final body = jsonEncode({
      'payload': base64Encode(payload),
      'signature': base64Encode(signature.bytes),
    });
    return UpdateChecker(
      publicKeyBase64: base64Encode((await key.extractPublicKey()).bytes),
      client: MockClient((_) async => http.Response(body, 200)),
      currentVersion: '1.0.0',
      catalogUri: Uri.parse('https://encrypchat.com/update-manifest.json'),
      channel: channel,
    );
  }

  AutoUpdater updater({
    bool enabled = true,
    bool busy = false,
    bool visible = true,
    Future<bool> Function()? canInstall,
  }) => AutoUpdater(
    checker: checker,
    applier: applier,
    isEnabled: () => enabled,
    isBusy: () => busy,
    isVisible: () => visible,
    canInstallSilently: canInstall,
  );

  setUp(() async {
    applier = _RecordingApplier();
    checker = await checkerFor(UpdateChannel.androidApk);
  });

  tearDown(() {
    checker.dispose();
    applier.dispose();
  });

  test('installs at launch', () async {
    await updater().run(atLaunch: true);
    expect(applier.applied.single.channel, UpdateChannel.androidApk);
  });

  test('later checks wait until the app is out of sight', () async {
    await updater(visible: true).run(atLaunch: false);
    expect(applier.applied, isEmpty);

    await updater(visible: false).run(atLaunch: false);
    expect(applier.applied, hasLength(1));
  });

  test('never during a call', () async {
    await updater(busy: true, visible: false).run(atLaunch: true);
    expect(applier.applied, isEmpty);
  });

  test('the switch turns it off', () async {
    await updater(enabled: false).run(atLaunch: true);
    expect(applier.applied, isEmpty);
  });

  test('waits for the Android install permission', () async {
    await updater(canInstall: () async => false).run(atLaunch: true);
    expect(applier.applied, isEmpty);
  });

  test('Linux stays manual', () async {
    checker.dispose();
    checker = await checkerFor(UpdateChannel.linuxRpm);
    await updater().run(atLaunch: true);
    expect(applier.applied, isEmpty);
  });
}
