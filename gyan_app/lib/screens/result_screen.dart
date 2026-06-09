// lib/screens/result_screen.dart
//
// Displays the AIFeedback from the analyzer in a clean, theme-aware layout
// (full light + dark support via AppProvider.appTheme).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../services/answer_sheet_service.dart';

class ResultScreen extends StatelessWidget {
  final AnalysisResult result;
  final AnalysisParameters params;

  const ResultScreen({super.key, required this.result, required this.params});

  static Color gradeColor(String grade) {
    switch (grade) {
      case 'A':
        return const Color(0xFF2DC88A);
      case 'B':
        return const Color(0xFF5865F2);
      case 'C':
        return const Color(0xFFFFA000);
      case 'D':
        return const Color(0xFFFF7043);
      default:
        return const Color(0xFFED4245);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = result.feedback;
    return Consumer<AppProvider>(builder: (context, prov, _) {
      final t = prov.appTheme;

      return Scaffold(
        backgroundColor: t.background,
        appBar: AppBar(
          backgroundColor: t.background,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: t.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text('Analysis Results',
              style: GoogleFonts.inder(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18)),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            _scoreCard(t, f),
            const SizedBox(height: 18),
            _card(t, 'Summary', Icons.summarize_rounded,
                child: Text(f.summary,
                    style: GoogleFonts.inder(
                        color: t.textMuted, fontSize: 14, height: 1.55))),
            const SizedBox(height: 16),
            _card(t, 'Skills Assessment', Icons.radar_rounded,
                child: Column(children: [
                  _skillBar(t, 'Comprehension', f.skillsAssessment.comprehension),
                  _skillBar(t, 'Accuracy', f.skillsAssessment.accuracy),
                  _skillBar(t, 'Presentation', f.skillsAssessment.presentation),
                  _skillBar(t, 'Completeness', f.skillsAssessment.completeness),
                ])),
            const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: _card(t, 'Strengths', Icons.thumb_up_alt_rounded,
                    iconColor: AppColors.green,
                    child: Column(
                        children: f.strengths.isEmpty
                            ? [_emptyLine(t)]
                            : f.strengths
                                .map((s) => _bullet(t, s, AppColors.green))
                                .toList())),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _card(t, 'Improve', Icons.trending_up_rounded,
                    iconColor: const Color(0xFFFFA000),
                    child: Column(
                        children: f.improvements.isEmpty
                            ? [_emptyLine(t)]
                            : f.improvements
                                .map((s) =>
                                    _bullet(t, s, const Color(0xFFFFA000)))
                                .toList())),
              ),
            ]),
            const SizedBox(height: 16),
            if (f.questionBreakdown.isNotEmpty) ...[
              _card(
                t,
                'Question Breakdown',
                Icons.checklist_rounded,
                trailing: Text('${f.questionBreakdown.length} questions',
                    style:
                        GoogleFonts.inder(color: t.textMuted, fontSize: 11)),
                child: Column(
                    children: f.questionBreakdown
                        .map((q) => _questionTile(t, q))
                        .toList()),
              ),
              const SizedBox(height: 16),
            ],
            if (f.recommendedTopics.isNotEmpty) ...[
              _card(t, 'Topics to Revise', Icons.menu_book_rounded,
                  child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          f.recommendedTopics.map((x) => _chip(t, x)).toList())),
              const SizedBox(height: 16),
            ],
            if (f.teacherNote.isNotEmpty)
              _card(t, 'Note', Icons.note_alt_rounded,
                  child: Text(f.teacherNote,
                      style: GoogleFonts.inder(
                          color: t.textMuted, fontSize: 13, height: 1.5))),
          ],
        ),
      );
    });
  }

  // ── Score card ──────────────────────────────────────────────────────────────
  Widget _scoreCard(AppThemeData t, AIFeedback f) {
    final c = gradeColor(f.grade);
    final pct = (f.overallScore.clamp(0, 100)) / 100.0;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.withOpacity(t.isDark ? 0.18 : 0.12), t.widgetBg],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withOpacity(0.4)),
        boxShadow: t.widgetShadow,
      ),
      child: Column(children: [
        Row(children: [
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.withOpacity(0.14),
              border: Border.all(color: c, width: 2.5),
            ),
            child: Center(
              child: Text(f.grade,
                  style: GoogleFonts.inder(
                      color: c, fontSize: 32, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  '${f.estimatedMarks.toStringAsFixed(0)} / ${params.totalMarks}',
                  style: GoogleFonts.inder(
                      color: t.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('${f.overallScore.toStringAsFixed(1)}% overall',
                  style: GoogleFonts.inder(color: c, fontSize: 14)),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (f.passed ? AppColors.green : AppColors.red)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(f.passed ? '✓  Passed' : '✗  Failed',
                    style: GoogleFonts.inder(
                        color: f.passed ? AppColors.green : AppColors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 18),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: pct),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => LinearProgressIndicator(
              value: v,
              minHeight: 8,
              backgroundColor: t.isDark ? Colors.white12 : Colors.black12,
              valueColor: AlwaysStoppedAnimation(c),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.subject_rounded, size: 13, color: t.textMuted),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
                '${params.subject.isEmpty ? 'Subject' : params.subject} · ${params.gradeLevel} · ${params.strictness[0].toUpperCase()}${params.strictness.substring(1)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inder(color: t.textMuted, fontSize: 11)),
          ),
        ]),
      ]),
    );
  }

  // ── Reusable card ─────────────────────────────────────────────────────────
  Widget _card(AppThemeData t, String title, IconData icon,
      {required Widget child, Color? iconColor, Widget? trailing}) {
    final ic = iconColor ?? t.accent;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.widgetBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.cardBorder),
        boxShadow: t.widgetShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: ic, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: GoogleFonts.inder(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
          ),
          if (trailing != null) trailing,
        ]),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }

  Widget _skillBar(AppThemeData t, String label, double value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        SizedBox(
            width: 100,
            child: Text(label,
                style: GoogleFonts.inder(color: t.textMuted, fontSize: 12))),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (value / 10).clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor: t.isDark ? Colors.white12 : Colors.black12,
                valueColor: AlwaysStoppedAnimation(t.accent),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('${value.toStringAsFixed(1)}/10',
            style: GoogleFonts.inder(
                color: t.accent, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _bullet(AppThemeData t, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: CircleAvatar(radius: 3, backgroundColor: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: GoogleFonts.inder(
                  color: t.textMuted, fontSize: 12, height: 1.4)),
        ),
      ]),
    );
  }

  Widget _emptyLine(AppThemeData t) => Text('—',
      style: GoogleFonts.inder(color: t.textMuted, fontSize: 12));

  Widget _questionTile(AppThemeData t, QuestionFeedback q) {
    final pct = q.maxScore > 0 ? q.scoreAwarded / q.maxScore : 0.0;
    final color = pct >= 0.7
        ? AppColors.green
        : pct >= 0.4
            ? const Color(0xFFFFA000)
            : AppColors.red;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Q${q.questionNumber}',
              style: GoogleFonts.inder(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(7)),
            child: Text(
                '${q.scoreAwarded.toStringAsFixed(q.scoreAwarded.truncateToDouble() == q.scoreAwarded ? 0 : 1)} / ${q.maxScore.toStringAsFixed(q.maxScore.truncateToDouble() == q.maxScore ? 0 : 1)}',
                style: GoogleFonts.inder(
                    color: color, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ]),
        if (q.detectedAnswer.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text('Answer: ${q.detectedAnswer}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inder(
                  color: t.textMuted.withOpacity(0.8), fontSize: 11)),
        ],
        const SizedBox(height: 6),
        Text(q.feedback,
            style: GoogleFonts.inder(
                color: t.textMuted, fontSize: 12, height: 1.4)),
      ]),
    );
  }

  Widget _chip(AppThemeData t, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: t.accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.accent.withOpacity(0.35)),
      ),
      child: Text(label,
          style: GoogleFonts.inder(
              color: t.accent, fontSize: 12, fontWeight: FontWeight.w500)),
    );
  }
}
