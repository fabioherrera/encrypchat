import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'core/media_picker.dart';
import 'screens/onboarding_page.dart';
import 'screens/shell_page.dart';
import 'services/session_controller.dart';
import 'theme/encrypchat_colors.dart';
import 'theme/encrypchat_theme.dart';
import 'widgets/window_chrome.dart';

/// Encrypchat shell — Phase 3: identity + encrypted local store + brand UI.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureMediaPicker();
  await _configureDesktopWindow();
  // Sweeps what a crash (or a build before this existed) left in the cache:
  // plaintext copies of photos already sent. Not awaited — the UI does not
  // depend on it and it only touches the app's own temp dir.
  unawaited(purgePickerTemps());
  runApp(const EncrypchatApp());
}

/// Hides the OS title bar on Linux/Windows/macOS so Encrypchat draws its own
/// (see `DesktopWindowScaffold`). No-op on mobile and web.
Future<void> _configureDesktopWindow() async {
  if (!isDesktopWindow) return;
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1180, 760),
    minimumSize: Size(880, 600),
    center: true,
    backgroundColor: EncrypchatColors.canvas,
    title: 'Encrypchat',
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

class EncrypchatApp extends StatefulWidget {
  const EncrypchatApp({super.key, this.session});

  /// Injectable for tests.
  final SessionController? session;

  @override
  State<EncrypchatApp> createState() => _EncrypchatAppState();
}

class _EncrypchatAppState extends State<EncrypchatApp> {
  late final SessionController _session = widget.session ?? SessionController();

  @override
  void initState() {
    super.initState();
    if (widget.session == null) {
      _session.bootstrap();
    }
    _session.addListener(_onSession);
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    if (widget.session == null) {
      _session.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Encrypchat',
      debugShowCheckedModeBanner: false,
      theme: buildEncrypchatLightTheme(),
      builder: (context, child) =>
          DesktopWindowScaffold(child: child ?? const SizedBox.shrink()),
      home: _home(),
    );
  }

  Widget _home() {
    switch (_session.phase) {
      case AppPhase.loading:
        return const Scaffold(
          backgroundColor: EncrypchatColors.canvas,
          body: Center(
            child: CircularProgressIndicator(color: EncrypchatColors.navy),
          ),
        );
      case AppPhase.needsOnboarding:
        return OnboardingPage(session: _session);
      case AppPhase.ready:
        return ShellPage(session: _session);
      case AppPhase.error:
        return Scaffold(
          backgroundColor: EncrypchatColors.canvas,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'No se pudo iniciar Encrypchat',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: EncrypchatColors.ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _session.errorMessage ?? 'Error desconocido',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: EncrypchatColors.muted),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _session.bootstrap,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
        );
    }
  }
}
