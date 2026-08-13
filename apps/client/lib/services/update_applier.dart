import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/update_copy.dart';
import 'update_checker.dart';

enum UpdateApplyPhase {
  idle,
  downloading,
  verifying,
  installing,
  done,
  failed,
}

/// Downloads the catalogued package, checks SHA-256, then hands it to the OS
/// installer. Never runs without the user having accepted the consent dialog.
class UpdateApplier extends ChangeNotifier {
  UpdateApplier({
    http.Client? client,
    this.installHook,
    this.tempDirectory,
    this.android = const AndroidUpdateBridge(),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  /// Tests replace the OS installer.
  final Future<void> Function(File file, UpdateChannel channel)? installHook;

  /// Tests replace the cache directory.
  final Directory Function()? tempDirectory;

  final AndroidUpdateBridge android;

  UpdateApplyPhase _phase = UpdateApplyPhase.idle;
  double _progress = 0;
  String? _error;
  bool _disposed = false;

  UpdateApplyPhase get phase => _phase;
  double get progress => _progress;
  String? get error => _error;

  Future<void> apply(UpdatePackage package) async {
    if (_disposed) return;
    _phase = UpdateApplyPhase.downloading;
    _progress = 0;
    _error = null;
    notifyListeners();
    try {
      final file = await _download(package);
      if (_disposed) return;
      _phase = UpdateApplyPhase.verifying;
      notifyListeners();
      final digest = sha256.convert(await file.readAsBytes()).toString();
      if (digest != package.sha256) {
        try {
          await file.delete();
        } catch (_) {}
        throw UpdateApplyException(UpdateCopy.hashMismatch);
      }
      if (_disposed) return;
      _phase = UpdateApplyPhase.installing;
      notifyListeners();
      final hook = installHook;
      if (hook != null) {
        await hook(file, package.channel);
      } else {
        await _install(file, package.channel);
      }
      if (_disposed) return;
      _phase = UpdateApplyPhase.done;
      notifyListeners();
    } on UpdateApplyException catch (e) {
      if (_disposed) return;
      _phase = UpdateApplyPhase.failed;
      _error = e.message;
      notifyListeners();
    } catch (e) {
      if (_disposed) return;
      _phase = UpdateApplyPhase.failed;
      _error = e.toString();
      notifyListeners();
    }
  }

  void reset() {
    _phase = UpdateApplyPhase.idle;
    _progress = 0;
    _error = null;
    notifyListeners();
  }

  Future<File> _download(UpdatePackage package) async {
    final dir = tempDirectory != null
        ? tempDirectory!()
        : Directory(p.join((await getTemporaryDirectory()).path, 'updates'));
    await dir.create(recursive: true);
    final dest = File(p.join(dir.path, package.fileName));
    final req = http.Request('GET', package.url);
    final res = await _client.send(req).timeout(const Duration(minutes: 5));
    if (res.statusCode != 200) {
      throw UpdateApplyException(
        'No se pudo descargar el paquete (${res.statusCode}).',
      );
    }
    final total = res.contentLength ?? 0;
    final sink = dest.openWrite();
    var got = 0;
    await for (final chunk in res.stream) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) {
        _progress = got / total;
        notifyListeners();
      }
    }
    await sink.close();
    return dest;
  }

  Future<void> _install(File file, UpdateChannel channel) async {
    switch (channel) {
      case UpdateChannel.androidApk:
        await android.installApk(file);
      case UpdateChannel.linuxRpm:
        await _linuxRpm(file);
      case UpdateChannel.linuxTarball:
        await _openWith(file.parent.path);
      case UpdateChannel.windowsZip:
        await _openWith(file.path);
    }
  }

  Future<void> _linuxRpm(File file) async {
    try {
      final pkexec = await Process.run('pkexec', [
        'dnf',
        'install',
        '-y',
        file.path,
      ]);
      if (pkexec.exitCode == 0) return;
    } on ProcessException {
      // No polkit, or pkexec missing: fall through to the desktop opener.
    }
    await _openWith(file.path);
  }

  Future<void> _openWith(String path) async {
    final opener = Platform.isWindows ? 'explorer' : 'xdg-open';
    final opened = await Process.run(opener, [path]);
    if (opened.exitCode != 0) {
      throw UpdateApplyException(
        'El archivo está en $path. Abrilo con el instalador del sistema.',
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsClient) _client.close();
    super.dispose();
  }
}

class UpdateApplyException implements Exception {
  const UpdateApplyException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Android package installer. Production talks to [MainActivity]; tests stub it.
class AndroidUpdateBridge {
  const AndroidUpdateBridge({this.channel});

  static const _name = 'encrypchat/updates';
  final MethodChannel? channel;

  MethodChannel get _ch => channel ?? const MethodChannel(_name);

  Future<bool> canInstall() async {
    final allowed = await _ch.invokeMethod<bool>('canInstall');
    return allowed ?? false;
  }

  Future<void> openInstallPermission() =>
      _ch.invokeMethod<void>('openInstallPermission');

  Future<void> installApk(File file) async {
    if (!await canInstall()) {
      await openInstallPermission();
      throw const UpdateApplyException(
        'Android pide permiso para instalar esta app. Concedelo y volvé a '
        'tocar Actualizar la app.',
      );
    }
    await _ch.invokeMethod<void>('installApk', {'path': file.path});
  }
}
