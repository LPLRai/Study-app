// ─────────────────────────────────────────────────────────────────────────────
// services/focus_monitor.dart
//
// The brain of Focus Lock, running in the MAIN isolate while a session is active
// (timer running + GYAN backgrounded). Every tick it:
//   1. consumes any command the overlay left ("launch:<pkg>" / "exit"), and
//   2. checks the foreground app and tells the overlay to lock or hide:
//        • an ALLOWED app in front → "hidden" (overlay invisible / passthrough)
//        • anything else           → "locked" (cover the screen)
//
// The foreground app is read from a file written in real time by
// FocusAccessibilityService (usage_stats is too laggy/unreliable for this).
// Communication with the overlay is file-based (FocusLockStore) because
// shareData between the overlay's plugin-less engine and this isolate is
// unreliable. The overlay's foreground service keeps this process alive.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'focus_lock_store.dart';

class FocusMonitor {
  FocusMonitor._();
  static final FocusMonitor instance = FocusMonitor._();

  static const String ownPackage = 'com.example.gyan_app';
  static const MethodChannel _native = MethodChannel('gyan/native');

  // The accessibility service writes the foreground package to the NATIVE
  // cacheDir, which is NOT the same as Dart's Directory.systemTemp — so we ask
  // native for the path once and read from there.
  String? _fgPath;

  Future<File?> _fgFile() async {
    _fgPath ??= await _native.invokeMethod<String>('getCacheDir');
    if (_fgPath == null) return null;
    return File('$_fgPath/fg_pkg.txt');
  }

  Timer? _timer;
  DateTime _graceUntil = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastMove = ''; // throttle moveOverlay calls

  Future<bool> hasPermission() async {
    try {
      return (await _native.invokeMethod<bool>('isAccessibilityEnabled')) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestPermission() async {
    try {
      await _native.invokeMethod('openAccessibilitySettings');
    } catch (_) {}
  }

  void start() {
    stop();
    _graceUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _lastMove = '';
    _resetForeground(); // drop any stale foreground so we begin LOCKED
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
  }

  // Park the window: full-screen lock centered, or the bubble near the top so
  // it doesn't cover the middle of the allowed app. moveOverlay only works from
  // this (main) isolate, so the monitor drives it.
  Future<void> _position(String mode) async {
    if (mode == _lastMove) return;
    _lastMove = mode;
    try {
      if (mode == 'hidden') {
        final v = WidgetsBinding.instance.platformDispatcher.views.first;
        final hDp = v.physicalSize.height / v.devicePixelRatio;
        await FlutterOverlayWindow.moveOverlay(
            OverlayPosition(0, -(hDp / 2 - 60)));
      } else {
        await FlutterOverlayWindow.moveOverlay(const OverlayPosition(0, 0));
      }
    } catch (_) {}
  }

  // Clears the last-known foreground at the start of a session. Otherwise the
  // first tick could read a stale allowed app (from a previous session) and
  // immediately hide the lock instead of showing it.
  Future<void> _resetForeground() async {
    try {
      final f = await _fgFile();
      if (f != null && await f.exists()) await f.delete();
    } catch (_) {}
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    try {
      // 1) Act on any command the overlay left for us.
      final cmd = await FocusLockStore.takeCommand();
      if (cmd.startsWith('launch:')) {
        _graceUntil = DateTime.now().add(const Duration(seconds: 2));
        await FocusLockStore.writeMode('hidden');
        await _position('hidden');
        await _native.invokeMethod(
            'launchApp', {'package': cmd.substring('launch:'.length)});
        return;
      } else if (cmd == 'exit') {
        await _exit();
        return;
      }

      // 2) Brief grace right after a launch so the launcher flashing past
      //    during the app switch doesn't snap the lock back.
      if (DateTime.now().isBefore(_graceUntil)) {
        await FocusLockStore.writeMode('hidden');
        await _position('hidden');
        return;
      }

      // 3) Lock or hide based on the real foreground app. The overlay's own
      //    poll reads this and resizes itself (it stays alive as a small bubble
      //    while hidden, so it can grow back — we never stop the service, which
      //    Android would block from restarting in the background).
      final fg = await _foreground();
      if (fg == null || fg == ownPackage) return;
      final allowed = await FocusLockStore.loadApps();
      final mode = allowed.any((a) => a.package == fg) ? 'hidden' : 'locked';
      await FocusLockStore.writeMode(mode);
      await _position(mode);
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
      final f = await _fgFile();
      if (f == null || !await f.exists()) return null;
      final p = (await f.readAsString()).trim();
      return p.isEmpty ? null : p;
    } catch (_) {
      return null;
    }
  }
}
