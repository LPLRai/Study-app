// ─────────────────────────────────────────────────────────────────────────────
// screens/ai_features_screen.dart
//
// Merges the Quiz Generator and the Answer Sheet Analyzer ("Scan") into a
// single "AI Features" tab. A segmented toggle at the top switches between the
// two tools while preserving each one's state via an IndexedStack.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import 'quiz_screen.dart';
import 'upload_screen.dart';

class AiFeaturesScreen extends StatefulWidget {
  const AiFeaturesScreen({super.key});

  @override
  State<AiFeaturesScreen> createState() => _AiFeaturesScreenState();
}

class _AiFeaturesScreenState extends State<AiFeaturesScreen> {
  // 0 = Quiz, 1 = Scan
  int _sub = 0;

  static const _accent = Color(0xFF5865F2);

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(builder: (context, prov, _) {
      final t = prov.appTheme;

      return Scaffold(
        backgroundColor: t.background,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ── Header (centred title + back button, like the other tabs) ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Stack(alignment: Alignment.center, children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => prov.switchTab(0),
                      child: Icon(Icons.chevron_left_rounded,
                          color: t.textPrimary, size: 28),
                    ),
                  ),
                  Text(
                    'AI Features',
                    style: GoogleFonts.inder(
                      color: t.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ]),
              ),

              // ── Segmented toggle ────────────────────────────────────
              Container(
                margin: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: t.inputBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(children: [
                  Expanded(
                    child: _segButton(
                      t,
                      index: 0,
                      icon: Icons.quiz_rounded,
                      label: 'Quiz',
                    ),
                  ),
                  Expanded(
                    child: _segButton(
                      t,
                      index: 1,
                      icon: Icons.document_scanner_rounded,
                      label: 'Scan',
                    ),
                  ),
                ]),
              ),

              // ── Active tool ─────────────────────────────────────────
              Expanded(
                child: IndexedStack(
                  index: _sub,
                  children: const [
                    QuizScreen(embedded: true),
                    UploadScreen(embedded: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _segButton(
    dynamic t, {
    required int index,
    required IconData icon,
    required String label,
  }) {
    final selected = _sub == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _sub = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _accent : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18,
                color: selected ? Colors.white : t.textMuted),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inder(
                color: selected ? Colors.white : t.textMuted,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
