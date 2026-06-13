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
import '../services/focus_lock_store.dart';
import '../services/focus_monitor.dart';
import '../widgets/white_noise_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Overlay helper (stub — replace body with real calls once package is added)
// ─────────────────────────────────────────────────────────────────────────────
// import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class _OverlayHelper {
  static const String _keyEndTime = 'timer_overlay_end_time';
  static const String _keySubjectName = 'timer_overlay_subject';
  static const String _keyTotal = 'timer_overlay_total';
  static const String _keyPhase = 'timer_overlay_phase';

  /// Call when timer starts running so the overlay can count down independently.
  /// [phaseLabel] is "Pomodoro" / "Short Break" / "Long Break" so the overlay
  /// can show what's running (otherwise a break looks like a stopped timer).
  static Future<void> saveEndTime(int remainingSecs, int totalSecs,
      String subjectName, String phaseLabel) async {
    final prefs = await SharedPreferences.getInstance();
    final endTime = DateTime.now().add(Duration(seconds: remainingSecs));
    await prefs.setString(_keyEndTime, endTime.toIso8601String());
    await prefs.setString(_keySubjectName, subjectName);
    await prefs.setInt(_keyTotal, totalSecs);
    await prefs.setString(_keyPhase, phaseLabel);
  }

  /// Call when timer is paused / stopped / complete.
  static Future<void> clearEndTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEndTime);
    await prefs.remove(_keySubjectName);
    await prefs.remove(_keyTotal);
    await prefs.remove(_keyPhase);
  }

  /// Seconds remaining against the stored phase end time, or null if none.
  /// May be NEGATIVE: a negative value means the phase finished while the app
  /// was away, and its magnitude is how far into later phases we now are — the
  /// timer screen uses that to credit every session that completed in between.
  static Future<int?> getRawRemainingFromStore() async {
    final prefs = await SharedPreferences.getInstance();
    final endStr = prefs.getString(_keyEndTime);
    if (endStr == null) return null;
    return DateTime.parse(endStr).difference(DateTime.now()).inSeconds;
  }

  // ── Overlay window calls ──────────────────────────────────────────────────
  static Future<void> showOverlay() async {
    if (!await FlutterOverlayWindow.isPermissionGranted()) return;
    if (await FlutterOverlayWindow.isActive()) return;
    await FlutterOverlayWindow.showOverlay(
      // matchParent (the real screen), NOT fullCover: fullCover sizes the window
      // to screenHeight() which double-counts the system bars, making the lock
      // taller than the panel so it renders above the top of the screen.
      height: WindowSize.matchParent,
      width: WindowSize.matchParent,
      alignment: OverlayAlignment.center,
      flag: OverlayFlag.defaultFlag,
      visibility: NotificationVisibility.visibilityPublic,
    );
    // The overlay reloads the end time / lists itself on a short poll, so a
    // re-shown cached engine refreshes within a couple of seconds.
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
    // Restore an in-progress timer (paused) after a cold start / hard kill, so
    // the countdown isn't lost and doesn't reset.
    _restoreActiveTimer();
    // If the app was recreated while a Focus Lock session was running, credit
    // any sessions that finished in the meantime before clearing the end time.
    _reconcileColdStartIfLocked();
  }

  // A stored overlay end time only exists while the timer is actively running
  // and the app is backgrounded. If we find one on a fresh start, the activity
  // was recreated mid-lock — reconcile the elapsed time so completed focus
  // sessions still count, then restore paused (the user resumes manually).
  Future<void> _reconcileColdStartIfLocked() async {
    final raw = await _OverlayHelper.getRawRemainingFromStore();
    await _OverlayHelper.clearEndTime();
    if (raw == null || !mounted || _loadedSubjectId == null) return;
    setState(() {
      if (raw <= 0) {
        _fastForward(-raw); // credit every focus session finished while gone
      } else {
        _remainingSecs = raw;
      }
      _isRunning = false; // always restore paused on a cold start
    });
    _syncActiveTimer(context.read<AppProvider>());
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
    _lockSync?.cancel();
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

  // True between "left the app with the timer running" and the next resume.
  // _onAppResumed must NOT touch the timer outside a lock session — that was
  // the bug where a paused timer got reset just by leaving and reopening.
  bool _lockSessionActive = false;

  // While the app is minimised in a Focus Lock, the in-app ticker is stopped,
  // so we drive live progress (study time + group rankings) from this timer
  // instead, recomputed from the wall-clock phase-end so it stays accurate even
  // if background timers are throttled.
  Timer? _lockSync;
  DateTime? _phaseEndAt; // wall-clock end of the phase running when we minimised
  DateTime _lastLockPublish = DateTime.fromMillisecondsSinceEpoch(0);

  void _startLockSync() {
    _lockSync?.cancel();
    _lastLockPublish = DateTime.fromMillisecondsSinceEpoch(0);
    // Tick every second so phase changes (and their chime) land on time in the
    // overlay; the group/Firestore push below is throttled separately.
    _lockSync =
        Timer.periodic(const Duration(seconds: 1), (_) => _lockEngineTick());
    _lockEngineTick(); // run once immediately so "studying" shows fast
  }

  // The timer keeps RUNNING while the app is minimised in a Focus Lock. Since
  // the in-app ticker is stopped, this drives the clock from the wall-clock
  // phase-end: it rolls the phase over when it finishes (recording the focus
  // session + chiming), tells the overlay about the new phase so the break
  // actually counts down there, and periodically pushes study time + group
  // rankings. Recomputing from the wall clock keeps it accurate even if the OS
  // throttles background timers.
  void _lockEngineTick() {
    if (!mounted) return;
    final prov = context.read<AppProvider>();
    final subject = prov.selectedSubject;
    final now = DateTime.now();

    // 1) Roll forward through any phase(s) that ended while minimised. We chime
    //    once for the net transition (so a catch-up after a stalled tick doesn't
    //    fire a burst of dings) and refresh the overlay's phase + countdown.
    var advanced = false;
    var guard = 0;
    while (_phaseEndAt != null && !now.isBefore(_phaseEndAt!) && guard++ < 16) {
      final prevEnd = _phaseEndAt!;
      _advancePhase(silent: true); // record finished focus + set up next phase
      _phaseEndAt = prevEnd.add(Duration(seconds: _phaseTotalSecs));
      advanced = true;
    }
    if (advanced) {
      _playPhaseEntrySound(); // one chime for the phase we just entered
      if (subject != null && _phaseEndAt != null) {
        final rem = math.max(0, _phaseEndAt!.difference(now).inSeconds);
        // The overlay reads these to show the new phase's label, colour and
        // countdown instead of sitting frozen at 00:00.
        _OverlayHelper.saveEndTime(
            rem, _phaseTotalSecs, subject.name, _phaseLabel);
      }
    }

    // 2) Throttled live push — keep study time + group rankings advancing.
    if (subject != null && now.difference(_lastLockPublish).inSeconds >= 20) {
      _lastLockPublish = now;
      final remaining = _phaseEndAt == null
          ? 0
          : math.max(0, _phaseEndAt!.difference(now).inSeconds);
      final elapsed = _phase == TimerPhase.focus
          ? math.min(_phaseTotalSecs, math.max(0, _phaseTotalSecs - remaining))
          : 0;
      final status = _phase == TimerPhase.focus
          ? 'studying'
          : (_phase == TimerPhase.shortBreak ? 'short_break' : 'long_break');
      prov.pushLiveProgress(
        subjectId: subject.id,
        subjectName: subject.name,
        colorIndex: subject.colorIndex,
        remainingSecs: remaining,
        phaseIndex: _phase.index,
        currentCycle: _currentCycle,
        sessionStart: _sessionStart,
        elapsedSeconds: elapsed,
        status: status,
      );
    }
  }

  // Chime for the phase we just ENTERED (mirrors the foreground transitions).
  void _playPhaseEntrySound() {
    switch (_phase) {
      case TimerPhase.shortBreak:
        _playNotificationSound('audio/focus_end.mp3');
        break;
      case TimerPhase.longBreak:
        _playNotificationSound('audio/focus_end.mp3');
        _playNotificationSound('audio/long_break_start.mp3');
        break;
      case TimerPhase.focus:
        _playNotificationSound('audio/break_end.mp3');
        break;
    }
  }

  Future<void> _onAppPaused() async {
    // The lock only ever appears while the timer is running; when the timer is
    // stopped or paused this returns immediately, so it can't show up elsewhere.
    if (!_isRunning) return;

    // Save the expected end time so we can recalculate on resume
    await _OverlayHelper.saveEndTime(
      _remainingSecs,
      _phaseTotalSecs,
      context.read<AppProvider>().selectedSubject?.name ?? '',
      _phaseLabel,
    );
    _lockSessionActive = true;
    // Remember when the running phase ends so the background sync can recompute
    // live progress from the wall clock.
    _phaseEndAt = DateTime.now().add(Duration(seconds: _remainingSecs));

    // Stop the in-app ticker (the stored end-time handles background elapsed)
    _ticker?.cancel();
    setState(() => _isRunning = false);

    // Reset the overlay⇄main channel (start locked, drop any stale command),
    // show the lock, and start guarding the foreground: an allowed app makes
    // the lock invisible, anything else brings it back full-screen.
    await FocusLockStore.clearChannel();
    await _OverlayHelper.showOverlay();
    FocusMonitor.instance.start();
    // Keep study time + group rankings advancing while we're minimised.
    _startLockSync();
  }

  Future<void> _onAppResumed() async {
    // Back in GYAN — stop the background sync, stop guarding, close the lock.
    _lockSync?.cancel();
    _lockSync = null;
    _phaseEndAt = null;
    FocusMonitor.instance.stop();
    await _OverlayHelper.closeOverlay();
    await FocusLockStore.clearChannel();

    // Only a lock session may touch the timer state. If the timer was paused
    // or idle when the app was left, leave everything exactly as it was.
    if (!_lockSessionActive) return;
    _lockSessionActive = false;

    // The timer KEEPS RUNNING across the lock (Exit just unlocks the screen —
    // only the in-app pause/reset buttons stop a session). Reconcile against the
    // stored wall-clock end time so the countdown is accurate AND every focus
    // session that completed while away is credited to the stats.
    final raw = await _OverlayHelper.getRawRemainingFromStore();
    await _OverlayHelper.clearEndTime();
    if (!mounted) return;
    // Land the user on the timer screen, where the clock is still ticking.
    context.read<AppProvider>().switchTab(1);

    if (raw == null) {
      // No stored end time (shouldn't happen during a lock) — just resume.
      setState(() => _isRunning = true);
    } else if (raw > 0) {
      // Still inside the same phase — restore the accurate remaining time.
      setState(() {
        _remainingSecs = raw;
        _isRunning = true;
      });
    } else {
      // The phase (and maybe later ones) finished while away — credit them.
      final endedFocus = _phase == TimerPhase.focus;
      setState(() => _fastForward(-raw));
      // Acknowledge the most recent transition with a single chime.
      if (endedFocus) _playNotificationSound('audio/focus_end.mp3');
    }
    _syncActiveTimer(context.read<AppProvider>());
    if (_isRunning) _startTicker();
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
  Future<void> _play() async {
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
    // If a permission settings page was opened, don't start this press — the
    // timer starting now would trigger the lock over the settings screen.
    if (await _openedPermissionSettings()) return;
    if (!mounted) return;
    if (_phase == TimerPhase.focus && _sessionStart == null) {
      _sessionStart = DateTime.now();
    }
    setState(() => _isRunning = true);
    _syncActiveTimer(prov);
    _startTicker();
  }

  // Focus Lock needs two permissions: "display over other apps" (the lock
  // window itself) and "usage access" (detecting the foreground app so the
  // lock returns over non-allowed apps). Each is asked at most once per app
  // run, and declining never blocks the timer — the lock just degrades.
  static bool _askedOverlayPermission = false;
  static bool _askedUsagePermission = false;

  /// Returns true if a system settings page was opened for a missing
  /// permission (the user grants it, comes back, presses play again).
  Future<bool> _openedPermissionSettings() async {
    if (!await FlutterOverlayWindow.isPermissionGranted() &&
        !_askedOverlayPermission) {
      _askedOverlayPermission = true;
      _toastInfo(
          'Allow “Display over other apps” so Focus Lock can guard your session, then press play again');
      await FlutterOverlayWindow.requestPermission();
      return true;
    }
    if (!await FocusMonitor.instance.hasPermission() &&
        !_askedUsagePermission) {
      _askedUsagePermission = true;
      _toastInfo(
          'Turn on “GYAN Focus Lock” under Accessibility so the lock can block other apps, then press play again');
      await FocusMonitor.instance.requestPermission();
      return true;
    }
    return false;
  }

  void _toastInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.blue,
        duration: const Duration(seconds: 5),
        content: Text(msg,
            style: GoogleFonts.inder(color: Colors.white, fontSize: 13)),
      ));
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
    setState(() {
      _advancePhase(silent: false); // chime + record the finished focus session
      _isRunning = true;
    });
    _syncActiveTimer(context.read<AppProvider>());
    _startTicker();
  }

  // Move from the phase that just finished to the next one: record the focus
  // session if a focus just ended, then set up the next phase's length/cycle.
  // This is the single source of truth for phase transitions — used both by the
  // live ticker (silent:false → plays the chime) and by the resume/cold-start
  // reconciler that replays phases which elapsed while the app was away
  // (silent:true → no chime). It never starts the ticker; the caller does.
  // Returns true when it just closed a FULL Pomodoro set (a long break ended),
  // which the reconciler uses to stop crediting further sessions for one absence.
  bool _advancePhase({required bool silent}) {
    if (_phase == TimerPhase.focus) {
      if (!silent) _playNotificationSound('audio/focus_end.mp3');
      if (_sessionStart != null) {
        // A full focus phase finished — always counts, even if it's a short
        // (admin-configured) focus under the legacy 10-minute threshold.
        _saveSession(_phaseTotalSecs, completed: true);
        _sessionStart = null;
      }
      if (_currentCycle < _totalCycles) {
        _phase = TimerPhase.shortBreak;
        _phaseTotalSecs = _shortBreakSecs;
      } else {
        if (!silent) _playNotificationSound('audio/long_break_start.mp3');
        _phase = TimerPhase.longBreak;
        _phaseTotalSecs = _longBreakSecs;
      }
      _remainingSecs = _phaseTotalSecs;
      return false;
    } else if (_phase == TimerPhase.shortBreak) {
      if (!silent) _playNotificationSound('audio/break_end.mp3');
      _phase = TimerPhase.focus;
      _currentCycle++;
      _phaseTotalSecs = _focusSecs;
      _remainingSecs = _phaseTotalSecs;
      _sessionStart = DateTime.now();
      return false;
    } else {
      if (!silent) _playNotificationSound('audio/break_end.mp3');
      _phase = TimerPhase.focus;
      _currentCycle = 1;
      _phaseTotalSecs = _focusSecs;
      _remainingSecs = _phaseTotalSecs;
      _sessionStart = DateTime.now();
      return true; // a full Pomodoro set just completed
    }
  }

  // Fast-forward the timer to "now" after the current phase already ended while
  // the app was backgrounded in a Focus Lock. [overshoot] is how many seconds
  // passed beyond the current phase's end. We close out the finished phase and
  // each later phase the overshoot fully covers, crediting every completed focus
  // session, then land inside the phase the user is actually in. Caps at one
  // full set so a very long absence can't keep inventing sessions. Sets state
  // fields directly; call inside setState. Never starts the ticker.
  void _fastForward(int overshoot) {
    if (_advancePhase(silent: true)) {
      _idleAfterSet(); // a full set finished right at the boundary
      return;
    }
    var guard = 0;
    while (overshoot >= _remainingSecs && _remainingSecs > 0 && guard++ < 64) {
      overshoot -= _remainingSecs;
      if (_advancePhase(silent: true)) {
        _idleAfterSet(); // credited one full set — stop for this absence
        return;
      }
    }
    _remainingSecs = math.max(1, _remainingSecs - overshoot);
    _isRunning = true; // still mid-phase — keep running
  }

  // A whole Pomodoro set elapsed while away: the sessions are already credited
  // and _advancePhase left us on a fresh focus — sit idle & paused so the user
  // starts the next set deliberately (rather than auto-running endless sets).
  void _idleAfterSet() {
    _sessionStart = null;
    _isRunning = false;
  }

  // [completed] = a full focus phase finished (vs a manual/partial stop). A
  // completed phase always counts toward stats even if the configured focus is
  // under 10 minutes; a partial stop keeps the legacy ≥10-minute rule.
  void _saveSession(int durationSecs, {bool completed = false}) {
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
      completed: completed,
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
                const SizedBox(height: 16),
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
