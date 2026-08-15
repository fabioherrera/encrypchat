import 'package:flutter/material.dart';

import '../services/session_controller.dart';
import '../theme/encrypchat_colors.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.session});

  final SessionController session;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  bool _busy = false;
  String? _error;

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.createIdentity();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EncrypchatColors.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Image.asset(
                  'assets/brand/logo-mark.png',
                  height: 96,
                  filterQuality: FilterQuality.high,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Encrypchat',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: EncrypchatColors.navy,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'DECENTRALIZED P2P CHAT | ZERO-CLOUD',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: EncrypchatColors.muted,
                  letterSpacing: 0.4,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Crea una identidad en este dispositivo. '
                'Las claves privadas no salen del teléfono o el computador.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: EncrypchatColors.ink,
                  height: 1.45,
                  fontSize: 16,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFB42318)),
                ),
              ],
              const Spacer(),
              FilledButton(
                onPressed: _busy ? null : _create,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: EncrypchatColors.navy,
                ),
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Crear identidad'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
