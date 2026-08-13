import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../services/session_controller.dart';
import '../theme/encrypchat_colors.dart';
import '../widgets/raised_controls.dart';
import 'chat_page.dart';
import 'requests_page.dart';

enum _ChatFilter { all, unread, relay }

class ChatsPage extends StatefulWidget {
  const ChatsPage({
    super.key,
    required this.session,
    this.onOpenChat,
    this.selectedToken,
  });

  final SessionController session;

  /// When set (desktop split), the conversation opens in the right pane.
  /// When null, the page pushes [ChatPage] itself.
  final ValueChanged<Contact>? onOpenChat;
  final String? selectedToken;

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  final _search = TextEditingController();
  _ChatFilter _filter = _ChatFilter.all;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Contact> _visible() {
    final q = _search.text.trim().toLowerCase();
    return widget.session.contacts.where((c) {
      if (q.isNotEmpty && !c.label.toLowerCase().contains(q)) return false;
      // Unread and relay-per-chat are not in the list model yet. The chips
      // exist so the chrome matches the mockup; they do not invent counts.
      if (_filter == _ChatFilter.unread || _filter == _ChatFilter.relay) {
        return false;
      }
      return true;
    }).toList();
  }

  void _open(Contact c) {
    final open = widget.onOpenChat;
    if (open != null) {
      open(c);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(session: widget.session, peer: c),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final contacts = _visible();
    final requests = session.requests;
    final listen = session.hasMessaging ? session.messaging.listenAddr : null;
    final relayInsecure =
        session.hasMessaging && session.messaging.relayIsInsecure;
    final filterEmpty =
        session.contacts.isNotEmpty &&
        contacts.isEmpty &&
        (_filter != _ChatFilter.all || _search.text.trim().isNotEmpty);

    return Scaffold(
      backgroundColor: EncrypchatColors.canvas,
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          RaisedCircleButton(
            tooltip: 'Relay ciego',
            onPressed: session.hasMessaging
                ? () => showRelayDialog(context, session)
                : null,
            icon: Icons.cloud_outlined,
            iconColor: session.hasMessaging && session.messaging.relayConfigured
                ? EncrypchatColors.relay
                : EncrypchatColors.navy,
          ),
          const SizedBox(width: 8),
          RaisedCircleButton(
            tooltip: 'Conectar peer',
            onPressed: session.hasMessaging
                ? () => showConnectPeerDialog(context, session)
                : null,
            icon: Icons.link,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: EncrypchatColors.paper,
                borderRadius: BorderRadius.circular(22),
                boxShadow: EncrypchatColors.raisedShadow,
              ),
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  hintText: 'Buscar chats…',
                  prefixIcon: Icon(
                    Icons.search,
                    color: EncrypchatColors.muted,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              children: [
                RaisedFilterChip(
                  label: 'Todos',
                  selected: _filter == _ChatFilter.all,
                  onTap: () => setState(() => _filter = _ChatFilter.all),
                ),
                RaisedFilterChip(
                  label: 'No leídos',
                  selected: _filter == _ChatFilter.unread,
                  onTap: () => setState(() => _filter = _ChatFilter.unread),
                ),
                RaisedFilterChip(
                  label: 'Relé',
                  selected: _filter == _ChatFilter.relay,
                  onTap: () => setState(() => _filter = _ChatFilter.relay),
                ),
              ],
            ),
          ),
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
            child: session.contacts.isEmpty
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
                : filterEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _filter == _ChatFilter.unread
                            ? 'Los no leídos todavía no se cuentan en la lista. '
                                  'Usá Todos.'
                            : _filter == _ChatFilter.relay
                            ? 'El filtro Relé llega cuando la lista sepa qué '
                                  'chat fue por relé. Usá Todos.'
                            : 'Ningún chat coincide con la búsqueda.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: EncrypchatColors.muted,
                          height: 1.4,
                        ),
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
                      final selected = widget.selectedToken == c.token;
                      final online =
                          session.hasMessaging && session.messaging.nodeRunning;
                      return ListTile(
                        selected: selected,
                        selectedTileColor: EncrypchatColors.bubbleOut,
                        tileColor: EncrypchatColors.paper,
                        leading: StatusAvatar(
                          label: c.label,
                          blocked: blocked,
                          online: online && !blocked,
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
                        onTap: () => _open(c),
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
