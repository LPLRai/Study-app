// ─────────────────────────────────────────────────────────────────────────────
// providers/app_provider.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/avatars.dart';
import '../models/user_model.dart';
import '../models/subject_model.dart';
import '../models/study_session_model.dart';
import '../models/group_model.dart';
import '../services/firebase_service.dart';
import '../services/push_service.dart';
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
  // Defaults are the classic Pomodoro. Normal users never see an editor, so
  // their experience is unchanged. Reset on sign-out so a shared device never
  // leaks an admin's custom timings to the next account.
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
  // Root admins come from AdminConfig (verified email); granted admins are
  // loaded from Firestore at init.
  bool _grantedAdmin = false;

  // Real-time group backend
  StreamSubscription? _groupsSub;
  List<String> _myGroupIds = [];
  // studying | paused | short_break | long_break | idle — shown to group members
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

  /// Extra profile fields saved from GetStartedPage
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

  // Today's studied time, precise (seconds) → minutes for display.
  int get todayStudiedMinutes => todayStudiedSeconds ~/ 60;
  // Counts sessions of ≥1 min (incl. the in-progress one) so it updates in
  // real time as soon as you study, not only after a 10-min qualifying block.
  int get todaySessionCount {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return sessionsInRange(start, now.add(const Duration(seconds: 1)));
  }

  /// TODAY's most recently studied DISTINCT subjects (max 4), newest first.
  /// Resets automatically at midnight (only today's sessions are considered),
  /// de-duplicated by subject name so the same subject never appears twice.
  /// Includes the in-progress (live) session once it has logged ≥1 minute, so
  /// the list and its timings update in real time while studying.
  List<StudySessionModel> get recentSessions {
    final now = DateTime.now();
    bool isToday(DateTime d) =>
        d.year == now.year && d.month == now.month && d.day == now.day;

    final seen = <String>{};
    final result = <StudySessionModel>[];

    // Live, in-progress session first (visible after the first minute).
    final live = _liveSession;
    if (live != null &&
        live.durationMinutes >= 1 &&
        isToday(live.startTime)) {
      seen.add(live.subjectName.toLowerCase().trim());
      result.add(live);
    }

    for (final s in _sessions.reversed) {
      if (result.length >= 4) break;
      if (s.durationMinutes < 1) continue;
      if (!isToday(s.startTime)) continue;
      final key = s.subjectName.toLowerCase().trim();
      if (seen.contains(key)) continue;
      seen.add(key);
      result.add(s);
    }
    return result;
  }

  // ── Daily activity (for the streak week view & mini chart) ────────────────
  /// Whether the user logged a qualifying (≥10 min) session on [day].
  bool didStudyOn(DateTime day) {
    final d = _dateOnly(day);
    return _sessions
        .any((s) => s.isQualifying && _dateOnly(s.startTime).isAtSameMomentAs(d));
  }

  // ── Streak — derived from sessions so it's always accurate ────────────────
  /// Distinct days (midnight) with a qualifying (≥10 min) session.
  Set<DateTime> get studiedDays {
    final set = <DateTime>{};
    for (final s in _sessions) {
      if (s.isQualifying) set.add(_dateOnly(s.startTime));
    }
    return set;
  }

  bool studiedOnDay(DateTime day) => studiedDays.contains(_dateOnly(day));

  /// Whether [day] should appear as a "fire" streak day in the calendars.
  /// With an admin streak override active, the current streak is exactly the
  /// last N days ending today; otherwise it's the real qualifying-session days.
  /// (Best streak is unaffected — only the current-streak window lights up.)
  bool isStreakDay(DateTime day) {
    final d = _dateOnly(day);
    final ovr = _ovrStreak;
    if (ovr != null) {
      if (ovr <= 0) return false;
      final today = _dateOnly(DateTime.now());
      if (d.isAfter(today)) return false;
      final start = today.subtract(Duration(days: ovr - 1));
      return !d.isBefore(start); // within [start, today]
    }
    return studiedDays.contains(d);
  }

  int get totalStudiedDays => studiedDays.length;

  /// Consecutive studied days ending today (or yesterday if today isn't done
  /// yet — the streak is still alive until the day ends).
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

  /// Longest run of consecutive studied days, ever.
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

  /// Total minutes studied on [day] across all sessions.
  int minutesStudiedOn(DateTime day) {
    final d = _dateOnly(day);
    return _sessions
        .where((s) => _dateOnly(s.startTime).isAtSameMomentAs(d))
        .fold(0, (sum, s) => sum + s.durationMinutes);
  }

  /// All-time minutes studied for a subject, derived from saved sessions so the
  /// value stays consistent with statistics everywhere it is displayed.
  int minutesForSubjectId(String subjectId) => _sessions
      .where((s) => s.subjectId == subjectId)
      .fold(0, (sum, s) => sum + s.durationMinutes);

  /// All-time SECONDS studied for a subject (precise), from saved sessions.
  int secondsForSubjectId(String subjectId) => _sessions
      .where((s) => s.subjectId == subjectId)
      .fold(0, (sum, s) => sum + s.durationSeconds);

  // ── Aggregate statistics — all derived from saved sessions so every screen
  //    shows the same, accurate numbers. [end] is exclusive. ────────────────
  //
  // Time totals include the in-progress (live) session so stats update in real
  // time while studying; session COUNTS use only completed sessions.
  List<StudySessionModel> get _statSessions =>
      _liveSession == null ? _sessions : [..._sessions, _liveSession!];

  int secondsInRange(DateTime start, DateTime end) => _statSessions
      .where((s) => !s.startTime.isBefore(start) && s.startTime.isBefore(end))
      .fold(0, (sum, s) => sum + s.durationSeconds);

  // A "session" counts once it has ≥1 min of focus; includes the live session
  // so the count updates in real time while studying.
  int sessionsInRange(DateTime start, DateTime end) {
    bool inRange(DateTime d) => !d.isBefore(start) && d.isBefore(end);
    var c = _sessions
        .where((s) => s.durationMinutes >= 1 && inRange(s.startTime))
        .length;
    final live = _liveSession;
    if (live != null && live.durationMinutes >= 1 && inRange(live.startTime)) {
      c++;
    }
    return c;
  }

  /// Session counts per subject name (≥1 min, incl. live) within [start, end).
  Map<String, int> subjectSessionCounts(DateTime start, DateTime end) {
    bool inRange(DateTime d) => !d.isBefore(start) && d.isBefore(end);
    final m = <String, int>{};
    for (final s in _sessions) {
      if (s.durationMinutes < 1 || !inRange(s.startTime)) continue;
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
  /// All-time seconds for HEADLINE displays (honours the admin override). The
  /// per-subject / per-day data used by graphs always uses the real values, so
  /// charts are never distorted by an override.
  int get displayTotalSeconds =>
      _ovrStudyMinutes != null ? _ovrStudyMinutes! * 60 : totalSecondsAllTime;
  int get totalSessionsCount =>
      _ovrSessions ?? _sessions.where((s) => s.isQualifying).length;

  /// Per-subject totals (merged by name) within [start, end), sorted desc.
  /// Includes the live session, so the breakdown updates in real time.
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
    if (_remoteBackendReady) {
      await _loadRemoteData();
    }
    await _loadActiveTimer();
    _checkStreakReset();
    _scheduleMidnightRollover();
    if (_remoteBackendReady) {
      _subscribeGroups();
      _firebaseService.ensureEmailIndex(); // make me findable by email
      await _loadAdminStatus(); // load granted-admin flag for this account
      _firebaseService.touchPresence(); // heartbeat for the active-users metric
      PushService.instance.init(); // register for push notifications
    }
    notifyListeners();
  }

  /// Loads whether the signed-in account has been granted admin in Firestore.
  /// (Root admins are determined purely by their verified email via AdminConfig.)
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
      _publishToGroups(); // push current stats to any new groups
    });
  }

  String? get currentUid => _firebaseService.currentUser?.uid;

  Stream<int> unreadNotificationsStream() =>
      _firebaseService.unreadCountStream();
  Future<void> markNotificationsSeen() =>
      _firebaseService.markAllNotificationsSeen();

  // ── Curated avatars (developer-provided, bundled with the app) ────────────
  // No backend / Firebase Storage needed — the choices live in
  // constants/avatars.dart and ship as app assets.
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
          String groupId, String name, String description) =>
      _firebaseService.updateGroupInfo(groupId, name.trim(), description.trim());
  Future<Map<String, dynamic>?> fetchUserProfile(String uid) =>
      _firebaseService.fetchUserProfile(uid);
  Future<void> sendStudyReminder(String toUid) =>
      _firebaseService.sendStudyReminder(toUid);

  /// Creates a group (max 5 owned). Returns 'ok', 'limit', or 'error'.
  Future<String> createGroupRemote(String name, {String description = ''}) async {
    if (!_remoteBackendReady) return 'error';
    try {
      if (!isAdmin && await _firebaseService.ownedGroupCount() >= 5) {
        return 'limit';
      }
      await _firebaseService.createGroup(name.trim(), totalSecondsAllTime, description: description);
      return 'ok';
    } catch (_) {
      return 'error';
    }
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

  /// Called by the Timer screen as its state changes; republishes to groups.
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

  /// Pushes the current user's study stats to every group they're in.
  void _publishToGroups() {
    if (!_remoteBackendReady || _myGroupIds.isEmpty) return;
    final now = DateTime.now();
    final weekStart =
        DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    final daily = todayStudiedSeconds;
    final week = secondsInRange(weekStart, now.add(const Duration(seconds: 1)));
    final total = totalSecondsAllTime;
    for (final gid in _myGroupIds) {
      _firebaseService.publishStats(
        gid,
        dailySeconds: daily,
        weekSeconds: week,
        totalSeconds: total,
        studying: _studyStatus == 'studying',
        status: _studyStatus,
      );
    }
  }

  // ── Active timer persistence (survives app restart / hard kill) ────────────
  static const String _kActiveTimer = 'active_timer';

  /// Loads the persisted in-progress timer so the countdown and the Recent
  /// "live" entry survive a cold start. The Timer screen reads [activeTimer]
  /// to restore its countdown; here we also rebuild the live Recent entry and
  /// re-select the subject so the display matches.
  Future<void> _loadActiveTimer() async {
    final p = await _prefs;
    final raw = p.getString(_kActiveTimer);
    if (raw == null) return;
    try {
      final m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final subId = m['subjectId'] as String?;
      if (subId == null || !_subjects.any((s) => s.id == subId)) {
        await p.remove(_kActiveTimer); // subject gone → drop stale state
        return;
      }
      _activeTimer = m;
      _selectedSubjectId = subId; // restore selection so the display matches
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

  // Derive the Recent "live" entry from the active timer (focus phase only).
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

  /// At midnight, refresh day-scoped data (today's sessions, the recent list,
  /// statistics, streak) so the UI rolls over to a fresh day even if the app
  /// is left open. Re-arms itself for the following day.
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
    } catch (_) {
      // Keep local data on Firestore sync errors.
    }
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
    } catch (_) {
      // Ignore backend errors.
    }
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
      PushService.instance.init(); // register for push notifications
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
    // Detach this device's push token while we're still authenticated, so the
    // next account doesn't inherit the previous user's notifications.
    await PushService.instance.clearToken();
    try {
      await _firebaseService.signOut();
    } catch (_) {}
    _groupsSub?.cancel();
    _groupsSub = null;
    _myGroupIds = [];
    _studyStatus = 'idle';
    _remoteBackendReady = false;

    // Clear this account's data so the next account that logs in doesn't
    // inherit it (profile picture, sessions, subjects, etc.).
    _user = UserModel();
    _subjects = [];
    _sessions = [];
    _groups = [];
    _liveSession = null;
    _activeTimer = null;
    _selectedSubjectId = null;

    // Reset admin privileges, custom timings and stat overrides so the next
    // account on this device starts clean (no leaked admin settings).
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

    // Timer configuration + admin stat overrides (default to classic values).
    _focusMinutes = p.getInt('cfg_focus') ?? 25;
    _shortBreakMinutes = p.getInt('cfg_short') ?? 5;
    _longBreakMinutes = p.getInt('cfg_long') ?? 15;
    _cycles = p.getInt('cfg_cycles') ?? 4;
    _ovrStreak = p.getInt('ovr_streak');
    _ovrBestStreak = p.getInt('ovr_best');
    _ovrSessions = p.getInt('ovr_sessions');
    _ovrStudyMinutes = p.getInt('ovr_minutes');

    // ── Load study-profile fields written by GetStartedPage ──
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
    _publishToGroups(); // reflect new totals on group leaderboards
  }

  Future<void> clearStatOverrides() => adminSetStatOverrides();

  // ── Admin: aggregate metrics & grants (delegates to the backend) ────────────
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
    if (name != null)               _user.name = name;
    if (grade != null)              _user.grade = grade;
    if (dailyStudyGoalHours != null) _user.dailyStudyGoalHours = dailyStudyGoalHours;
    if (profileImagePath != null)   _user.profileImagePath = profileImagePath;
    if (studyTime != null)          _user.studyTime = studyTime;
    if (studyGoal != null)          _user.studyGoal = studyGoal;
    if (strongSubjects != null)     _user.strongSubjects = strongSubjects;
    if (weakSubjects != null)       _user.weakSubjects = weakSubjects;
    await _saveUser();
    await _syncToFirestore();
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
    _publishToGroups(); // update group leaderboards with the new total
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
  /// Called by the Timer screen on every meaningful change. Persists the full
  /// countdown state (so it restores after a restart) and refreshes the Recent
  /// "live" entry. Notifies listeners only when the visible minute (or subject)
  /// changes, so Home refreshes ~once per minute rather than every second.
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
    if (key(_liveSession) != before) {
      notifyListeners();
      _publishToGroups(); // keep group leaderboards live (≈ once per minute)
    }
  }

  void clearActiveTimer() {
    final hadLive = _liveSession != null;
    _activeTimer = null;
    _liveSession = null;
    _persistActiveTimer();
    if (hadLive) notifyListeners();
    _publishToGroups(); // studying stopped → push studying=false
  }

  /// Opens the subject behind [s] in the Timer tab.
  ///
  /// Matching rules (no duplicates ever created):
  ///  • If a subject with the same name (case-insensitive) still exists, it is
  ///    selected — even if its id changed.
  ///  • If the original subject was deleted, OR was renamed to something else
  ///    (so no subject carries this name anymore), a fresh subject is created
  ///    from the session's saved name + colour.
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
    _currentTabIndex = 1; // Timer tab
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