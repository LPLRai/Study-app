// ─────────────────────────────────────────────────────────────────────────────
// services/buddy_chat_service.dart
//
// Study-Buddy peer-help chat (Feature B). Pairs a learner WEAK in a subject with
// a helper STRONG in it, restricted to the SAME grade or ONE above, with the
// helper's consent. Text-only (no Storage / no Blaze). Notifications reuse the
// existing in-app notifications collection + the push-server via FirebaseService.
//
// Firestore composite indexes this needs (the console will also prompt with a
// one-click link the first time each query runs):
//   • chats: requesterUid (ASC) + subject (ASC)        — anti-spam check
// All other queries are single-field (auto-indexed): helpSubjects array-contains,
// participants array-contains, messages orderBy(createdAt).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/buddy_chat_model.dart';
import 'firebase_service.dart';

class BuddyChatService {
  BuddyChatService._();
  static final BuddyChatService instance = BuddyChatService._();

  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _chats => _db.collection('chats');
  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('study_app_users');

  // Same fixed order used by onboarding/profile dropdowns.
  static const List<String> grades = [
    '6th Grade', '7th Grade', '8th Grade', '9th Grade', '10th Grade',
    '11th Grade', '12th Grade', 'Bachelor',
  ];

  /// The grades a learner of [g] may be helped by: same grade OR exactly one above.
  static List<String> helperGradesFor(String g) {
    final i = grades.indexOf(g);
    if (i < 0) return [g];
    final above = (i + 1 < grades.length) ? grades[i + 1] : grades[i];
    return above == g ? [g] : [g, above];
  }

  String _slug(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  /// Deterministic id so a given pair never gets a duplicate thread per subject.
  String chatId(String a, String b, String subject) {
    final pair = [a, b]..sort();
    return '${pair[0]}_${pair[1]}_${_slug(subject)}';
  }

  /// Opted-in helpers for [subject] whose grade is the learner's grade or one
  /// above. Grade is filtered in Dart (cheap, small list) to avoid combining
  /// array-contains with a disjunction in the query.
  Future<List<Map<String, dynamic>>> searchHelpers({
    required String subject,
    required String myGrade,
    required String myUid,
  }) async {
    final allowed = helperGradesFor(myGrade).toSet();
    final snap = await _users
        .where('helpSubjects', arrayContains: subject)
        .limit(50)
        .get()
        .timeout(const Duration(seconds: 10));
    final out = <Map<String, dynamic>>[];
    for (final d in snap.docs) {
      if (d.id == myUid) continue;
      final data = d.data();
      final grade = (data['matchGrade'] as String?) ?? '';
      if (!allowed.contains(grade)) continue;
      final user = (data['user'] as Map<String, dynamic>?) ?? const {};
      out.add({
        'uid': d.id,
        'name': (user['name'] as String?) ?? 'User',
        'grade': grade,
        'strongSubjects':
            List<String>.from(user['strongSubjects'] ?? const []),
        'totalMinutes': (user['totalMinutesStudied'] as num?)?.toInt() ?? 0,
      });
    }
    // Surface the most-studied helpers first.
    out.sort((a, b) =>
        (b['totalMinutes'] as int).compareTo(a['totalMinutes'] as int));
    return out;
  }

  /// Profile info for the chat's profile popup: the other user's profile fields
  /// plus today's studied seconds (summed from their synced sessions). Returns
  /// null if the doc can't be read.
  Future<Map<String, dynamic>?> fetchBuddyInfo(String uid) async {
    try {
      final snap = await _users.doc(uid).get().timeout(const Duration(seconds: 6));
      if (!snap.exists) return null;
      final data = snap.data() ?? const <String, dynamic>{};
      final user = (data['user'] as Map<String, dynamic>?) ?? const {};
      final now = DateTime.now();
      var todaySecs = 0;
      for (final s in (data['sessions'] as List?) ?? const []) {
        if (s is! Map) continue;
        final start = DateTime.tryParse((s['startTime'] as String?) ?? '');
        if (start == null) continue;
        if (start.year == now.year &&
            start.month == now.month &&
            start.day == now.day) {
          final secs = (s['durationSeconds'] as num?)?.toInt();
          todaySecs += secs ?? (((s['durationMinutes'] as num?)?.toInt() ?? 0) * 60);
        }
      }
      return {
        'name': (user['name'] as String?) ?? 'User',
        'grade': (user['grade'] as String?) ?? '',
        'studyTime': (user['studyTime'] as String?) ?? '',
        'studyGoal': (user['studyGoal'] as String?) ?? '',
        'strongSubjects': List<String>.from(user['strongSubjects'] ?? const []),
        'weakSubjects': List<String>.from(user['weakSubjects'] ?? const []),
        'bestStreak': (user['bestStreak'] as num?)?.toInt() ?? 0,
        'todaySeconds': todaySecs,
      };
    } catch (_) {
      return null;
    }
  }

  /// True if the learner already has a pending OR active buddy for [subject]
  /// (anti-spam: one open thread per subject at a time). Queries by
  /// `participants` — the same field the security rules check — so the LIST is
  /// permitted, then filters requester/subject/status in Dart. This avoids both
  /// a composite index AND the Firestore "query doesn't match the rule" rejection.
  Future<bool> hasOpenChatForSubject(String myUid, String subject) async {
    final snap = await _chats.where('participants', arrayContains: myUid).get();
    return snap.docs.any((d) {
      final data = d.data();
      final s = (data['status'] as String?) ?? '';
      return data['requesterUid'] == myUid &&
          data['subject'] == subject &&
          (s == 'pending' || s == 'active');
    });
  }

  /// Sends a help request → creates the chat in 'pending' + notifies the helper.
  /// Returns 'sent' | 'exists' | 'denied' (Firestore rules) | 'error'.
  Future<String> requestHelp({
    required String learnerUid,
    required String learnerName,
    required String learnerGrade,
    required String helperUid,
    required String helperName,
    required String helperGrade,
    required String subject,
  }) async {
    try {
      if (await hasOpenChatForSubject(learnerUid, subject)) return 'exists';
      final id = chatId(learnerUid, helperUid, subject);
      await _chats.doc(id).set({
        'participants': [learnerUid, helperUid],
        'participantNames': {learnerUid: learnerName, helperUid: helperName},
        'subject': subject,
        'learnerGrade': learnerGrade,
        'helperGrade': helperGrade,
        'requesterUid': learnerUid,
        'helperUid': helperUid,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      // The chat is created — the request has succeeded. The notification is
      // best-effort, so a failure there must NOT turn this into an error.
      try {
        await FirebaseService.instance.sendBuddyNotification(
          helperUid,
          type: 'buddy_request',
          title: 'New help request',
          body:
              '$learnerName ($learnerGrade) needs help with $subject. Open Groups → Buddies to accept.',
        );
      } catch (_) {/* notification is optional */}
      return 'sent';
    } on FirebaseException catch (e) {
      // permission-denied ⇒ the `chats` security rules aren't published yet.
      return e.code == 'permission-denied' ? 'denied' : 'error';
    } catch (_) {
      return 'error';
    }
  }

  /// Helper accepts or declines a pending request.
  Future<void> respond(BuddyChat chat, bool accept,
      {required String myName}) async {
    await _chats.doc(chat.id).update({'status': accept ? 'active' : 'declined'});
    await FirebaseService.instance.sendBuddyNotification(
      chat.requesterUid,
      type: accept ? 'buddy_accepted' : 'buddy_declined',
      title: accept ? 'Request accepted' : 'Request declined',
      body: accept
          ? '$myName accepted your ${chat.subject} help request — say hi!'
          : "$myName can't help with ${chat.subject} right now.",
    );
  }

  /// All of my chats (pending + active + closed), newest activity first.
  Stream<List<BuddyChat>> myChatsStream(String myUid) => _chats
      .where('participants', arrayContains: myUid)
      .snapshots()
      .map((s) {
        final list =
            s.docs.map((d) => BuddyChat.fromDoc(d.id, d.data())).toList();
        list.sort((a, b) => (b.lastMessageAt ?? DateTime(0))
            .compareTo(a.lastMessageAt ?? DateTime(0)));
        return list;
      });

  /// Live view of one chat doc (so a thread reflects accept/decline in place).
  Stream<BuddyChat?> chatStream(String id) => _chats.doc(id).snapshots().map(
      (d) => d.exists ? BuddyChat.fromDoc(d.id, d.data()!) : null);

  Stream<List<BuddyMessage>> messagesStream(String chatId) => _chats
      .doc(chatId)
      .collection('messages')
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) =>
          s.docs.map((d) => BuddyMessage.fromDoc(d.id, d.data())).toList());

  /// Sends a message (only meaningful when status == 'active') + bumps the
  /// thread's preview and pings the other participant.
  Future<void> sendMessage(
    BuddyChat chat, {
    required String senderUid,
    required String senderName,
    required String text,
  }) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final ref = _chats.doc(chat.id);
    await ref.collection('messages').add({
      'senderUid': senderUid,
      'senderName': senderName,
      'text': t,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await ref.update({
      'lastMessage': t,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
    final other = chat.otherUid(senderUid);
    if (other.isNotEmpty) {
      await FirebaseService.instance.sendBuddyNotification(
        other,
        type: 'buddy_message',
        title: senderName,
        body: t.length > 80 ? '${t.substring(0, 80)}…' : t,
      );
    }
  }

  /// Either participant ends the thread.
  Future<void> leave(String chatId) async =>
      _chats.doc(chatId).update({'status': 'closed'});
}
