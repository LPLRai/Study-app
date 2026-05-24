// ─────────────────────────────────────────────────────────────────────────────
// screens/timer_screen.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert'; // Added for JSON encoding/decoding
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
// Daily Timer Persistence Helper
// ─────────────────────────────────────────────────────────────────────────────
class _TimerStateHelper {
  static const _prefix = 'timer_state_';

  static Future<void> saveState({
    required String subjectId,
    required int cycle,
    required int remainingSecs,
    required TimerPhase phase,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    // Use ISO date to restrict saves to "a day"
    final today = DateTime.now().toIso8601String().substring(0, 10);

    int savedCycle = cycle;
    int savedRemaining = remainingSecs;

    // "Not the breaks though" — If saving during a break, default state to the start of the next focus
    if (phase != TimerPhase.focus) {
      savedCycle = (phase == TimerPhase.shortBreak) ? cycle + 1 : 1;
      if (savedCycle > TimerScreen._totalCycles) savedCycle = 1;
      savedRemaining = TimerScreen._focusSecs;
    }

    final data = jsonEncode({
      'date': today,
      'cycle': savedCycle,
      'remainingSecs': savedRemaining,
    });
    await prefs.setString('$_prefix$subjectId', data);
  }

  static Future<Map<String, dynamic>?> loadState(String subjectId) async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString('$_prefix$subjectId');
    if (str == null) return null;

    try {
      final data = jsonDecode(str);
      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (data['date'] == today) {
        return data; // Same day, return the saved state
      } else {
        await prefs.remove('$_prefix$subjectId'); // New day, clear it
        return null;
      }
    } catch (_) {
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Overlay helper
// ─────────────────────────────────────────────────────────────────────────────
class _OverlayHelper {
  static const String _keyEndTime = 'timer_overlay_end_time';
  static const String _keySubjectName = 'timer_overlay_subject';

  static Future<void> saveEndTime(int remainingSecs, String subjectName) async {
    final prefs = await SharedPreferences.getInstance();
    final endTime = DateTime.now().add(Duration(seconds: remainingSecs));
    await prefs.setString(_keyEndTime, endTime.toIso8601String());
    await prefs.setString(_keySubjectName, subjectName);
  }

  static Future<void> clearEndTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEndTime);
    await prefs.remove(_keySubjectName);
  }

  static Future<int?> getRemainingFromStore() async {
    final prefs = await SharedPreferences.getInstance();
    final endStr = prefs.getString(_keyEndTime);
    if (endStr == null) return null;
    final remaining =
        DateTime.parse(endStr).difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

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
// Per-subject snapshot
// ─────────────────────────────────────────────────────────────────────────────
class _SubjectTimerSnapshot {
  final int remainingSecs;
  final TimerPhase phase;
  final int currentCycle;
  final DateTime? sessionStart;
  final bool pauseSaved;
  final bool thresholdShown;
  final String? currentSessionId;

  const _SubjectTimerSnapshot({
    required this.remainingSecs,
    required this.phase,
    required this.currentCycle,
    this.sessionStart,
    this.pauseSaved = false,
    this.thresholdShown = false,
    this.currentSessionId,
  });
}

enum TimerPhase { focus, shortBreak, longBreak }

// ─────────────────────────────────────────────────────────────────────────────
class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  static const int _focusSecs = 25 * 60;
  static const int _shortBreakSecs = 5 * 60;
  static const int _longBreakSecs = 15 * 60;
  static const int _totalCycles = 4;
  static const int _sessionCountThreshold = 10;

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  TimerPhase _phase = TimerPhase.focus;
  int _currentCycle = 1;
  int _remainingSecs = TimerScreen._focusSecs;
  bool _isRunning = false;
  Timer? _ticker;
  DateTime? _sessionStart;

  bool _pauseSaved = false;
  bool _thresholdShown = false;
  String? _currentSessionId;

  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription? _dingSubscription;

  final Map<String, _SubjectTimerSnapshot> _snapshots = {};
  String? _loadedSubjectId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _dingSubscription?.cancel();
    _audioPlayer.dispose();
    _OverlayHelper.clearEndTime();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) _onAppPaused();
    if (state == AppLifecycleState.resumed) _onAppResumed();
  }

  Future<void> _saveCurrentStateToPrefs() async {
    if (_loadedSubjectId == null) return;
    await _TimerStateHelper.saveState(
      subjectId: _loadedSubjectId!,
      cycle: _currentCycle,
      remainingSecs: _remainingSecs,
      phase: _phase,
    );
  }

  Future<void> _onAppPaused() async {
    if (!_isRunning) return;
    await _OverlayHelper.saveEndTime(
      _remainingSecs,
      context.read<AppProvider>().selectedSubject?.name ?? '',
    );
    await _saveCurrentStateToPrefs();
    _ticker?.cancel();
    setState(() => _isRunning = false);
    await _OverlayHelper.showOverlay();
  }

  Future<void> _onAppResumed() async {
    await _OverlayHelper.closeOverlay();
    final remaining = await _OverlayHelper.getRemainingFromStore();

    if (remaining == null) {
      _maybeSaveOnStop();
      setState(() {
        _isRunning = false;
        _remainingSecs = _phaseDuration;
        _sessionStart = null;
        _pauseSaved = false;
        _thresholdShown = false;
        _currentSessionId = null;
      });
      return;
    }

    setState(() {
      _remainingSecs = remaining;
      _isRunning = true;
    });
    await _OverlayHelper.clearEndTime();
    _startTicker();
  }

  int get _phaseDuration {
    switch (_phase) {
      case TimerPhase.focus:
        return TimerScreen._focusSecs;
      case TimerPhase.shortBreak:
        return TimerScreen._shortBreakSecs;
      case TimerPhase.longBreak:
        return TimerScreen._longBreakSecs;
    }
  }

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

  Future<void> _playSound(String fileName) async {
    try {
      _dingSubscription?.cancel();
      await _audioPlayer.stop();

      await _audioPlayer.setAudioContext(AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {AVAudioSessionOptions.mixWithOthers},
        ),
        android: AudioContextAndroid(
          isSpeakerphoneOn: false,
          audioMode: AndroidAudioMode.normal,
          usageType: AndroidUsageType.media,
        ),
      ));

      WhiteNoiseWidget.duck();

      await _audioPlayer.play(AssetSource('audio/$fileName'));

      _dingSubscription = _audioPlayer.onPlayerComplete.listen((_) {
        WhiteNoiseWidget.unduck();
        _dingSubscription?.cancel();
        _dingSubscription = null;
      });
    } catch (_) {
      WhiteNoiseWidget.unduck();
    }
  }

  Future<void> _onSubjectTapped(String newSubjectId, AppProvider prov) async {
    if (newSubjectId == _loadedSubjectId) return;

    if (_loadedSubjectId != null) {
      _snapshots[_loadedSubjectId!] = _SubjectTimerSnapshot(
        remainingSecs: _remainingSecs,
        phase: _phase,
        currentCycle: _currentCycle,
        sessionStart: _sessionStart,
        pauseSaved: _pauseSaved,
        thresholdShown: _thresholdShown,
        currentSessionId: _currentSessionId,
      );
      await _saveCurrentStateToPrefs();
    }

    if (_isRunning) {
      _ticker?.cancel();
      _isRunning = false;
    }

    _loadedSubjectId = newSubjectId;
    prov.selectSubject(newSubjectId);

    if (_snapshots.containsKey(newSubjectId)) {
      final snap = _snapshots[newSubjectId]!;
      setState(() {
        _remainingSecs = snap.remainingSecs;
        _phase = snap.phase;
        _currentCycle = snap.currentCycle;
        _sessionStart = snap.sessionStart;
        _pauseSaved = snap.pauseSaved;
        _thresholdShown = snap.thresholdShown;
        _currentSessionId = snap.currentSessionId;
        _isRunning = false;
      });
    } else {
      // Load persistence from earlier today
      final saved = await _TimerStateHelper.loadState(newSubjectId);
      if (saved != null && mounted) {
        setState(() {
          _remainingSecs = saved['remainingSecs'];
          _currentCycle = saved['cycle'];
          _phase = TimerPhase.focus; // Break logic forces phase=focus locally
          _isRunning = false;
          _sessionStart = null;
          _pauseSaved = false;
          _thresholdShown = false;
          _currentSessionId = null;
        });
        _snapshots[newSubjectId] = _SubjectTimerSnapshot(
          remainingSecs: _remainingSecs,
          phase: _phase,
          currentCycle: _currentCycle,
        );
      } else if (mounted) {
        // First load of the day (or explicitly new)
        setState(() {
          _remainingSecs = TimerScreen._focusSecs;
          _phase = TimerPhase.focus;
          _currentCycle = 1;
          _sessionStart = null;
          _pauseSaved = false;
          _thresholdShown = false;
          _currentSessionId = null;
          _isRunning = false;
        });
      }
    }
  }

  void _play() {
    if (_loadedSubjectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Choose a subject first',
              style: GoogleFonts.inder(color: Colors.white)),
          backgroundColor: const Color(0xFF2C2C34),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    if (_phase == TimerPhase.focus && _sessionStart == null) {
      _sessionStart = DateTime.now();
      _pauseSaved = false;
      _thresholdShown = false;
      _currentSessionId =
          '${_loadedSubjectId}_${_sessionStart!.millisecondsSinceEpoch}';
    }

    setState(() => _isRunning = true);
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remainingSecs > 0) {
        setState(() => _remainingSecs--);

        if (_phase == TimerPhase.focus &&
            !_thresholdShown &&
            _sessionStart != null) {
          final elapsed = TimerScreen._focusSecs - _remainingSecs;
          if (elapsed >= TimerScreen._sessionCountThreshold) {
            _upsertSession(elapsed);
            _thresholdShown = true;
          }
        }
      } else {
        _onPhaseComplete();
      }
    });
  }

  void _pause() {
    _ticker?.cancel();
    setState(() => _isRunning = false);
    _OverlayHelper.clearEndTime();

    if (!_pauseSaved && _sessionStart != null && _phase == TimerPhase.focus) {
      final elapsed = TimerScreen._focusSecs - _remainingSecs;
      if (elapsed >= TimerScreen._sessionCountThreshold) {
        _upsertSession(elapsed);
        _thresholdShown = true;
        _pauseSaved = true;
      }
    }

    _saveCurrentStateToPrefs();
  }

  void _reset() {
    _ticker?.cancel();
    _OverlayHelper.clearEndTime();
    _maybeSaveOnStop();
    setState(() {
      _isRunning = false;
      _remainingSecs = _phaseDuration;
      _sessionStart = null;
      _pauseSaved = false;
      _thresholdShown = false;
      _currentSessionId = null;
    });
    if (_loadedSubjectId != null) _snapshots.remove(_loadedSubjectId);
    _saveCurrentStateToPrefs();
  }

  void _maybeSaveOnStop() {
    if (_sessionStart != null && _phase == TimerPhase.focus) {
      final elapsed = TimerScreen._focusSecs - _remainingSecs;
      if (elapsed >= TimerScreen._sessionCountThreshold) {
        _upsertSession(elapsed);
      }
    }
  }

  void _onPhaseComplete() {
    _ticker?.cancel();
    _OverlayHelper.clearEndTime();

    if (_phase == TimerPhase.focus) {
      if (_sessionStart != null) {
        _upsertSession(TimerScreen._focusSecs);
      }
      _sessionStart = null;
      _pauseSaved = false;
      _thresholdShown = false;
      _currentSessionId = null;

      _playSound('focus_end.mp3');

      if (_currentCycle < TimerScreen._totalCycles) {
        setState(() {
          _phase = TimerPhase.shortBreak;
          _remainingSecs = TimerScreen._shortBreakSecs;
          _isRunning = true;
        });
      } else {
        setState(() {
          _phase = TimerPhase.longBreak;
          _remainingSecs = TimerScreen._longBreakSecs;
          _isRunning = true;
        });
      }
      _startTicker();
    } else if (_phase == TimerPhase.shortBreak) {
      _playSound('break_end.mp3');

      setState(() {
        _phase = TimerPhase.focus;
        _currentCycle++;
        _remainingSecs = TimerScreen._focusSecs;
        _pauseSaved = false;
        _thresholdShown = false;
        _currentSessionId = null;
        _isRunning = true;
      });
      _sessionStart = DateTime.now();
      _currentSessionId =
          '${_loadedSubjectId}_${_sessionStart!.millisecondsSinceEpoch}';
      _startTicker();
    } else {
      _playSound('break_end.mp3');

      setState(() {
        _phase = TimerPhase.focus;
        _currentCycle = 1;
        _remainingSecs = TimerScreen._focusSecs;
        _pauseSaved = false;
        _thresholdShown = false;
        _currentSessionId = null;
        _isRunning = true;
      });
      _sessionStart = DateTime.now();
      _currentSessionId =
          '${_loadedSubjectId}_${_sessionStart!.millisecondsSinceEpoch}';
      _startTicker();
    }

    // Save cycle progression to local storage
    _saveCurrentStateToPrefs();
  }

  void _upsertSession(int durationSecs) {
    if (_sessionStart == null || _currentSessionId == null) return;
    final prov = context.read<AppProvider>();
    final subject = prov.selectedSubject;
    if (subject == null) return;

    final minutes = math.max(1, durationSecs ~/ 60);

    prov.upsertSession(StudySessionModel(
      id: _currentSessionId!,
      subjectId: subject.id,
      subjectName: subject.name,
      colorIndex: subject.colorIndex,
      durationMinutes: minutes,
      startTime: _sessionStart!,
      endTime: DateTime.now(),
    ));
  }

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

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Consumer<AppProvider>(builder: (ctx, prov, _) {
      final t = prov.appTheme;
      final subject = prov.selectedSubject;

      // Handle async loading smoothly via post-frame callback
      if (subject != null && _loadedSubjectId != subject.id) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _onSubjectTapped(subject.id, prov);
        });
      }

      final arcColor = subject != null
          ? AppColors.subjectColor(subject.colorIndex)
          : AppColors.blue;

      final labelColor = subject != null
          ? AppColors.subjectColor(subject.colorIndex)
          : t.widgetBg;

      return SafeArea(
        child: Column(children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(children: [
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
                _CircularTimer(
                  progress: _progress,
                  arcColor: arcColor,
                  timeLabel: _formattedTime,
                  phaseLabel: _phaseLabel,
                  textPrimary: t.textPrimary,
                ),
                const SizedBox(height: 18),
                Text('Cycle $_currentCycle of ${TimerScreen._totalCycles}',
                    style: GoogleFonts.inder(color: t.textMuted, fontSize: 14)),
                const SizedBox(height: 22),
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
                                    'No subjects yet — press Edit to add one',
                                    style: GoogleFonts.inder(
                                        color: t.textMuted, fontSize: 13))),
                          )
                        else
                          ...prov.subjects.map((sub) => _subjectTile(
                              sub, _loadedSubjectId == sub.id, prov, t)),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () => _showSubjectOverlay(ctx, prov),
                          child: Row(children: [
                            Icon(Icons.edit, color: t.textMuted, size: 15),
                            const SizedBox(width: 5),
                            Text('Edit',
                                style: GoogleFonts.inder(
                                    color: t.textMuted, fontSize: 13)),
                          ]),
                        ),
                        const SizedBox(height: 16),
                      ]),
                ),
              ]),
            ),
          ),
          const WhiteNoiseWidget(),
        ]),
      );
    });
  }

  Widget _controlBtn({
    required IconData icon,
    required double size,
    required Color color,
    required VoidCallback onTap,
    bool outline = false,
  }) =>
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

    final extraSecs = isSelected && _isRunning && _phase == TimerPhase.focus
        ? (TimerScreen._focusSecs - _remainingSecs)
        : 0;

    final totalSeconds = (sub.totalMinutes * 60) + extraSecs;

    final hours = totalSeconds ~/ 3600;
    final mins = (totalSeconds % 3600) ~/ 60;
    final secs = totalSeconds % 60;

    final timeStr =
        '${hours.toString().padLeft(1, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

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

class _CircularTimer extends StatelessWidget {
  final double progress;
  final Color arcColor;
  final String timeLabel;
  final String phaseLabel;
  final Color textPrimary;

  const _CircularTimer({
    required this.progress,
    required this.arcColor,
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
        painter: _ArcPainter(progress: progress, color: arcColor),
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
  const _ArcPainter({required this.progress, required this.color});

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
          ..color = Colors.white.withOpacity(0.08)
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
      old.progress != progress || old.color != color;
}
