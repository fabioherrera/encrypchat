import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Loads `libencrypchat_core` for Dart FFI.
DynamicLibrary loadEncrypchatCore() {
  final override = Platform.environment['ENCRYPCHAT_CORE_LIB'];
  if (override != null && override.isNotEmpty) {
    return DynamicLibrary.open(override);
  }

  if (Platform.isLinux) {
    for (final candidate in _linuxCandidates()) {
      final file = File(candidate);
      if (file.existsSync()) {
        return DynamicLibrary.open(candidate);
      }
    }
    return DynamicLibrary.open('libencrypchat_core.so');
  }

  if (Platform.isAndroid) {
    return DynamicLibrary.open('libencrypchat_core.so');
  }

  if (Platform.isWindows) {
    for (final candidate in _windowsCandidates()) {
      if (File(candidate).existsSync()) {
        return DynamicLibrary.open(candidate);
      }
    }
    return DynamicLibrary.open('encrypchat_core.dll');
  }

  if (Platform.isIOS || Platform.isMacOS) {
    try {
      return DynamicLibrary.open('encrypchat_core.framework/encrypchat_core');
    } catch (_) {
      return DynamicLibrary.process();
    }
  }

  throw UnsupportedError(
    'encrypchat_core FFI is not bundled for ${Platform.operatingSystem}',
  );
}

List<String> _linuxCandidates() {
  final execDir = File(Platform.resolvedExecutable).parent.path;
  final cwd = Directory.current.path;
  return [
    p.join(execDir, 'lib', 'libencrypchat_core.so'),
    p.join(execDir, 'libencrypchat_core.so'),
    p.join(cwd, 'native', 'libencrypchat_core.so'),
    p.join(cwd, 'apps', 'client', 'native', 'libencrypchat_core.so'),
    // Dev: monorepo apps/client → ../../target/release
    p.normalize(p.join(cwd, '..', '..', 'target', 'release', 'libencrypchat_core.so')),
    p.normalize(p.join(cwd, 'target', 'release', 'libencrypchat_core.so')),
  ];
}

List<String> _windowsCandidates() {
  final execDir = File(Platform.resolvedExecutable).parent.path;
  final cwd = Directory.current.path;
  return [
    p.join(execDir, 'encrypchat_core.dll'),
    p.join(cwd, 'native', 'encrypchat_core.dll'),
  ];
}

/// True when we can open the native library (best-effort probe).
bool canLoadEncrypchatCore() {
  try {
    loadEncrypchatCore();
    return true;
  } catch (e, st) {
    debugPrint('encrypchat_core load failed: $e\n$st');
    return false;
  }
}
