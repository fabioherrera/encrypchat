import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/abuse_report.dart';

/// Where the report file ended up, which is not the same story on every
/// platform.
enum ReportLocation {
  /// The person picked the file in the system save dialog.
  chosen,

  /// Encrypchat's own folder, because this platform has no save dialog.
  appFolder,
}

@immutable
class SavedReport {
  const SavedReport({required this.path, required this.location});

  final String path;
  final ReportLocation location;
}

/// Signature of [saveAbuseReport], so the screen can be driven in a test
/// without a system dialog.
typedef AbuseReportSaver = Future<SavedReport?> Function(AbuseReport report);

/// True where `file_selector` can ask the person where to put the file.
///
/// `getSaveLocation` is desktop-only: neither the Android nor the iOS
/// implementation overrides it, so on a phone the interface default throws.
bool get _platformPicksPath =>
    Platform.isLinux || Platform.isWindows || Platform.isMacOS;

const _plainText = XTypeGroup(
  label: 'Texto',
  extensions: ['txt'],
  mimeTypes: ['text/plain'],
  uniformTypeIdentifiers: ['public.plain-text'],
);

/// Writes the report to a file instead of putting it on the clipboard.
///
/// The clipboard is a shared channel: on Android any app in the foreground can
/// read it, on Windows it syncs to the account when clipboard history is on,
/// and on a desktop every process of the same user sees it. This report ties
/// the reporter's identity to the reported one and is written by someone who is
/// being harassed, so the default way out of the app cannot be that channel
/// (F-14 in docs/audit-f10.md). A file the person names is the narrowest one
/// available: it goes where they say and nothing else observes it.
///
/// Returns null when the person closes the save dialog without choosing, which
/// is a cancel and not a failure. IO errors are thrown for the caller to show.
///
/// [platformPicksPath] and [pickPath] are test seams; production resolves both
/// from the platform.
Future<SavedReport?> saveAbuseReport(
  AbuseReport report, {
  bool? platformPicksPath,
  Future<String?> Function(String suggestedName)? pickPath,
}) async {
  final name = reportFileName(report.createdAt);
  final text = report.render();

  if (platformPicksPath ?? _platformPicksPath) {
    final path = await (pickPath ?? _askWhereToSave)(name);
    if (path == null) return null;
    await File(path).writeAsString(text, flush: true);
    return SavedReport(path: path, location: ReportLocation.chosen);
  }

  final dir = await _appReportsDirectory();
  await dir.create(recursive: true);
  final file = File(p.join(dir.path, name));
  await file.writeAsString(text, flush: true);
  return SavedReport(path: file.path, location: ReportLocation.appFolder);
}

/// The name the save dialog starts with. Only the moment goes in it: a file
/// sitting in a folder should not announce who was reported.
String reportFileName(DateTime createdAt) {
  final t = createdAt.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final day = '${t.year}-${two(t.month)}-${two(t.day)}';
  final time = '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  return 'informe-encrypchat-$day-$time.txt';
}

Future<String?> _askWhereToSave(String suggestedName) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: const [_plainText],
  );
  return location?.path;
}

/// Removes the reports this app filed in its own folder, and returns how many
/// survived.
///
/// A saved report is plaintext by design — it exists to leave the app — and it
/// names the reporter next to the reported. So it cannot outlive the identity
/// it belongs to, for the same reason the picker's temporary copies cannot: it
/// is the part that was never inside the encrypted store.
///
/// Only this app's folder. A report saved through the system dialog sits
/// wherever the person put it, and hunting for it would mean deleting a file
/// they own because its name looks familiar. That one stays theirs to remove,
/// and the copy says so instead of implying this reaches it.
Future<int> purgeSavedReports() async {
  final Directory dir;
  try {
    dir = await _appReportsDirectory();
  } catch (e) {
    debugPrint('report purge: folder unavailable (${e.runtimeType})');
    return 1;
  }
  if (!dir.existsSync()) return 0;

  var left = 0;
  for (final file in dir.listSync(followLinks: false).whereType<File>()) {
    try {
      await file.delete();
    } catch (e) {
      // Never the path: it names the app's own layout and the log survives
      // release builds.
      debugPrint('report purge: not removed (${e.runtimeType})');
      left++;
    }
  }
  try {
    await dir.delete();
  } catch (e) {
    debugPrint('report purge: folder kept (${e.runtimeType})');
  }
  return left;
}

/// The folder used where there is no save dialog.
///
/// On Android this is the app's directory on shared storage, which a computer
/// plugged in over USB can read and which costs no permission. On iOS it is the
/// app's Documents, which the Files app shows because `Info.plist` opts in. The
/// database and the media live in the support directory, so neither becomes
/// reachable by putting reports here.
Future<Directory> _appReportsDirectory() async {
  Directory? base;
  if (Platform.isAndroid) {
    try {
      base = await getExternalStorageDirectory();
    } catch (e) {
      debugPrint('shared storage unavailable (${e.runtimeType})');
    }
  }
  base ??= await getApplicationDocumentsDirectory();
  return Directory(p.join(base.path, 'Informes'));
}
