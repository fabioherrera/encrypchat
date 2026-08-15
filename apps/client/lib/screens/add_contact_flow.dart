import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../services/messaging_service.dart';
import '../services/session_controller.dart';
import 'scan_contact_page.dart';

/// Pastes the export line the other device copied from Mi token.
///
/// A bare `ec_…` token is not enough: the card has to carry the public key.
Future<void> showAddContactDialog(
  BuildContext context,
  SessionController session,
) async {
  final raw = await showDialog<String>(
    context: context,
    builder: (_) => const _AddContactDialog(),
  );
  if (raw == null || raw.trim().isEmpty) return;
  if (!context.mounted) return;
  await importContactRaw(context, session, raw);
}

class _AddContactDialog extends StatefulWidget {
  const _AddContactDialog();

  @override
  State<_AddContactDialog> createState() => _AddContactDialogState();
}

class _AddContactDialogState extends State<_AddContactDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar contacto'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Pídele a la otra persona que abra Mi token y toque '
              'Exportar contacto. Pega esa línea aquí. Primero se intenta '
              'P2P; si no hay ruta, el aviso va en un sobre al relay. Si '
              'llega, le aparece en Solicitudes para que te autorice.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              maxLines: 4,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'encrypchat:contact:v1:…',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}

Future<void> scanAndImportContact(
  BuildContext context,
  SessionController session, {
  Future<String?> Function(BuildContext context)? scanCard,
}) async {
  final raw = await (scanCard ?? scanContactCard)(context);
  if (raw == null || raw.trim().isEmpty) return;
  if (!context.mounted) return;
  await importContactRaw(context, session, raw);
}

Future<void> importContactRaw(
  BuildContext context,
  SessionController session,
  String raw,
) async {
  try {
    final contact = await session.importContact(raw);
    final announce = await session.announceNewContact(contact);
    if (context.mounted) {
      await showContactSaved(context, announce: announce);
    }
  } on ContactCardException catch (e) {
    if (context.mounted) await showContactCardRejected(context, e);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo importar: $e')));
    }
  }
}

Future<void> showContactSaved(
  BuildContext context, {
  required ContactAnnounce announce,
}) {
  final text = switch (announce) {
    ContactAnnounce.delivered =>
      'Le avisamos. En su Encrypchat debería aparecer Solicitudes '
          'para que te autorice (sin sonido).',
    ContactAnnounce.viaRelay =>
      'Le avisamos por relay. Cuando abra la app, verá Solicitudes '
          'para que te autorice.',
    ContactAnnounce.noRoute =>
      'Quedó guardado aquí, pero el aviso no salió: no hay sesión P2P '
          'y el relay no pudo tomarlo. Los dos necesitan internet y el '
          'relay encendido (☁, por defecto el de Encrypchat). En la misma '
          'Wi‑Fi también puedes abrir el puerto del nodo.',
  };
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Contacto guardado'),
      content: Text(text),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Entendido'),
        ),
      ],
    ),
  );
}

Future<void> showContactCardRejected(
  BuildContext context,
  ContactCardException error,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Tarjeta no válida'),
      content: Text(error.message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Entendido'),
        ),
      ],
    ),
  );
}
