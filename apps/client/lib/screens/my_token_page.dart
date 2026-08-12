import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/legal_links.dart';
import '../services/session_controller.dart';
import '../theme/encrypchat_colors.dart';
import 'about_page.dart';

class MyTokenPage extends StatelessWidget {
  const MyTokenPage({super.key, required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final token = session.identity.token ?? '';
    final export = session.exportOwnContact();

    return Scaffold(
      backgroundColor: EncrypchatColors.canvas,
      appBar: AppBar(
        title: const Text('Mi token'),
        actions: [
          IconButton(
            tooltip: 'Acerca de, privacidad y bloqueos',
            onPressed: () => _openAbout(context),
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Tu identidad en Encrypchat',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: EncrypchatColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Compartí el QR o el export con contactos de confianza. '
            'Nunca compartas la clave secreta del dispositivo.',
            style: TextStyle(color: EncrypchatColors.muted, height: 1.4),
          ),
          const SizedBox(height: 28),
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: EncrypchatColors.paper,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: EncrypchatColors.navy.withValues(alpha: 0.12),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: QrImageView(
                  data: export,
                  version: QrVersions.auto,
                  size: 220,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: EncrypchatColors.navy,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: EncrypchatColors.navy,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SelectableText(
            token,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: EncrypchatColors.ink,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: token));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Token copiado')),
                    );
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copiar token'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: export));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Contacto exportado al portapapeles')),
                    );
                  }
                },
                icon: const Icon(Icons.ios_share),
                label: const Text('Exportar contacto'),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Divider(color: EncrypchatColors.navy.withValues(alpha: 0.12)),
          const SizedBox(height: 4),
          Wrap(
            children: [
              TextButton(
                onPressed: () => openExternalUrl(
                  context,
                  LegalLinks.privacy(LegalLinks.deviceLocale),
                ),
                child: const Text('Privacidad'),
              ),
              TextButton(
                onPressed: () => openExternalUrl(
                  context,
                  LegalLinks.terms(LegalLinks.deviceLocale),
                ),
                child: const Text('Términos'),
              ),
              TextButton(
                onPressed: () => _openAbout(context),
                child: const Text('Acerca de'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openAbout(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AboutPage(session: session),
      ),
    );
  }
}
