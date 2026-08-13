import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
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
import '../widgets/raised_controls.dart';
import 'safety_actions.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.session,
    required this.peer,
    this.embedded = false,
  });

  final SessionController session;
  final Contact peer;

  /// Desktop split: no back button, header sits next to the list.
  final bool embedded;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  /// The list is rendered bottom-up (`reverse: true`), so scroll offset 0 is the
  /// newest message and the offsets grow towards the oldest. That is what makes
  /// paging safe: an older page is laid out on the far side of the viewport, at
  /// offsets nobody is looking at, so inserting it cannot move the reading
  /// position. Anchoring a forward list by hand would have to guess the height
  /// of items that have not been built yet.
  static const _atBottom = 32.0;

  /// How close to the oldest end the user gets before the next page is asked
  /// for — about a screenful, so the page is there before the scroll reaches it.
  static const _prefetchExtent = 600.0;

  final _controller = TextEditingController();
  final _scroll = ScrollController();

  /// What is on screen: the window up to [_anchorId], oldest-first.
  List<ChatMessage> _visible = const [];

  /// The newest message the user has been shown. While they are reading back
  /// this stays put, so a message arriving does not appear under their thumb
  /// and shift what they were reading.
  String? _anchorId;

  /// Messages held back behind [_anchorId], counted for the pill.
  int _pendingNew = 0;

  /// Whether the newest message is on screen. While it is, everything that
  /// arrives is shown immediately and the view stays at the bottom on its own.
  bool _pinnedToNewest = true;

  bool _loadingOlder = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    widget.session.messaging.addListener(_reload);
    _scroll.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    widget.session.messaging.removeListener(_reload);
    // Whatever the user scrolled back through stops being held in memory when
    // the conversation is no longer on screen.
    widget.session.messaging.releaseWindow(widget.peer.token);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final window = await widget.session.messaging.messagesFor(
      widget.peer.token,
    );
    if (!mounted) return;
    setState(() => _applyWindow(window));
    WidgetsBinding.instance.addPostFrameCallback((_) => _fillViewport());
  }

  /// Decides how much of the loaded window to show.
  ///
  /// Pinned to the newest message, that is all of it. Reading back, it is
  /// everything up to the anchor: the messages behind it exist, are stored, and
  /// are announced by the pill — they are just not spliced in underneath
  /// somebody who is reading something else.
  void _applyWindow(List<ChatMessage> window) {
    if (window.isEmpty) {
      _visible = const [];
      _anchorId = null;
      _pendingNew = 0;
      return;
    }
    if (_pinnedToNewest) {
      _visible = window;
      _anchorId = window.last.id;
      _pendingNew = 0;
      return;
    }
    final anchor = _anchorId;
    final at = anchor == null ? -1 : window.indexWhere((m) => m.id == anchor);
    if (at < 0) {
      // The anchor is no longer in the window — the conversation was deleted
      // and refilled, or it aged out of a window that kept receiving. Showing a
      // prefix of a thread it is not part of would be worse than resynchronising.
      _visible = window;
      _anchorId = window.last.id;
      _pendingNew = 0;
      return;
    }
    _visible = window.sublist(0, at + 1);
    _pendingNew = window.length - 1 - at;
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pinned = _scroll.position.pixels <= _atBottom;
    if (pinned != _pinnedToNewest) {
      setState(() => _pinnedToNewest = pinned);
      // Coming back to the bottom is the moment the held-back messages belong
      // on screen.
      if (pinned) unawaited(_reload());
    }
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - _prefetchExtent) {
      unawaited(_loadOlder());
    }
  }

  /// A first page that does not fill the window leaves nothing to scroll, and
  /// therefore no way to ask for the page before it. Desktop windows are tall
  /// enough for this to be the ordinary case, not an edge one.
  void _fillViewport() {
    if (!mounted || !_scroll.hasClients) return;
    if (_scroll.position.maxScrollExtent > 0) return;
    unawaited(_loadOlder());
  }

  Future<void> _loadOlder() async {
    final messaging = widget.session.messaging;
    if (_loadingOlder || !messaging.hasOlderMessages(widget.peer.token)) return;
    setState(() => _loadingOlder = true);
    try {
      final added = await messaging.loadOlderMessages(widget.peer.token);
      if (!mounted) return;
      if (added > 0) {
        final window = await messaging.messagesFor(widget.peer.token);
        if (!mounted) return;
        setState(() => _applyWindow(window));
        WidgetsBinding.instance.addPostFrameCallback((_) => _fillViewport());
      }
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _goToNewest() async {
    setState(() => _pinnedToNewest = true);
    await _reload();
    if (!mounted || !_scroll.hasClients) return;
    _scroll.jumpTo(0);
  }

  Future<void> _send() async {
    final text = _controller.text;
    if (text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.session.messaging.sendText(peer: widget.peer, text: text);
      _controller.clear();
      // Writing is asking to be at the end of the conversation.
      await _goToNewest();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    if (_sending) return;
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: source,
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
      await _goToNewest();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
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
        automaticallyImplyLeading: !widget.embedded,
        titleSpacing: 0,
        title: Row(
          children: [
            StatusAvatar(
              label: widget.peer.label,
              radius: 18,
              blocked: blocked,
              online: online && !blocked,
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
          RaisedCircleButton(
            tooltip: 'Videollamada',
            onPressed: online && !blocked
                ? () => _startCall(CallMediaMode.av)
                : null,
            icon: Icons.videocam,
            iconColor: EncrypchatColors.navyMid,
          ),
          const SizedBox(width: 8),
          RaisedCircleButton(
            tooltip: 'Llamada de audio',
            onPressed: online && !blocked
                ? () => _startCall(CallMediaMode.audio)
                : null,
            icon: Icons.call,
            iconColor: EncrypchatColors.p2p,
          ),
          PopupMenuButton<String>(
            tooltip: 'Más acciones',
            padding: EdgeInsets.zero,
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
            icon: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: EncrypchatColors.paper,
                boxShadow: EncrypchatColors.raisedShadow,
              ),
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  Icons.more_horiz,
                  color: EncrypchatColors.muted,
                  size: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
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
                Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: EncrypchatColors.muted,
                ),
                SizedBox(width: 6),
                Text(
                  'Cifrado E2EE · en este dispositivo',
                  style: TextStyle(fontSize: 12, color: EncrypchatColors.muted),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                ListView.builder(
                  controller: _scroll,
                  // Newest first in list order, drawn from the bottom up.
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: _visible.length + (_showOlderRow ? 1 : 0),
                  itemBuilder: (context, index) {
                    // Past the last message is the oldest end of the list.
                    if (index == _visible.length) return _olderRow();
                    return _bubble(_visible[_visible.length - 1 - index]);
                  },
                ),
                if (_pendingNew > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12,
                    child: Center(child: _newMessagesPill()),
                  ),
              ],
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

  bool get _showOlderRow =>
      _loadingOlder ||
      widget.session.messaging.hasOlderMessages(widget.peer.token);

  /// The oldest end of the list. The button is not decoration: scrolling is not
  /// the only way people reach the top of a list — a keyboard on desktop and a
  /// screen reader both need something to activate.
  Widget _olderRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: _loadingOlder
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: _loadOlder,
                child: const Text('Cargar mensajes anteriores'),
              ),
      ),
    );
  }

  /// What arrived while the user was reading further back. It is deliberately
  /// an invitation and not a jump: the conversation moving on its own is the
  /// behaviour this replaces.
  Widget _newMessagesPill() {
    return Material(
      color: EncrypchatColors.navy,
      shape: const StadiumBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: _goToNewest,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _pendingNew == 1
                    ? '1 mensaje nuevo'
                    : '$_pendingNew mensajes nuevos',
                style: const TextStyle(
                  color: EncrypchatColors.paper,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.arrow_downward,
                size: 16,
                color: EncrypchatColors.paper,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bubble(ChatMessage m) {
    final mine = m.direction == MessageDirection.outbound;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: mine ? EncrypchatColors.bubbleOut : EncrypchatColors.paper,
          borderRadius: BorderRadius.circular(14),
          boxShadow: EncrypchatColors.raisedShadow,
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
                  _StatusTick(status: m.status),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer() {
    final mobileCamera = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: EncrypchatColors.paper,
        borderRadius: BorderRadius.circular(28),
        boxShadow: EncrypchatColors.raisedShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        child: Row(
          children: [
            RaisedCircleButton(
              tooltip: 'Adjuntar foto',
              onPressed: _sending
                  ? null
                  : () => _pickAndSendImage(ImageSource.gallery),
              icon: Icons.attach_file,
              iconColor: EncrypchatColors.navy,
              size: 38,
            ),
            if (mobileCamera) ...[
              const SizedBox(width: 4),
              RaisedCircleButton(
                tooltip: 'Cámara',
                onPressed: _sending
                    ? null
                    : () => _pickAndSendImage(ImageSource.camera),
                icon: Icons.photo_camera_outlined,
                iconColor: EncrypchatColors.iconContacts,
                size: 38,
              ),
            ],
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: 'Mensaje',
                  filled: true,
                  fillColor: EncrypchatColors.paper,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),
            RaisedCircleButton(
              tooltip: 'Enviar',
              onPressed: _sending ? null : _send,
              icon: Icons.send,
              background: EncrypchatColors.navy,
              iconColor: EncrypchatColors.paper,
              size: 44,
              iconSize: 20,
            ),
          ],
        ),
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

/// The mark under an outbound message, and the words that go with it.
///
/// The words are the point. There is exactly one delivery confirmation in this
/// app — the peer's own ACK over P2P — and the relay does not produce one: a
/// mailbox over quota answers an enqueue exactly like an acceptance, because
/// that difference told anyone holding a token whether its owner had come
/// online to empty it. So the most a sender ever learns from the relay is that
/// it took the blob, and the mark says that and stops. A `cloud_done` tick,
/// which is what this used to draw, reads as "arrived" — the app claiming the
/// one bit it deliberately cannot have.
class _StatusTick extends StatelessWidget {
  const _StatusTick({required this.status});

  final MessageStatus status;

  static const _errorRed = Color(0xFFB42318);

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (status) {
      MessageStatus.error => (
        Icons.error_outline,
        _errorRed,
        'No se pudo enviar',
      ),
      MessageStatus.sending => (
        Icons.schedule,
        EncrypchatColors.navy,
        'Enviando',
      ),
      MessageStatus.viaRelay => (
        Icons.cloud_upload_outlined,
        EncrypchatColors.relay,
        'Entregado al relay, cifrado. No hay confirmación de entrega: el relay '
            'no dice si le llegó ni si sigue esperándolo.',
      ),
      MessageStatus.delivered => (
        Icons.done_all,
        EncrypchatColors.navy,
        'Entregado a su dispositivo por P2P',
      ),
      // Pre-F5 rows, from a schema that only recorded that the send returned.
      MessageStatus.sent => (Icons.done_all, EncrypchatColors.navy, 'Enviado'),
    };
    return Tooltip(
      // Hover on desktop, long press on touch, and — what the bare icon never
      // had — a label for a screen reader on all four platforms.
      message: label,
      child: Icon(icon, size: 14, color: color),
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
        // The drop summary grows with the number of distinct reasons, which on a
        // short phone screen is enough to overflow the dialog.
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Solo ciphertext + token + TTL. Sin plaintext. '
              'Ejemplo: http://192.168.1.10:8787',
              style: TextStyle(fontSize: 13, color: EncrypchatColors.muted),
            ),
            const SizedBox(height: 8),
            // The relay's silence is a property, not a gap, and this is the one
            // surface with room to say why: it accepts a blob the same way
            // whether or not it has space for that mailbox, because answering
            // differently told anybody holding a token when its owner was
            // online. The cost lands on the sender, so the sender is told.
            const Text(
              'El relay no confirma entregas: acepta el mensaje igual aunque no '
              'le quede sitio para ese buzón, porque responder distinto '
              'delataría si esa persona se conectó. La única confirmación real '
              'es P2P, cuando su dispositivo acusa recibo.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: EncrypchatColors.muted,
              ),
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
            // Repeated here because this dialog is where the banner sends you,
            // and arriving without the reason turns it into a guess.
            RelayPullFaultNotice(session: session, compact: true),
            _InboundDropsSummary(messaging: session.messaging),
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

/// Per-reason tally of what arrived and this device refused, by either route.
/// Lives in the relay dialog so the banner can stay to a single line.
class _InboundDropsSummary extends StatelessWidget {
  const _InboundDropsSummary({required this.messaging});

  final MessagingService messaging;

  @override
  Widget build(BuildContext context) {
    final drops = messaging.inboundDrops;
    if (drops.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Descartados en esta sesión',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: EncrypchatColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          for (final entry in drops.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${entry.value}× ${entry.key.title}',
                style: TextStyle(
                  fontSize: 12,
                  color: entry.key.isHostile
                      ? const Color(0xFF8C1C13)
                      : EncrypchatColors.muted,
                  fontWeight: entry.key.isHostile
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            ),
        ],
      ),
    );
  }
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

/// Shown while the relay cannot be drained for a reason that will not pass on
/// its own — a protocol mismatch or a proof the relay keeps refusing.
///
/// Tapping it opens the relay dialog, which is where the only two answers live:
/// change the address or clear it. Offline never lands here.
class RelayPullFaultNotice extends StatelessWidget {
  const RelayPullFaultNotice({
    super.key,
    required this.session,
    this.compact = false,
  });

  final SessionController session;
  final bool compact;

  static const _red = Color(0xFF8C1C13);
  static const _redBg = Color(0xFFFDECEA);

  @override
  Widget build(BuildContext context) {
    final fault = session.hasMessaging
        ? session.messaging.relayPullFault
        : null;
    if (fault == null) return const SizedBox.shrink();
    return Material(
      color: _redBg,
      child: InkWell(
        // Inside the relay dialog there is nowhere left to go.
        onTap: compact ? null : () => showRelayDialog(context, session),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 16,
            vertical: compact ? 8 : 10,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.cloud_off, size: 16, color: _red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'No se puede recoger del relay. $fault',
                  style: TextStyle(
                    fontSize: compact ? 12 : 12.5,
                    height: 1.35,
                    color: _red,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Banner for payloads that arrived and never became messages, by either route.
///
/// A sender that could not be authenticated is shown apart from the rest: the
/// other reasons are incidents (old client, truncated, stale, a stranger who
/// hit a ceiling), that one is an attempt to impersonate a contact, and it is
/// the only one worth alarming about. Neither case ever names a sender, because
/// a blob that fails the binding has no trustworthy identity to name.
class InboundDropNotice extends StatelessWidget {
  const InboundDropNotice({super.key, required this.messaging});

  final MessagingService messaging;

  static const _amber = Color(0xFF8A5A00);
  static const _amberBg = Color(0xFFFFF4E5);
  static const _alert = Color(0xFF8C1C13);
  static const _alertBg = Color(0xFFFCEBEA);

  @override
  Widget build(BuildContext context) {
    // The hostile reason wins over recency: a forged blob must not be pushed
    // out of the banner by a later duplicate.
    final reason = messaging.sawForgedSender
        ? InboundDropReason.forged
        : messaging.lastDrop;
    if (reason == null) return const SizedBox.shrink();
    final hostile = reason.isHostile;
    final total = messaging.dropCount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: hostile ? _alertBg : _amberBg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hostile ? Icons.gpp_maybe : Icons.info_outline,
            size: 16,
            color: hostile ? _alert : _amber,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  total > 1
                      ? '${reason.title} · $total mensajes descartados'
                      : reason.title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: hostile ? _alert : _amber,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reason.detail,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: hostile ? _alert : _amber,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Entendido',
            visualDensity: VisualDensity.compact,
            onPressed: messaging.clearDrops,
            icon: Icon(Icons.close, size: 16, color: hostile ? _alert : _amber),
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
