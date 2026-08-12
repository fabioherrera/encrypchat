import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/encrypchat_core.dart';
import 'local_database.dart';

/// Sealed media files under app-support (never plaintext on disk).
class MediaStore {
  MediaStore({required EncrypchatCore core, required LocalDatabase database})
    : _core = core,
      _database = database;

  final EncrypchatCore _core;
  final LocalDatabase _database;

  static final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  String _relForId(String id) {
    if (!_safeId.hasMatch(id)) {
      throw ArgumentError('Invalid media id');
    }
    return p.join('media', '$id.bin');
  }

  Future<Directory> _mediaRoot() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'media'));
  }

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
