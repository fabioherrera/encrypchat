import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/session_controller.dart';
import '../theme/encrypchat_colors.dart';

class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key, required this.session});

  final SessionController session;

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  Future<void> _importDialog() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Importar contacto'),
          content: TextField(
            controller: controller,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Pegá encrypchat:contact:v1:…',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Importar'),
            ),
          ],
        );
      },
    );
    if (raw == null || raw.trim().isEmpty) return;
    try {
      await widget.session.importContact(raw);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contacto guardado')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo importar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = widget.session.contacts;

    return Scaffold(
      backgroundColor: EncrypchatColors.canvas,
      appBar: AppBar(
        title: const Text('Contactos'),
        actions: [
          IconButton(
            tooltip: 'Importar',
            onPressed: _importDialog,
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
                      'Importá un export o QR de otro dispositivo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: EncrypchatColors.muted),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _importDialog,
                      child: const Text('Importar contacto'),
                    ),
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
                return ListTile(
                  tileColor: EncrypchatColors.paper,
                  leading: CircleAvatar(
                    backgroundColor: EncrypchatColors.navy,
                    foregroundColor: EncrypchatColors.paper,
                    child: Text(
                      c.label.isEmpty ? '?' : c.label[0].toUpperCase(),
                    ),
                  ),
                  title: Text(
                    c.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: EncrypchatColors.ink,
                    ),
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
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'copy') {
                        await Clipboard.setData(ClipboardData(text: c.exportLine()));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Export copiado')),
                          );
                        }
                      } else if (value == 'delete') {
                        await widget.session.removeContact(c.token);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'copy', child: Text('Exportar')),
                      PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
