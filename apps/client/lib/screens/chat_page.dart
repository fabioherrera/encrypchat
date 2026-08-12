import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/call_signal.dart';
import '../core/media_picker.dart';
import '../models/chat_message.dart';
import '../models/contact.dart';
import '../services/messaging_service.dart';
import '../services/relay_client.dart';
import '../services/session_controller.dart';
import '../theme/encrypchat_colors.dart';
import 'safety_actions.dart';

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

  Future<void> _pickAndSendImage() async {
    if (_sending) return;
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 75,
    );
    if (x == null) return;
    setState(() => _sending = true);
    try {
      final bytes = await x.readAsBytes();
      final mime = x.mimeType ?? 'image/jpeg';
      final name = x.name;
      await widget.session.messaging.sendMedia(
        peer: widget.peer,
        bytes: bytes,
        mime: mime,
        name: name,
      );
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      // The picker handed us a plaintext copy in the app cache and nothing else
      // deletes it. It is useless whether the send worked or not: the bytes it
      // carried are already sealed under `media/`.
      await purgePickerTemps(justUsed: x.path);
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _startCall(CallMediaMode media) async {
    final calls = widget.session.calls;
    if (calls == null) return;
    try {
      await calls.startCall(peer: widget.peer, media: media);
      // CallOverlayHost / CallPage opened via session.calls listener.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<void> _block() async {
    await confirmBlock(
      context,
      widget.session,
      token: widget.peer.token,
      label: widget.peer.label,
    );
    if (mounted) setState(() {});
  }

  Future<void> _unblock() async {
    await confirmUnblock(
      context,
      widget.session,
      token: widget.peer.token,
      label: widget.peer.label,
    );
    if (mounted) setState(() {});
  }

  Future<void> _report() async {
    await showReportDialog(
      context,
      widget.session,
      token: widget.peer.token,
      label: widget.peer.label,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final online = widget.session.messaging.nodeRunning;
    final blocked = widget.session.isBlocked(widget.peer.token);

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
                    blocked
                        ? 'Bloqueado'
                        : online
                        ? 'P2P · en línea'
                        : 'P2P · nodo detenido',
                    style: TextStyle(
                      fontSize: 12,
                      color: blocked || !online
                          ? EncrypchatColors.offline
                          : EncrypchatColors.p2p,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Llamada de audio',
            onPressed: online && !blocked
                ? () => _startCall(CallMediaMode.audio)
                : null,
            icon: const Icon(Icons.call),
          ),
          IconButton(
            tooltip: 'Videollamada',
            onPressed: online && !blocked
                ? () => _startCall(CallMediaMode.av)
                : null,
            icon: const Icon(Icons.videocam),
          ),
          PopupMenuButton<String>(
            tooltip: 'Más acciones',
            onSelected: (value) async {
              switch (value) {
                case 'block':
                  await _block();
                case 'unblock':
                  await _unblock();
                case 'report':
                  await _report();
              }
            },
            itemBuilder: (context) => [
              if (blocked)
                const PopupMenuItem(
                  value: 'unblock',
                  child: Text('Desbloquear contacto'),
                )
              else
                const PopupMenuItem(
                  value: 'block',
                  child: Text('Bloquear contacto'),
                ),
              const PopupMenuItem(
                value: 'report',
                child: Text('Reportar abuso'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (blocked)
            Material(
              color: EncrypchatColors.bubbleOut,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.block,
                      size: 18,
                      color: EncrypchatColors.ink,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Contacto bloqueado. Sus mensajes, fotos y llamadas se '
                        'descartan en este dispositivo.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: EncrypchatColors.ink,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _unblock,
                      child: const Text('Desbloquear'),
                    ),
                  ],
                ),
              ),
            ),
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
                        if (m.isMedia)
                          _SealedImage(
                            key: ValueKey(m.id),
                            messaging: widget.session.messaging,
                            message: m,
                          )
                        else
                          Text(
                            m.plaintext ?? '',
                            style: const TextStyle(
                              color: EncrypchatColors.ink,
                              height: 1.35,
                            ),
                          ),
                        if (m.isMedia &&
                            m.plaintext != null &&
                            m.plaintext!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            m.plaintext!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: EncrypchatColors.muted,
                            ),
                          ),
                        ],
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
                                    : m.status == MessageStatus.viaRelay
                                    ? Icons.cloud_done_outlined
                                    : Icons.done_all,
                                size: 14,
                                color: m.status == MessageStatus.error
                                    ? const Color(0xFFB42318)
                                    : m.status == MessageStatus.viaRelay
                                    ? EncrypchatColors.relay
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
              child: blocked
                  ? const Text(
                      'No podés escribirle mientras esté bloqueado.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: EncrypchatColors.muted,
                      ),
                    )
                  : _composer(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    return Row(
      children: [
        IconButton(
          tooltip: 'Adjuntar foto',
          onPressed: _sending ? null : _pickAndSendImage,
          icon: const Icon(Icons.image_outlined, color: EncrypchatColors.navy),
        ),
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
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Reads the sealed attachment on demand: bytes live in this widget's state
/// while the bubble is on screen, never in the message cache.
class _SealedImage extends StatefulWidget {
  const _SealedImage({
    super.key,
    required this.messaging,
    required this.message,
  });

  final MessagingService messaging;
  final ChatMessage message;

  @override
  State<_SealedImage> createState() => _SealedImageState();
}

class _SealedImageState extends State<_SealedImage> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.messaging.mediaBytesFor(widget.message);
      if (!mounted) return;
      setState(() => _bytes = bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) {
      return SizedBox(
        width: 220,
        height: 120,
        child: Center(
          child: _failed
              ? const Text(
                  '📎 adjunto cifrado',
                  style: TextStyle(color: EncrypchatColors.muted),
                )
              : const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.memory(
        bytes,
        width: 220,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Text(
          '«imagen»',
          style: TextStyle(color: EncrypchatColors.muted),
        ),
      ),
    );
  }
}

Future<void> showRelayDialog(
  BuildContext context,
  SessionController session,
) async {
  final controller = TextEditingController(
    text: session.messaging.relayBaseUrl ?? 'http://127.0.0.1:8787',
  );
  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Relay ciego'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Solo ciphertext + token + TTL. Sin plaintext. '
              'Ejemplo: http://192.168.1.10:8787',
              style: TextStyle(fontSize: 13, color: EncrypchatColors.muted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'URL base del relay',
                hintText: 'http://127.0.0.1:8787',
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                if (RelayClient.isSecureUrl(value.text) ||
                    value.text.trim().isEmpty) {
                  return const SizedBox.shrink();
                }
                return const RelayInsecureNotice(compact: true);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await session.messaging.setRelayBaseUrl(null);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Quitar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          FilledButton(
            onPressed: () async {
              await session.messaging.setRelayBaseUrl(controller.text);
              unawaited(session.messaging.pullFromRelay());
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Guardar'),
          ),
        ],
      );
    },
  ).whenComplete(controller.dispose);
}

/// Shown while the relay is configured without TLS. Content stays E2EE; the
/// routing metadata does not.
class RelayInsecureNotice extends StatelessWidget {
  const RelayInsecureNotice({super.key, this.compact = false});

  final bool compact;

  static const _amber = Color(0xFF8A5A00);
  static const _amberBg = Color(0xFFFFF4E5);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 16,
        vertical: compact ? 8 : 10,
      ),
      color: _amberBg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_open, size: 16, color: _amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Relay sin TLS (http://). Los mensajes van cifrados de extremo a '
              'extremo, pero tu token de destino, tu clave pública y el proof '
              'viajan en claro: cualquiera en la red puede ver con quién hablás '
              'y cuándo. Usá https fuera de una LAN de confianza.',
              style: TextStyle(
                fontSize: compact ? 12 : 12.5,
                height: 1.35,
                color: _amber,
              ),
            ),
          ),
        ],
      ),
    );
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
  ).whenComplete(() {
    host.dispose();
    port.dispose();
  });
}
