// ─────────────────────────────────────────────────────────────────────────────
// services/focus_monitor.dart
//
// The brain of Focus Lock, running in the MAIN isolate while a session is active
// (timer running + GYAN backgrounded). Every 500ms tick it:
//   1. consumes any command the overlay left ("launch:<pkg>" / "exit"), and
//   2. checks the foreground app and writes the overlay's mode:
//        • an ALLOWED app (or the phone dialer) in front → "hidden" (bubble)
//        • the home launcher                             → "locked" (cover home)
//        • any other app                                 → "locked" + force-exit
//
// The monitor NEVER touches the overlay window's geometry. The overlay isolate
// owns that entirely: it reads the mode file and resizes ITSELF (small bubble vs
// full-screen) while the window's top gravity keeps both states correctly
// positioned. Two isolates fighting over moveOverlay/resizeOverlay was what made
// the overlay jump around, so the monitor's only job here is the mode string.
//
// Foreground detection uses Android's UsageStatsManager via the native channel —
// the same approach YPT/Forest use. NO AccessibilityService is involved, so the
// app no longer trips Google Play Protect's "sensitive data" install block.
// Blocked apps are pushed away with a CATEGORY_HOME intent (goHome), exactly like
// YPT. Communication with the overlay is file-based (FocusLockStore) because
// shareData between the overlay's plugin-less engine and this isolate is
// unreliable. The overlay's foreground service keeps this process alive.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'focus_lock_store.dart';

class FocusMonitor {
  FocusMonitor._();
  static final FocusMonitor instance = FocusMonitor._();

  static const String ownPackage = 'com.example.gyan_app';
  static const MethodChannel _native = MethodChannel('gyan/native');

  Timer? _timer;
  String _mode = 'locked'; // last mode written to the overlay
  DateTime _graceUntil = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastForced = ''; // last package we force-exited (avoid repeat goHome)
  String? _launcherPkg; // home launcher — covered by the lock but never forced
  int _lockStreak = 0; // consecutive "should lock" ticks (debounce, see _tick)
  // After launching an allowed app, UsageStatsManager lags ~1-2s before it
  // reports the new app (it briefly still returns the launcher / null / GYAN).
  // We "protect" the just-launched package during that window so the lag can't
  // re-lock over — or force-exit — the app the user just chose to open.
  String _expectedFg = '';
  DateTime _expectedUntil = DateTime.fromMillisecondsSinceEpoch(0);

  // ── Permission: "Usage access" (PACKAGE_USAGE_STATS), not accessibility ──────
  Future<bool> hasPermission() async {
    try {
      return (await _native.invokeMethod<bool>('isUsageAccessGranted')) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestPermission() async {
    try {
      await _native.invokeMethod('openUsageAccessSettings');
    } catch (_) {}
  }

  void start() {
    stop();
    _mode = 'locked';
    _graceUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _lastForced = '';
    _lockStreak = 0;
    _expectedFg = '';
    _resolveLauncher();
    // The plugin parks the freshly-shown window UP by the status-bar height (its
    // built-in default Y offset). With top gravity that clips the lock under the
    // status bar and leaves a gap at the bottom (the home dock peeks through), so
    // snap the offset back to 0 to sit flush against the top and fill the screen.
    // This is a ONE-OFF reset, not a per-mode move: resizeOverlay never changes
    // x/y, so once y is 0 it stays 0 — nothing races the overlay's own resizing.
    // Fired twice in case the service isn't attached yet on the first call.
    for (final ms in const [350, 1200]) {
      Future.delayed(Duration(milliseconds: ms), () async {
        try {
          await FlutterOverlayWindow.moveOverlay(const OverlayPosition(0, 0));
        } catch (_) {}
      });
    }
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
  }

  Future<void> _resolveLauncher() async {
    try {
      _launcherPkg = await _native.invokeMethod<String>('getLauncherPackage');
    } catch (_) {}
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  // Write the overlay's mode. The overlay isolate polls this file and resizes
  // itself accordingly — the monitor deliberately does NOT move/resize the
  // window (that's what used to make it jump).
  Future<void> _setMode(String mode) async {
    _mode = mode;
    await FocusLockStore.writeMode(mode);
  }

  Future<void> _tick() async {
    try {
      // 1) Act on any command the overlay left for us.
      final cmd = await FocusLockStore.takeCommand();
      if (cmd.startsWith('launch:')) {
        final pkg = cmd.substring('launch:'.length);
        _graceUntil = DateTime.now().add(const Duration(seconds: 2));
        // Protect the launched app until usage stats confirms it's on screen.
        _expectedFg = pkg;
        _expectedUntil = DateTime.now().add(const Duration(seconds: 12));
        _lastForced = '';
        _lockStreak = 0;
        await _setMode('hidden');
        await _native.invokeMethod('launchApp', {'package': pkg});
        return;
      } else if (cmd == 'exit') {
        await _exit();
        return;
      }

      // 2) Brief grace right after a launch so the launcher flashing past during
      //    the app switch doesn't snap the lock back.
      if (DateTime.now().isBefore(_graceUntil)) {
        await _setMode('hidden');
        return;
      }

      // 3) Lock or hide based on the real foreground app (Usage Access).
      final fg = await _foreground();

      // While waiting for a just-launched allowed app to actually surface (usage
      // stats lags 1-2s and briefly reports the launcher / null / GYAN), keep the
      // bubble — never re-lock or force-exit the app the user just chose to open.
      if (_expectedFg.isNotEmpty && DateTime.now().isBefore(_expectedUntil)) {
        if (fg == _expectedFg) {
          _expectedFg = ''; // confirmed on screen — resume normal detection
        } else if (fg == null ||
            fg == ownPackage ||
            fg == _launcherPkg ||
            fg.contains('systemui')) {
          await _setMode('hidden');
          return;
        } else {
          _expectedFg = ''; // a different real app surfaced — handle it below
        }
      }

      // GYAN itself / no reading: leave the current mode untouched.
      if (fg == null || fg == ownPackage) return;
      // The notification shade / recents are transient — don't let them toggle
      // the lock.
      if (fg.contains('systemui')) return;

      final allowed = await FocusLockStore.loadApps();
      // Always let the phone through so incoming/active calls aren't blocked.
      final isPhone = fg.contains('dialer') ||
          fg.contains('incallui') ||
          fg.contains('telecom') ||
          fg.endsWith('.phone');
      final isLauncher = fg == _launcherPkg;
      final isAllowed = isPhone || allowed.any((a) => a.package == fg);

      // Allowed app in front → bubble immediately (get out of the way fast).
      if (isAllowed) {
        _lockStreak = 0;
        _lastForced = '';
        await _setMode('hidden');
        return;
      }

      // Blocked app / home → lock. Debounce so a single stray usage-stats
      // reading (which can briefly mis-report during an app switch) can't flash
      // the full lock over an allowed app: require two consecutive ticks before
      // growing the lock back from the bubble.
      _lockStreak++;
      if (_mode == 'hidden' && _lockStreak < 2) return;
      await _setMode('locked');

      // Force the user out of a genuinely-blocked app (not home / phone / allowed)
      // — YPT-style CATEGORY_HOME. Fired once per blocked app so it doesn't loop.
      if (!isLauncher) {
        if (fg != _lastForced) {
          _lastForced = fg;
          await _native.invokeMethod('goHome');
        }
      } else {
        _lastForced = '';
      }
    } catch (_) {}
  }

  Future<void> _exit() async {
    stop();
    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (_) {}
    try {
      await _native.invokeMethod('bringSelfToFront');
    } catch (_) {}
  }

  Future<String?> _foreground() async {
    try {
      final p = await _native.invokeMethod<String>('getForegroundApp');
      return (p == null || p.isEmpty) ? null : p;
    } catch (_) {
      return null;
    }
  }
}
