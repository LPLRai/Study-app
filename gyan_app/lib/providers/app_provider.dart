// ─────────────────────────────────────────────────────────────────────────────
// providers/app_provider.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_model.dart';
import '../models/subject_model.dart';
import '../models/study_session_model.dart';
import '../models/group_model.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';

class AppProvider extends ChangeNotifier {
  final FirebaseService _firebaseService = FirebaseService.instance;

  UserModel _user = UserModel();
  List<SubjectModel> _subjects = [];
  List<StudySessionModel> _sessions = [];
  List<GroupModel> _groups = [];
  String? _selectedSubjectId;
  int _currentTabIndex = 0;
  bool _isDarkMode = true;
  bool _remoteBackendReady = false;

  bool get isAuthenticated => _firebaseService.isSignedIn;

  UserModel get user => _user;
  List<SubjectModel> get subjects => List.unmodifiable(_subjects);
  List<StudySessionModel> get sessions => List.unmodifiable(_sessions);
  List<GroupModel> get groups => List.unmodifiable(_groups);
  String? get selectedSubjectId => _selectedSubjectId;
  int get currentTabIndex => _currentTabIndex;
  bool get isDarkMode => _isDarkMode;
  AppThemeData get appTheme => AppThemeData(isDark: _isDarkMode);

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

  int get todayStudiedMinutes =>
      todaySessions.fold(0, (sum, s) => sum + s.durationMinutes);
  int get todaySessionCount =>
      todaySessions.where((s) => s.isQualifying).length;

  List<StudySessionModel> get recentSessions =>
      _sessions.where((s) => s.isQualifying).toList().reversed.take(5).toList();

  Future<void> init() async {
    await _initBackend();
    await _load();
    if (_remoteBackendReady) {
      await _loadRemoteData();
    }
    _checkStreakReset();
    notifyListeners();
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
            .map((e) => SubjectModel.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList();
      }

      final sessionsRemote = firebaseData['sessions'];
      if (sessionsRemote is List) {
        _sessions = sessionsRemote
            .map((e) => StudySessionModel.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList();
      }

      final groupsRemote = firebaseData['groups'];
      if (groupsRemote is List) {
        _groups = groupsRemote
            .map((e) => GroupModel.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList();
      }

      if (_subjects.isNotEmpty && _selectedSubjectId == null) {
        _selectedSubjectId = _subjects.first.id;
      }

      await _saveLocalState();
    } catch (_) {
      // Ignore Firestore sync errors and keep local data.
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
      // Ignore backend errors and keep local state.
    }
  }

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

      // check if email is verified
      final verified = _firebaseService.currentUser?.emailVerified ?? false;
      if (!verified) {
        await _firebaseService.signOut();
        return false;
      }

      _remoteBackendReady = true;
      await _loadRemoteData();
      await _syncToFirestore();
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
      _user.name = username.trim().isEmpty ? _user.name : username.trim();
      await _saveLocalState();

      // save to Firestore using uid directly (user not verified yet)
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
    try {
      await _firebaseService.signOut();
    } catch (_) {
      // ignore
    }
    _remoteBackendReady = false;
    notifyListeners();
  }

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
    _isDarkMode = p.getBool('isDarkMode') ?? true;
    if (_subjects.isNotEmpty) _selectedSubjectId = _subjects.first.id;
  }

  Future<void> _saveUser() async =>
      (await _prefs).setString('user', jsonEncode(_user.toJson()));
  Future<void> _saveSubjects() async => (await _prefs).setString(
      'subjects', jsonEncode(_subjects.map((s) => s.toJson()).toList()));
  Future<void> _saveSessions() async => (await _prefs).setString(
      'sessions', jsonEncode(_sessions.map((s) => s.toJson()).toList()));
  Future<void> _saveGroups() async => (await _prefs)
      .setString('groups', jsonEncode(_groups.map((g) => g.toJson()).toList()));

  void _checkStreakReset() {
    if (_user.lastSessionDate == null) return;
    final today = _dateOnly(DateTime.now());
    final last = _dateOnly(_user.lastSessionDate!);
    if (today.difference(last).inDays > 1) {
      _user.currentStreak = 0;
      _saveUser();
    }
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  Future<void> setDarkMode(bool value) async {
    _isDarkMode = value;
    (await _prefs).setBool('isDarkMode', value);
    await _syncToFirestore();
    notifyListeners();
  }

  void switchTab(int index) {
    _currentTabIndex = index;
    notifyListeners();
  }

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
      final today = _dateOnly(DateTime.now());
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
  }

  Future<void> updateUser(
      {String? name,
      String? grade,
      int? dailyStudyGoalHours,
      String? profileImagePath}) async {
    if (name != null) _user.name = name;
    if (grade != null) _user.grade = grade;
    if (dailyStudyGoalHours != null) {
      _user.dailyStudyGoalHours = dailyStudyGoalHours;
    }
    if (profileImagePath != null) _user.profileImagePath = profileImagePath;
    await _saveUser();
    await _syncToFirestore();
    notifyListeners();
  }

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