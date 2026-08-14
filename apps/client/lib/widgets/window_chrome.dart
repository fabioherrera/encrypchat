import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/encrypchat_colors.dart';

/// True on the three desktop targets that draw their own window frame. Android
/// and iOS keep the OS chrome, so the custom title bar is desktop-only.
///
/// Excludes `flutter test`: those run on a Linux/macOS host but have no
/// window_manager native side, so building the bar there would throw
/// MissingPluginException. Widget tests keep the plain child.
bool get isDesktopWindow =>
    !kIsWeb &&
    !Platform.environment.containsKey('FLUTTER_TEST') &&
    (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

/// Wraps every screen with the Encrypchat title bar on desktop. The native
/// decorations are hidden (see `main.dart`), so this bar is what moves, resizes
/// and closes the window. On mobile it is a no-op and returns the child as-is.
class DesktopWindowScaffold extends StatelessWidget {
  const DesktopWindowScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopWindow) return child;
    return Column(
      children: [
        const _EncrypchatTitleBar(),
        Expanded(child: child),
      ],
    );
  }
}

class _EncrypchatTitleBar extends StatefulWidget {
  const _EncrypchatTitleBar();

  @override
  State<_EncrypchatTitleBar> createState() => _EncrypchatTitleBarState();
}

class _EncrypchatTitleBarState extends State<_EncrypchatTitleBar>
    with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_syncMaximized());
  }

  Future<void> _syncMaximized() async {
    final max = await windowManager.isMaximized();
    if (mounted) setState(() => _maximized = max);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [EncrypchatColors.navyMid, EncrypchatColors.navy],
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Draggable region: brand on the left, empty space fills the rest.
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => windowManager.startDragging(),
                onDoubleTap: _toggleMaximize,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: _Brand(),
                ),
              ),
            ),
            _WindowButton(
              tooltip: 'Minimizar',
              onPressed: windowManager.minimize,
              builder: (color) => _MinimizeIcon(color: color),
            ),
            _WindowButton(
              tooltip: _maximized ? 'Restaurar' : 'Maximizar',
              onPressed: _toggleMaximize,
              builder: (color) => _maximized
                  ? _RestoreIcon(color: color)
                  : _MaximizeIcon(color: color),
            ),
            _WindowButton(
              tooltip: 'Cerrar',
              hoverColor: const Color(0xFFE23B3B),
              onPressed: windowManager.close,
              builder: (color) => _CloseIcon(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Encrypchat',
      style: TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
  }
}

/// One window control. Full-height hit target, subtle hover wash, and a red
/// wash for close — the convention users already read as "this closes it".
class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.tooltip,
    required this.onPressed,
    required this.builder,
    this.hoverColor = const Color(0x24FFFFFF),
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget Function(Color iconColor) builder;
  final Color hoverColor;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool danger = widget.hoverColor.a > 0.5;
    final iconColor = _hover && danger
        ? Colors.white
        : Colors.white.withValues(alpha: 0.82);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 600),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: 46,
            height: 44,
            color: _hover ? widget.hoverColor : Colors.transparent,
            alignment: Alignment.center,
            child: widget.builder(iconColor),
          ),
        ),
      ),
    );
  }
}

class _MinimizeIcon extends StatelessWidget {
  const _MinimizeIcon({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) =>
      Container(width: 11, height: 1.3, color: color);
}

class _MaximizeIcon extends StatelessWidget {
  const _MaximizeIcon({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      border: Border.all(color: color, width: 1.3),
      borderRadius: BorderRadius.circular(1.5),
    ),
  );
}

class _RestoreIcon extends StatelessWidget {
  const _RestoreIcon({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      height: 12,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 1.2),
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: EncrypchatColors.navy,
                border: Border.all(color: color, width: 1.2),
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CloseIcon extends StatelessWidget {
  const _CloseIcon({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) =>
      Icon(Icons.close_rounded, size: 16, color: color);
}
