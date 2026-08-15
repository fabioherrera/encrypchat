import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/legal_links.dart';
import '../services/session_controller.dart';
import '../theme/encrypchat_colors.dart';
import 'about_page.dart';
import 'delete_identity_page.dart';

class MyTokenPage extends StatefulWidget {
  const MyTokenPage({super.key, required this.session});

  final SessionController session;

  @override
  State<MyTokenPage> createState() => _MyTokenPageState();
}

class _MyTokenPageState extends State<MyTokenPage> {
  @override
  void initState() {
    super.initState();
    final session = widget.session;
    if (session.hasMessaging) {
      session.messaging.refreshLanListenAddrs().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
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
            'Para que te agreguen, toca Exportar contacto y pásales esa '
            'línea — o muestra el QR. El token solo no alcanza: hace falta '
            'la clave pública. Si el nodo está en marcha, el export incluye '
            'tu dirección en esta Wi‑Fi.\n\n'
            'Dar tu tarjeta no te agrega a nadie. Si esa persona te agrega '
            'y hay ruta (P2P en esta red, o el relay), te aparece '
            'Solicitudes. Si no aparece nada, pega también su export en '
            'Agregar contacto. Nunca compartas la clave secreta.',
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
                  if (session.hasMessaging) {
                    await session.messaging.refreshLanListenAddrs();
                  }
                  if (!context.mounted) return;
                  final line = session.exportOwnContact();
                  await Clipboard.setData(ClipboardData(text: line));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Contacto exportado al portapapeles'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.ios_share),
                label: const Text('Exportar contacto'),
              ),
              OutlinedButton.icon(
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
          const SizedBox(height: 24),
          // Next to the identity it destroys, and reachable: an app that keeps
          // your data only on your device has to let you take it off the device.
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_forever_outlined, color: _danger),
            title: const Text(
              'Borrar identidad de este dispositivo',
              style: TextStyle(fontWeight: FontWeight.w600, color: _danger),
            ),
            subtitle: const Text(
              'Tu clave, tus chats y tus adjuntos. Irreversible.',
              style: TextStyle(fontSize: 12.5, color: EncrypchatColors.muted),
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DeleteIdentityPage(session: session),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _danger = Color(0xFF8C1C13);

  void _openAbout(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AboutPage(session: widget.session),
      ),
    );
  }
}
