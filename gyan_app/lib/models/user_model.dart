// ─────────────────────────────────────────────────────────────────────────────
// models/user_model.dart
//
// Holds all persistent user data: profile info, streak, all-time stats.
// Serialised to JSON and stored via SharedPreferences (no external DB).
// ─────────────────────────────────────────────────────────────────────────────

class UserModel {
  String name;
  String grade;
  String email;
  int    dailyStudyGoalHours; // target hours the user wants to study each day
  String? profileImagePath;   // absolute path to copied profile picture on device

  // ── Onboarding / study-profile (from GetStartedPage) ──────────────────────
  String studyTime;            // e.g. 'Morning', 'Evening', 'Flexible'
  String studyGoal;            // e.g. 'Improve Grades', 'Prepare for Exams'
  List<String> strongSubjects; // subjects the user is confident in
  List<String> weakSubjects;   // subjects the user wants to improve

  // ── Streak ────────────────────────────────────────────────────────────────
  int      currentStreak;     // consecutive days with ≥1 qualifying session
  int      bestStreak;        // all-time highest streak
  DateTime? lastSessionDate;  // date of most recent qualifying session

  // ── All-time stats ────────────────────────────────────────────────────────
  int totalSessions;           // sessions with duration ≥ 10 min
  int totalMinutesStudied;     // all-time minutes across all qualifying sessions

  UserModel({
    this.name                = 'User',
    this.grade               = '',
    this.email               = '',
    this.dailyStudyGoalHours = 4,
    this.profileImagePath,
    this.studyTime           = '',
    this.studyGoal           = '',
    List<String>? strongSubjects,
    List<String>? weakSubjects,
    this.currentStreak       = 0,
    this.bestStreak          = 0,
    this.lastSessionDate,
    this.totalSessions       = 0,
    this.totalMinutesStudied = 0,
  })  : strongSubjects = strongSubjects ?? [],
        weakSubjects   = weakSubjects   ?? [];

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'name':                name,
    'grade':               grade,
    'email':               email,
    'dailyStudyGoalHours': dailyStudyGoalHours,
    'profileImagePath':    profileImagePath,
    'studyTime':           studyTime,
    'studyGoal':           studyGoal,
    'strongSubjects':      strongSubjects,
    'weakSubjects':        weakSubjects,
    'currentStreak':       currentStreak,
    'bestStreak':          bestStreak,
    'lastSessionDate':     lastSessionDate?.toIso8601String(),
    'totalSessions':       totalSessions,
    'totalMinutesStudied': totalMinutesStudied,
  };

  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(
    name:                j['name']                ?? 'User',
    grade:               j['grade']               ?? '',
    email:               j['email']               ?? '',
    dailyStudyGoalHours: j['dailyStudyGoalHours'] ?? 4,
    profileImagePath:    j['profileImagePath'],
    studyTime:           j['studyTime']           ?? '',
    studyGoal:           j['studyGoal']           ?? '',
    strongSubjects:      List<String>.from(j['strongSubjects'] ?? []),
    weakSubjects:        List<String>.from(j['weakSubjects']   ?? []),
    currentStreak:       j['currentStreak']       ?? 0,
    bestStreak:          j['bestStreak']           ?? 0,
    lastSessionDate:     j['lastSessionDate'] != null
                           ? DateTime.parse(j['lastSessionDate'])
                           : null,
    totalSessions:       j['totalSessions']       ?? 0,
    totalMinutesStudied: j['totalMinutesStudied'] ?? 0,
  );
}