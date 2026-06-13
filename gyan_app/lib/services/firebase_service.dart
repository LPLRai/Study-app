import 'dart:convert';
import '../firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class FirebaseService {
  FirebaseService._();
  static final FirebaseService instance = FirebaseService._();
  bool _initialized = false;

  bool get initialized => _initialized;
  User? get currentUser => FirebaseAuth.instance.currentUser;
  bool get isAnonymous => currentUser?.isAnonymous ?? false;

  // blocks unverified users from accessing the app
  bool get isSignedIn =>
      currentUser != null &&
      !isAnonymous &&
      (currentUser?.emailVerified ?? false);

  Future<void> init() async {
    if (_initialized) return;
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    _initialized = true;
  }

  Future<UserCredential> signInWithEmail(String email, String password) async {
    await init();
    return FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );
  }

  // sends verification email right after registration
  Future<UserCredential> registerWithEmail(String email, String password) async {
    await init();
    final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );
    await credential.user?.sendEmailVerification();
    return credential;
  }

  Future<UserCredential> signInAnonymously() async {
    await init();
    return FirebaseAuth.instance.signInAnonymously();
  }

  Future<void> signOut() async {
    if (!_initialized) return;
    await FirebaseAuth.instance.signOut();
  }

  Future<String?> emailForUsername(String username) async {
    if (!_initialized) return null;
    final snapshot = await FirebaseFirestore.instance
        .collection('study_app_users')
        .where('user.name', isEqualTo: username.trim())
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    final data = snapshot.docs.first.data();
    final userMap = data['user'] as Map<String, dynamic>?;
    return userMap == null ? null : userMap['email'] as String?;
  }

  DocumentReference<Map<String, dynamic>> get userDoc {
    final user = currentUser;
    if (user == null) {
      throw StateError('FirebaseService has not been initialized or signed in.');
    }
    return FirebaseFirestore.instance
        .collection('study_app_users')
        .doc(user.uid);
  }

  // used during registration before email is verified
  Future<void> saveAppStateForUid({
    required String uid,
    required Map<String, dynamic> user,
    required bool isDarkMode,
  }) async {
    await FirebaseFirestore.instance
        .collection('study_app_users')
        .doc(uid)
        .set({
      'user': user,
      'subjects': [],
      'sessions': [],
      'groups': [],
      'isDarkMode': isDarkMode,
    }, SetOptions(merge: true));
  }

  Future<void> saveAppState({
    required Map<String, dynamic> user,
    required List<Map<String, dynamic>> subjects,
    required List<Map<String, dynamic>> sessions,
    required List<Map<String, dynamic>> groups,
    required bool isDarkMode,
  }) async {
    if (!_initialized || currentUser == null) return;
    await userDoc.set(
      {
        'user': user,
        'subjects': subjects,
        'sessions': sessions,
        'groups': groups,
        'isDarkMode': isDarkMode,
      },
      SetOptions(merge: true),
    );
  }

  Future<Map<String, dynamic>?> loadAppState() async {
    if (!_initialized) return null;
    final snapshot = await userDoc.get();
    return snapshot.exists ? snapshot.data() : null;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Groups / leaderboard / invitations (real-time via Firestore)
  // ───────────────────────────────────────────────────────────────────────────
  CollectionReference<Map<String, dynamic>> get _groups =>
      FirebaseFirestore.instance.collection('study_groups');

  CollectionReference<Map<String, dynamic>> _notifs(String uid) =>
      FirebaseFirestore.instance
          .collection('study_app_users')
          .doc(uid)
          .collection('notifications');

  String get _todayKey {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  /// Find the uid for an account by email (case-insensitive). Null if none.
  Future<String?> uidForEmail(String email) async {
    if (!_initialized) return null;
    final raw = email.trim();
    final lower = raw.toLowerCase();
    final col = FirebaseFirestore.instance.collection('study_app_users');
    // 1) normalized index field
    var snap = await col.where('emailLower', isEqualTo: lower).limit(1).get();
    if (snap.docs.isNotEmpty) return snap.docs.first.id;
    // 2) fallback for older docs without emailLower
    snap = await col.where('user.email', isEqualTo: raw).limit(1).get();
    if (snap.docs.isNotEmpty) return snap.docs.first.id;
    snap = await col.where('user.email', isEqualTo: lower).limit(1).get();
    return snap.docs.isEmpty ? null : snap.docs.first.id;
  }

  /// Writes a lowercase email index on the current user's doc so others can
  /// find them by email regardless of case. Safe to call on every launch.
  Future<void> ensureEmailIndex() async {
    final u = currentUser;
    final email = u?.email;
    if (u == null || email == null) return;
    try {
      await userDoc.set(
          {'emailLower': email.trim().toLowerCase()}, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Fire-and-forget: asks the free push server (see push-server/) to deliver an
  /// FCM notification to [toUid]. No-op when PUSH_ENDPOINT isn't configured, so
  /// the in-app notification still works on its own. Never throws to the caller.
  void _sendPush(String toUid, String type, {String groupName = ''}) {
    final endpoint = dotenv.env['PUSH_ENDPOINT'] ?? '';
    if (endpoint.isEmpty) return;
    () async {
      try {
        final token = await currentUser?.getIdToken();
        if (token == null) return;
        await http
            .post(
              Uri.parse(endpoint),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode({
                'toUid': toUid,
                'type': type,
                'groupName': groupName,
                'fromName': await _myName(),
              }),
            )
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        // Ignore — the in-app notification has already been recorded.
      }
    }();
  }

  Future<String> _myName() async {
    final data = (await userDoc.get()).data();
    final n = (data?['user'] as Map<String, dynamic>?)?['name'] as String?;
    return (n == null || n.trim().isEmpty) ? 'User' : n;
  }

  /// Number of groups the current user OWNS (for the max-5 limit).
  Future<int> ownedGroupCount() async {
    final uid = currentUser?.uid;
    if (uid == null) return 0;
    final snap = await _groups.where('ownerUid', isEqualTo: uid).get();
    return snap.docs.length;
  }

  /// Creates a group with the current user as owner + first member.
  Future<String> createGroup(String name, int myTotalSeconds, {
    String description = '',
    bool isPublic = true,
    List<String> subjects = const [],
  }) async {
    final uid = currentUser!.uid;
    final myName = await _myName();
    final ref = await _groups.add({
      'name': name,
      'description': description,
      'ownerUid': uid,
      'ownerName': myName,
      'memberUids': [uid],
      'isPublic': isPublic,
      'subjects': subjects,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await ref.collection('members').doc(uid).set({
      'name': myName,
      'joinedAt': FieldValue.serverTimestamp(),
      'baseline': myTotalSeconds, // all-time studied at join → scope "since join"
      'dailySeconds': 0,
      'dailyDate': _todayKey,
      'weekSeconds': 0,
      'totalSeconds': myTotalSeconds,
      'studying': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> deleteGroup(String groupId) async {
    // Best-effort: remove members then the group doc.
    final members = await _groups.doc(groupId).collection('members').get();
    for (final m in members.docs) {
      await m.reference.delete();
    }
    await _groups.doc(groupId).delete();
  }

  Future<void> leaveGroup(String groupId) async {
    final uid = currentUser!.uid;
    await _groups.doc(groupId).update({
      'memberUids': FieldValue.arrayRemove([uid])
    });
    await _groups.doc(groupId).collection('members').doc(uid).delete();
  }

  /// Removes [memberUid] from a group — called by the group owner.
  Future<void> kickMember(String groupId, String memberUid) async {
    await _groups.doc(groupId).update({
      'memberUids': FieldValue.arrayRemove([memberUid])
    });
    await _groups.doc(groupId).collection('members').doc(memberUid).delete();
  }

  /// Sends an in-app invite (notification) to the account behind [email].
  /// Returns 'invited', 'no_account' (no app account for that email — email-only),
  /// or 'already' if they're already a member.
  Future<String> inviteByEmail(
      String groupId, String groupName, String email) async {
    final uid = await uidForEmail(email);
    if (uid == null) return 'no_account';
    final groupSnap = await _groups.doc(groupId).get();
    final members = List<String>.from(groupSnap.data()?['memberUids'] ?? []);
    if (members.contains(uid)) return 'already';
    await _notifs(uid).add({
      'type': 'group_invite',
      'groupId': groupId,
      'groupName': groupName,
      'fromName': await _myName(),
      'status': 'pending',
      'seen': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    _sendPush(uid, 'group_invite', groupName: groupName);
    return 'invited';
  }

  /// Count of unseen notifications (missing/false `seen`) — drives the badge.
  Stream<int> unreadCountStream() {
    final uid = currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _notifs(uid).snapshots().map(
        (s) => s.docs.where((d) => d.data()['seen'] != true).length);
  }

  /// Marks every notification as seen (clears the badge).
  Future<void> markAllNotificationsSeen() async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await _notifs(uid).get();
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) {
        if (d.data()['seen'] != true) {
          batch.update(d.reference, {'seen': true});
        }
      }
      await batch.commit();
    } catch (_) {}
  }

  Stream<List<Map<String, dynamic>>> notificationsStream() {
    final uid = currentUser?.uid;
    if (uid == null) return const Stream.empty();
    // No server orderBy: docs with a pending serverTimestamp would otherwise be
    // skipped. Sort client-side instead so every invite shows immediately.
    return _notifs(uid).snapshots().map((s) {
      final list = s.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      list.sort((a, b) {
        final ta = (a['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        final tb = (b['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        return tb.compareTo(ta);
      });
      return list;
    });
  }

  Future<void> acceptInvite(
      String notifId, String groupId, int myTotalSeconds) async {
    final uid = currentUser!.uid;
    final myName = await _myName();
    await _groups.doc(groupId).update({
      'memberUids': FieldValue.arrayUnion([uid])
    });
    await _groups.doc(groupId).collection('members').doc(uid).set({
      'name': myName,
      'joinedAt': FieldValue.serverTimestamp(),
      'baseline': myTotalSeconds,
      'dailySeconds': 0,
      'dailyDate': _todayKey,
      'weekSeconds': 0,
      'totalSeconds': myTotalSeconds,
      'studying': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _notifs(uid).doc(notifId).update({'status': 'accepted'});
  }

  Future<void> declineInvite(String notifId) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    await _notifs(uid).doc(notifId).update({'status': 'declined'});
  }

  Future<void> dismissNotification(String notifId) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    await _notifs(uid).doc(notifId).delete();
  }

  /// Groups the current user is a member of (live).
  Stream<List<Map<String, dynamic>>> myGroupsStream() {
    final uid = currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _groups
        .where('memberUids', arrayContains: uid)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  /// Live member leaderboard for a group.
  Stream<List<Map<String, dynamic>>> groupMembersStream(String groupId) {
    return _groups
        .doc(groupId)
        .collection('members')
        .snapshots()
        .map((s) => s.docs.map((d) => {'uid': d.id, ...d.data()}).toList());
  }

  /// Live single-group document (name, description, ownerUid, memberUids…).
  /// Emits null if the group no longer exists (e.g. owner deleted it).
  Stream<Map<String, dynamic>?> groupStream(String groupId) {
    return _groups.doc(groupId).snapshots().map(
        (d) => d.exists ? {'id': d.id, ...?d.data()} : null);
  }

  /// Owner edits the group's name, description, type, and subjects.
  Future<void> updateGroupInfo(
    String groupId,
    String name,
    String description, {
    bool isPublic = true,
    List<String> subjects = const [],
  }) async {
    await _groups.doc(groupId).update({
      'name': name,
      'description': description,
      'isPublic': isPublic,
      'subjects': subjects,
    });
  }

  /// Directly joins a public group.
  Future<void> joinGroup(String groupId, int myTotalSeconds) async {
    final uid = currentUser!.uid;
    final myName = await _myName();
    await _groups.doc(groupId).update({
      'memberUids': FieldValue.arrayUnion([uid])
    });
    await _groups.doc(groupId).collection('members').doc(uid).set({
      'name': myName,
      'joinedAt': FieldValue.serverTimestamp(),
      'baseline': myTotalSeconds,
      'dailySeconds': 0,
      'dailyDate': _todayKey,
      'weekSeconds': 0,
      'totalSeconds': myTotalSeconds,
      'studying': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Reads another user's public profile (the `user` map on their doc) so the
  /// group can show class, subjects, study goal, etc. Null if unavailable.
  Future<Map<String, dynamic>?> fetchUserProfile(String uid) async {
    if (!_initialized) return null;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('study_app_users')
          .doc(uid)
          .get();
      final user = snap.data()?['user'];
      return user is Map<String, dynamic> ? user : null;
    } catch (_) {
      return null;
    }
  }

  /// Sends a "time to study" nudge notification to [toUid].
  Future<void> sendStudyReminder(String toUid) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    await _notifs(toUid).add({
      'type': 'study_reminder',
      'fromName': await _myName(),
      'seen': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    _sendPush(toUid, 'study_reminder');
  }

  /// Sends a study-reminder notification to the account behind [email].
  /// Returns 'sent', 'no_account', or 'error'. Used by the admin test tool to
  /// verify the notification pipeline end-to-end.
  Future<String> sendStudyReminderByEmail(String email) async {
    if (!_initialized) return 'error';
    try {
      final uid = await uidForEmail(email);
      if (uid == null) return 'no_account';
      await _notifs(uid).add({
        'type': 'study_reminder',
        'fromName': await _myName(),
        'seen': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _sendPush(uid, 'study_reminder');
      return 'sent';
    } catch (_) {
      return 'error';
    }
  }

  /// Publishes the current user's study stats to one group's member doc.
  Future<void> publishStats(
    String groupId, {
    required int dailySeconds,
    required int weekSeconds,
    required int totalSeconds,
    required bool studying,
    String status = 'idle',
  }) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    try {
      await _groups.doc(groupId).collection('members').doc(uid).set({
        'dailySeconds': dailySeconds,
        'dailyDate': _todayKey,
        'weekSeconds': weekSeconds,
        'totalSeconds': totalSeconds,
        'studying': studying,
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {/* offline — will sync when back */}
  }
      /// Saves onboarding profile data for a user.
  /// Works before email verification since we reference the UID directly.
  Future<void> saveOnboardingProfile({
    required String uid,
    required Map<String, dynamic> userData,
  }) async {
    await init();
    await FirebaseFirestore.instance
        .collection('study_app_users')
        .doc(uid)
        .set({'user': userData}, SetOptions(merge: true));
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Admin panel — presence, aggregate counts, and admin grants
  // ───────────────────────────────────────────────────────────────────────────
  String? get currentEmail => currentUser?.email;

  CollectionReference<Map<String, dynamic>> get _admins =>
      FirebaseFirestore.instance.collection('admins');

  /// Records that this user is active now (heartbeat for the "active users"
  /// metric). Writes only to the user's own doc, so the existing rules allow it.
  Future<void> touchPresence() async {
    if (!_initialized || currentUser == null) return;
    try {
      await userDoc
          .set({'lastActiveAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Stores this device's FCM token on the user doc so the Cloud Function can
  /// push notifications (group invites, study reminders) to their phone.
  Future<void> saveFcmToken(String token) async {
    if (!_initialized || currentUser == null) return;
    try {
      await userDoc.set(
          {'fcmTokens': FieldValue.arrayUnion([token])}, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Detaches a token (on sign-out) so the device stops receiving that account's
  /// notifications.
  Future<void> removeFcmToken(String token) async {
    if (!_initialized || currentUser == null) return;
    try {
      await userDoc.set(
          {'fcmTokens': FieldValue.arrayRemove([token])}, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Asks the free push server to delete "orphan" user docs (accounts removed
  /// from Firebase Auth). Returns {purged, registered} or null if unavailable
  /// (endpoint not set / not an admin / network). Auth accounts are untouched.
  Future<Map<String, int>?> purgeDeletedUsers() async {
    final endpoint = dotenv.env['PUSH_ENDPOINT'] ?? '';
    if (endpoint.isEmpty) return null;
    final purgeUrl =
        '${endpoint.replaceFirst(RegExp(r'/send/?$'), '')}/purge';
    try {
      final token = await currentUser?.getIdToken();
      if (token == null) return null;
      final res = await http.post(
        Uri.parse(purgeUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) return null;
      final data = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
      return {
        'purged': (data['purged'] as num?)?.toInt() ?? 0,
        'registered': (data['registered'] as num?)?.toInt() ?? 0,
      };
    } catch (_) {
      return null;
    }
  }

  /// Total registered accounts (aggregate count — cheap, no full read).
  Future<int> registeredUserCount() async {
    if (!_initialized) return 0;
    try {
      final agg = await FirebaseFirestore.instance
          .collection('study_app_users')
          .count()
          .get();
      return agg.count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Accounts active within [window] (based on the lastActiveAt heartbeat).
  Future<int> activeUserCount(
      {Duration window = const Duration(minutes: 10)}) async {
    if (!_initialized) return 0;
    try {
      final cutoff = Timestamp.fromDate(DateTime.now().subtract(window));
      final agg = await FirebaseFirestore.instance
          .collection('study_app_users')
          .where('lastActiveAt', isGreaterThan: cutoff)
          .count()
          .get();
      return agg.count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Paid (subscribed) accounts. Counts docs whose top-level `isPaid` == true.
  /// Returns 0 until a paywall starts setting that flag (see the paywall guide).
  Future<int> paidUserCount() async {
    if (!_initialized) return 0;
    try {
      final agg = await FirebaseFirestore.instance
          .collection('study_app_users')
          .where('isPaid', isEqualTo: true)
          .count()
          .get();
      return agg.count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Whether the account [uid] has been granted admin (Firestore-backed).
  Future<bool> isAdminUid(String uid) async {
    if (!_initialized) return false;
    try {
      final d = await _admins.doc(uid).get();
      return d.exists && d.data()?['isAdmin'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Grants admin to the account behind [email].
  /// Returns 'granted', 'no_account', or 'error'.
  /// (Server rules only permit ROOT admins to actually write here.)
  Future<String> grantAdminByEmail(String email) async {
    if (!_initialized || currentUser == null) return 'error';
    try {
      final uid = await uidForEmail(email);
      if (uid == null) return 'no_account';
      await _admins.doc(uid).set({
        'isAdmin': true,
        'email': email.trim().toLowerCase(),
        'grantedBy': currentUser!.email,
        'grantedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return 'granted';
    } catch (_) {
      return 'error';
    }
  }

  /// Revokes a granted admin. (Root admins from AdminConfig are unaffected.)
  Future<void> revokeAdmin(String uid) async {
    if (!_initialized) return;
    try {
      await _admins.doc(uid).delete();
    } catch (_) {}
  }

  /// Live list of granted admins (for the manage-admins UI).
  Stream<List<Map<String, dynamic>>> adminsStream() {
    if (!_initialized) return const Stream.empty();
    return _admins
        .snapshots()
        .map((s) => s.docs.map((d) => {'uid': d.id, ...d.data()}).toList());
  }
  }
