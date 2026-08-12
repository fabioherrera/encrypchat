import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Opts the Android client into the system Photo Picker.
///
/// The Photo Picker returns a per-item read grant for the photo the user
/// picked, so the app ships with no gallery permission at all. On devices
/// without it (pre-Android 13 with no Play Services backport) AndroidX falls
/// back to `ACTION_OPEN_DOCUMENT`, which is also user-mediated and needs no
/// permission — see docs/legal-f9-stores.md for the degraded UX.
///
/// Call once at startup: the flag lives on the plugin instance, so every
/// picker call in the app inherits it.
void configureMediaPicker() {
  final implementation = ImagePickerPlatform.instance;
  if (implementation is ImagePickerAndroid) {
    implementation.useAndroidPhotoPicker = true;
  }
}

/// True where `image_picker` hands back a **copy it made**, which is ours to
/// delete.
///
/// Android materializes the picked URI into `<cache>/<uuid>/<name>` and, with
/// resize options, writes `<cache>/scaled_<name>`; iOS writes
/// `<tmp>/image_picker_<uuid>.<ext>`. Linux and Windows do not resize and hand
/// back the **user's own file** — deleting there would destroy the original,
/// and their temp dir is shared with the rest of the system anyway.
bool get _pickerCopiesToTemp => Platform.isAndroid || Platform.isIOS;

/// Matches the per-pick directory Android creates in the app cache.
final _uuidDir = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Removes the plaintext copies the picker leaves in the app's private temp
/// directory: [justUsed] (the file we were handed) plus leftovers from earlier
/// picks, which nothing else cleans up — the plugin marks them `deleteOnExit`
/// and documents that it does not work on Android.
///
/// Returns how many entries were removed. Failures are logged and swallowed:
/// the photo is already sealed and sent by the time this runs, so a file we
/// could not delete must not turn into an error the user sees.
///
/// [platformCopiesPickedFiles] is a test seam; production always resolves it
/// from the platform.
Future<int> purgePickerTemps({
  String? justUsed,
  bool? platformCopiesPickedFiles,
}) async {
  if (!(platformCopiesPickedFiles ?? _pickerCopiesToTemp)) return 0;
  var removed = 0;
  try {
    final temp = p.normalize((await getTemporaryDirectory()).path);

    if (justUsed != null) {
      final path = p.normalize(justUsed);
      // Never step outside the app's own temp dir: anywhere else the path is
      // something the user owns.
      if (p.isWithin(temp, path)) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          removed++;
        }
      }
    }

    final dir = Directory(temp);
    if (!await dir.exists()) return removed;
    await for (final entity in dir.list(followLinks: false)) {
      final name = p.basename(entity.path);
      final leftover = entity is Directory
          ? _uuidDir.hasMatch(name)
          : name.startsWith('scaled_') || name.startsWith('image_picker_');
      if (!leftover) continue;
      try {
        await entity.delete(recursive: true);
        removed++;
      } catch (e) {
        debugPrint('picker temp not removed: ${e.runtimeType}');
      }
    }
  } catch (e) {
    debugPrint('picker temp sweep failed: ${e.runtimeType}');
  }
  return removed;
}
