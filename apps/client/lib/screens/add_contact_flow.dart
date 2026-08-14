import 'package:flutter/material.dart';

import '../models/contact.dart';
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
              'Pedile al otro que abra Mi token y toque Exportar contacto. '
              'Pegá esa línea acá.',
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
    await session.importContact(raw);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Contacto guardado')));
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
