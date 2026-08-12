import 'package:flutter/material.dart';

import '../services/session_controller.dart';
import '../theme/encrypchat_colors.dart';
import 'safety_actions.dart';

/// Blocked tokens live on this device only; the list is the whole state of the
/// feature, so it doubles as the place to undo a block.
class BlockedPage extends StatefulWidget {
  const BlockedPage({super.key, required this.session});

  final SessionController session;

  @override
  State<BlockedPage> createState() => _BlockedPageState();
}

class _BlockedPageState extends State<BlockedPage> {
  @override
  Widget build(BuildContext context) {
    final tokens = widget.session.blockedTokens;

    return Scaffold(
      backgroundColor: EncrypchatColors.canvas,
      appBar: AppBar(title: const Text('Contactos bloqueados')),
      body: tokens.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.block,
                      size: 56,
                      color: EncrypchatColors.offline,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No bloqueaste a nadie',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: EncrypchatColors.ink,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Podés bloquear desde el chat o desde la ficha del '
                      'contacto. El bloqueo se aplica en este dispositivo y '
                      'sigue activo después de reiniciar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: EncrypchatColors.muted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              itemCount: tokens.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: EncrypchatColors.navy.withValues(alpha: 0.12),
              ),
              itemBuilder: (context, index) {
                final token = tokens[index];
                final contact = widget.session.contactByToken(token);
                final label = contact?.label ?? token;
                return ListTile(
                  tileColor: EncrypchatColors.paper,
                  leading: const CircleAvatar(
                    backgroundColor: EncrypchatColors.offline,
                    foregroundColor: EncrypchatColors.paper,
                    child: Icon(Icons.block, size: 20),
                  ),
                  title: Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: EncrypchatColors.ink,
                    ),
                  ),
                  subtitle: Text(
                    token,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: EncrypchatColors.muted,
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      await confirmUnblock(
                        context,
                        widget.session,
                        token: token,
                        label: label,
                      );
                      if (mounted) setState(() {});
                    },
                    child: const Text('Desbloquear'),
                  ),
                );
              },
            ),
    );
  }
}
