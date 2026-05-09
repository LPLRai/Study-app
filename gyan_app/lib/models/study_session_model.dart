// ─────────────────────────────────────────────────────────────────────────────
// models/study_session_model.dart
//
// Records a single completed (or manually stopped) focus period.
// Sessions with durationMinutes < 10 are saved but do NOT count toward stats.
// ─────────────────────────────────────────────────────────────────────────────

class StudySessionModel {
  final String   id;
  final String   subjectId;
  final String   subjectName;
  final int      colorIndex;       // snapshot of subject colour at session time
  final int      durationMinutes;
  final DateTime startTime;
  final DateTime endTime;

  const StudySessionModel({
    required this.id,
    required this.subjectId,
    required this.subjectName,
    required this.colorIndex,
    required this.durationMinutes,
    required this.startTime,
    required this.endTime,
  });

  /// Whether this session qualifies for streak / counter purposes.
  bool get isQualifying => durationMinutes >= 10;

  Map<String, dynamic> toJson() => {
    'id':              id,
    'subjectId':       subjectId,
    'subjectName':     subjectName,
    'colorIndex':      colorIndex,
    'durationMinutes': durationMinutes,
    'startTime':       startTime.toIso8601String(),
    'endTime':         endTime.toIso8601String(),
  };

  factory StudySessionModel.fromJson(Map<String, dynamic> j) =>
      StudySessionModel(
        id:              j['id'],
        subjectId:       j['subjectId'],
        subjectName:     j['subjectName'],
        colorIndex:      j['colorIndex']      ?? 0,
        durationMinutes: j['durationMinutes'],
        startTime:       DateTime.parse(j['startTime']),
        endTime:         DateTime.parse(j['endTime']),
      );
}
