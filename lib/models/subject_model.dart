// ─────────────────────────────────────────────────────────────────────────────
// models/subject_model.dart
//
// A "subject" is a named study topic the user creates in the Timer screen.
// Each subject has a colour (index into AppColors.subjectPalette) and tracks
// its own all-time accumulated study minutes.
// ─────────────────────────────────────────────────────────────────────────────

class SubjectModel {
  final String id;         // unique — millisecondsSinceEpoch as string
  String       name;
  int          colorIndex; // index into AppColors.subjectPalette
  int          totalMinutes; // all-time minutes studied for this subject

  SubjectModel({
    required this.id,
    required this.name,
    this.colorIndex   = 0,
    this.totalMinutes = 0,
  });

  Map<String, dynamic> toJson() => {
    'id':           id,
    'name':         name,
    'colorIndex':   colorIndex,
    'totalMinutes': totalMinutes,
  };

  factory SubjectModel.fromJson(Map<String, dynamic> j) => SubjectModel(
    id:           j['id'],
    name:         j['name'],
    colorIndex:   j['colorIndex']   ?? 0,
    totalMinutes: j['totalMinutes'] ?? 0,
  );
}
