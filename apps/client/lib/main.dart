import 'package:flutter/material.dart';

import 'screens/onboarding_page.dart';
import 'screens/shell_page.dart';
import 'services/session_controller.dart';
import 'theme/encrypchat_colors.dart';
import 'theme/encrypchat_theme.dart';

/// Encrypchat shell — Phase 3: identity + encrypted local store + brand UI.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EncrypchatApp());
}

class EncrypchatApp extends StatefulWidget {
  const EncrypchatApp({super.key, this.session});

  /// Injectable for tests.
  final SessionController? session;

  @override
  State<EncrypchatApp> createState() => _EncrypchatAppState();
}

class _EncrypchatAppState extends State<EncrypchatApp> {
  late final SessionController _session =
      widget.session ?? SessionController();

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
