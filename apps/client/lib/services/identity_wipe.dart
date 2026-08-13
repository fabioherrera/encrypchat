import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../core/media_picker.dart';
import 'identity_service.dart';
import 'local_database.dart';
import 'media_store.dart';
import 'messaging_service.dart';
import 'report_export.dart';

/// What a wipe left behind. Everything here is unreadable — the key that opened
/// it is gone before the first file is touched — but it is still bytes on the
/// disk, and saying so is the difference between a report and a promise.
@immutable
class IdentityWipeReport {
  const IdentityWipeReport({required this.filesLeft});

  /// Files the OS refused to remove. Zero is the normal case; on Windows a file
  /// another process still holds open is the way this is not zero.
  final int filesLeft;

  bool get isClean => filesLeft == 0;
}

/// Erasing an identity from this device: the private key, the encrypted
/// database, the sealed attachments, the `db_key` that opens both, and the
/// plaintext leftovers that were never inside them — picker copies and abuse
/// reports the app filed in its own folder.
///
/// There is no copy anywhere else — no account, no server, no backup this app
/// controls — so this is the one destructive operation in the product where a
/// half-finished state cannot be papered over. Two things make it survivable:
///
/// - **A mark, written first.** [markPending] lands before a single byte is
///   removed and is cleared only when there is nothing left to remove, so an
///   interrupted wipe is not a state the app can start in: [resumeIfPending]
///   finds the mark on the next launch and finishes the job. Without it, dying
///   between "the key is gone" and "the database is gone" leaves a file that
///   cannot be opened, cannot be repaired, and blocks the app on an error
///   screen — the limbo this is built to avoid.
/// - **The key goes first.** `db_key` is deleted before the files it protects.
///   From that moment the database and every sealed attachment are ciphertext
///   nobody can open, so the worst outcome of a failure further down is
///   unreadable leftovers rather than readable data. Deleting the files first
///   and the key last would invert exactly that.
///
/// What it does **not** do is overwrite. `File.delete()` unlinks; on flash
/// storage even overwriting would not reliably reach the physical blocks, and
/// pretending otherwise in the UI would be a claim the filesystem cannot keep.
/// What is claimed instead is what actually holds: those blocks are ciphertext
/// and the key is gone.
abstract final class IdentityWipe {
  /// Set while a wipe is in flight. It lives in the same secure store it is
  /// about to empty, and it is the last entry removed, so it outlives every
  /// step it guards.
  static const pendingKey = 'identity_wipe_pending_v1';

  /// Every entry this app writes to the OS secure store, in deletion order.
  ///
  /// `db_key` leads for the reason above. The identity secret follows, because
  /// after it the device can no longer act as, or be reached as, that identity.
  /// Ordering the rest is housekeeping.
  static const storageKeys = [
    LocalDatabase.dbKeyStorageKey,
    IdentityService.secretStorageKey,
    IdentityService.tokenStorageKey,
    MessagingService.relayUrlStorageKey,
  ];

  static Future<bool> isPending(FlutterSecureStorage storage) async {
    final value = await storage.read(key: pendingKey);
    return value != null && value.isNotEmpty;
  }

  static Future<void> markPending(FlutterSecureStorage storage) =>
      storage.write(key: pendingKey, value: '1');

  /// Finishes a wipe that was interrupted, if there was one. Returns `null` when
  /// there was nothing to finish.
  ///
  /// Called before the database is opened. Running after would create a fresh
  /// `db_key`, fail to open the old file with it, and report a corrupt database
  /// instead of a wipe that never ended.
  static Future<IdentityWipeReport?> resumeIfPending(
    FlutterSecureStorage storage,
  ) async {
    if (!await isPending(storage)) return null;
    debugPrint('identity wipe: unfinished, resuming');
    return run(storage);
  }

  /// Removes everything and clears the mark. Safe to run again: every step is
  /// "make sure this is gone", which is what makes a retry — by hand or on the
  /// next launch — the whole recovery story.
  ///
  /// Throws if the secure store refuses a deletion. That is the part that
  /// cannot be left half done, and the mark stays set so the next attempt
  /// resumes. Files that will not delete are reported instead: by then they are
  /// unreadable, and refusing to finish over one locked file would trap the
  /// user in a wipe that never completes.
  static Future<IdentityWipeReport> run(FlutterSecureStorage storage) async {
    for (final key in storageKeys) {
      await storage.delete(key: key);
    }
    final filesLeft = await _deleteFiles();
    await storage.delete(key: pendingKey);
    debugPrint('identity wipe: done ($filesLeft file(s) left behind)');
    return IdentityWipeReport(filesLeft: filesLeft);
  }

  static Future<int> _deleteFiles() async {
    var left = 0;
    final Directory support;
    try {
      support = await getApplicationSupportDirectory();
    } catch (e) {
      debugPrint('identity wipe: support dir unavailable (${e.runtimeType})');
      return 1;
    }
    final media = MediaStore.directoryIn(support);
    if (media.existsSync()) {
      // File by file so the report is a count of what survived, not a single
      // "the directory would not go".
      for (final entry
          in media
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()) {
        left += await _delete(entry);
      }
      // The directory holds no content of its own; what it exposes is the
      // listing — how many attachments there are, how big, and when they
      // arrived — and that goes with the files.
      await _delete(media);
    }
    for (final path in LocalDatabase.filePathsIn(support)) {
      left += await _delete(File(path));
    }
    // The picker leaves plaintext copies of photos in the app cache. They are
    // not part of the encrypted store, which is exactly why they cannot be left
    // out of a wipe.
    await purgePickerTemps();
    // Same category, and the one most worth catching: an abuse report is
    // plaintext on purpose and puts the reporter's token next to the reported
    // one. It also lives outside the support directory, so nothing above
    // reaches it.
    left += await purgeSavedReports();
    return left;
  }

  /// Returns how many entities survived, so the caller can report a number
  /// rather than a claim.
  static Future<int> _delete(FileSystemEntity entity) async {
    if (!entity.existsSync()) return 0;
    try {
      await entity.delete(recursive: entity is Directory);
      return 0;
    } catch (e) {
      // Never the path: it names the app's own directory layout, and the log
      // survives release builds.
      debugPrint('identity wipe: not removed (${e.runtimeType})');
      return 1;
    }
  }
}
