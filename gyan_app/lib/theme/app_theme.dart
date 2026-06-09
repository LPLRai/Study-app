// ─────────────────────────────────────────────────────────────────────────────
// theme/app_theme.dart
//
// All colours that differ between dark and light mode live here.
// Brand colours (blue, green, yellow, red, subject palette) are fixed and
// don't change between modes — they stay in app_colors.dart.
//
// Usage in any widget:
//   final t = context.watch<AppProvider>().appTheme;
//   Container(color: t.background, ...)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppThemeData {
  final bool isDark;

  const AppThemeData({required this.isDark});

  // ── Backgrounds ────────────────────────────────────────────────────────────
  Color get background => isDark
      ? const Color(0xFF202225)
      : const Color(0xFFF0F0F7);

  Color get widgetBg => isDark
      ? const Color(0xFF2B2B30)
      : const Color(0xFFFFFFFF);

  Color get inputBg => isDark
      ? const Color(0xFF34343A)
      : const Color(0xFFE8E8F0);

  Color get navBar => isDark
      ? const Color(0xFF2B2B30)
      : const Color(0xFFFFFFFF);

  // ── Brand accent (single source of truth for the whole app) ─────────────────
  // One consistent accent in both modes — readable with white text everywhere.
  // Change these two lines to re-theme every accent in the app at once.
  Color get accent => const Color(0xFF5865F2);
  Color get onAccent => Colors.white;

  // ── Text ───────────────────────────────────────────────────────────────────
  Color get textPrimary => isDark
      ? const Color(0xFFFFFFFF)
      : const Color(0xFF1A1A22);

  Color get textMuted => isDark
      ? const Color(0xFF9B9B9B)
      : const Color(0xFF68686E);

  // ── Structural ─────────────────────────────────────────────────────────────
  Color get divider => isDark
      ? const Color(0xFF2A2A2E)
      : const Color(0xFFDDDDE6);

  Color get cardBorder => isDark
      ? Colors.white.withOpacity(0.07)
      : Colors.black.withOpacity(0.07);

  // ── Overlay on cards (e.g. hover states) ──────────────────────────────────
  Color get overlayLight => isDark
      ? Colors.white.withOpacity(0.05)
      : Colors.black.withOpacity(0.04);

  // ── Shadows ────────────────────────────────────────────────────────────────
  List<BoxShadow>? get widgetShadow => isDark
      ? null
      : [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ];

  // ── Status bar style ───────────────────────────────────────────────────────
  SystemUiOverlayStyle get systemUiStyle => isDark
      ? const SystemUiOverlayStyle(
          statusBarColor:          Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness:     Brightness.dark,
        )
      : const SystemUiOverlayStyle(
          statusBarColor:          Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness:     Brightness.light,
        );
}
