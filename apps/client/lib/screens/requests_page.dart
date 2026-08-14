import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_message.dart';
import '../models/message_request.dart';
import '../services/messaging_service.dart';
import '../services/session_controller.dart';
import '../theme/encrypchat_colors.dart';

/// Messages from identities that are not contacts.
///
/// Before this screen they were stored and shown nowhere (F-6): the chat list
/// walks contacts, so a stranger's message could not be read, deleted, or
/// answered with a block. The policy the screen makes visible is deliberately
/// narrow — text only, a few messages, no ring — and it is stated here rather
/// than left for the user to infer.
class RequestsPage extends StatefulWidget {
  const RequestsPage({super.key, required this.session});

  final SessionController session;

  @override
  State<RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageState extends State<RequestsPage> {
  /// A pushed route does not rebuild with the shell, and a request can arrive
  /// (or be resolved) while this screen is open.
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final requests = session.requests;

    return Scaffold(
      backgroundColor: EncrypchatColors.canvas,
      appBar: AppBar(title: const Text('Solicitudes')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PolicyHeader(displaced: session.messaging.displacedRequests),
          Expanded(
            child: requests.isEmpty
                ? const _EmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: requests.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _RequestCard(
                      session: session,
                      request: requests[index],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PolicyHeader extends StatelessWidget {
  const _PolicyHeader({required this.displaced});

  /// Requests pushed out by newer ones since the app started. Shown only when
  /// it happened: the inbox rolling over is normal, but a flood of throwaway
  /// identities looks exactly like this and the user should be able to see it.
  final int displaced;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: EncrypchatColors.paper,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Alguien que no tenés agendado puede escribirte, porque tu token '
            'está hecho para compartirse. Hasta que lo aceptes: no suena, no '
            'puede mandarte adjuntos ni llamarte, y solo entran '
            '${MessagingService.maxRequestMessagesPerPeer} mensajes cortos '
            'suyos. Se guardan las ${MessagingService.maxPendingRequests} '
            'solicitudes más recientes: si llegan más, se borra la más vieja '
            'sin responder.',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: EncrypchatColors.muted,
            ),
          ),
          if (displaced > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                displaced == 1
                    ? 'Desde que abriste la app se borró 1 solicitud vieja para '
                          'hacerle lugar a otra más nueva.'
                    : 'Desde que abriste la app se borraron $displaced '
                          'solicitudes viejas para hacerle lugar a otras más '
                          'nuevas.',
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: EncrypchatColors.relay,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mark_email_unread_outlined,
              size: 56,
              color: EncrypchatColors.navy.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 16),
            const Text(
              'Sin solicitudes',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: EncrypchatColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cuando alguien te agregue y haya ruta (misma Wi‑Fi o relay), '
              'aparece acá para que lo autorices. Agendar en el otro '
              'dispositivo no alcanza si el aviso no llega.',
              textAlign: TextAlign.center,
              style: TextStyle(color: EncrypchatColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.session, required this.request});

  final SessionController session;
  final MessageRequest request;

  Future<void> _accept(BuildContext context) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(request: request),
    );
    if (name == null) return;
    try {
      await session.acceptRequest(
        request,
        displayName: name.trim().isEmpty ? null : name.trim(),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aceptado: ya está en Chats')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo aceptar: $e')));
      }
    }
  }

  Future<void> _discard(BuildContext context, {required bool block}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(block ? 'Bloquear y descartar' : 'Descartar solicitud'),
        content: Text(
          block
              ? 'Se borran sus mensajes de este dispositivo y no vas a recibir '
                    'nada más de este token: ni mensajes, ni adjuntos, ni '
                    'llamadas. No se le avisa.'
              : 'Se borran sus mensajes de este dispositivo. Si vuelve a '
                    'escribir, aparecerá otra vez acá.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(block ? 'Bloquear' : 'Descartar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await session.discardRequest(request.peerToken, alsoBlock: block);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: EncrypchatColors.paper,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  request.shortToken,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: EncrypchatColors.ink,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copiar token',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy, size: 16),
                color: EncrypchatColors.muted,
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: request.peerToken),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Token copiado')),
                    );
                  }
                },
              ),
            ],
          ),
          Text(
            '${request.messageCount} '
            '${request.messageCount == 1 ? 'mensaje' : 'mensajes'} · '
            '${request.viaRelay ? 'por relay' : 'P2P'}',
            style: const TextStyle(fontSize: 12, color: EncrypchatColors.muted),
          ),
          const SizedBox(height: 10),
          _Preview(session: session, token: request.peerToken),
          if (!request.canAccept)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Escribió por P2P, y una trama P2P no trae su clave pública: '
                'para responderle necesitás su tarjeta de contacto (token + QR) '
                'e importarla desde Contactos.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: EncrypchatColors.relay,
                ),
              ),
            ),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            children: [
              TextButton(
                onPressed: () => _discard(context, block: true),
                child: const Text('Bloquear'),
              ),
              TextButton(
                onPressed: () => _discard(context, block: false),
                child: const Text('Descartar'),
              ),
              FilledButton(
                onPressed: request.canAccept ? () => _accept(context) : null,
                child: const Text('Aceptar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// What they wrote. Read through the same path as any conversation, so the
/// bodies are opened from their sealed form and never shown raw.
class _Preview extends StatelessWidget {
  const _Preview({required this.session, required this.token});

  final SessionController session;
  final String token;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ChatMessage>>(
      future: session.messaging.messagesFor(token),
      builder: (context, snapshot) {
        final messages = snapshot.data;
        if (messages == null) {
          return const SizedBox(
            height: 18,
            child: Text(
              'Abriendo…',
              style: TextStyle(fontSize: 12, color: EncrypchatColors.muted),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final m in messages)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: EncrypchatColors.canvas,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    m.plaintext ?? '«no se pudo abrir»',
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: EncrypchatColors.ink,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.request});

  final MessageRequest request;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Aceptar contacto'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Se guarda ${widget.request.shortToken} como contacto: desde ahora '
            'podrá mandarte adjuntos y llamarte, y vos podrás escribirle.',
            style: const TextStyle(fontSize: 13, color: EncrypchatColors.muted),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Nombre (opcional)',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}
