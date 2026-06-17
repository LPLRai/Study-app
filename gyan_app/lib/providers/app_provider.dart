// ─────────────────────────────────────────────────────────────────────────────
// providers/app_provider.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/avatars.dart';
import '../models/user_model.dart';
import '../models/subject_model.dart';
import '../models/study_session_model.dart';
import '../models/group_model.dart';
import 'package:installed_apps/installed_apps.dart';

import '../services/firebase_service.dart';
import '../services/push_service.dart';
import '../services/local_notification_service.dart'; // ← NEW
import '../services/focus_lock_store.dart';
import '../theme/app_theme.dart';
import '../config/admin_config.dart';

class AppProvider extends ChangeNotifier {
  final FirebaseService _firebaseService = FirebaseService.instance;

  UserModel _user = UserModel();
  List<SubjectModel> _subjects = [];
  List<StudySessionModel> _sessions = [];
  List<GroupModel> _groups = [];
  String? _selectedSubjectId;
  int _currentTabIndex = 0;
  bool _isDarkMode = false;
  bool _remoteBackendReady = false;
  Timer? _midnightTimer;

  // ── Timer configuration (per-device; only the Admin Panel changes it) ───────
  int _focusMinutes = 25;
  int _shortBreakMinutes = 5;
  int _longBreakMinutes = 15;
  int _cycles = 4;

  // ── Admin-only headline stat overrides (null = use real, derived value) ─────
  int? _ovrStreak;
  int? _ovrBestStreak;
  int? _ovrSessions;
  int? _ovrStudyMinutes;

  // ── Admin status ────────────────────────────────────────────────────────────
  bool _grantedAdmin = false;

  // Real-time group backend
  StreamSubscription? _groupsSub;
  List<String> _myGroupIds = [];
  List<String> get myGroupIds => _myGroupIds;
  String _studyStatus = 'idle';
  String get studyStatus => _studyStatus;

  /// In-progress focus session (not yet saved). Drives the live Recent list.
  StudySessionModel? _liveSession;
  StudySessionModel? get liveSession => _liveSession;

  /// Persisted in-progress timer (countdown) state, so it survives a restart.
  Map<String, dynamic>? _activeTimer;
  Map<String, dynamic>? get activeTimer => _activeTimer;

  // ── Onboarding / study-profile ──────────────────────────────────────────
  bool _onboardingComplete = false;

  String? profileCourse;
  String? profileStudyTime;
  String? profileGoal;
  List<String> profileStrongSubjects = [];
  List<String> profileWeakSubjects   = [];

  bool get onboardingComplete => _onboardingComplete;

  bool get isAuthenticated => _firebaseService.isSignedIn;

  UserModel get user => _user;
  List<SubjectModel> get subjects => List.unmodifiable(_subjects);
  List<StudySessionModel> get sessions => List.unmodifiable(_sessions);
  List<GroupModel> get groups => List.unmodifiable(_groups);
  String? get selectedSubjectId => _selectedSubjectId;
  int get currentTabIndex => _currentTabIndex;
  bool get isDarkMode => _isDarkMode;
  AppThemeData get appTheme => AppThemeData(isDark: _isDarkMode);

  // ── Timer configuration ─────────────────────────────────────────────────────
  int get focusMinutes => _focusMinutes;
  int get shortBreakMinutes => _shortBreakMinutes;
  int get longBreakMinutes => _longBreakMinutes;
  int get cyclesPerSession => _cycles;
  int get focusSecs => _focusMinutes * 60;
  int get shortBreakSecs => _shortBreakMinutes * 60;
  int get longBreakSecs => _longBreakMinutes * 60;
  int get totalCycles => _cycles;

  // ── Admin status ────────────────────────────────────────────────────────────
  String? get currentEmail => _firebaseService.currentEmail;
  bool get isRootAdmin => AdminConfig.isRootAdmin(currentEmail);
  bool get isAdmin => isRootAdmin || _grantedAdmin;
  bool get hasStatOverrides =>
      _ovrStreak != null ||
      _ovrBestStreak != null ||
      _ovrSessions != null ||
      _ovrStudyMinutes != null;
  int? get overrideStreak => _ovrStreak;
  int? get overrideBestStreak => _ovrBestStreak;
  int? get overrideSessions => _ovrSessions;
  int? get overrideStudyMinutes => _ovrStudyMinutes;

  // ── Focus Lock ──────────────────────────────────────────────────────────────
  Future<void> refreshAppCatalog() async {
    try {
      final apps = await InstalledApps.getInstalledApps(true, true);
      final catalog = apps
          .where((a) => a.packageName != 'com.example.gyan_app')
          .map((a) => AllowedApp(
                package: a.packageName,
                name: a.name,
                iconB64: a.icon != null ? base64Encode(a.icon!) : '',
              ))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      await FocusLockStore.saveCatalog(catalog);
    } catch (_) {}
  }

  SubjectModel? get selectedSubject {
    if (_selectedSubjectId == null) {
      return _subjects.isEmpty ? null : _subjects.first;
    }
    try {
      return _subjects.firstWhere((s) => s.id == _selectedSubjectId);
    } catch (_) {
      return _subjects.isEmpty ? null : _subjects.first;
    }
  }

  List<StudySessionModel> get todaySessions {
    final now = DateTime.now();
    return _sessions
        .where((s) =>
            s.startTime.year == now.year &&
            s.startTime.month == now.month &&
            s.startTime.day == now.day)
        .toList();
  }

  int get todayStudiedSeconds {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return secondsInRange(start, now.add(const Duration(seconds: 1)));
  }

  int get todayStudiedMinutes => todayStudiedSeconds ~/ 60;
  int get todaySessionCount {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return sessionsInRange(start, now.add(const Duration(seconds: 1)));
  }

  List<StudySessionModel> get recentSessions {
    final now = DateTime.now();
    bool isToday(DateTime d) =>
        d.year == now.year && d.month == now.month && d.day == now.day;

    final seen = <String>{};
    final result = <StudySessionModel>[];

    final live = _liveSession;
    if (live != null &&
        live.durationMinutes >= 1 &&
        isToday(live.startTime)) {
      seen.add(live.subjectName.toLowerCase().trim());
      result.add(live);
    }

    for (final s in _sessions.reversed) {
      if (result.length >= 4) break;
      if (!_countsAsSession(s)) continue;
      if (!isToday(s.startTime)) continue;
      final key = s.subjectName.toLowerCase().trim();
      if (seen.contains(key)) continue;
      seen.add(key);
      result.add(s);
    }
    return result;
  }

  // ── Daily activity ────────────────────────────────────────────────────────
  bool didStudyOn(DateTime day) => studiedOnDay(day);

  // ── Streak ────────────────────────────────────────────────────────────────
  // A day counts toward the streak once its TOTAL focus time reaches 10 minutes
  // — summed across every session that day (one long pomodoro, or several short
  // stops), plus the focus phase currently in progress. Counting cumulative
  // seconds (not "one ≥10-min session") is what lets the day flip the moment you
  // cross 10 min even if you pause or leave mid-phase instead of finishing.
  static const int _dayQualifySecs = 600; // 10 min/day

  // The running focus phase isn't written as a session until it completes or is
  // reset, so the timer pushes its in-progress elapsed seconds here (see
  // setLiveFocusSecs). It's pushed back to 0 the instant the focus saves, so the
  // saved session is never double-counted on top of this.
  int _liveFocusSecs = 0;
  DateTime? _liveFocusDay;

  Set<DateTime> get studiedDays {
    final secsByDay = <DateTime, int>{};
    for (final s in _sessions) {
      final d = _dateOnly(s.startTime);
      secsByDay[d] = (secsByDay[d] ?? 0) + s.durationSeconds;
    }
    if (_liveFocusDay != null && _liveFocusSecs > 0) {
      final d = _dateOnly(_liveFocusDay!);
      secsByDay[d] = (secsByDay[d] ?? 0) + _liveFocusSecs;
    }
    final set = <DateTime>{};
    secsByDay.forEach((d, secs) {
      if (secs >= _dayQualifySecs) set.add(d);
    });
    return set;
  }

  int _savedFocusSecsOn(DateTime day) {
    final d = _dateOnly(day);
    var secs = 0;
    for (final s in _sessions) {
      if (_dateOnly(s.startTime) == d) secs += s.durationSeconds;
    }
    return secs;
  }

  /// Fed by the timer with the in-progress focus phase's elapsed seconds (0 when
  /// not focusing). Lets the daily-cumulative streak flip mid-session — covering
  /// a pause or leaving the app — without waiting for the session to be saved.
  void setLiveFocusSecs(int secs) {
    secs = secs < 0 ? 0 : secs;
    final today = _dateOnly(DateTime.now());
    final prev = (_liveFocusDay == today) ? _liveFocusSecs : 0;
    if (_liveFocusDay == today && secs == prev) return;
    final saved = _savedFocusSecsOn(today);
    _liveFocusDay = today;
    _liveFocusSecs = secs;
    // Rebuild listeners only when "studied today" actually flips — not every tick.
    if ((saved + prev >= _dayQualifySecs) != (saved + secs >= _dayQualifySecs)) {
      notifyListeners();
    }
  }

  bool studiedOnDay(DateTime day) => studiedDays.contains(_dateOnly(day));

  bool isStreakDay(DateTime day) {
    final d = _dateOnly(day);
    final ovr = _ovrStreak;
    if (ovr != null) {
      if (ovr <= 0) return false;
      final today = _dateOnly(DateTime.now());
      if (d.isAfter(today)) return false;
      final start = today.subtract(Duration(days: ovr - 1));
      return !d.isBefore(start);
    }
    return studiedDays.contains(d);
  }

  int get totalStudiedDays => studiedDays.length;

  int get currentStreakDays {
    if (_ovrStreak != null) return _ovrStreak!;
    final days = studiedDays;
    if (days.isEmpty) return 0;
    final today = _dateOnly(DateTime.now());
    var cursor = today;
    if (!days.contains(cursor)) {
      cursor = today.subtract(const Duration(days: 1));
      if (!days.contains(cursor)) return 0;
    }
    int streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  int get bestStreakDays {
    if (_ovrBestStreak != null) return _ovrBestStreak!;
    final days = studiedDays.toList()..sort();
    if (days.isEmpty) return 0;
    int best = 1, run = 1;
    for (var i = 1; i < days.length; i++) {
      final gap = days[i].difference(days[i - 1]).inDays;
      if (gap == 1) {
        run++;
      } else if (gap > 1) {
        run = 1;
      }
      if (run > best) best = run;
    }
    return best;
  }

  int minutesStudiedOn(DateTime day) {
    final d = _dateOnly(day);
    return _sessions
        .where((s) => _dateOnly(s.startTime).isAtSameMomentAs(d))
        .fold(0, (sum, s) => sum + s.durationMinutes);
  }

  int minutesForSubjectId(String subjectId) => _sessions
      .where((s) => s.subjectId == subjectId)
      .fold(0, (sum, s) => sum + s.durationMinutes);

  int secondsForSubjectId(String subjectId) => _sessions
      .where((s) => s.subjectId == subjectId)
      .fold(0, (sum, s) => sum + s.durationSeconds);

  List<StudySessionModel> get _statSessions =>
      _liveSession == null ? _sessions : [..._sessions, _liveSession!];

  int secondsInRange(DateTime start, DateTime end) => _statSessions
      .where((s) => !s.startTime.isBefore(start) && s.startTime.isBefore(end))
      .fold(0, (sum, s) => sum + s.durationSeconds);

  bool _countsAsSession(StudySessionModel s) =>
      s.durationMinutes >= 1 || s.completed;

  int sessionsInRange(DateTime start, DateTime end) {
    bool inRange(DateTime d) => !d.isBefore(start) && d.isBefore(end);
    var c = _sessions
        .where((s) => _countsAsSession(s) && inRange(s.startTime))
        .length;
    final live = _liveSession;
    if (live != null && live.durationMinutes >= 1 && inRange(live.startTime)) {
      c++;
    }
    return c;
  }

  Map<String, int> subjectSessionCounts(DateTime start, DateTime end) {
    bool inRange(DateTime d) => !d.isBefore(start) && d.isBefore(end);
    final m = <String, int>{};
    for (final s in _sessions) {
      if (!_countsAsSession(s) || !inRange(s.startTime)) continue;
      m[s.subjectName] = (m[s.subjectName] ?? 0) + 1;
    }
    final live = _liveSession;
    if (live != null && live.durationMinutes >= 1 && inRange(live.startTime)) {
      m[live.subjectName] = (m[live.subjectName] ?? 0) + 1;
    }
    return m;
  }

  int get totalSecondsAllTime =>
      _statSessions.fold(0, (sum, s) => sum + s.durationSeconds);
  int get totalMinutesAllTime => _ovrStudyMinutes ?? (totalSecondsAllTime ~/ 60);
  int get displayTotalSeconds =>
      _ovrStudyMinutes != null ? _ovrStudyMinutes! * 60 : totalSecondsAllTime;
  int get totalSessionsCount =>
      _ovrSessions ?? _sessions.where((s) => s.isQualifying).length;

  List<SubjectTimeStat> subjectStats(DateTime start, DateTime end) {
    final sec = <String, int>{};
    final col = <String, int>{};
    for (final s in _statSessions) {
      if (s.startTime.isBefore(start) || !s.startTime.isBefore(end)) continue;
      sec[s.subjectName] = (sec[s.subjectName] ?? 0) + s.durationSeconds;
      col.putIfAbsent(s.subjectName, () => s.colorIndex);
    }
    final list = sec.entries
        .map((e) => SubjectTimeStat(e.key, col[e.key] ?? 0, e.value))
        .toList()
      ..sort((a, b) => b.seconds.compareTo(a.seconds));
    return list;
  }

  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> init() async {
    await _initBackend();
    await _load();
    await _loadActiveTimer();
    _checkStreakReset();
    _scheduleMidnightRollover();
    notifyListeners();

    _initRemote();
    refreshAppCatalog();
  }

  Future<void> _initRemote() async {
    if (!_remoteBackendReady) return;
    try {
      await _loadRemoteData();
    } catch (_) {}
    try {
      await _loadAdminStatus();
    } catch (_) {}
    _subscribeGroups();
    _firebaseService.ensureEmailIndex();
    _firebaseService.touchPresence();
    PushService.instance.init();
    // ── Schedule local notifications based on the loaded user profile ──
    LocalNotificationService.instance.scheduleAll(_user.studyTime); // ← NEW
    notifyListeners();
  }

  Future<void> _loadAdminStatus() async {
    final uid = _firebaseService.currentUser?.uid;
    if (uid == null) {
      _grantedAdmin = false;
      return;
    }
    _grantedAdmin = await _firebaseService.isAdminUid(uid);
  }

  // ── Real-time group backend ───────────────────────────────────────────────
  void _subscribeGroups() {
    _groupsSub?.cancel();
    _groupsSub = _firebaseService.myGroupsStream().listen((groups) {
      _myGroupIds = groups.map((g) => g['id'] as String).toList();
      _publishToGroups();
    });
  }

  String? get currentUid => _firebaseService.currentUser?.uid;

  Stream<int> unreadNotificationsStream() =>
      _firebaseService.unreadCountStream();
  Future<void> markNotificationsSeen() =>
      _firebaseService.markAllNotificationsSeen();

  List<String> get avatarOptions => kAvatarAssets;

  Future<void> setProfileAvatar(String assetPath) =>
      updateUser(profileImagePath: assetPath);

  Stream<List<Map<String, dynamic>>> notificationsStream() =>
      _firebaseService.notificationsStream();
  Stream<List<Map<String, dynamic>>> myGroupsStream() =>
      _firebaseService.myGroupsStream();
  Stream<List<Map<String, dynamic>>> groupMembersStream(String groupId) =>
      _firebaseService.groupMembersStream(groupId);
  Stream<Map<String, dynamic>?> groupStream(String groupId) =>
      _firebaseService.groupStream(groupId);
  Future<void> updateGroupInfo(
    String groupId,
    String name,
    String description, {
    bool isPublic = true,
    List<String> subjects = const [],
  }) =>
      _firebaseService.updateGroupInfo(
        groupId,
        name.trim(),
        description.trim(),
        isPublic: isPublic,
        subjects: subjects,
      );
  Future<Map<String, dynamic>?> fetchUserProfile(String uid) =>
      _firebaseService.fetchUserProfile(uid);
  Future<void> sendStudyReminder(String toUid) =>
      _firebaseService.sendStudyReminder(toUid);

  Future<String> createGroupRemote(
    String name, {
    String description = '',
    bool isPublic = true,
    List<String> subjects = const [],
  }) async {
    if (!_remoteBackendReady) return 'error';
    try {
      if (!isAdmin && await _firebaseService.ownedGroupCount() >= 5) {
        return 'limit';
      }
      await _firebaseService.createGroup(
        name.trim(),
        totalSecondsAllTime,
        description: description,
        isPublic: isPublic,
        subjects: subjects,
      );
      return 'ok';
    } catch (_) {
      return 'error';
    }
  }

  Future<void> joinGroupRemote(String groupId) async {
    if (!_remoteBackendReady) return;
    try {
      await _firebaseService.joinGroup(groupId, totalSecondsAllTime);
      _publishToGroups();
    } catch (_) {}
  }

  Stream<List<Map<String, dynamic>>> publicGroupsStream() {
    return FirebaseFirestore.instance
        .collection('study_groups')
        .where('isPublic', isEqualTo: true)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  Future<String> inviteByEmail(
      String groupId, String groupName, String email) async {
    if (!_remoteBackendReady) return 'error';
    try {
      return await _firebaseService.inviteByEmail(groupId, groupName, email);
    } catch (_) {
      return 'error';
    }
  }

  Future<void> acceptInvite(String notifId, String groupId) async {
    try {
      await _firebaseService.acceptInvite(notifId, groupId, totalSecondsAllTime);
    } catch (_) {}
  }

  void setStudyStatus(String s) {
    if (_studyStatus == s) return;
    _studyStatus = s;
    _publishToGroups();
  }

  Future<void> declineInvite(String notifId) =>
      _firebaseService.declineInvite(notifId);
  Future<void> dismissNotification(String notifId) =>
      _firebaseService.dismissNotification(notifId);
  Future<void> leaveGroupRemote(String groupId) =>
      _firebaseService.leaveGroup(groupId);
  Future<void> deleteGroupRemote(String groupId) =>
      _firebaseService.deleteGroup(groupId);
  Future<void> kickMember(String groupId, String memberUid) =>
      _firebaseService.kickMember(groupId, memberUid);

  void forcePublishToGroups() => _publishToGroups();

  void _publishToGroups() {
    if (!_remoteBackendReady || _myGroupIds.isEmpty) return;
    final now = DateTime.now();
    final weekStart =
        DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    final studyingNow = _studyStatus == 'studying';
    final live = _liveSession;
    final liveSecs = (studyingNow && live != null) ? live.durationSeconds : 0;
    final liveStartMs = (studyingNow && live != null)
        ? now.millisecondsSinceEpoch - liveSecs * 1000
        : 0;
    final daily = math.max(0, todayStudiedSeconds - liveSecs);
    final week = math.max(
        0, secondsInRange(weekStart, now.add(const Duration(seconds: 1))) - liveSecs);
    final total = math.max(0, totalSecondsAllTime - liveSecs);
    for (final gid in _myGroupIds) {
      _firebaseService.publishStats(
        gid,
        dailySeconds: daily,
        weekSeconds: week,
        totalSeconds: total,
        liveStartMs: liveStartMs,
        studying: studyingNow,
        status: _studyStatus,
      );
    }
  }

  // ── Active timer persistence ───────────────────────────────────────────────
  static const String _kActiveTimer = 'active_timer';

  Future<void> _loadActiveTimer() async {
    final p = await _prefs;
    final raw = p.getString(_kActiveTimer);
    if (raw == null) return;
    try {
      final m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final subId = m['subjectId'] as String?;
      if (subId == null || !_subjects.any((s) => s.id == subId)) {
        await p.remove(_kActiveTimer);
        return;
      }
      _activeTimer = m;
      _selectedSubjectId = subId;
      _rebuildLiveFromActive();
    } catch (_) {
      _activeTimer = null;
      await p.remove(_kActiveTimer);
    }
  }

  Future<void> _persistActiveTimer() async {
    final p = await _prefs;
    if (_activeTimer == null) {
      await p.remove(_kActiveTimer);
    } else {
      await p.setString(_kActiveTimer, jsonEncode(_activeTimer));
    }
  }

  void _rebuildLiveFromActive() {
    final m = _activeTimer;
    final phaseIndex = (m?['phaseIndex'] as int?) ?? 0;
    final startMs = m?['sessionStartMs'] as int?;
    final elapsed = (m?['elapsedSeconds'] as int?) ?? 0;
    if (m != null && phaseIndex == 0 && startMs != null) {
      _liveSession = StudySessionModel(
        id: 'live',
        subjectId: m['subjectId'] as String,
        subjectName: (m['subjectName'] as String?) ?? '',
        colorIndex: (m['colorIndex'] as int?) ?? 0,
        durationMinutes: elapsed ~/ 60,
        durationSeconds: elapsed,
        startTime: DateTime.fromMillisecondsSinceEpoch(startMs),
        endTime: DateTime.now(),
      );
    } else {
      _liveSession = null;
    }
  }

  void _scheduleMidnightRollover() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    _midnightTimer = Timer(nextMidnight.difference(now), () {
      _checkStreakReset();
      notifyListeners();
      _scheduleMidnightRollover();
    });
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    _groupsSub?.cancel();
    super.dispose();
  }

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<void> _initBackend() async {
    try {
      await _firebaseService.init();
      _remoteBackendReady = _firebaseService.isSignedIn;
    } catch (_) {
      _remoteBackendReady = false;
    }
  }

  Future<void> _loadRemoteData() async {
    if (!_remoteBackendReady) return;
    try {
      final firebaseData = await _firebaseService.loadAppState();
      if (firebaseData == null) return;

      final remoteUser = firebaseData['user'];
      if (remoteUser is Map<String, dynamic>) {
        _user = UserModel.fromJson(remoteUser);
      }

      final subjectsRemote = firebaseData['subjects'];
      if (subjectsRemote is List) {
        _subjects = subjectsRemote
            .map((e) => SubjectModel.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }

      final sessionsRemote = firebaseData['sessions'];
      if (sessionsRemote is List) {
        _sessions = sessionsRemote
            .map((e) => StudySessionModel.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }

      final groupsRemote = firebaseData['groups'];
      if (groupsRemote is List) {
        _groups = groupsRemote
            .map((e) => GroupModel.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }

      if (_subjects.isNotEmpty && _selectedSubjectId == null) {
        _selectedSubjectId = _subjects.first.id;
      }

      await _saveLocalState();
    } catch (_) {}
  }

  Future<void> _saveLocalState() async {
    await _saveUser();
    await _saveSubjects();
    await _saveSessions();
    await _saveGroups();
  }

  Future<void> _syncToFirestore() async {
    if (!_remoteBackendReady) return;
    try {
      await _firebaseService.saveAppState(
        user: _user.toJson(),
        subjects: _subjects.map((s) => s.toJson()).toList(),
        sessions: _sessions.map((s) => s.toJson()).toList(),
        groups: _groups.map((g) => g.toJson()).toList(),
        isDarkMode: _isDarkMode,
      );
    } catch (_) {}
  }

  // ── Auth ──────────────────────────────────────────────────────────────────
  Future<bool> signIn({
    required String usernameOrEmail,
    required String password,
  }) async {
    try {
      await _firebaseService.init();
      final email = usernameOrEmail.contains('@')
          ? usernameOrEmail.trim()
          : await _firebaseService.emailForUsername(usernameOrEmail.trim());

      if (email == null || email.isEmpty) return false;
      await _firebaseService.signInWithEmail(email, password);

      final verified = _firebaseService.currentUser?.emailVerified ?? false;
      if (!verified) {
        await _firebaseService.signOut();
        return false;
      }

      _remoteBackendReady = true;
      await _loadRemoteData();
      await _syncToFirestore();
      _subscribeGroups();
      _firebaseService.ensureEmailIndex();
      await _loadAdminStatus();
      _firebaseService.touchPresence();
      PushService.instance.init();
      // ── Schedule notifications on sign-in with loaded study time ──
      LocalNotificationService.instance.scheduleAll(_user.studyTime); // ← NEW
      notifyListeners();
      return true;
    } catch (e) {
      print('SignIn error: $e');
      return false;
    }
  }

  Future<bool> register({
    required String email,
    required String username,
    required String password,
  }) async {
    try {
      await _firebaseService.init();
      final credential = await _firebaseService.registerWithEmail(email, password);

      _user.email = email.trim();
      _user.name  = username.trim().isEmpty ? _user.name : username.trim();
      await _saveLocalState();

      final uid = credential.user?.uid;
      if (uid != null) {
        await _firebaseService.saveAppStateForUid(
          uid: uid,
          user: _user.toJson(),
          isDarkMode: _isDarkMode,
        );
      }

      notifyListeners();
      return true;
    } catch (e) {
      print('Register error: $e');
      return false;
    }
  }

  Future<void> signOutUser() async {
    // Cancel scheduled notifications before clearing the token ── NEW
    await LocalNotificationService.instance.cancelAll(); // ← NEW
    await PushService.instance.clearToken();
    try {
      await _firebaseService.signOut();
    } catch (_) {}
    _groupsSub?.cancel();
    _groupsSub = null;
    _myGroupIds = [];
    _studyStatus = 'idle';
    _remoteBackendReady = false;

    _user = UserModel();
    _subjects = [];
    _sessions = [];
    _groups = [];
    _liveSession = null;
    _activeTimer = null;
    _selectedSubjectId = null;

    _grantedAdmin = false;
    _focusMinutes = 25;
    _shortBreakMinutes = 5;
    _longBreakMinutes = 15;
    _cycles = 4;
    _ovrStreak = _ovrBestStreak = _ovrSessions = _ovrStudyMinutes = null;

    try {
      final p = await _prefs;
      await p.remove('user');
      await p.remove('subjects');
      await p.remove('sessions');
      await p.remove('groups');
      await p.remove('active_timer');
      await p.remove('cfg_focus');
      await p.remove('cfg_short');
      await p.remove('cfg_long');
      await p.remove('cfg_cycles');
      await p.remove('ovr_streak');
      await p.remove('ovr_best');
      await p.remove('ovr_sessions');
      await p.remove('ovr_minutes');
    } catch (_) {}

    notifyListeners();
  }

  // ── Local persistence ────────────────────────────────────────────────────
  Future<void> _load() async {
    final p = await _prefs;

    final userRaw = p.getString('user');
    if (userRaw != null) _user = UserModel.fromJson(jsonDecode(userRaw));

    final subjectsRaw = p.getString('subjects');
    if (subjectsRaw != null) {
      _subjects = (jsonDecode(subjectsRaw) as List)
          .map((e) => SubjectModel.fromJson(e))
          .toList();
    }

    final sessionsRaw = p.getString('sessions');
    if (sessionsRaw != null) {
      _sessions = (jsonDecode(sessionsRaw) as List)
          .map((e) => StudySessionModel.fromJson(e))
          .toList();
    }

    final groupsRaw = p.getString('groups');
    if (groupsRaw != null) {
      _groups = (jsonDecode(groupsRaw) as List)
          .map((e) => GroupModel.fromJson(e))
          .toList();
    }

    _isDarkMode = p.getBool('isDarkMode') ?? false;
    if (_subjects.isNotEmpty) _selectedSubjectId = _subjects.first.id;

    _focusMinutes = p.getInt('cfg_focus') ?? 25;
    _shortBreakMinutes = p.getInt('cfg_short') ?? 5;
    _longBreakMinutes = p.getInt('cfg_long') ?? 15;
    _cycles = p.getInt('cfg_cycles') ?? 4;
    _ovrStreak = p.getInt('ovr_streak');
    _ovrBestStreak = p.getInt('ovr_best');
    _ovrSessions = p.getInt('ovr_sessions');
    _ovrStudyMinutes = p.getInt('ovr_minutes');

    _onboardingComplete = p.getBool('onboarding_complete') ?? false;
    profileCourse        = p.getString('profile_course');
    profileStudyTime     = p.getString('profile_studyTime');
    profileGoal          = p.getString('profile_goal');
    profileStrongSubjects = p.getStringList('profile_strong') ?? [];
    profileWeakSubjects   = p.getStringList('profile_weak')   ?? [];
  }

  Future<void> _saveUser() async =>
      (await _prefs).setString('user', jsonEncode(_user.toJson()));
  Future<void> _saveSubjects() async => (await _prefs).setString(
      'subjects', jsonEncode(_subjects.map((s) => s.toJson()).toList()));
  Future<void> _saveSessions() async => (await _prefs).setString(
      'sessions', jsonEncode(_sessions.map((s) => s.toJson()).toList()));
  Future<void> _saveGroups() async => (await _prefs).setString(
      'groups', jsonEncode(_groups.map((g) => g.toJson()).toList()));

  void _checkStreakReset() {
    if (_user.lastSessionDate == null) return;
    final today = _dateOnly(DateTime.now());
    final last  = _dateOnly(_user.lastSessionDate!);
    if (today.difference(last).inDays > 1) {
      _user.currentStreak = 0;
      _saveUser();
    }
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  // ── Settings ──────────────────────────────────────────────────────────────
  Future<void> setDarkMode(bool value) async {
    _isDarkMode = value;
    (await _prefs).setBool('isDarkMode', value);
    await _syncToFirestore();
    notifyListeners();
  }

  // ── Admin: timer configuration ──────────────────────────────────────────────
  Future<void> setTimerConfig({
    int? focusMinutes,
    int? shortBreakMinutes,
    int? longBreakMinutes,
    int? cycles,
  }) async {
    if (focusMinutes != null) _focusMinutes = focusMinutes.clamp(1, 180);
    if (shortBreakMinutes != null) {
      _shortBreakMinutes = shortBreakMinutes.clamp(1, 120);
    }
    if (longBreakMinutes != null) _longBreakMinutes = longBreakMinutes.clamp(1, 180);
    if (cycles != null) _cycles = cycles.clamp(1, 12);
    final p = await _prefs;
    await p.setInt('cfg_focus', _focusMinutes);
    await p.setInt('cfg_short', _shortBreakMinutes);
    await p.setInt('cfg_long', _longBreakMinutes);
    await p.setInt('cfg_cycles', _cycles);
    notifyListeners();
  }

  Future<void> resetTimerConfig() => setTimerConfig(
      focusMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15, cycles: 4);

  // ── Admin: headline stat overrides ──────────────────────────────────────────
  Future<void> adminSetStatOverrides({
    int? streak,
    int? bestStreak,
    int? sessions,
    int? studyMinutes,
  }) async {
    _ovrStreak = streak;
    _ovrBestStreak = bestStreak;
    _ovrSessions = sessions;
    _ovrStudyMinutes = studyMinutes;
    final p = await _prefs;
    Future<void> put(String k, int? v) =>
        v == null ? p.remove(k) : p.setInt(k, v);
    await put('ovr_streak', _ovrStreak);
    await put('ovr_best', _ovrBestStreak);
    await put('ovr_sessions', _ovrSessions);
    await put('ovr_minutes', _ovrStudyMinutes);
    notifyListeners();
    _publishToGroups();
  }

  Future<void> clearStatOverrides() => adminSetStatOverrides();

  // ── Admin: aggregate metrics & grants ────────────────────────────────────────
  Future<int> registeredUserCount() => _firebaseService.registeredUserCount();
  Future<int> activeUserCount() => _firebaseService.activeUserCount();
  Future<int> paidUserCount() => _firebaseService.paidUserCount();
  Future<Map<String, int>?> purgeDeletedUsers() =>
      _firebaseService.purgeDeletedUsers();
  Future<String> grantAdminByEmail(String email) =>
      _firebaseService.grantAdminByEmail(email);
  Future<String> sendStudyReminderByEmail(String email) =>
      _firebaseService.sendStudyReminderByEmail(email);
  Future<void> revokeAdmin(String uid) => _firebaseService.revokeAdmin(uid);
  Stream<List<Map<String, dynamic>>> adminsStream() =>
      _firebaseService.adminsStream();

  void switchTab(int index) {
    _currentTabIndex = index;
    notifyListeners();
  }

  // ── User update (called by GetStartedPage & ProfileScreen) ────────────────
  Future<void> updateUser({
    String? name,
    String? grade,
    int? dailyStudyGoalHours,
    String? profileImagePath,
    String? studyTime,
    String? studyGoal,
    List<String>? strongSubjects,
    List<String>? weakSubjects,
  }) async {
    if (name != null)                _user.name = name;
    if (grade != null)               _user.grade = grade;
    if (dailyStudyGoalHours != null) _user.dailyStudyGoalHours = dailyStudyGoalHours;
<<<<<<< HEAD
<<<<<<< HEAD
    if (profileImagePath != null)   _user.profileImagePath = profileImagePath;
    if (studyTime != null)          _user.studyTime = studyTime;
    if (studyGoal != null)          _user.studyGoal = studyGoal;
=======
    if (profileImagePath != null)    _user.profileImagePath = profileImagePath;
    if (studyTime != null)           _user.studyTime = studyTime;
    if (studyGoal != null)           _user.studyGoal = studyGoal;
>>>>>>> df487c82a070bc50041db46059ed4168141aeef8
    if (strongSubjects != null) {
      _user.strongSubjects = strongSubjects;
      // Can't keep offering help in a subject you no longer mark as strong.
      _user.helpSubjects =
          _user.helpSubjects.where(strongSubjects.contains).toList();
    }
<<<<<<< HEAD
    if (weakSubjects != null)       _user.weakSubjects = weakSubjects;
=======
    if (weakSubjects != null)        _user.weakSubjects = weakSubjects;
>>>>>>> df487c82a070bc50041db46059ed4168141aeef8
    await _saveUser();
    await _syncToFirestore();
    // Keep the top-level helper-search mirror fresh when grade/subjects change.
    if (_user.helpSubjects.isNotEmpty) {
      await _firebaseService.publishHelperProfile(
          grade: _user.grade, helpSubjects: _user.helpSubjects);
    }
<<<<<<< HEAD
=======
    // Re-schedule local study-time notifications when the preferred time changes.
    if (studyTime != null) {
      LocalNotificationService.instance.scheduleAll(_user.studyTime);
    }
>>>>>>> df487c82a070bc50041db46059ed4168141aeef8
    notifyListeners();
  }

  // ── Study Buddy (peer-help opt-in) ─────────────────────────────────────────
  /// True if the user has opted in to help peers in at least one subject.
  bool get isStudyBuddy => _user.helpSubjects.isNotEmpty;
  List<String> get helpSubjects => List.unmodifiable(_user.helpSubjects);

  /// Opt in/out of being a Study Buddy. [subjects] defaults to all of the
  /// user's strong subjects (and is always intersected with them — you can only
  /// help in subjects you're strong in). Persists locally + to Firestore and
  /// mirrors the top-level matchGrade/helpSubjects fields the helper search uses.
  Future<void> setStudyBuddy(bool enabled, {List<String>? subjects}) async {
    _user.helpSubjects = enabled
        ? (subjects ?? List<String>.from(_user.strongSubjects))
            .where(_user.strongSubjects.contains)
            .toList()
        : <String>[];
    await _saveUser();
    await _syncToFirestore();
    await _firebaseService.publishHelperProfile(
        grade: _user.grade, helpSubjects: _user.helpSubjects);
<<<<<<< HEAD
=======
    if (profileImagePath != null)    _user.profileImagePath = profileImagePath;
    if (studyTime != null)           _user.studyTime = studyTime;
    if (studyGoal != null)           _user.studyGoal = studyGoal;
    if (strongSubjects != null)      _user.strongSubjects = strongSubjects;
    if (weakSubjects != null)        _user.weakSubjects = weakSubjects;
    await _saveUser();
    await _syncToFirestore();
    // ── Re-schedule notifications if study time changed ──
    if (studyTime != null) {
      LocalNotificationService.instance.scheduleAll(_user.studyTime); // ← NEW
    }
>>>>>>> 06e72ee (Add daily study reminders and streak nudge notifications)
=======
>>>>>>> df487c82a070bc50041db46059ed4168141aeef8
    notifyListeners();
  }

  // ── Sessions ──────────────────────────────────────────────────────────────
  Future<void> addSession(StudySessionModel session) async {
    _sessions.add(session);
    final idx = _subjects.indexWhere((s) => s.id == session.subjectId);
    if (idx != -1) {
      _subjects[idx].totalMinutes += session.durationMinutes;
      await _saveSubjects();
    }
    if (session.isQualifying) {
      _user.totalSessions++;
      _user.totalMinutesStudied += session.durationMinutes;
      final today    = _dateOnly(DateTime.now());
      final lastDate = _user.lastSessionDate != null
          ? _dateOnly(_user.lastSessionDate!)
          : null;
      if (lastDate == null) {
        _user.currentStreak = 1;
      } else if (today.difference(lastDate).inDays == 1) {
        _user.currentStreak++;
      } else if (today.difference(lastDate).inDays > 1) {
        _user.currentStreak = 1;
      }
      _user.lastSessionDate = DateTime.now();
      if (_user.currentStreak > _user.bestStreak) {
        _user.bestStreak = _user.currentStreak;
      }
      await _saveUser();
    }
    await _saveSessions();
    await _syncToFirestore();
    notifyListeners();
    _publishToGroups();
  }

  // ── Subjects ──────────────────────────────────────────────────────────────
  Future<void> addSubject(String name, int colorIndex) async {
    final sub = SubjectModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        colorIndex: colorIndex);
    _subjects.add(sub);
    _selectedSubjectId ??= sub.id;
    await _saveSubjects();
    await _syncToFirestore();
    notifyListeners();
  }

  Future<void> removeSubject(String id) async {
    _subjects.removeWhere((s) => s.id == id);
    if (_selectedSubjectId == id) {
      _selectedSubjectId = _subjects.isNotEmpty ? _subjects.first.id : null;
    }
    await _saveSubjects();
    await _syncToFirestore();
    notifyListeners();
  }

  void selectSubject(String id) {
    _selectedSubjectId = id;
    notifyListeners();
  }

  // ── Active (in-progress) timer ─────────────────────────────────────────────
  void saveActiveTimer({
    required String subjectId,
    required String subjectName,
    required int colorIndex,
    required int remainingSecs,
    required int phaseIndex,
    required int currentCycle,
    required DateTime? sessionStart,
    required int elapsedSeconds,
  }) {
    _activeTimer = {
      'subjectId': subjectId,
      'subjectName': subjectName,
      'colorIndex': colorIndex,
      'remainingSecs': remainingSecs,
      'phaseIndex': phaseIndex,
      'currentCycle': currentCycle,
      'sessionStartMs': sessionStart?.millisecondsSinceEpoch,
      'elapsedSeconds': elapsedSeconds,
    };
    _persistActiveTimer();

    String? key(StudySessionModel? l) =>
        l == null ? null : '${l.subjectId}:${l.durationMinutes}';
    final before = key(_liveSession);
    _rebuildLiveFromActive();
    notifyListeners();
    if (key(_liveSession) != before) {
      _publishToGroups();
    }
  }

  void pushLiveProgress({
    required String subjectId,
    required String subjectName,
    required int colorIndex,
    required int remainingSecs,
    required int phaseIndex,
    required int currentCycle,
    required DateTime? sessionStart,
    required int elapsedSeconds,
    required String status,
  }) {
    _activeTimer = {
      'subjectId': subjectId,
      'subjectName': subjectName,
      'colorIndex': colorIndex,
      'remainingSecs': remainingSecs,
      'phaseIndex': phaseIndex,
      'currentCycle': currentCycle,
      'sessionStartMs': sessionStart?.millisecondsSinceEpoch,
      'elapsedSeconds': elapsedSeconds,
    };
    _persistActiveTimer();
    _rebuildLiveFromActive();
    _studyStatus = status;
    notifyListeners();
    _publishToGroups();
  }

  void clearActiveTimer() {
    final hadLive = _liveSession != null;
    _activeTimer = null;
    _liveSession = null;
    _persistActiveTimer();
    if (hadLive) notifyListeners();
    _publishToGroups();
  }

  Future<void> openSubjectFromSession(StudySessionModel s) async {
    final wanted = s.subjectName.toLowerCase().trim();
    SubjectModel? match;
    for (final sub in _subjects) {
      if (sub.name.toLowerCase().trim() == wanted) {
        match = sub;
        break;
      }
    }
    if (match == null) {
      final created = SubjectModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: s.subjectName,
        colorIndex: s.colorIndex,
      );
      _subjects.add(created);
      match = created;
      await _saveSubjects();
      await _syncToFirestore();
    }
    _selectedSubjectId = match.id;
    _currentTabIndex = 1;
    notifyListeners();
  }

  // ── Groups ────────────────────────────────────────────────────────────────
  Future<void> addGroup(String name) async {
    _groups.add(GroupModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(), name: name));
    await _saveGroups();
    await _syncToFirestore();
    notifyListeners();
  }

  Future<void> removeGroup(String id) async {
    _groups.removeWhere((g) => g.id == id);
    await _saveGroups();
    await _syncToFirestore();
    notifyListeners();
  }

  Future<void> addMemberToGroup(String groupId, String email) async {
    final g = _groups.firstWhere((g) => g.id == groupId);
    if (!g.memberEmails.contains(email)) g.memberEmails.add(email);
    await _saveGroups();
    notifyListeners();
  }

  // ── Analytics ─────────────────────────────────────────────────────────────
  Map<String, int> studyTimePerSubject(DateTime start, DateTime end) {
    final result = <String, int>{};
    for (final s in _sessions) {
      if (s.startTime.isAfter(start) && s.startTime.isBefore(end)) {
        result[s.subjectId] = (result[s.subjectId] ?? 0) + s.durationMinutes;
      }
    }
    return result;
  }
}

/// A subject's accumulated study time (seconds) for a stats breakdown.
class SubjectTimeStat {
  final String name;
  final int colorIndex;
  final int seconds;
  const SubjectTimeStat(this.name, this.colorIndex, this.seconds);
}