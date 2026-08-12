import 'package:flutter/material.dart';

import '../core/call_signal.dart';
import '../services/call_service.dart';
import '../services/session_controller.dart';
import '../theme/encrypchat_colors.dart';
import 'call_page.dart';

/// Incoming call banner + routes to [CallPage].
class CallOverlayHost extends StatefulWidget {
  const CallOverlayHost({
    super.key,
    required this.session,
    required this.child,
  });

  final SessionController session;
  final Widget child;

  @override
  State<CallOverlayHost> createState() => _CallOverlayHostState();
}

class _CallOverlayHostState extends State<CallOverlayHost> {
  bool _pushedCall = false;

  @override
  void initState() {
    super.initState();
    widget.session.calls?.addListener(_onCalls);
  }

  @override
  void didUpdateWidget(covariant CallOverlayHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.calls != widget.session.calls) {
      oldWidget.session.calls?.removeListener(_onCalls);
      widget.session.calls?.addListener(_onCalls);
    }
  }

  void _onCalls() {
    if (!mounted) return;
    setState(() {});
    final calls = widget.session.calls;
    if (calls == null) return;

    final activeUi =
        calls.phase == CallPhase.outgoing ||
        calls.phase == CallPhase.connecting ||
        calls.phase == CallPhase.active;
    if (activeUi && !_pushedCall) {
      _pushedCall = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => CallPage(calls: calls),
              ),
            )
            .whenComplete(() {
              _pushedCall = false;
            });
      });
    }
  }

  @override
  void dispose() {
    widget.session.calls?.removeListener(_onCalls);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final calls = widget.session.calls;
    final incoming = calls != null && calls.phase == CallPhase.incoming;

    return Stack(
      children: [
        widget.child,
        if (incoming)
          Positioned(
            left: 12,
            right: 12,
            top: MediaQuery.paddingOf(context).top + 8,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(16),
              color: EncrypchatColors.paper,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Llamada ${calls.media == CallMediaMode.av ? 'video' : 'audio'}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: EncrypchatColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      calls.peer?.label ?? 'Contacto',
                      style: const TextStyle(color: EncrypchatColors.muted),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                            ),
                            onPressed: () async {
                              try {
                                await calls.acceptIncoming();
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(
                                    context,
                                  ).showSnackBar(SnackBar(content: Text('$e')));
                                }
                              }
                            },
                            child: const Text('Contestar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => calls.rejectIncoming(),
                            child: const Text('Rechazar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
