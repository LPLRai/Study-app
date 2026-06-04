import '../firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

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

  /// Find the uid for an account by email (exact, trimmed). Null if no account.
  Future<String?> uidForEmail(String email) async {
    if (!_initialized) return null;
    final e = email.trim();
    final snap = await FirebaseFirestore.instance
        .collection('study_app_users')
        .where('user.email', isEqualTo: e)
        .limit(1)
        .get();
    return snap.docs.isEmpty ? null : snap.docs.first.id;
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
  Future<String> createGroup(String name, int myTotalSeconds) async {
    final uid = currentUser!.uid;
    final myName = await _myName();
    final ref = await _groups.add({
      'name': name,
      'ownerUid': uid,
      'ownerName': myName,
      'memberUids': [uid],
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
      'createdAt': FieldValue.serverTimestamp(),
    });
    return 'invited';
  }

  Stream<List<Map<String, dynamic>>> notificationsStream() {
    final uid = currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _notifs(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
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
}