// ─────────────────────────────────────────────────────────────────────────────
// services/focus_lock_store.dart
//
// Shared, plugin-free storage for the Focus Lock feature. Both the main app and
// the overlay isolate read/write this, so the overlay never needs plugins.
//
// Focus Lock is ALWAYS ON: whenever the timer is running and the app is left,
// the lock overlay appears. Stored here:
//   • the user's "allowed apps" (small list, SharedPreferences, icons included);
//   • the catalog of ALL launchable apps incl. icons — too big for prefs, so it
//     lives as a JSON file in the app's cache dir. dart:io works in both
//     isolates and Directory.systemTemp resolves to the same app cache dir.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

/// One app the user may still open while a focus lock is active.
class AllowedApp {
  final String package;
  final String name;
  final String iconB64; // base64-encoded PNG (may be empty)

  const AllowedApp({
    required this.package,
    required this.name,
    this.iconB64 = '',
  });

  Map<String, dynamic> toJson() => {'p': package, 'n': name, 'i': iconB64};

  factory AllowedApp.fromJson(Map<String, dynamic> j) => AllowedApp(
        package: (j['p'] as String?) ?? '',
        name: (j['n'] as String?) ?? '',
        iconB64: (j['i'] as String?) ?? '',
      );
}

class FocusLockStore {
  static const String _kApps = 'focus_allowed_apps_json';

  // ── Allowed apps (user's picks — small, kept in prefs) ─────────────────────
  static Future<List<AllowedApp>> loadApps() async {
    final p = await SharedPreferences.getInstance();
    return _parse(p.getString(_kApps));
  }

  static Future<void> saveApps(List<AllowedApp> apps) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _kApps, jsonEncode(apps.map((a) => a.toJson()).toList()));
  }

  // ── Overlay ⇄ main channel (files — shareData is unreliable between the
  //    overlay's plugin-less engine and the main isolate, but plain files work
  //    in both, like the catalog does) ────────────────────────────────────────
  //   command file : overlay → main  ("launch:<pkg>" | "exit")
  //   mode file    : main → overlay  ("locked" | "hidden")
  static File get _cmdFile =>
      File('${Directory.systemTemp.path}/focus_cmd.txt');
  static File get _modeFile =>
      File('${Directory.systemTemp.path}/focus_mode.txt');

  /// Overlay writes a one-shot command for the main isolate to act on.
  static Future<void> writeCommand(String cmd) async {
    try {
      await _cmdFile.writeAsString(cmd);
    } catch (_) {}
  }

  /// Main reads + consumes the pending command ('' if none).
  static Future<String> takeCommand() async {
    try {
      if (!await _cmdFile.exists()) return '';
      final c = (await _cmdFile.readAsString()).trim();
      await _cmdFile.delete();
      return c;
    } catch (_) {
      return '';
    }
  }

  static Future<void> writeMode(String mode) async {
    try {
      await _modeFile.writeAsString(mode);
    } catch (_) {}
  }

  static Future<String> readMode() async {
    try {
      if (!await _modeFile.exists()) return 'locked';
      final m = (await _modeFile.readAsString()).trim();
      return m.isEmpty ? 'locked' : m;
    } catch (_) {
      return 'locked';
    }
  }

  static Future<void> clearChannel() async {
    try {
      if (await _cmdFile.exists()) await _cmdFile.delete();
    } catch (_) {}
    await writeMode('locked');
  }

  // ── App catalog (every launchable app + icon, built by the main app) ───────
  static File get _catalogFile =>
      File('${Directory.systemTemp.path}/focus_lock_catalog.json');

  static Future<void> saveCatalog(List<AllowedApp> apps) async {
    try {
      await _catalogFile
          .writeAsString(jsonEncode(apps.map((a) => a.toJson()).toList()));
    } catch (_) {}
  }

  static Future<List<AllowedApp>> loadCatalog() async {
    try {
      if (!await _catalogFile.exists()) return const [];
      return _parse(await _catalogFile.readAsString());
    } catch (_) {
      return const [];
    }
  }

  static List<AllowedApp> _parse(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => AllowedApp.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
