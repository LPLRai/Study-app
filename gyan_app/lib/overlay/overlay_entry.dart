// ─────────────────────────────────────────────────────────────────────────────
// overlay/overlay_entry.dart
//
// The full-screen overlay shown on Android when the app is backgrounded while
// the Pomodoro timer is running.  This widget runs in its own isolate.
//
// ── ANDROID SETUP REQUIRED ────────────────────────────────────────────────
//  1. pubspec.yaml:
//       flutter_overlay_window: ^0.4.2
//
//  2. android/app/src/main/AndroidManifest.xml — add inside <manifest>:
//       <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
//
//     And inside <application>:
//       <service
//         android:name="com.example.flutter_overlay_window.OverlayService"
//         android:exported="false"/>
//
//  3. Paste this into main.dart (already done in the updated main.dart):
//       @pragma("vm:entry-point")
//       void overlayMain() {
//         WidgetsFlutterBinding.ensureInitialized();
//         runApp(const OverlayEntryApp());
//       }
//
// ── HOW IT WORKS ──────────────────────────────────────────────────────────
//  • TimerScreen saves the target end DateTime to SharedPreferences when it
//    detects the app going to background with the timer running.
//  • This overlay reads that value and runs its own 1-second ticker to display
//    the remaining time (no need to communicate with the main isolate).
//  • Pressing "Exit" clears the stored end time and closes the overlay,
//    then the main app (which re-checks on resume) stops the timer.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
// import 'package:flutter_overlay_window/flutter_overlay_window.dart'; // uncomment when package is added

// ── Overlay app entry point ───────────────────────────────────────────────────
// This is called by the flutter_overlay_window package as a separate isolate.
// Register it in main.dart with @pragma("vm:entry-point").
class OverlayEntryApp extends StatelessWidget {
  const OverlayEntryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _OverlayScreen(),
    );
  }
}

class _OverlayScreen extends StatefulWidget {
  const _OverlayScreen();

  @override
  State<_OverlayScreen> createState() => _OverlayScreenState();
}

class _OverlayScreenState extends State<_OverlayScreen> {
  int _remainingSecs = 0;
  String _subjectName = '';
  Timer? _ticker;

  static const String _prefKeyEndTime     = 'timer_overlay_end_time';
  static const String _prefKeySubjectName = 'timer_overlay_subject';

  @override
  void initState() {
    super.initState();
    _loadAndStart();

    // Listen for signals from the main app (e.g. timer was stopped there)
    // FlutterOverlayWindow.overlayListener.listen((data) {
    //   if (data != null && data['action'] == 'stop') _closeOverlay();
    // });
  }

  Future<void> _loadAndStart() async {
    final prefs   = await SharedPreferences.getInstance();
    final endStr  = prefs.getString(_prefKeyEndTime);
    _subjectName  = prefs.getString(_prefKeySubjectName) ?? '';

    if (endStr == null) { _closeOverlay(); return; }

    final endTime = DateTime.parse(endStr);
    final remaining = endTime.difference(DateTime.now()).inSeconds;

    if (remaining <= 0) { _closeOverlay(); return; }

    setState(() => _remainingSecs = remaining);

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remainingSecs > 0) {
        setState(() => _remainingSecs--);
      } else {
        _closeOverlay();
      }
    });
  }

  Future<void> _exitPressed() async {
    _ticker?.cancel();
    // Clear stored end time so main app knows to stop the timer on resume
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyEndTime);
    _closeOverlay();
  }

  void _closeOverlay() {
    _ticker?.cancel();
    // FlutterOverlayWindow.closeOverlay(); // uncomment when package is added
  }

  String get _formattedTime {
    final m = _remainingSecs ~/ 60;
    final s = _remainingSecs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Lock status bar to dark icons
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return Scaffold(
      backgroundColor: const Color(0xFF1C1C20),
      body: SafeArea(
        child: SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Top label ────────────────────────────────────────────
              Text(
                'Focus Mode Active',
                style: GoogleFonts.inder(
                  color:    Colors.white54,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),

              if (_subjectName.isNotEmpty)
                Container(
                  margin:  const EdgeInsets.symmetric(horizontal: 40),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color:        const Color(0xFF5865F2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _subjectName,
                    style: GoogleFonts.inder(
                      color:      Colors.white,
                      fontSize:   16,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

              const SizedBox(height: 52),

              // ── Countdown ────────────────────────────────────────────
              Text(
                _formattedTime,
                style: GoogleFonts.inder(
                  color:      Colors.white,
                  fontSize:   72,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                'Stay focused — you\'ve got this 💪',
                style: GoogleFonts.inder(
                  color:    Colors.white38,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 60),

              // ── Exit button ──────────────────────────────────────────
              GestureDetector(
                onTap: _exitPressed,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 48, vertical: 16),
                  decoration: BoxDecoration(
                    color:        const Color(0xFFED4245),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'Exit',
                    style: GoogleFonts.inder(
                      color:      Colors.white,
                      fontSize:   18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Text(
                'Exits focus mode and returns to app',
                style: GoogleFonts.inder(
                  color:    Colors.white24,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
