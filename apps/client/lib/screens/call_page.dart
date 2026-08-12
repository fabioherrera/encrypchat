import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/call_signal.dart';
import '../services/call_service.dart';
import '../theme/encrypchat_colors.dart';

class CallPage extends StatefulWidget {
  const CallPage({super.key, required this.calls});

  final CallService calls;

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  @override
  void initState() {
    super.initState();
    widget.calls.addListener(_onChange);
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    if (widget.calls.phase == CallPhase.idle) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    widget.calls.removeListener(_onChange);
    super.dispose();
  }

  String get _status {
    return switch (widget.calls.phase) {
      CallPhase.outgoing => 'Llamando…',
      CallPhase.incoming => 'Entrante…',
      CallPhase.connecting => 'Conectando…',
      CallPhase.active => 'En llamada',
      CallPhase.ended => widget.calls.lastError ?? 'Finalizada',
      CallPhase.idle => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final calls = widget.calls;
    final video = calls.media == CallMediaMode.av;
    final peerLabel = calls.peer?.label ?? 'Peer';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await calls.hangup();
      },
      child: Scaffold(
        backgroundColor: EncrypchatColors.navy,
        body: SafeArea(
          child: Stack(
            children: [
              if (video)
                Positioned.fill(
                  child: RTCVideoView(
                    calls.remoteRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                )
              else
                Positioned.fill(
                  child: ColoredBox(
                    color: EncrypchatColors.navy,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 48,
                            backgroundColor: EncrypchatColors.paper,
                            foregroundColor: EncrypchatColors.navy,
                            child: Text(
                              peerLabel.isEmpty
                                  ? '?'
                                  : peerLabel[0].toUpperCase(),
                              style: const TextStyle(fontSize: 36),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            peerLabel,
                            style: const TextStyle(
                              color: EncrypchatColors.paper,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _status,
                            style: const TextStyle(
                              color: EncrypchatColors.bubbleOut,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (video)
                Positioned(
                  right: 16,
                  top: 16,
                  width: 120,
                  height: 160,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: RTCVideoView(
                      calls.localRenderer,
                      mirror: true,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              if (video)
                Positioned(
                  left: 16,
                  top: 16,
                  child: Text(
                    '$peerLabel · $_status',
                    style: const TextStyle(
                      color: EncrypchatColors.paper,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 32,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _RoundBtn(
                      icon: calls.muted ? Icons.mic_off : Icons.mic,
                      label: calls.muted ? 'Unmute' : 'Mute',
                      onTap: calls.toggleMute,
                    ),
                    if (video)
                      _RoundBtn(
                        icon: calls.cameraOff
                            ? Icons.videocam_off
                            : Icons.videocam,
                        label: 'Video',
                        onTap: calls.toggleCamera,
                      ),
                    _RoundBtn(
                      icon: Icons.call_end,
                      label: 'Colgar',
                      color: const Color(0xFFC62828),
                      onTap: () => calls.hangup(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color ?? EncrypchatColors.paper.withValues(alpha: 0.15),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Icon(icon, color: EncrypchatColors.paper, size: 28),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: EncrypchatColors.paper, fontSize: 12),
        ),
      ],
    );
  }
}
