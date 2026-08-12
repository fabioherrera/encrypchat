import 'package:flutter/material.dart';

import '../services/session_controller.dart';
import '../theme/encrypchat_colors.dart';
import 'chat_page.dart';

class ChatsPage extends StatelessWidget {
  const ChatsPage({super.key, required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final contacts = session.contacts;
    final listen = session.hasMessaging ? session.messaging.listenAddr : null;

    return Scaffold(
      backgroundColor: EncrypchatColors.canvas,
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            tooltip: 'Conectar peer',
            onPressed: session.hasMessaging
                ? () => showConnectPeerDialog(context, session)
                : null,
            icon: const Icon(Icons.link),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (listen != null)
            Material(
              color: EncrypchatColors.paper,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  'Nodo P2P: $listen',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: EncrypchatColors.muted,
                  ),
                ),
              ),
            ),
          Expanded(
            child: contacts.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 56,
                            color: EncrypchatColors.offline,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Sin chats aún',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: EncrypchatColors.ink,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Importá un contacto y conectá su IP:puerto '
                            '(ambos online). Sin relay en Fase 4.',
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
                        subtitle: const Text(
                          'Tocá para chatear · P2P',
                          style: TextStyle(color: EncrypchatColors.muted),
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ChatPage(
                                session: session,
                                peer: c,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
