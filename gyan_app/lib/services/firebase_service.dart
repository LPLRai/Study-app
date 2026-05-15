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
  bool get isSignedIn => currentUser != null && !isAnonymous;

  Future<void> init() async {
  if (_initialized) return;
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, // ← add this
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

  Future<UserCredential> registerWithEmail(String email, String password) async {
    await init();
    return FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );
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
    return FirebaseFirestore.instance.collection('study_app_users').doc(user.uid);
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
}
