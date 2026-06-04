# Firebase Setup Instructions

The app now includes Firebase backend wiring and Android Google Services plugin support, but you still need to provide platform configuration files from your Firebase project.

## Android
1. In the Firebase console, create or select your project.
2. Register an Android app with package name `com.example.gyan_app`.
3. Download `google-services.json`.
4. Copy `google-services.json` into `android/app/`.

## iOS
1. Register an iOS app with your app bundle ID.
2. Download `GoogleService-Info.plist`.
3. Add `GoogleService-Info.plist` to `ios/Runner/` and ensure it is included in the Xcode Runner target.

## What was updated
- `pubspec.yaml` now includes `firebase_core`, `firebase_auth`, and `cloud_firestore`.
- `android/build.gradle.kts` now registers the Google Services Gradle plugin.
- `android/app/build.gradle.kts` now applies `com.google.gms.google-services`.
- `lib/services/firebase_service.dart` contains Firebase initialization, anonymous auth, and Firestore app-state save/load.
- `lib/providers/app_provider.dart` now syncs local state with Firestore when available.

## Next steps
- Run `flutter pub get`.
- Add the native config files above.
- Run the app on Android or iOS to confirm Firebase initialization.

## Optional Web Support
If you want Firebase on web too, use `flutterfire configure` or add a `lib/firebase_options.dart` file with FirebaseOptions.
