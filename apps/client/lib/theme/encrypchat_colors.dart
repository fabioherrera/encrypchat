import 'package:flutter/material.dart';

/// Tokens light aprobados — ver docs/design/design-system.md
abstract final class EncrypchatColors {
  static const Color navy = Color(0xFF0F2744);
  static const Color navyMid = Color(0xFF1A365D);
  static const Color ink = Color(0xFF14233A);
  static const Color muted = Color(0xFF5A6B7D);
  static const Color paper = Color(0xFFFFFFFF);
  static const Color canvas = Color(0xFFF4F6F8);
  static const Color bubbleOut = Color(0xFFE6ECF4);
  static const Color p2p = Color(0xFF1B7F4E);
  static const Color relay = Color(0xFFC47B1A);
  static const Color offline = Color(0xFF8A94A0);

  /// Teal for the Contacts tab icon — same family as navy, not a second brand.
  static const Color iconContacts = Color(0xFF2A6F7A);

  static List<BoxShadow> get raisedShadow => [
    BoxShadow(
      color: ink.withValues(alpha: 0.16),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: paper.withValues(alpha: 0.85),
      blurRadius: 1,
      offset: const Offset(0, -0.5),
    ),
  ];
}
