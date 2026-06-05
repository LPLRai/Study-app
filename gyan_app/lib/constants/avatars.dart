// ─────────────────────────────────────────────────────────────────────────────
// constants/avatars.dart
//
// Developer-curated profile avatars that ship WITH the app (no backend / no
// Firebase Storage needed). The user picks one of these when editing their
// profile picture.
//
// HOW TO ADD / CHANGE THE IMAGES:
//   1. Put 10 image files in:  assets/avatars/
//      using these exact names: avatar_1.png … avatar_10.png
//      (square images, ~256×256 px, PNG, look best).
//   2. That folder is already registered in pubspec.yaml, so just run:
//      flutter pub get   (only needed the first time you add the folder)
//   3. To use different names/counts, simply edit the list below to match
//      your files — everything else updates automatically.
//
// The selected avatar is stored on the user as this asset path (e.g.
// 'assets/avatars/avatar_3.png'); because every install bundles the same
// assets, it also renders correctly for other users (e.g. in groups).
// ─────────────────────────────────────────────────────────────────────────────

const List<String> kAvatarAssets = [
  'assets/avatars/avatar_1.png',
  'assets/avatars/avatar_2.png',
  'assets/avatars/avatar_3.png',
  'assets/avatars/avatar_4.png',
  'assets/avatars/avatar_5.png',
  'assets/avatars/avatar_6.png',
  'assets/avatars/avatar_7.png',
  'assets/avatars/avatar_8.png',
  'assets/avatars/avatar_9.png',
  'assets/avatars/avatar_10.png',
];
