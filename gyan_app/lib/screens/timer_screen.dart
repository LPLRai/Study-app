// ─────────────────────────────────────────────────────────────────────────────
// screens/timer_screen.dart
//
// Features:
//  • Per-subject independent timer state  — switching subjects pauses &
//    saves the current state; returning to a subject restores it.
//  • Subject label background colour matches the selected subject's colour.
//  • Background timer  — if the app is minimised while the timer is running,
//    the elapsed time is calculated from a stored timestamp so the countdown
//    stays accurate on resume.
//  • App-lock overlay (Android)  — when the app goes to the background with
//    the timer running, an overlay is shown that prevents using other apps.
//    Pressing "Exit" stops the timer and returns to the app.
//    Requires flutter_overlay_window — see overlay/overlay_entry.dart for setup.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../constants/app_colors.dart';
import '../models/study_session_model.dart';
import '../models/subject_model.dart';
import '../providers/app_provider.dart';
import '../widgets/white_noise_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Overlay helper (stub — replace body with real calls once package is added)
// ─────────────────────────────────────────────────────────────────────────────
// import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class _OverlayHelper {
  static const String _keyEndTime = 'timer_overlay_end_time';
  static const String _keySubjectName = 'timer_overlay_subject';

  /// Call when timer starts running so the overlay can count down independently.
  static Future<void> saveEndTime(int remainingSecs, String subjectName) async {
    final prefs = await SharedPreferences.getInstance();
    final endTime = DateTime.now().add(Duration(seconds: remainingSecs));
    await prefs.setString(_keyEndTime, endTime.toIso8601String());
    await prefs.setString(_keySubjectName, subjectName);
  }

  /// Call when timer is paused / stopped / complete.
  static Future<void> clearEndTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEndTime);
    await prefs.remove(_keySubjectName);
  }

  /// Returns seconds remaining based on the stored end time, or null if none.
  static Future<int?> getRemainingFromStore() async {
    final prefs = await SharedPreferences.getInstance();
    final endStr = prefs.getString(_keyEndTime);
    if (endStr == null) return null;
    final remaining =
        DateTime.parse(endStr).difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  // ── Overlay window calls (uncomment after adding flutter_overlay_window) ──
  static Future<void> showOverlay() async {
    final granted = await FlutterOverlayWindow.isPermissionGranted();
    if (!granted) await FlutterOverlayWindow.requestPermission();
    await FlutterOverlayWindow.showOverlay(
      height: WindowSize.fullCover,
      width: WindowSize.matchParent,
      alignment: OverlayAlignment.center,
      flag: OverlayFlag.defaultFlag,
      visibility: NotificationVisibility.visibilityPublic,
    );
  }

  static Future<void> closeOverlay() async {
    if (await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.closeOverlay();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-subject timer snapshot — everything needed to fully restore a subject's
// timer state when the user taps back to it.
// ─────────────────────────────────────────────────────────────────────────────
class _SubjectTimerSnapshot {
  final int remainingSecs;
  final int phaseTotalSecs;
  final TimerPhase phase;
  final int currentCycle;
  final DateTime? sessionStart;

  const _SubjectTimerSnapshot({
    required this.remainingSecs,
    required this.phaseTotalSecs,
    required this.phase,
    required this.currentCycle,
    this.sessionStart,
  });
}

enum TimerPhase { focus, shortBreak, longBreak }

// ─────────────────────────────────────────────────────────────────────────────
class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  // Keep this page (and its running ticker) alive when the user swipes to
  // another tab, so the timer never resets on navigation.
  @override
  bool get wantKeepAlive => true;

  // ── Active timer state ────────────────────────────────────────────────────
  TimerPhase _phase = TimerPhase.focus;
  int _currentCycle = 1;
  int _remainingSecs = 25 * 60; // placeholder; set from config in initState
  // Full length of the CURRENT phase, captured when the phase starts. Using a
  // captured value (not the live config) means changing the Pomodoro length
  // never retroactively corrupts an in-progress session's elapsed time.
  int _phaseTotalSecs = 25 * 60;
  bool _isRunning = false;
  Timer? _ticker;
  DateTime? _sessionStart;

  // ── Per-subject snapshots ─────────────────────────────────────────────────
  // Keys are subject IDs.  A missing entry means "use defaults (25:00, cycle 1)".
  final Map<String, _SubjectTimerSnapshot> _snapshots = {};

  // Track which subject's state is currently loaded so we know when a switch happens.
  String? _loadedSubjectId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Start from the configured focus length (admins can change it).
    _remainingSecs = context.read<AppProvider>().focusSecs;
    _phaseTotalSecs = _remainingSecs;
    // Clear any stale overlay end-time left over from a previous hard kill.
    _OverlayHelper.clearEndTime();
    // Restore an in-progress timer (paused) after a cold start / hard kill, so
    // the countdown isn't lost and doesn't reset.
    _restoreActiveTimer();
  }

  // Reads the persisted timer state from the provider and restores it (paused).
  void _restoreActiveTimer() {
    final prov = context.read<AppProvider>();
    final m = prov.activeTimer;
    if (m == null) return;
    final subId = m['subjectId'] as String?;
    if (subId == null || !prov.subjects.any((s) => s.id == subId)) return;
    _loadedSubjectId = subId;
    final pi = (m['phaseIndex'] as int?) ?? 0;
    _phase = TimerPhase.values[pi.clamp(0, TimerPhase.values.length - 1)];
    _remainingSecs = (m['remainingSecs'] as int?) ?? _configDurationFor(_phase);
    // Phase total is at least the configured length, but never less than the
    // restored remaining (so progress/elapsed can't go out of range).
    _phaseTotalSecs = _configDurationFor(_phase);
    if (_remainingSecs > _phaseTotalSecs) _phaseTotalSecs = _remainingSecs;
    _currentCycle = (m['currentCycle'] as int?) ?? 1;
    final startMs = m['sessionStartMs'] as int?;
    _sessionStart =
        startMs != null ? DateTime.fromMillisecondsSinceEpoch(startMs) : null;
    _isRunning = false; // always restore paused — the user resumes manually
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _OverlayHelper.clearEndTime();
    super.dispose();
  }

  // ── App lifecycle — background / foreground ───────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused) {
      _onAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    }
  }

  Future<void> _onAppPaused() async {
    if (!_isRunning) return;

    // Save the expected end time so we can recalculate on resume
    await _OverlayHelper.saveEndTime(
      _remainingSecs,
      context.read<AppProvider>().selectedSubject?.name ?? '',
    );

    // Stop the in-app ticker (the stored end-time handles background elapsed)
    _ticker?.cancel();
    setState(() => _isRunning = false);

    // Show the lock overlay (Android only — no-op until package is added)
    await _OverlayHelper.showOverlay();
  }

  Future<void> _onAppResumed() async {
    // Close overlay if it was open
    await _OverlayHelper.closeOverlay();

    // Check if the user pressed "Exit" in the overlay (clears the stored key)
    final remaining = await _OverlayHelper.getRemainingFromStore();

    if (remaining == null) {
      // Overlay "Exit" was pressed — stop timer and save session
      if (_sessionStart != null) {
        final elapsed = _phase == TimerPhase.focus
            ? math.max(0, _phaseTotalSecs - _remainingSecs)
            : 0;
        if (elapsed > 0) _saveSession(elapsed);
      }
      setState(() {
        _isRunning = false;
        _remainingSecs = _phaseDuration;
        _sessionStart = null;
      });
      if (mounted) _syncActiveTimer(context.read<AppProvider>());
      return;
    }

    // Still running — restore the accurate remaining time and resume
    setState(() {
      _remainingSecs = remaining;
      _isRunning = true;
    });
    await _OverlayHelper.clearEndTime();
    _startTicker();
  }

  // ── Configurable durations (admins can change these via the Admin Panel;
  //    everyone else uses the classic 25 / 5 / 15 × 4 defaults) ───────────────
  int get _focusSecs => context.read<AppProvider>().focusSecs;
  int get _shortBreakSecs => context.read<AppProvider>().shortBreakSecs;
  int get _longBreakSecs => context.read<AppProvider>().longBreakSecs;
  int get _totalCycles => context.read<AppProvider>().totalCycles;

  // Configured length for a phase — what the clock resets to for a fresh start.
  int _configDurationFor(TimerPhase p) {
    switch (p) {
      case TimerPhase.focus:
        return _focusSecs;
      case TimerPhase.shortBreak:
        return _shortBreakSecs;
      case TimerPhase.longBreak:
        return _longBreakSecs;
    }
  }

  // ── Phase helpers ─────────────────────────────────────────────────────────
  // Length of the current phase as captured when it started (see _phaseTotalSecs).
  int get _phaseDuration => _phaseTotalSecs;

  String get _phaseLabel {
    switch (_phase) {
      case TimerPhase.focus:
        return 'Pomodoro';
      case TimerPhase.shortBreak:
        return 'Short Break';
      case TimerPhase.longBreak:
        return 'Long Break';
    }
  }

  String get _formattedTime {
    final m = _remainingSecs ~/ 60;
    final s = _remainingSecs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  double get _progress => _remainingSecs / _phaseDuration;

  // ── Subject switching ─────────────────────────────────────────────────────
  void _onSubjectTapped(String newSubjectId, AppProvider prov) {
    if (newSubjectId == _loadedSubjectId) return; // already selected

    // 1. Save current state under the currently loaded subject
    if (_loadedSubjectId != null) {
      _snapshots[_loadedSubjectId!] = _SubjectTimerSnapshot(
        remainingSecs: _remainingSecs,
        phaseTotalSecs: _phaseTotalSecs,
        phase: _phase,
        currentCycle: _currentCycle,
        sessionStart: _sessionStart,
      );
    }

    // 2. Pause if running
    if (_isRunning) {
      _ticker?.cancel();
      _isRunning = false;
    }

    // 3. Load snapshot for the new subject (or defaults if first time)
    final snap = _snapshots[newSubjectId];

    setState(() {
      _loadedSubjectId = newSubjectId;
      _phase = snap?.phase ?? TimerPhase.focus;
      _remainingSecs = snap?.remainingSecs ?? _configDurationFor(_phase);
      _phaseTotalSecs = snap?.phaseTotalSecs ?? _configDurationFor(_phase);
      if (_remainingSecs > _phaseTotalSecs) _phaseTotalSecs = _remainingSecs;
      _currentCycle = snap?.currentCycle ?? 1;
      _sessionStart = snap?.sessionStart;
      _isRunning = false; // never auto-start on switch
    });

    prov.selectSubject(newSubjectId);
    _syncActiveTimer(prov); // persist the newly loaded subject's state
  }

  // Persist the current timer state into the provider so (a) it survives a
  // restart/hard kill and (b) the Home "Recent Session" list reflects it live.
  // Status published to study groups so members can see Studying / Idle /
  // Short break / Long break (the timer screen itself stays unchanged).
  String _statusString() {
    if (_isRunning) {
      switch (_phase) {
        case TimerPhase.focus:
          return 'studying';
        case TimerPhase.shortBreak:
          return 'short_break';
        case TimerPhase.longBreak:
          return 'long_break';
      }
    }
    final hasProgress = _sessionStart != null ||
        _remainingSecs != _phaseDuration ||
        _phase != TimerPhase.focus ||
        _currentCycle != 1;
    if (!hasProgress) return 'idle';
    switch (_phase) {
      case TimerPhase.focus:
        return 'paused';
      case TimerPhase.shortBreak:
        return 'short_break';
      case TimerPhase.longBreak:
        return 'long_break';
    }
  }

  void _syncActiveTimer(AppProvider prov) {
    prov.setStudyStatus(_statusString()); // feed group member status
    final subject = prov.selectedSubject;
    if (subject == null) {
      prov.clearActiveTimer();
      return;
    }
    // Idle (fresh focus, nothing started) → nothing to persist.
    final idle = _phase == TimerPhase.focus &&
        _sessionStart == null &&
        _remainingSecs == _phaseTotalSecs &&
        _currentCycle == 1;
    if (idle) {
      prov.clearActiveTimer();
      return;
    }
    final elapsed = (_phase == TimerPhase.focus && _sessionStart != null)
        ? math.max(0, _phaseTotalSecs - _remainingSecs)
        : 0;
    prov.saveActiveTimer(
      subjectId: subject.id,
      subjectName: subject.name,
      colorIndex: subject.colorIndex,
      remainingSecs: _remainingSecs,
      phaseIndex: _phase.index,
      currentCycle: _currentCycle,
      sessionStart: _sessionStart,
      elapsedSeconds: elapsed,
    );
  }

  // ── Timer controls ────────────────────────────────────────────────────────
  void _play() {
    final prov = context.read<AppProvider>();
    // Require a subject before the timer can run.
    if (prov.selectedSubject == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.red,
          content: Text(
            'Add and choose a subject before starting the timer',
            style: GoogleFonts.inder(color: Colors.white, fontSize: 13),
          ),
        ));
      _showSubjectOverlay(context, prov); // help the user add one right away
      return;
    }
    if (_phase == TimerPhase.focus && _sessionStart == null) {
      _sessionStart = DateTime.now();
    }
    setState(() => _isRunning = true);
    _syncActiveTimer(prov);
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remainingSecs > 0) {
        setState(() => _remainingSecs--);
        _syncActiveTimer(context.read<AppProvider>());
      } else {
        _onPhaseComplete();
      }
    });
  }

  Future<void> _playNotificationSound(String assetPath) async {
    final player = AudioPlayer();
    await player.play(AssetSource(assetPath));
    player.onPlayerComplete.first.then((_) => player.dispose());
  }

  void _pause() {
    _ticker?.cancel();
    setState(() => _isRunning = false);
    _OverlayHelper.clearEndTime();
    _syncActiveTimer(context.read<AppProvider>()); // persist the paused state
  }

  void _reset() {
    _ticker?.cancel();
    _OverlayHelper.clearEndTime();
    if (_phase == TimerPhase.focus && _sessionStart != null) {
      final elapsed = math.max(0, _phaseTotalSecs - _remainingSecs);
      if (elapsed > 0) _saveSession(elapsed);
    }
    setState(() {
      _isRunning = false;
      _phaseTotalSecs = _configDurationFor(_phase); // pick up latest config
      _remainingSecs = _phaseTotalSecs;
      _sessionStart = null;
    });
    // Clear snapshot for current subject so it resets fresh
    if (_loadedSubjectId != null) _snapshots.remove(_loadedSubjectId);
    _syncActiveTimer(context.read<AppProvider>()); // now idle → clears it
  }

  void _onPhaseComplete() {
    _ticker?.cancel();
    _OverlayHelper.clearEndTime();

    if (_phase == TimerPhase.focus) {
      _playNotificationSound('audio/focus_end.mp3');
      if (_sessionStart != null) {
        _saveSession(_phaseTotalSecs); // the focus length just completed
        _sessionStart = null;
      }
      if (_currentCycle < _totalCycles) {
        setState(() {
          _phase = TimerPhase.shortBreak;
          _phaseTotalSecs = _shortBreakSecs;
          _remainingSecs = _phaseTotalSecs;
          _isRunning = true;
        });
      } else {
        _playNotificationSound('audio/long_break_start.mp3');
        setState(() {
          _phase = TimerPhase.longBreak;
          _phaseTotalSecs = _longBreakSecs;
          _remainingSecs = _phaseTotalSecs;
          _isRunning = true;
        });
      }
    } else if (_phase == TimerPhase.shortBreak) {
      _playNotificationSound('audio/break_end.mp3');
      setState(() {
        _phase = TimerPhase.focus;
        _currentCycle++;
        _phaseTotalSecs = _focusSecs;
        _remainingSecs = _phaseTotalSecs;
        _sessionStart = DateTime.now();
        _isRunning = true;
      });
    } else {
      _playNotificationSound('audio/break_end.mp3');
      setState(() {
        _phase = TimerPhase.focus;
        _currentCycle = 1;
        _phaseTotalSecs = _focusSecs;
        _remainingSecs = _phaseTotalSecs;
        _sessionStart = DateTime.now();
        _isRunning = true;
      });
    }
    _syncActiveTimer(context.read<AppProvider>());
    _startTicker();
  }

  void _saveSession(int durationSecs) {
    if (_sessionStart == null) return;
    final prov = context.read<AppProvider>();
    final subject = prov.selectedSubject;
    if (subject == null) return;
    prov.addSession(StudySessionModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      subjectId: subject.id,
      subjectName: subject.name,
      colorIndex: subject.colorIndex,
      durationMinutes: durationSecs ~/ 60,
      durationSeconds: durationSecs, // keep precise seconds
      startTime: _sessionStart!,
      endTime: DateTime.now(),
    ));
  }

  // ── Subject overlay ───────────────────────────────────────────────────────
  void _showSubjectOverlay(BuildContext ctx, AppProvider prov) {
    final nameCtrl = TextEditingController();
    int selectedColor = 0;
    final t = prov.appTheme;

    showModalBottomSheet(
      context: ctx,
      backgroundColor: t.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(builder: (ctx2, setSheet) {
        return Padding(
          padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx2).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Add / Remove Sessions',
                            style: GoogleFonts.inder(
                                color: t.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.bold)),
                        IconButton(
                            icon: Icon(Icons.close, color: t.textPrimary),
                            onPressed: () => Navigator.pop(ctx2)),
                      ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: nameCtrl,
                        style: GoogleFonts.inder(color: t.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Subject name',
                          hintStyle: GoogleFonts.inder(color: t.textMuted),
                          filled: true,
                          fillColor: t.inputBg,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () {
                        if (nameCtrl.text.trim().isNotEmpty) {
                          prov.addSubject(nameCtrl.text.trim(), selectedColor);
                          nameCtrl.clear();
                          Navigator.pop(ctx2);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 13),
                        decoration: BoxDecoration(
                            color: AppColors.blue,
                            borderRadius: BorderRadius.circular(8)),
                        child: Text('Add',
                            style: GoogleFonts.inder(
                                color: Colors.white, fontSize: 14)),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Text('Choose colour:',
                      style:
                          GoogleFonts.inder(color: t.textMuted, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    children:
                        List.generate(AppColors.subjectPalette.length, (i) {
                      final c = AppColors.subjectPalette[i];
                      return GestureDetector(
                        onTap: () => setSheet(() => selectedColor = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: selectedColor == i
                                ? Border.all(color: Colors.white, width: 3)
                                : null,
                            boxShadow: selectedColor == i
                                ? [
                                    BoxShadow(
                                        color: c.withOpacity(0.6),
                                        blurRadius: 6)
                                  ]
                                : null,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 18),
                  if (prov.subjects.isNotEmpty) ...[
                    Text('Existing sessions:',
                        style: GoogleFonts.inder(
                            color: t.textMuted, fontSize: 13)),
                    const SizedBox(height: 8),
                    ...prov.subjects.map((sub) {
                      final c = AppColors.subjectColor(sub.colorIndex);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                            color: t.widgetBg,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: t.widgetShadow),
                        child: Row(children: [
                          Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                  color: c, shape: BoxShape.circle)),
                          const SizedBox(width: 12),
                          Text(sub.name,
                              style: GoogleFonts.inder(
                                  color: t.textPrimary, fontSize: 14)),
                          const Spacer(),
                          GestureDetector(
                            onTap: () {
                              prov.removeSubject(sub.id);
                              setSheet(() {});
                            },
                            child: const Icon(
                                Icons.remove_circle_outline_rounded,
                                color: AppColors.red,
                                size: 22),
                          ),
                        ]),
                      );
                    }),
                  ],
                ]),
          ),
        );
      }),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    return Consumer<AppProvider>(builder: (ctx, prov, _) {
      final t = prov.appTheme;
      final subject = prov.selectedSubject;

      // While idle on a fresh phase, follow the latest configured length so an
      // admin changing the Pomodoro timing updates the clock immediately —
      // without ever touching an in-progress or paused session.
      if (!_isRunning && _sessionStart == null) {
        final cfg = _configDurationFor(_phase);
        if (_remainingSecs == _phaseTotalSecs && _phaseTotalSecs != cfg) {
          _phaseTotalSecs = cfg;
          _remainingSecs = cfg;
        }
      }

      // If the provider's selected subject changed externally and we haven't
      // loaded it yet (e.g. first build), sync up without saving.
      if (subject != null && _loadedSubjectId == null) {
        _loadedSubjectId = subject.id;
      } else if (subject != null && subject.id != _loadedSubjectId) {
        // External switch (e.g. tapping a Recent Session on Home). Load that
        // subject's snapshot after this frame, reusing the normal switch logic.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final p = context.read<AppProvider>();
          final sel = p.selectedSubject;
          if (sel != null && sel.id != _loadedSubjectId) {
            _onSubjectTapped(sel.id, p);
          }
        });
      }

      final arcColor = subject != null
          ? AppColors.subjectColor(subject.colorIndex)
          : AppColors.blue;

      // Subject label background: use the subject's own colour
      final labelColor = subject != null
          ? AppColors.subjectColor(subject.colorIndex)
          : t.widgetBg;

      return SafeArea(
        child: Column(children: [
          // ── Scrollable content fills available space ────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(children: [
                // ── Title bar ───────────────────────────────────────────
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Stack(alignment: Alignment.center, children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onTap: () => prov.switchTab(0),
                        child: Icon(Icons.chevron_left_rounded,
                            color: t.textPrimary, size: 28),
                      ),
                    ),
                    Text('Focus Timer',
                        style: GoogleFonts.inder(
                            color: t.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                  ]),
                ),

                // ── Subject label (colour = subject colour) ─────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                        color: labelColor,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      subject != null
                          ? 'Subject: ${subject.name}'
                          : 'No subject selected — tap Edit below',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inder(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // ── Circular timer ──────────────────────────────────────
                _CircularTimer(
                  progress: _progress,
                  arcColor: arcColor,
                  trackColor: t.textPrimary.withOpacity(0.1),
                  timeLabel: _formattedTime,
                  phaseLabel: _phaseLabel,
                  textPrimary: t.textPrimary,
                ),

                const SizedBox(height: 18),

                Text('Cycle $_currentCycle of $_totalCycles',
                    style: GoogleFonts.inder(color: t.textMuted, fontSize: 14)),

                const SizedBox(height: 22),

                // ── Controls ────────────────────────────────────────────
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (_isRunning || _remainingSecs != _phaseDuration) ...[
                    _controlBtn(
                        icon: Icons.refresh_rounded,
                        size: 46,
                        color: t.widgetBg,
                        outline: true,
                        onTap: _reset),
                    const SizedBox(width: 22),
                  ],
                  _controlBtn(
                    icon: _isRunning
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 64,
                    color: AppColors.blue,
                    onTap: _isRunning ? _pause : _play,
                  ),
                ]),

                const SizedBox(height: 28),
                Divider(color: t.divider, height: 1),
                const SizedBox(height: 4),

                // ── Choose Subjects ─────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Choose Subjects',
                            style: GoogleFonts.inder(
                                color: t.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        if (prov.subjects.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                                color: t.widgetBg,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: t.widgetShadow),
                            child: Center(
                                child: Text(
                                    'No subjects yet — tap “Add / Edit Subjects” below',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inder(
                                        color: t.textMuted, fontSize: 13))),
                          )
                        else
                          ...prov.subjects.map((sub) => _subjectTile(
                              sub, _loadedSubjectId == sub.id, prov, t)),
                        const SizedBox(height: 14),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _showSubjectOverlay(ctx, prov),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            decoration: BoxDecoration(
                              color: AppColors.blue.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: AppColors.blue.withOpacity(0.5),
                                  width: 1.5),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.edit_rounded,
                                    color: AppColors.blue, size: 19),
                                const SizedBox(width: 8),
                                Text('Add / Edit Subjects',
                                    style: GoogleFonts.inder(
                                        color: AppColors.blue,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ]),
                ),
              ]), // close inner Column
            ), // close SingleChildScrollView
          ), // close Expanded

          // ── White Noise widget — always pinned above nav bar ─────────
          const WhiteNoiseWidget(),
        ]),
      );
    });
  }

  Widget _controlBtn(
          {required IconData icon,
          required double size,
          required Color color,
          required VoidCallback onTap,
          bool outline = false}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: outline ? Colors.transparent : color,
            shape: BoxShape.circle,
            border:
                outline ? Border.all(color: Colors.white24, width: 1.5) : null,
          ),
          child: Icon(icon, color: Colors.white, size: size * 0.52),
        ),
      );

  Widget _subjectTile(
      SubjectModel sub, bool isSelected, AppProvider prov, appTheme) {
    final c = AppColors.subjectColor(sub.colorIndex);
    // Studied time is derived from saved sessions (so it matches statistics
    // everywhere), plus the live elapsed seconds while THIS subject's focus
    // timer is running — giving a real-time count instead of a frozen 0:00:00.
    int totalSecs = prov.secondsForSubjectId(sub.id);
    // Show the in-progress focus time for this subject — even after switching
    // to another one. The active subject reads its live state; switched-away
    // subjects read their saved snapshot, so their elapsed time stays visible
    // (frozen) instead of resetting to 0:00:00.
    if (isSelected) {
      if (_phase == TimerPhase.focus && _sessionStart != null) {
        totalSecs += math.max(0, _phaseTotalSecs - _remainingSecs);
      }
    } else {
      final snap = _snapshots[sub.id];
      if (snap != null &&
          snap.phase == TimerPhase.focus &&
          snap.sessionStart != null) {
        totalSecs += math.max(0, snap.phaseTotalSecs - snap.remainingSecs);
      }
    }
    final hours = totalSecs ~/ 3600;
    final mins = (totalSecs % 3600) ~/ 60;
    final secs = totalSecs % 60;
    final timeStr =
        '$hours:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: () => _onSubjectTapped(sub.id, prov),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: isSelected ? c.withOpacity(0.15) : appTheme.widgetBg,
          borderRadius: BorderRadius.circular(10),
          border: isSelected ? Border.all(color: c, width: 1.5) : null,
          boxShadow: appTheme.widgetShadow,
        ),
        child: Row(children: [
          Container(
              width: 4,
              height: 32,
              decoration: BoxDecoration(
                  color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 14),
          Text(sub.name,
              style:
                  GoogleFonts.inder(color: appTheme.textPrimary, fontSize: 15)),
          const Spacer(),
          Text(timeStr,
              style:
                  GoogleFonts.inder(color: appTheme.textMuted, fontSize: 13)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Circular arc timer — CustomPainter
// ─────────────────────────────────────────────────────────────────────────────
class _CircularTimer extends StatelessWidget {
  final double progress;
  final Color arcColor;
  final Color trackColor;
  final String timeLabel;
  final String phaseLabel;
  final Color textPrimary;

  const _CircularTimer({
    required this.progress,
    required this.arcColor,
    required this.trackColor,
    required this.timeLabel,
    required this.phaseLabel,
    required this.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      height: 210,
      child: CustomPaint(
        painter: _ArcPainter(progress: progress, color: arcColor, trackColor: trackColor),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(timeLabel,
                style: GoogleFonts.inder(
                    color: textPrimary,
                    fontSize: 44,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
            const SizedBox(height: 4),
            Text(phaseLabel,
                style: GoogleFonts.inder(color: AppColors.blue, fontSize: 14)),
          ]),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;
  const _ArcPainter({required this.progress, required this.color, required this.trackColor});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = math.min(cx, cy) - 8;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
    canvas.drawArc(
        rect,
        0,
        2 * math.pi,
        false,
        Paint()
          ..color = trackColor
          ..strokeWidth = 9
          ..style = PaintingStyle.stroke);
    if (progress > 0) {
      canvas.drawArc(
          rect,
          -math.pi / 2,
          2 * math.pi * progress,
          false,
          Paint()
            ..color = color
            ..strokeWidth = 9
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.progress != progress || old.color != color || old.trackColor != trackColor;
}
