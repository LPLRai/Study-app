// ─────────────────────────────────────────────────────────────────────────────
// config/admin_config.dart
//
// The list of "root" admin emails that get full Admin Panel access.
//
// HOW TO MAKE YOURSELF AN ADMIN:
//   1. Add your account's email below (lowercase), e.g.
//        static const List<String> rootAdminEmails = ['me@example.com'];
//   2. Add the SAME email(s) to your Firestore security rules so the
//      server also trusts you (see the `admins` rule in the instructions).
//
// Security notes:
//   • An empty list means NOBODY is an admin (safe default).
//   • The email is matched against the *verified* Firebase Auth email, so a
//     user cannot fake it without actually owning that verified account.
//   • Root admins can grant admin to other accounts from inside the panel;
//     those grants live in Firestore (collection `admins`) and are enforced
//     server-side by the rules — a tampered client cannot self-promote.
// ─────────────────────────────────────────────────────────────────────────────

class AdminConfig {
  /// Root admin emails — full, non-revocable admin access. Keep them lowercase.
  static const List<String> rootAdminEmails = <String>[
    'teamgyan457@gmail.com',
  ];

  /// True if [email] (the verified auth email) is a root admin.
  static bool isRootAdmin(String? email) {
    if (email == null) return false;
    final e = email.trim().toLowerCase();
    if (e.isEmpty) return false;
    return rootAdminEmails.any((a) => a.trim().toLowerCase() == e);
  }
}
