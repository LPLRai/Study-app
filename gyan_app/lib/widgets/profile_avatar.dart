// ─────────────────────────────────────────────────────────────────────────────
// widgets/profile_avatar.dart
//
// Returns the image child for a circular profile avatar.
//   • Bundled asset (assets/…) → Image.asset   (the current, developer-curated path)
//   • Cloud URL (http…)        → Image.network (legacy / backward compatibility)
//   • Legacy local path        → Image.file    (backward compatibility)
//   • Otherwise                → fallback icon
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
    if (path.startsWith('assets/')) {
      return Image.asset(
        path,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => Icon(icon, color: color, size: iconSize),
      );
    }
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
