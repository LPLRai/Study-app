// ─────────────────────────────────────────────────────────────────────────────
// models/buddy_chat_model.dart
//
// Study-Buddy 1-on-1 help chat. A `chats/{chatId}` doc pairs a learner (weak in
// a subject) with a helper (strong in it), same grade or one above. Messages
// live in a `messages` subcollection. See buddy_chat_service.dart.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';

class BuddyChat {
  final String id;
  final List<String> participants;        // [requesterUid, helperUid]
  final Map<String, String> participantNames;
  final String subject;
  final String requesterUid;              // the learner
  final String helperUid;
  final String learnerGrade;
  final String helperGrade;
  final String status;                    // pending | active | declined | closed
  final String lastMessage;
  final DateTime? lastMessageAt;

  const BuddyChat({
    required this.id,
    required this.participants,
    required this.participantNames,
    required this.subject,
    required this.requesterUid,
    required this.helperUid,
    required this.learnerGrade,
    required this.helperGrade,
    required this.status,
    required this.lastMessage,
    required this.lastMessageAt,
  });

  factory BuddyChat.fromDoc(String id, Map<String, dynamic> d) => BuddyChat(
        id: id,
        participants: List<String>.from(d['participants'] ?? const []),
        participantNames: ((d['participantNames'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k.toString(), v.toString())),
        subject: (d['subject'] as String?) ?? '',
        requesterUid: (d['requesterUid'] as String?) ?? '',
        helperUid: (d['helperUid'] as String?) ?? '',
        learnerGrade: (d['learnerGrade'] as String?) ?? '',
        helperGrade: (d['helperGrade'] as String?) ?? '',
        status: (d['status'] as String?) ?? 'pending',
        lastMessage: (d['lastMessage'] as String?) ?? '',
        lastMessageAt: (d['lastMessageAt'] as Timestamp?)?.toDate(),
      );

  bool get isPending => status == 'pending';
  bool get isActive => status == 'active';

  String otherUid(String myUid) =>
      participants.firstWhere((u) => u != myUid, orElse: () => '');
  String otherName(String myUid) => participantNames[otherUid(myUid)] ?? 'User';
  bool amHelper(String myUid) => myUid == helperUid;
}

class BuddyMessage {
  final String id;
  final String senderUid;
  final String senderName;
  final String text;
  final DateTime? createdAt;

  const BuddyMessage({
    required this.id,
    required this.senderUid,
    required this.senderName,
    required this.text,
    required this.createdAt,
  });

  factory BuddyMessage.fromDoc(String id, Map<String, dynamic> d) => BuddyMessage(
        id: id,
        senderUid: (d['senderUid'] as String?) ?? '',
        senderName: (d['senderName'] as String?) ?? '',
        text: (d['text'] as String?) ?? '',
        createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      );
}
