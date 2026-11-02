import 'dart:async';

import 'package:flutter/foundation.dart';

import 'update_applier.dart';
import 'update_checker.dart';

/// Installs signed updates without being asked, on the channels that can.
///
/// An update closes the app, so it waits for a moment that interrupts nothing:
/// right after launch, or while the app is in the background, and never during
/// a call. Linux keeps the manual flow because `dnf` needs the user's password.
class AutoUpdater {
  AutoUpdater({
    required this.checker,
    required this.applier,
    required this.isEnabled,
    required this.isBusy,
    required this.isVisible,
    this.canInstallSilently,
    this.interval = const Duration(hours: 6),
  });

  final UpdateChecker checker;
  final UpdateApplier applier;
  final bool Function() isEnabled;

  /// True during a call.
  final bool Function() isBusy;
  final bool Function() isVisible;

  /// Android needs the "install unknown apps" permission first. Without it the
  /// banner stays and the person grants it from there.
  final Future<bool> Function()? canInstallSilently;
  final Duration interval;

  Timer? _timer;
  bool _running = false;

  void start() {
    unawaited(run(atLaunch: true));
    _timer = Timer.periodic(interval, (_) => unawaited(run(atLaunch: false)));
  }

  static bool supports(UpdateChannel? channel) =>
      channel == UpdateChannel.androidApk ||
      channel == UpdateChannel.windowsSetup;

  @visibleForTesting
  Future<void> run({required bool atLaunch}) async {
    if (_running) return;
    _running = true;
    try {
      await checker.check(force: !atLaunch);
      final package = checker.info.package;
      if (package == null || !checker.info.canApply) return;
      if (!supports(package.channel) || !isEnabled() || isBusy()) return;
      if (!atLaunch && isVisible()) return;
      if (applier.phase != UpdateApplyPhase.idle) return;
      final allowed = await canInstallSilently?.call() ?? true;
      if (!allowed) return;
      await applier.apply(package);
    } catch (e) {
      debugPrint('auto update failed: ${e.runtimeType}');
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
