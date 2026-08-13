import 'package:flutter/material.dart';

import 'encrypchat_colors.dart';

/// Tema light canónico Encrypchat (dark pendiente de aprobación).
ThemeData buildEncrypchatLightTheme() {
  final base = ColorScheme.fromSeed(
    seedColor: EncrypchatColors.navy,
    brightness: Brightness.light,
    primary: EncrypchatColors.navy,
    onPrimary: EncrypchatColors.paper,
    secondary: EncrypchatColors.navyMid,
    surface: EncrypchatColors.paper,
    onSurface: EncrypchatColors.ink,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: base,
    scaffoldBackgroundColor: EncrypchatColors.canvas,
    appBarTheme: const AppBarTheme(
      backgroundColor: EncrypchatColors.paper,
      foregroundColor: EncrypchatColors.navy,
      elevation: 0,
      scrolledUnderElevation: 0.5,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: EncrypchatColors.navy,
      foregroundColor: EncrypchatColors.paper,
    ),
    dividerColor: EncrypchatColors.navy.withValues(alpha: 0.12),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: EncrypchatColors.paper,
      indicatorColor: EncrypchatColors.bubbleOut,
      elevation: 8,
      shadowColor: EncrypchatColors.ink.withValues(alpha: 0.12),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? EncrypchatColors.navy : EncrypchatColors.muted,
        );
      }),
    ),
  );
}
