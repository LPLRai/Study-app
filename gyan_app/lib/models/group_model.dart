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
  List<String>  memberEmails; // TODO: resolve against backend user records

  GroupModel({
    required this.id,
    required this.name,
    List<String>? memberEmails,
  }) : memberEmails = memberEmails ?? [];

  int get memberCount => memberEmails.length;

  Map<String, dynamic> toJson() => {
    'id':           id,
    'name':         name,
    'memberEmails': memberEmails,
  };

  factory GroupModel.fromJson(Map<String, dynamic> j) => GroupModel(
    id:           j['id'],
    name:         j['name'],
    memberEmails: List<String>.from(j['memberEmails'] ?? []),
  );
}
