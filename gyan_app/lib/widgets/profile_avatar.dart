// ─────────────────────────────────────────────────────────────────────────────
// widgets/profile_avatar.dart
//
// Returns the image child for a circular profile avatar.
//   • Cloud URL (http…)  → Image.network  (the new, account-scoped path)
//   • Legacy local path  → Image.file     (kept for backward compatibility)
//   • Otherwise          → fallback icon
// Wrap the result in a ClipOval.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/material.dart';

Widget profileImageChild(
  String? path, {
  required IconData icon,
  required Color color,
  required double iconSize,
}) {
  if (path != null && path.isNotEmpty) {
    if (path.startsWith('http')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) =>
            Icon(icon, color: color, size: iconSize),
        loadingBuilder: (ctx, child, progress) =>
            progress == null ? child : Icon(icon, color: color, size: iconSize),
      );
    }
    final f = File(path);
    if (f.existsSync()) return Image.file(f, fit: BoxFit.cover);
  }
  return Icon(icon, color: color, size: iconSize);
}
