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
    final relayInsecure =
        session.hasMessaging && session.messaging.relayIsInsecure;

    return Scaffold(
      backgroundColor: EncrypchatColors.canvas,
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            tooltip: 'Relay ciego',
            onPressed: session.hasMessaging
                ? () => showRelayDialog(context, session)
                : null,
            icon: Icon(
              Icons.cloud_outlined,
              color: session.hasMessaging && session.messaging.relayConfigured
                  ? EncrypchatColors.relay
                  : null,
            ),
          ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
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
          if (relayInsecure) const RelayInsecureNotice(),
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
                            'Importá un contacto. Preferí P2P; si está offline '
                            'y configurás relay (☁), el mensaje espera cifrado.',
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
                      final blocked = session.isBlocked(c.token);
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
                                  c.label.isEmpty
                                      ? '?'
                                      : c.label[0].toUpperCase(),
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
                          blocked
                              ? 'Bloqueado · no recibís nada de este token'
                              : 'Tocá para chatear · P2P',
                          style: const TextStyle(color: EncrypchatColors.muted),
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  ChatPage(session: session, peer: c),
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
