// ─────────────────────────────────────────────────────────────────────────────
// constants/app_colors.dart
//
// Single source of truth for every colour used in the app.
// Change a value here and it propagates everywhere.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

class AppColors {
  AppColors._(); // prevent instantiation

  // ── Core palette ──────────────────────────────────────────────────────────
  static const Color background   = Color(0xFF1C1C20); // page background
  static const Color widgetBg     = Color(0xFF353536); // cards / interactables
  static const Color blue         = Color(0xFF5865F2); // primary accent
  static const Color green        = Color(0xFF57F287); // success / sessions
  static const Color yellow       = Color(0xFFFFFF00); // quiz / ai tool
  static const Color red          = Color(0xFFED4245); // streak / danger
  static const Color textPrimary  = Color(0xFFFFFFFF);
  static const Color textMuted    = Color(0xFF9B9B9B);
  static const Color divider      = Color(0xFF2A2A2E);

  // ── Subject colour palette (8 distinct colours for coding subjects) ────────
  static const List<Color> subjectPalette = [
    Color(0xFF5865F2), // blue
    Color(0xFF57F287), // green
    Color(0xFFFFFF00), // yellow
    Color(0xFFED4245), // red
    Color(0xFFFF8C00), // orange
    Color(0xFF9B59B6), // purple
    Color(0xFF1ABC9C), // teal
    Color(0xFFE91E63), // pink
  ];

  /// Returns the subject colour for a given index, cycling if needed.
  static Color subjectColor(int index) =>
      subjectPalette[index % subjectPalette.length];
}
