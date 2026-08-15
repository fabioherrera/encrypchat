import 'package:flutter/material.dart';

import '../core/app_version.dart';
import '../core/legal_links.dart';
import '../services/session_controller.dart';
import '../services/update_applier.dart';
import '../services/update_checker.dart';
import '../theme/encrypchat_colors.dart';
import '../widgets/update_banner.dart';
import 'about_page.dart';
import 'blocked_page.dart';

/// Ajustes: versión, actualización con consentimiento y legal/bloqueo.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.session,
    required this.updates,
    required this.applier,
  });

  final SessionController session;
  final UpdateChecker updates;
  final UpdateApplier applier;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([session, updates, applier]),
      builder: (context, _) => _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
    final info = updates.info;
    final latest = info.latestVersion;
    final statusLine = switch (info.status) {
      UpdateStatus.idle => 'No se buscó todavía.',
      UpdateStatus.checking => 'Consultando encrypchat.com…',
      UpdateStatus.current =>
        'Estás en $encrypchatVersion, la última publicada.',
      UpdateStatus.available =>
        'Hay $latest. Esta copia es $encrypchatVersion.',
      UpdateStatus.failed =>
        'No se pudo consultar. Prueba de nuevo o abre la página de descargas.',
    };

    return Scaffold(
      backgroundColor: EncrypchatColors.canvas,
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: [
          UpdateBanner(
            info: info,
            onReview: () =>
                showUpdateOffer(context: context, info: info, applier: applier),
          ),
          const _SectionTitle('Esta instalación'),
          ListTile(
            tileColor: EncrypchatColors.paper,
            leading: const Icon(
              Icons.info_outline,
              color: EncrypchatColors.navy,
            ),
            title: const Text('Versión'),
            subtitle: Text(
              encrypchatVersion,
              style: const TextStyle(color: EncrypchatColors.muted),
            ),
          ),
          ListTile(
            tileColor: EncrypchatColors.paper,
            leading: Icon(
              info.hasUpdate
                  ? Icons.system_update_alt
                  : Icons.verified_outlined,
              color: info.hasUpdate
                  ? EncrypchatColors.relay
                  : EncrypchatColors.p2p,
            ),
            title: const Text('Actualizaciones'),
            subtitle: Text(
              statusLine,
              style: const TextStyle(color: EncrypchatColors.muted),
            ),
            trailing: info.status == UpdateStatus.checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(
                    onPressed: () => updates.check(force: true),
                    child: const Text('Buscar'),
                  ),
          ),
          if (info.hasUpdate)
            ListTile(
              tileColor: EncrypchatColors.paper,
              leading: const Icon(
                Icons.system_update_alt,
                color: EncrypchatColors.navy,
              ),
              title: const Text('Actualizar la app'),
              subtitle: const Text(
                'Solo el programa: seguridad, estabilidad y funciones. '
                'Tus chats se quedan en este dispositivo.',
                style: TextStyle(color: EncrypchatColors.muted),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showUpdateOffer(
                context: context,
                info: info,
                applier: applier,
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'La actualización es explícita: aparece un aviso, lees de qué '
              'se trata y tocas Actualizar la app. Encrypchat descarga el '
              'paquete, comprueba su SHA-256 e invoca el instalador del '
              'sistema. No se tocan chats, fotos ni claves: viven en este '
              'dispositivo.\n\n'
              '· Fedora (RPM): el sistema pide tu contraseña y reemplaza '
              'los archivos en /usr/lib64/encrypchat.\n'
              '· Linux portable: se descarga el tar.gz; ejecuta install.sh '
              'en el mismo prefijo.\n'
              '· Android: el instalador del sistema pide confirmar. Los '
              'datos se conservan si la firma es la misma.\n'
              '· Windows / iOS: todavía no hay paquete automático; se abre '
              'la página de descargas.\n\n'
              'Para saber si hay versión nueva, la app lee '
              'encrypchat.com/latest.json. No envía tu token ni tus chats.',
              style: TextStyle(
                color: EncrypchatColors.muted,
                height: 1.45,
                fontSize: 13,
              ),
            ),
          ),
          const _SectionTitle('Legal y seguridad'),
          _LinkTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Política de privacidad',
            url: LegalLinks.privacy(LegalLinks.deviceLocale),
          ),
          _LinkTile(
            icon: Icons.gavel_outlined,
            title: 'Términos de uso',
            url: LegalLinks.terms(LegalLinks.deviceLocale),
          ),
          ListTile(
            tileColor: EncrypchatColors.paper,
            leading: const Icon(Icons.block, color: EncrypchatColors.navy),
            title: const Text('Contactos bloqueados'),
            subtitle: Text(
              session.blockedTokens.isEmpty
                  ? 'Ninguno'
                  : '${session.blockedTokens.length} en este dispositivo',
              style: const TextStyle(color: EncrypchatColors.muted),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => BlockedPage(session: session),
              ),
            ),
          ),
          ListTile(
            tileColor: EncrypchatColors.paper,
            leading: const Icon(
              Icons.article_outlined,
              color: EncrypchatColors.navy,
            ),
            title: const Text('Acerca de'),
            subtitle: const Text(
              'Moderación, bloqueo y reportes locales',
              style: TextStyle(color: EncrypchatColors.muted),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AboutPage(session: session),
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
    );
  }
}
