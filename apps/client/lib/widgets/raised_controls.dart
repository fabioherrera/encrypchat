import 'package:flutter/material.dart';

import '../theme/encrypchat_colors.dart';

/// Soft extruded control — the 3D language of the desktop chat mockup.
///
/// Depth comes from a top highlight and a drop shadow, not from a second
/// colour palette. Navy stays navy; status colours stay the product tokens.
class RaisedCircleButton extends StatelessWidget {
  const RaisedCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.background = EncrypchatColors.paper,
    this.iconColor = EncrypchatColors.navy,
    this.size = 40,
    this.iconSize = 18,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color background;
  final Color iconColor;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final button = Opacity(
      opacity: enabled ? 1 : 0.38,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Ink(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(background, EncrypchatColors.paper, 0.28)!,
                  background,
                ],
              ),
              boxShadow: enabled ? EncrypchatColors.raisedShadow : const [],
            ),
            child: Center(
              child: Icon(icon, size: iconSize, color: iconColor),
            ),
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

class RaisedFilterChip extends StatelessWidget {
  const RaisedFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? EncrypchatColors.navy : EncrypchatColors.paper;
    final fg = selected ? EncrypchatColors.paper : EncrypchatColors.ink;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          customBorder: const StadiumBorder(),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(20),
              boxShadow: EncrypchatColors.raisedShadow,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Initials avatar with an optional P2P / offline / blocked status dot.
class StatusAvatar extends StatelessWidget {
  const StatusAvatar({
    super.key,
    required this.label,
    this.radius = 22,
    this.online = false,
    this.blocked = false,
  });

  final String label;
  final double radius;
  final bool online;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    final letter = label.isEmpty ? '?' : label[0].toUpperCase();
    final fill = blocked ? EncrypchatColors.offline : EncrypchatColors.navy;
    final dot = blocked
        ? EncrypchatColors.offline
        : online
        ? EncrypchatColors.p2p
        : EncrypchatColors.offline;
    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: radius,
            backgroundColor: fill,
            foregroundColor: EncrypchatColors.paper,
            child: blocked
                ? Icon(Icons.block, size: radius, color: EncrypchatColors.paper)
                : Text(
                    letter,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: radius * 0.78,
                    ),
                  ),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: radius * 0.55,
              height: radius * 0.55,
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
                border: Border.all(color: EncrypchatColors.paper, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
