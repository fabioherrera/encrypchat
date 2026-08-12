import 'package:flutter/material.dart';

import '../services/session_controller.dart';
import '../theme/encrypchat_colors.dart';
import 'chat_page.dart';
import 'requests_page.dart';

class ChatsPage extends StatelessWidget {
  const ChatsPage({super.key, required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final contacts = session.contacts;
    final requests = session.requests;
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
          RelayPullFaultNotice(session: session),
          if (session.hasMessaging)
            InboundDropNotice(messaging: session.messaging),
          if (requests.isNotEmpty) _RequestsTile(session: session),
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
                          // "El mensaje espera cifrado" was a promise the relay
                          // never makes: it accepts a blob it may not have room
                          // to keep, and saying so would tell a stranger when
                          // somebody is online. P2P is the only path with an
                          // acknowledgement, so that is what the copy leads on.
                          Text(
                            'Importá un contacto. P2P es el camino directo y el '
                            'único que confirma la entrega; si está offline y '
                            'configurás relay (☁), el mensaje sale cifrado '
                            'hacia ahí.',
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

/// Entry point for messages from identities that are not contacts.
///
/// It sits above the list rather than inside it: a stranger is not a chat yet,
/// and mixing them in would put someone the user never agended next to their
/// contacts. Deliberately quiet — no badge colour, no count in a pill — because
/// the whole point of the policy is that a stranger cannot demand attention.
class _RequestsTile extends StatelessWidget {
  const _RequestsTile({required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final count = session.requests.length;
    return Material(
      color: EncrypchatColors.paper,
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: EncrypchatColors.bubbleOut,
          foregroundColor: EncrypchatColors.navy,
          child: Icon(Icons.mark_email_unread_outlined, size: 20),
        ),
        title: const Text(
          'Solicitudes',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: EncrypchatColors.ink,
          ),
        ),
        subtitle: Text(
          count == 1
              ? '1 persona que no tenés agendada te escribió'
              : '$count personas que no tenés agendadas te escribieron',
          style: const TextStyle(color: EncrypchatColors.muted),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: EncrypchatColors.muted,
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RequestsPage(session: session),
          ),
        ),
      ),
    );
  }
}
