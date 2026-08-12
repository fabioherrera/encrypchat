import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/legal_links.dart';
import '../services/session_controller.dart';
import '../theme/encrypchat_colors.dart';
import 'blocked_page.dart';

/// Legal links + safety controls in one place: what the stores ask an app with
/// user-generated content to expose, and what this architecture can honestly
/// offer (block locally, document abuse locally — no moderation backend).
class AboutPage extends StatefulWidget {
  const AboutPage({super.key, required this.session});

  final SessionController session;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final locale = LegalLinks.deviceLocale;
    final blockedCount = session.blockedTokens.length;

    return Scaffold(
      backgroundColor: EncrypchatColors.canvas,
      appBar: AppBar(title: const Text('Acerca de')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const _SectionTitle('Legal'),
          _LinkTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Política de privacidad',
            url: LegalLinks.privacy(locale),
          ),
          _LinkTile(
            icon: Icons.gavel_outlined,
            title: 'Términos de uso',
            url: LegalLinks.terms(locale),
          ),
          const _SectionTitle('Seguridad y abuso'),
          ListTile(
            tileColor: EncrypchatColors.paper,
            leading: const Icon(Icons.block, color: EncrypchatColors.navy),
            title: const Text('Contactos bloqueados'),
            subtitle: Text(
              blockedCount == 0
                  ? 'Ninguno'
                  : '$blockedCount ${blockedCount == 1 ? 'token' : 'tokens'} '
                        'en este dispositivo',
              style: const TextStyle(color: EncrypchatColors.muted),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BlockedPage(session: session),
                ),
              );
              if (mounted) setState(() {});
            },
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Los mensajes van cifrados de extremo a extremo: Encrypchat no '
              'los puede leer ni moderar, y no hay servidor que reciba una '
              'denuncia. Lo que sí podés hacer desde el chat o desde la ficha '
              'de un contacto:\n\n'
              '· Bloquear: sus mensajes, fotos y llamadas se descartan en este '
              'dispositivo antes de abrirlos, y el bloqueo sigue después de '
              'reiniciar.\n'
              '· Reportar: se arma un informe con el token, el motivo y tu '
              'descripción, y se copia a tu portapapeles. No se envía a ningún '
              'servidor ni incluye el contenido de la conversación; vos '
              'decidís si se lo das a alguien.\n\n'
              'Bloquear no impide que esa persona cree una identidad nueva con '
              'otro token.',
              style: TextStyle(
                color: EncrypchatColors.muted,
                height: 1.45,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: EncrypchatColors.muted,
        ),
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.icon, required this.title, required this.url});

  final IconData icon;
  final String title;
  final String url;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      tileColor: EncrypchatColors.paper,
      leading: Icon(icon, color: EncrypchatColors.navy),
      title: Text(title),
      subtitle: Text(
        url,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: EncrypchatColors.muted),
      ),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: () => openExternalUrl(context, url),
      onLongPress: () => _copy(context, url),
    );
  }
}

/// Opens the page in the OS browser. When no handler exists (a desktop session
/// without a browser, a locked-down device), the URL is copied instead of
/// failing silently: the address stays reachable.
Future<void> openExternalUrl(BuildContext context, String url) async {
  var opened = false;
  try {
    opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    opened = false;
  }
  if (opened || !context.mounted) return;
  await _copy(context, url);
}

Future<void> _copy(BuildContext context, String url) async {
  await Clipboard.setData(ClipboardData(text: url));
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('Enlace copiado: $url')));
}
