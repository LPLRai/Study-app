import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/study_session_model.dart';
import '../providers/app_provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return 'Good morning,';
    if (h >= 12 && h < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  String _fmtTime(int minutes) => '${minutes ~/ 60}h ${minutes % 60}m';

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(builder: (context, prov, _) {
      final t = prov.appTheme;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Header ─────────────────────────────────────────────────
            _header(prov, t),
            const SizedBox(height: 20),
            _studiedTodayCard(prov, t),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _sessionsCard(prov, t)),
              const SizedBox(width: 12),
              Expanded(child: _streakCard(prov, t)),
            ]),
            const SizedBox(height: 22),
            _label('Quick Start', t),
            const SizedBox(height: 8),
            _quickStartCard(context, prov, t),
            const SizedBox(height: 22),
            _label('AI Tools', t),
            const SizedBox(height: 8),
            _aiCard(
              // MODULE: Answer Sheet Analyser
              // put (answer_sheet_icon) path in this section
              icon: Icons.document_scanner_rounded, iconColor: AppColors.green,
              label: 'Answer Sheet Analyzer', sublabel: 'Upload & get AI feedback',
              badgeColor: AppColors.green, t: t,
              onTap: () {/* TODO: navigate to AnswerSheetAnalyserScreen */},
            ),
            const SizedBox(height: 10),
            _aiCard(
              // MODULE: Make a Quiz
              // put (quiz_icon) path in this section
              icon: Icons.quiz_rounded, iconColor: AppColors.yellow,
              label: 'Make a Quiz', sublabel: 'AI generates questions for you',
              badgeColor: AppColors.yellow, t: t,
              onTap: () {/* TODO: navigate to MakeQuizScreen */},
            ),
            const SizedBox(height: 22),
            _label('Recent Session', t),
            const SizedBox(height: 8),
            ...prov.recentSessions.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _sessionTile(s, t))),
            if (prov.recentSessions.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: t.widgetBg, borderRadius: BorderRadius.circular(12)),
                child: Center(child: Text('No sessions yet. Start studying!', style: GoogleFonts.inder(color: t.textMuted))),
              ),
            const SizedBox(height: 16),
          ]),
        ),
      );
    });
  }

  Widget _label(String text, t) =>
      Text(text, style: GoogleFonts.inder(color: t.textMuted, fontSize: 14));

  Widget _header(AppProvider prov, t) {
    final imgPath = prov.user.profileImagePath;
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_greeting(), style: GoogleFonts.inder(color: t.textMuted, fontSize: 15)),
        Row(children: [
          Text(prov.user.name, style: GoogleFonts.inder(color: t.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(width: 6),
          const Text('👋', style: TextStyle(fontSize: 20)),
        ]),
      ]),
      Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle, color: t.widgetBg,
          border: Border.all(color: AppColors.blue.withOpacity(0.5), width: 2),
        ),
        child: ClipOval(
          child: imgPath != null && File(imgPath).existsSync()
              ? Image.file(File(imgPath), fit: BoxFit.cover)
              : Icon(Icons.person_rounded, color: t.textMuted, size: 28),
        ),
      ),
    ]);
  }

  Widget _studiedTodayCard(AppProvider prov, t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: t.widgetBg, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.blue.withOpacity(0.65), width: 1.5),
    ),
    child: Row(children: [
      const Icon(Icons.access_time_rounded, color: AppColors.blue, size: 30),
      const SizedBox(width: 14),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_fmtTime(prov.todayStudiedMinutes), style: GoogleFonts.inder(color: t.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
        Text('Studied Today', style: GoogleFonts.inder(color: t.textMuted, fontSize: 13)),
      ]),
    ]),
  );

  Widget _sessionsCard(AppProvider prov, t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: t.widgetBg, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.green.withOpacity(0.65), width: 1.5),
    ),
    child: Row(children: [
      const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 26),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${prov.todaySessionCount}', style: GoogleFonts.inder(color: t.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
        Text('Sessions Done', style: GoogleFonts.inder(color: t.textMuted, fontSize: 11)),
      ]),
    ]),
  );

  Widget _streakCard(AppProvider prov, t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: t.widgetBg, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.red.withOpacity(0.65), width: 1.5),
    ),
    child: Row(children: [
      const Text('🔥', style: TextStyle(fontSize: 24)),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${prov.user.currentStreak}', style: GoogleFonts.inder(color: t.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
        Text('Day Streak', style: GoogleFonts.inder(color: t.textMuted, fontSize: 11)),
      ]),
    ]),
  );

  Widget _quickStartCard(BuildContext ctx, AppProvider prov, t) =>
      GestureDetector(
        onTap: () => prov.switchTab(1),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.blue.withOpacity(0.15), borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.blue, width: 1.5),
          ),
          child: Row(children: [
            Container(width: 38, height: 38,
                decoration: const BoxDecoration(color: AppColors.blue, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26)),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Start Pomodoro', style: GoogleFonts.inder(color: t.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
              Text('25 min focus • 5 min break', style: GoogleFonts.inder(color: t.textMuted, fontSize: 12)),
            ]),
            const Spacer(),
            Icon(Icons.chevron_right_rounded, color: t.textMuted),
          ]),
        ),
      );

  Widget _aiCard({required IconData icon, required Color iconColor, required String label,
      required String sublabel, required Color badgeColor, required t, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: t.widgetBg, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: iconColor.withOpacity(0.55), width: 1.5),
          ),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: iconColor.withOpacity(0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: iconColor.withOpacity(0.6))),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: GoogleFonts.inder(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
              Text(sublabel, style: GoogleFonts.inder(color: t.textMuted, fontSize: 12)),
            ]),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: badgeColor.withOpacity(0.18), borderRadius: BorderRadius.circular(20), border: Border.all(color: badgeColor.withOpacity(0.7))),
              child: Text('Try', style: GoogleFonts.inder(color: badgeColor, fontSize: 12)),
            ),
          ]),
        ),
      );

  Widget _sessionTile(StudySessionModel s, t) {
    final color  = AppColors.subjectColor(s.colorIndex);
    final h12    = s.startTime.hour % 12 == 0 ? 12 : s.startTime.hour % 12;
    final period = s.startTime.hour < 12 ? 'AM' : 'PM';
    final time   = '${h12.toString().padLeft(2,'0')}:${s.startTime.minute.toString().padLeft(2,'0')} $period';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(color: t.widgetBg, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Container(width: 4, height: 38, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.subjectName, style: GoogleFonts.inder(color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          Text(time, style: GoogleFonts.inder(color: t.textMuted, fontSize: 12)),
        ]),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: color.withOpacity(0.18), borderRadius: BorderRadius.circular(20)),
          child: Text('${s.durationMinutes} min', style: GoogleFonts.inder(color: color, fontSize: 12)),
        ),
      ]),
    );
  }
}
