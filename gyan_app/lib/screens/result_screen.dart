// lib/screens/result_screen.dart
//
// Displays the AIFeedback from Groq in a polished, scrollable layout.

import 'package:flutter/material.dart';
import '../services/answer_sheet_service.dart';

class ResultScreen extends StatelessWidget {
  final AnalysisResult result;
  final AnalysisParameters params;

  const ResultScreen({
    super.key,
    required this.result,
    required this.params,
  });

  @override
  Widget build(BuildContext context) {
    final f = result.feedback;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Analysis Results',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Color(0xFF6C63FF)),
            onPressed: () {}, // hook up share if needed
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          // ── Score card ─────────────────────────────────────────────────────
          _ScoreCard(feedback: f, params: params),

          const SizedBox(height: 20),

          // ── Summary ────────────────────────────────────────────────────────
          _Card(
            title: 'Summary',
            icon: Icons.summarize_rounded,
            child: Text(f.summary,
                style: const TextStyle(
                    color: Color(0xFFCDD0E0), fontSize: 14, height: 1.55)),
          ),

          const SizedBox(height: 16),

          // ── Skills radar ───────────────────────────────────────────────────
          _Card(
            title: 'Skills Assessment',
            icon: Icons.radar_rounded,
            child: Column(
              children: [
                _SkillBar('Comprehension', f.skillsAssessment.comprehension),
                _SkillBar('Accuracy',      f.skillsAssessment.accuracy),
                _SkillBar('Presentation',  f.skillsAssessment.presentation),
                _SkillBar('Completeness',  f.skillsAssessment.completeness),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Strengths & improvements ───────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Card(
                  title: 'Strengths',
                  icon: Icons.thumb_up_rounded,
                  iconColor: const Color(0xFF22C55E),
                  child: Column(
                    children: f.strengths
                        .map((s) => _BulletItem(s, color: const Color(0xFF22C55E)))
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Card(
                  title: 'Improve',
                  icon: Icons.trending_up_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  child: Column(
                    children: f.improvements
                        .map((s) => _BulletItem(s, color: const Color(0xFFF59E0B)))
                        .toList(),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Question breakdown ─────────────────────────────────────────────
          if (f.questionBreakdown.isNotEmpty) ...[
            _Card(
              title: 'Question Breakdown',
              icon: Icons.quiz_rounded,
              child: Column(
                children: f.questionBreakdown
                    .map((q) => _QuestionTile(q))
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Recommended topics ─────────────────────────────────────────────
          if (f.recommendedTopics.isNotEmpty)
            _Card(
              title: 'Topics to Revise',
              icon: Icons.book_rounded,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: f.recommendedTopics
                    .map((t) => _Chip(t))
                    .toList(),
              ),
            ),

          const SizedBox(height: 16),

          // ── Teacher note ───────────────────────────────────────────────────
          if (f.teacherNote.isNotEmpty)
            _Card(
              title: 'Note for Teacher',
              icon: Icons.note_alt_rounded,
              iconColor: const Color(0xFF6C63FF),
              child: Text(f.teacherNote,
                  style: const TextStyle(
                      color: Color(0xFFCDD0E0), fontSize: 13, height: 1.5)),
            ),
        ],
      ),
    );
  }
}

// ─── Score card ───────────────────────────────────────────────────────────────

class _ScoreCard extends StatelessWidget {
  final AIFeedback feedback;
  final AnalysisParameters params;
  const _ScoreCard({required this.feedback, required this.params});

  Color get _gradeColor {
    switch (feedback.grade) {
      case 'A': return const Color(0xFF22C55E);
      case 'B': return const Color(0xFF3B82F6);
      case 'C': return const Color(0xFFF59E0B);
      case 'D': return const Color(0xFFF97316);
      default:  return const Color(0xFFEF4444);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF1C1F2E), _gradeColor.withOpacity(0.08)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _gradeColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          // Grade circle
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _gradeColor.withOpacity(0.12),
              border: Border.all(color: _gradeColor, width: 2.5),
            ),
            child: Center(
              child: Text(
                feedback.grade,
                style: TextStyle(
                  color: _gradeColor,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${feedback.estimatedMarks.toStringAsFixed(0)} / ${params.totalMarks}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${feedback.overallScore.toStringAsFixed(1)}% overall',
                  style: TextStyle(color: _gradeColor, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: feedback.passed
                        ? const Color(0xFF22C55E).withOpacity(0.15)
                        : const Color(0xFFEF4444).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    feedback.passed ? '✓  Passed' : '✗  Failed',
                    style: TextStyle(
                      color: feedback.passed
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFEF4444),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Reusable card ────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget child;

  const _Card({
    required this.title,
    required this.icon,
    this.iconColor = const Color(0xFF6C63FF),
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E3147)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
          ]),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ─── Skill bar ────────────────────────────────────────────────────────────────

class _SkillBar extends StatelessWidget {
  final String label;
  final double value; // 0-10

  const _SkillBar(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(
                    color: Color(0xFF8B8FA8), fontSize: 12)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: value / 10),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => LinearProgressIndicator(
                  value: v,
                  minHeight: 6,
                  backgroundColor: const Color(0xFF2E3147),
                  valueColor:
                      const AlwaysStoppedAnimation(Color(0xFF6C63FF)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('${value.toStringAsFixed(1)}/10',
              style: const TextStyle(
                  color: Color(0xFF6C63FF),
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─── Bullet item ──────────────────────────────────────────────────────────────

class _BulletItem extends StatelessWidget {
  final String text;
  final Color color;
  const _BulletItem(this.text, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: CircleAvatar(radius: 3, backgroundColor: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: Color(0xFFCDD0E0), fontSize: 12, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

// ─── Question tile ────────────────────────────────────────────────────────────

class _QuestionTile extends StatelessWidget {
  final QuestionFeedback q;
  const _QuestionTile(this.q);

  @override
  Widget build(BuildContext context) {
    final pct = q.maxScore > 0 ? q.scoreAwarded / q.maxScore : 0.0;
    final color = pct >= 0.7
        ? const Color(0xFF22C55E)
        : pct >= 0.4
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1117),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Q${q.questionNumber}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
              Text('${q.scoreAwarded}/${q.maxScore}',
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ],
          ),
          if (q.detectedAnswer.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Answer: ${q.detectedAnswer}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Color(0xFF555870), fontSize: 11)),
          ],
          const SizedBox(height: 6),
          Text(q.feedback,
              style: const TextStyle(
                  color: Color(0xFFCDD0E0), fontSize: 12, height: 1.4)),
        ],
      ),
    );
  }
}

// ─── Chip ─────────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  const _Chip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF6C63FF).withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.3)),
      ),
      child: Text(label,
          style: const TextStyle(
              color: Color(0xFF6C63FF),
              fontSize: 12,
              fontWeight: FontWeight.w500)),
    );
  }
}