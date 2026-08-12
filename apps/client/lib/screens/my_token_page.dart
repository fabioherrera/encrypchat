import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/session_controller.dart';
import '../theme/encrypchat_colors.dart';

class MyTokenPage extends StatelessWidget {
  const MyTokenPage({super.key, required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final token = session.identity.token ?? '';
    final export = session.exportOwnContact();

    return Scaffold(
      backgroundColor: EncrypchatColors.canvas,
      appBar: AppBar(title: const Text('Mi token')),
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
        ],
      ),
    );
  }
}
