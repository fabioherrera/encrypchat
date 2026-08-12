import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/encrypchat_core.dart';
import 'local_database.dart';

/// An inbound attachment was refused because storing it would push this peer,
/// or the store as a whole, past its ceiling.
class MediaQuotaException implements Exception {
  const MediaQuotaException(this.message, {required this.global});

  final String message;

  /// `true` when the store as a whole is full, `false` when it is this one
  /// peer's budget. The distinction matters to the user: one is "delete
  /// attachments", the other is "this contact is sending too much".
  final bool global;

  @override
  String toString() => 'MediaQuotaException: $message';
}

/// Sealed media files under app-support (never plaintext on disk).
class MediaStore {
  MediaStore({
    required EncrypchatCore core,
    required LocalDatabase database,
    this.maxInboundBytesPerPeer = defaultMaxInboundBytesPerPeer,
    this.maxInboundBytesTotal = defaultMaxInboundBytesTotal,
  }) : _core = core,
       _database = database;

  final EncrypchatCore _core;
  final LocalDatabase _database;

  /// Overridable so a test can reach the ceiling without writing gigabytes.
  final int maxInboundBytesPerPeer;
  final int maxInboundBytesTotal;

  static final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  /// Ceilings for **inbound** attachments (F-6: there was no limit at all, and
  /// a peer could loop 12 MiB frames until the device ran out of space).
  ///
  /// Outbound media is the user's own choice and is not metered; these bound
  /// what somebody else can leave on the disk. Both are checked before writing,
  /// and hitting either surfaces in the UI — a silent refusal would only trade
  /// a full disk for photos that stop arriving for no visible reason.
  static const defaultMaxInboundBytesPerPeer = 512 * 1024 * 1024;
  static const defaultMaxInboundBytesTotal = 2 * 1024 * 1024 * 1024;

  String _relForId(String id) {
    if (!_safeId.hasMatch(id)) {
      throw ArgumentError('Invalid media id');
    }
    return p.join('media', '$id.bin');
  }

  /// Where sealed attachments live under [support]. Public so deleting the
  /// identity can remove the directory without a second copy of the layout.
  static Directory directoryIn(Directory support) =>
      Directory(p.join(support.path, 'media'));

  Future<Directory> _mediaRoot() async =>
      directoryIn(await getApplicationSupportDirectory());

  Future<String> _absChecked(String rel) async {
    final root = await _mediaRoot();
    final abs = p.normalize(p.join(root.parent.path, rel));
    final rootPath = p.normalize(root.path);
    if (abs != rootPath && !p.isWithin(rootPath, abs)) {
      throw StateError('Media path escapes store');
    }
    return abs;
  }

  /// Writes `local_seal(db_key, bytes)` → relative `media/<id>.bin`.
  Future<String> writeSealed({
    required String id,
    required Uint8List plaintextBytes,
  }) async {
    final sealed = _core.localSeal(
      dbKey: _database.dbKey,
      plaintext: plaintextBytes,
    );
    final rel = _relForId(id);
    final path = await _absChecked(rel);
    await File(path).parent.create(recursive: true);
    await File(path).writeAsBytes(sealed, flush: true);
    return rel;
  }

  /// Refuses an inbound attachment that would break either ceiling.
  ///
  /// Usage is measured on disk rather than tracked in a counter: a counter and
  /// the filesystem drift apart the first time a write fails halfway or a file
  /// is removed outside the app, and drifting upwards would refuse attachments
  /// on a store that is actually empty.
  Future<void> ensureRoomFor({
    required int bytes,
    required String peerToken,
  }) async {
    final total = await totalBytes();
    if (total + bytes > maxInboundBytesTotal) {
      throw MediaQuotaException(
        'El almacén de adjuntos está lleno (${_mib(total)} MiB). Borrá algún '
        'adjunto para volver a recibir.',
        global: true,
      );
    }
    final forPeer = await bytesForPeer(peerToken);
    if (forPeer + bytes > maxInboundBytesPerPeer) {
      throw MediaQuotaException(
        'Este contacto ya usó su cupo de adjuntos (${_mib(forPeer)} MiB).',
        global: false,
      );
    }
  }

  /// Bytes on disk for every sealed attachment, inbound and outbound alike: the
  /// global ceiling is about the disk, and the disk does not care who sent it.
  Future<int> totalBytes() async {
    final root = await _mediaRoot();
    if (!root.existsSync()) return 0;
    var total = 0;
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! File) continue;
      try {
        total += await entry.length();
      } catch (_) {
        // Vanished between listing and stat: not our size to count.
      }
    }
    return total;
  }

  Future<int> bytesForPeer(String peerToken) async {
    final paths = await _database.listMediaRelPaths(peerToken: peerToken);
    var total = 0;
    for (final rel in paths) {
      try {
        final file = File(await _absChecked(rel));
        if (file.existsSync()) total += await file.length();
      } catch (_) {
        // A malformed relpath contributes nothing; reading it is not this
        // method's job to police.
      }
    }
    return total;
  }

  /// Best effort: a file that will not delete leaves bytes behind, which the
  /// quota will see, and that is better than refusing to forget the message.
  Future<void> deleteSealed(Iterable<String> relPaths) async {
    for (final rel in relPaths) {
      try {
        final file = File(await _absChecked(rel));
        if (file.existsSync()) await file.delete();
      } catch (e) {
        debugPrint('media not deleted: ${e.runtimeType}');
      }
    }
  }

  static String _mib(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(0);

  Future<Uint8List> readSealed(String relPath) async {
    final parts = p.split(relPath);
    if (parts.length != 2 ||
        parts[0] != 'media' ||
        !parts[1].endsWith('.bin') ||
        !_safeId.hasMatch(parts[1].substring(0, parts[1].length - 4))) {
      throw StateError('Invalid media_relpath');
    }
    final path = await _absChecked(relPath);
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('Media missing: $relPath');
    }
    final sealed = await file.readAsBytes();
    return _core.localOpen(dbKey: _database.dbKey, sealed: sealed);
  }
}
