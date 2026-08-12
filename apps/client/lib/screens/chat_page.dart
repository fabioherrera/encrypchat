import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_message.dart';
import '../models/contact.dart';
import '../services/session_controller.dart';
import '../theme/encrypchat_colors.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.session,
    required this.peer,
  });

  final SessionController session;
  final Contact peer;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  List<ChatMessage> _messages = const [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    widget.session.messaging.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.session.messaging.removeListener(_reload);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final list = await widget.session.messaging.messagesFor(widget.peer.token);
    if (!mounted) return;
    setState(() => _messages = list);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text;
    if (text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.session.messaging.sendText(peer: widget.peer, text: text);
      _controller.clear();
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = widget.session.messaging.nodeRunning;

    return Scaffold(
      backgroundColor: EncrypchatColors.canvas,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: EncrypchatColors.navy,
              foregroundColor: EncrypchatColors.paper,
              child: Text(
                widget.peer.label.isEmpty
                    ? '?'
                    : widget.peer.label[0].toUpperCase(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.peer.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: EncrypchatColors.ink,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    online ? 'P2P · en línea' : 'P2P · nodo detenido',
                    style: TextStyle(
                      fontSize: 12,
                      color: online ? EncrypchatColors.p2p : EncrypchatColors.offline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 14, color: EncrypchatColors.muted),
                SizedBox(width: 6),
                Text(
                  'Cifrado E2EE · en este dispositivo',
                  style: TextStyle(fontSize: 12, color: EncrypchatColors.muted),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final m = _messages[index];
                final mine = m.direction == MessageDirection.outbound;
                return Align(
                  alignment:
                      mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                    ),
                    decoration: BoxDecoration(
                      color: mine
                          ? EncrypchatColors.bubbleOut
                          : EncrypchatColors.paper,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          m.plaintext ?? '',
                          style: const TextStyle(
                            color: EncrypchatColors.ink,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatTime(m.createdAt),
                              style: const TextStyle(
                                fontSize: 11,
                                color: EncrypchatColors.muted,
                              ),
                            ),
                            if (mine) ...[
                              const SizedBox(width: 4),
                              Icon(
                                m.status == MessageStatus.error
                                    ? Icons.error_outline
                                    : m.status == MessageStatus.sending
                                        ? Icons.schedule
                                        : Icons.done_all,
                                size: 14,
                                color: m.status == MessageStatus.error
                                    ? const Color(0xFFB42318)
                                    : EncrypchatColors.navy,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Mensaje',
                        filled: true,
                        fillColor: EncrypchatColors.paper,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: EncrypchatColors.navy,
                    shape: const CircleBorder(),
                    child: IconButton(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: EncrypchatColors.paper,
                              ),
                            )
                          : const Icon(Icons.send, color: EncrypchatColors.paper),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Dialog helpers used from chats list.
Future<void> showConnectPeerDialog(
  BuildContext context,
  SessionController session,
) async {
  final host = TextEditingController();
  final port = TextEditingController();
  final addr = session.messaging.listenAddr;
  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Conectar peer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (addr != null) ...[
              const Text(
                'Tu dirección (compartila):',
                style: TextStyle(fontSize: 12, color: EncrypchatColors.muted),
              ),
              const SizedBox(height: 4),
              SelectableText(
                addr,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: addr));
                },
                child: const Text('Copiar multiaddr'),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: host,
              decoration: const InputDecoration(
                labelText: 'IP del peer',
                hintText: '192.168.1.20',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: port,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Puerto',
                hintText: '41234',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          FilledButton(
            onPressed: () async {
              final p = int.tryParse(port.text.trim());
              if (host.text.trim().isEmpty || p == null) return;
              try {
                await session.messaging.connectHostPort(host.text, p);
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('No se pudo conectar: $e')),
                  );
                }
              }
            },
            child: const Text('Conectar'),
          ),
        ],
      );
    },
  );
}
