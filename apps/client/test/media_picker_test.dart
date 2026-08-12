import 'dart:io';

import 'package:encrypchat/core/media_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as p;

/// Stands in for the Linux/Windows/iOS implementations, which have no
/// photo-picker flag.
class _OtherPlatformPicker extends ImagePickerPlatform {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('configureMediaPicker opts Android into the system Photo Picker', () {
    final android = ImagePickerAndroid();
    ImagePickerPlatform.instance = android;
    expect(android.useAndroidPhotoPicker, isFalse);

    configureMediaPicker();

    expect(android.useAndroidPhotoPicker, isTrue);
  });

  test('configureMediaPicker is a no-op on the other platforms', () {
    final other = _OtherPlatformPicker();
    ImagePickerPlatform.instance = other;

    configureMediaPicker();

    expect(ImagePickerPlatform.instance, same(other));
  });

  test('the Android manifest asks for no gallery permission', () {
    // The picker is the only path that touches user files, so the manifest must
    // stay free of storage permissions; Play review reads this as the app
    // having no access to the library beyond the picked item.
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest.contains('permission.READ_MEDIA_IMAGES'), isFalse);
    expect(manifest.contains('permission.READ_EXTERNAL_STORAGE'), isFalse);
  });

  group('picker temp files', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('encrypchat_picker_temp');
      _mockPathProvider(temp);
    });

    tearDown(() async {
      if (temp.existsSync()) await temp.delete(recursive: true);
    });

    File touch(String relative, {String content = 'jpeg-bytes'}) {
      final file = File(p.join(temp.path, relative));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
      return file;
    }

    test('the file the picker handed us is gone after a send', () async {
      // What image_picker returns on Android with resize options.
      final scaled = touch('scaled_foto.jpg');

      final removed = await purgePickerTemps(
        justUsed: scaled.path,
        platformCopiesPickedFiles: true,
      );

      expect(scaled.existsSync(), isFalse);
      expect(removed, 1);
    });

    test('leftovers of earlier picks are swept too', () async {
      // The full-size copy Android makes before scaling: the plugin's own
      // `deleteOnExit` does not run, so it survives across sessions.
      final copy = touch('6f1b0f4e-2f5a-4a1e-9f0b-2c3d4e5f6a7b/foto.jpg');
      final iosLeftover = touch('image_picker_ABC123.jpg');
      final mine = touch('encrypchat_v1.db', content: 'not the picker');

      final removed = await purgePickerTemps(platformCopiesPickedFiles: true);

      expect(copy.existsSync(), isFalse);
      expect(copy.parent.existsSync(), isFalse);
      expect(iosLeftover.existsSync(), isFalse);
      expect(mine.existsSync(), isTrue, reason: 'only picker files are swept');
      expect(removed, 2);
    });

    test('on desktop the picked file is the user\'s own and is kept', () async {
      // Linux/Windows do not resize: the path points at the original photo.
      final original = touch('mi-foto.jpg');

      final removed = await purgePickerTemps(
        justUsed: original.path,
        platformCopiesPickedFiles: false,
      );

      expect(original.existsSync(), isTrue);
      expect(removed, 0);
    });

    test('a path outside the app temp dir is never deleted', () async {
      final outside = await Directory.systemTemp.createTemp('encrypchat_other');
      final file = File(p.join(outside.path, 'foto.jpg'))
        ..writeAsStringSync('jpeg-bytes');

      final removed = await purgePickerTemps(
        justUsed: file.path,
        platformCopiesPickedFiles: true,
      );

      expect(file.existsSync(), isTrue);
      expect(removed, 0);
      await outside.delete(recursive: true);
    });

    test('a file that is already gone is not an error', () async {
      final removed = await purgePickerTemps(
        justUsed: p.join(temp.path, 'scaled_no-existe.jpg'),
        platformCopiesPickedFiles: true,
      );

      expect(removed, 0);
    });
  });
}

void _mockPathProvider(Directory dir) {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async => dir.path);
}
