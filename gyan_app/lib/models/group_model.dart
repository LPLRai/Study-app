// ─────────────────────────────────────────────────────────────────────────────
// models/group_model.dart
//
// Represents a study group.
// Member management (backend sync, real-time leaderboard) is intentionally
// left as a TODO — this file defines the local data shape only.
// ─────────────────────────────────────────────────────────────────────────────

class GroupModel {
  final String  id;
  String        name;
  String        description;
  List<String>  memberEmails; // TODO: resolve against backend user records
  bool          isPublic;
  List<String>  subjects;

  GroupModel({
    required this.id,
    required this.name,
    this.description = '',
    List<String>? memberEmails,
    this.isPublic = true,
    List<String>? subjects,
  }) : memberEmails = memberEmails ?? [],
       subjects = subjects ?? [];

  int get memberCount => memberEmails.length;

  Map<String, dynamic> toJson() => {
    'id':           id,
    'name':         name,
    'description':  description,
    'memberEmails': memberEmails,
    'isPublic':     isPublic,
    'subjects':     subjects,
  };

  factory GroupModel.fromJson(Map<String, dynamic> j) => GroupModel(
    id:           j['id'],
    name:         j['name'],
    description:  j['description']  ?? '',
    memberEmails: List<String>.from(j['memberEmails'] ?? []),
    isPublic:     j['isPublic']     ?? true,
    subjects:     List<String>.from(j['subjects'] ?? []),
  );
}
