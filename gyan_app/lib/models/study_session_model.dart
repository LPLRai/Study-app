// ─────────────────────────────────────────────────────────────────────────────
// models/study_session_model.dart
//
// Records a single completed (or manually stopped) focus period.
// A fully completed focus phase always counts toward stats (the user finished
// the Pomodoro length they configured). A manual / partial stop falls back to
// the legacy rule: it only counts once it reaches 10 minutes.
// ─────────────────────────────────────────────────────────────────────────────

class StudySessionModel {
  final String   id;
  final String   subjectId;
  final String   subjectName;
  final int      colorIndex;       // snapshot of subject colour at session time
  final int      durationMinutes;
  final int      durationSeconds;  // precise duration (defaults to minutes*60)
  final DateTime startTime;
  final DateTime endTime;
  final bool     completed;        // true if a full focus phase finished

  StudySessionModel({
    required this.id,
    required this.subjectId,
    required this.subjectName,
    required this.colorIndex,
    required this.durationMinutes,
    int? durationSeconds,
    required this.startTime,
    required this.endTime,
    this.completed = false,
  }) : durationSeconds = durationSeconds ?? durationMinutes * 60;

  /// Whether this session qualifies for streak / counter / calendar purposes.
  /// A completed focus phase always qualifies — even when the configured focus
  /// length is under 10 minutes — so finishing a Pomodoro always registers.
  /// Otherwise (a partial / manual stop) it falls back to the ≥10-minute rule.
  bool get isQualifying => completed || durationMinutes >= 10;

  Map<String, dynamic> toJson() => {
    'id':              id,
    'subjectId':       subjectId,
    'subjectName':     subjectName,
    'colorIndex':      colorIndex,
    'durationMinutes': durationMinutes,
    'durationSeconds': durationSeconds,
    'startTime':       startTime.toIso8601String(),
    'endTime':         endTime.toIso8601String(),
    'completed':       completed,
  };

  factory StudySessionModel.fromJson(Map<String, dynamic> j) =>
      StudySessionModel(
        id:              j['id'],
        subjectId:       j['subjectId'],
        subjectName:     j['subjectName'],
        colorIndex:      j['colorIndex']      ?? 0,
        durationMinutes: j['durationMinutes'] ?? 0,
        durationSeconds: j['durationSeconds'], // null → derived from minutes
        startTime:       DateTime.parse(j['startTime']),
        endTime:         DateTime.parse(j['endTime']),
        completed:       (j['completed'] as bool?) ?? false,
      );
}
