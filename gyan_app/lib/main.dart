// ─────────────────────────────────────────────────────────────────────────────
// main.dart — GYAN app entry point
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'providers/app_provider.dart';
import 'screens/auth_screen.dart';
import 'screens/main_screen.dart';
import 'overlay/overlay_entry.dart';
import 'services/push_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// ── Overlay entry point (Android app-lock) ────────────────────────────────────
@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OverlayEntryApp());
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Use the bundled Inder font (google_fonts/Inder-Regular.ttf) instead of
  // downloading it at runtime — removes the first-launch network fetch + flash.
  GoogleFonts.config.allowRuntimeFetching = false;
  await dotenv.load(fileName: ".env");
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  final appProvider = AppProvider();
  await appProvider.init();
  // Register the FCM background/terminated handler now that Firebase is ready
  // (AppProvider.init() initialises Firebase). Notification-type messages are
  // shown by the OS automatically when the app isn't in the foreground.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  runApp(
    ChangeNotifierProvider.value(
      value: appProvider,
      child: const GyanApp(),
    ),
  );
}

class GyanApp extends StatelessWidget {
  const GyanApp({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AppProvider>();
    final t = prov.appTheme;
    SystemChrome.setSystemUIOverlayStyle(t.systemUiStyle);
    return MaterialApp(
      title: 'GYAN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: t.background,
        colorScheme: ColorScheme(
          brightness: t.isDark ? Brightness.dark : Brightness.light,
          primary: const Color(0xFF5865F2),
          onPrimary: Colors.white,
          secondary: const Color(0xFF57F287),
          onSecondary: Colors.black,
          surface: t.widgetBg,
          onSurface: t.textPrimary,
          error: const Color(0xFFED4245),
          onError: Colors.white,
        ),
        textTheme: GoogleFonts.inderTextTheme(
          t.isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
        ),
        inputDecorationTheme: InputDecorationTheme(
          hintStyle: GoogleFonts.inder(color: t.textMuted),
        ),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      ),
      home: const AuthGate(),
    );
  }
}

// ── AuthGate ──────────────────────────────────────────────────────────────────
// Simple gate: authenticated → MainScreen, otherwise → AuthScreen.
// GetStartedPage is no longer part of this gate — it is shown directly from
// AuthScreen immediately after a successful registration, before the user
// ever logs in for the first time.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AppProvider>();
    if (prov.isAuthenticated) return const MainScreen();
    return const AuthScreen();
  }
}