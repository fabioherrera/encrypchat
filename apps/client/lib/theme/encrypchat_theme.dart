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
    dividerColor: EncrypchatColors.navy.withOpacity(0.12),
  );
}
