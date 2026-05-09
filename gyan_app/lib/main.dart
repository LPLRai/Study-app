// ─────────────────────────────────────────────────────────────────────────────
// main.dart — GYAN app entry point
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'providers/app_provider.dart';
import 'screens/main_screen.dart';
// import 'overlay/overlay_entry.dart'; // uncomment when flutter_overlay_window is added

// ── Overlay entry point (Android app-lock) ────────────────────────────────────
// Uncomment BOTH lines below once flutter_overlay_window is added to pubspec:
//
// @pragma("vm:entry-point")
// void overlayMain() {
//   WidgetsFlutterBinding.ensureInitialized();
//   runApp(const OverlayEntryApp());
// }

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final appProvider = AppProvider();
  await appProvider.init();

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
    final t    = prov.appTheme;

    SystemChrome.setSystemUIOverlayStyle(t.systemUiStyle);

    return MaterialApp(
      title:                     'GYAN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3:            true,
        scaffoldBackgroundColor: t.background,
        colorScheme: ColorScheme(
          brightness:  t.isDark ? Brightness.dark : Brightness.light,
          primary:     const Color(0xFF5865F2),
          onPrimary:   Colors.white,
          secondary:   const Color(0xFF57F287),
          onSecondary: Colors.black,
          surface:     t.widgetBg,
          onSurface:   t.textPrimary,
          error:       const Color(0xFFED4245),
          onError:     Colors.white,
        ),
        textTheme: GoogleFonts.inderTextTheme(
          t.isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
        ),
        inputDecorationTheme: InputDecorationTheme(
          hintStyle: GoogleFonts.inder(color: t.textMuted),
        ),
        splashFactory:  NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      ),
      home: const MainScreen(),
    );
  }
}
