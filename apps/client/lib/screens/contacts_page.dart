import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/contact.dart';
import '../services/session_controller.dart';
import '../theme/encrypchat_colors.dart';
import 'add_contact_flow.dart';
import 'safety_actions.dart';
import 'scan_contact_page.dart';

class ContactsPage extends StatefulWidget {
  const ContactsPage({
    super.key,
    required this.session,
    this.scanCard,
    this.onOpenContact,
  });

  final SessionController session;

  /// Production opens the camera on a phone. Tests pass a card without
  /// touching it. Desktop adds contacts by pasting the export, not by
  /// picking a screenshot.
  final Future<String?> Function(BuildContext context)? scanCard;

  /// Desktop split: opening a contact shows the chat in the right pane.
  final ValueChanged<Contact>? onOpenContact;

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  Future<void> _scan() =>
      scanAndImportContact(context, widget.session, scanCard: widget.scanCard);

  Future<void> _add() => showAddContactDialog(context, widget.session);

  /// Deleting a contact removes the conversation too, because the chat list is
  /// built from contacts: leaving the messages would leave them unreachable and
  /// growing, which is the invisibility F-6 was about. So it has to be said out
  /// loud before it happens.
  Future<void> _confirmDelete(String token, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Eliminar a $label'),
        content: const Text(
          'Se borran también los mensajes y los adjuntos de esta conversación '
          'en este dispositivo. No se puede deshacer.\n\n'
          'Eliminar no es bloquear: si te vuelve a escribir, aparecerá en '
          'Solicitudes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.session.removeContact(token);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final contacts = widget.session.contacts;

    return Scaffold(
      backgroundColor: EncrypchatColors.canvas,
      appBar: AppBar(
        title: const Text('Contactos'),
        actions: [
          if (liveCameraScanAvailable)
            IconButton(
              tooltip: 'Escanear QR',
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner),
            ),
          IconButton(
            tooltip: 'Agregar contacto',
            onPressed: _add,
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
      body: contacts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 56,
                      color: EncrypchatColors.navy.withValues(alpha: 0.45),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Sin contactos aún',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: EncrypchatColors.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Pídele que abra Mi token y toque Exportar contacto. '
                      'Pega esa línea aquí. Dar tu tarjeta no crea una '
                      'solicitud en este dispositivo: si no te llega '
                      'Solicitudes, agrega tú también la de esa persona.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: EncrypchatColors.muted),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _add,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Agregar contacto'),
                    ),
                    if (liveCameraScanAvailable) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _scan,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Escanear QR'),
                      ),
                    ],
                  ],
                ),
              ),
            )
          : ListView.separated(
              itemCount: contacts.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: EncrypchatColors.navy.withValues(alpha: 0.12),
              ),
              itemBuilder: (context, index) {
                final c = contacts[index];
                final blocked = widget.session.isBlocked(c.token);
                return ListTile(
                  tileColor: EncrypchatColors.paper,
                  leading: CircleAvatar(
                    backgroundColor: blocked
                        ? EncrypchatColors.offline
                        : EncrypchatColors.navy,
                    foregroundColor: EncrypchatColors.paper,
                    child: blocked
                        ? const Icon(Icons.block, size: 20)
                        : Text(
                            c.label.isEmpty ? '?' : c.label[0].toUpperCase(),
                          ),
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          c.label,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: EncrypchatColors.ink,
                          ),
                        ),
                      ),
                      if (blocked) ...[
                        const SizedBox(width: 8),
                        const Text(
                          'Bloqueado',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: EncrypchatColors.offline,
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    c.token,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: EncrypchatColors.muted,
                    ),
                  ),
                  onTap: widget.onOpenContact == null
                      ? null
                      : () => widget.onOpenContact!(c),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'copy') {
                        await Clipboard.setData(
                          ClipboardData(text: c.exportLine()),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Export copiado')),
                          );
                        }
                      } else if (value == 'block') {
                        await confirmBlock(
                          context,
                          widget.session,
                          token: c.token,
                          label: c.label,
                        );
                        if (mounted) setState(() {});
                      } else if (value == 'unblock') {
                        await confirmUnblock(
                          context,
                          widget.session,
                          token: c.token,
                          label: c.label,
                        );
                        if (mounted) setState(() {});
                      } else if (value == 'report') {
                        await showReportDialog(
                          context,
                          widget.session,
                          token: c.token,
                          label: c.label,
                        );
                        if (mounted) setState(() {});
                      } else if (value == 'delete') {
                        await _confirmDelete(c.token, c.label);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'copy',
                        child: Text('Exportar'),
                      ),
                      if (blocked)
                        const PopupMenuItem(
                          value: 'unblock',
                          child: Text('Desbloquear'),
                        )
                      else
                        const PopupMenuItem(
                          value: 'block',
                          child: Text('Bloquear'),
                        ),
                      const PopupMenuItem(
                        value: 'report',
                        child: Text('Reportar abuso'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Eliminar'),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
