// lib/widgets/analyzing_overlay.dart
//
// Full-screen overlay shown while the pipeline runs.
// Each technical stage maps to a friendly user-facing message.
// The compression / upload stages are intentionally labelled "Preparing…"
// so users never know WebP encoding is happening.

import 'dart:math';
import 'package:flutter/material.dart';
import '../services/answer_sheet_service.dart';

class AnalyzingOverlay extends StatefulWidget {
  final AnalysisStage stage;
  final double progress; // 0.0 – 1.0

  const AnalyzingOverlay({
    super.key,
    required this.stage,
    required this.progress,
  });

  @override
  State<AnalyzingOverlay> createState() => _AnalyzingOverlayState();
}

class _AnalyzingOverlayState extends State<AnalyzingOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _orbit;
  late final AnimationController _pulse;
  late final Animation<double> _pulseAnim;

  // Friendly labels — technical stages (compressing/uploading) shown as "Preparing"
  static const _labels = <AnalysisStage, String>{
    AnalysisStage.compressing:     'Preparing your answer sheet…',
    AnalysisStage.extractingText:  'Reading the answers…',
    AnalysisStage.analyzingWithAI: 'AI is evaluating responses…',
    AnalysisStage.saving:          'Saving your results…',
    AnalysisStage.done:            'Done!',
  };

  static const _subLabels = <AnalysisStage, String>{
    AnalysisStage.compressing:     'Optimising image quality',
    AnalysisStage.extractingText:  'Detecting text with OCR',
    AnalysisStage.analyzingWithAI: 'Applying evaluation rubric',
    AnalysisStage.saving:          'Writing to database',
    AnalysisStage.done:            'All done!',
  };

  @override
  void initState() {
    super.initState();
    _orbit = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _orbit.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label    = _labels[widget.stage]    ?? 'Processing…';
    final subLabel = _subLabels[widget.stage] ?? '';

    return Material(
      color: Colors.black.withOpacity(0.88),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Animated brain / orbit icon ──────────────────────────────
              SizedBox(
                width: 120,
                height: 120,
                child: AnimatedBuilder(
                  animation: _orbit,
                  builder: (_, __) {
                    return CustomPaint(
                      painter: _OrbitPainter(_orbit.value),
                      child: Center(
                        child: AnimatedBuilder(
                          animation: _pulseAnim,
                          builder: (_, child) =>
                              Transform.scale(scale: _pulseAnim.value, child: child),
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF6C63FF).withOpacity(0.15),
                              border: Border.all(
                                  color: const Color(0xFF6C63FF), width: 2),
                            ),
                            child: const Icon(
                              Icons.psychology_rounded,
                              color: Color(0xFF6C63FF),
                              size: 32,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 40),

              // ── Stage label ───────────────────────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Text(
                  label,
                  key: ValueKey(label),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  subLabel,
                  key: ValueKey(subLabel),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 14,
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // ── Progress bar ──────────────────────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: widget.progress),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  builder: (_, value, __) => LinearProgressIndicator(
                    value: value,
                    minHeight: 6,
                    backgroundColor: const Color(0xFF2E3147),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF6C63FF)),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: widget.progress),
                duration: const Duration(milliseconds: 600),
                builder: (_, v, __) => Text(
                  '${(v * 100).toInt()}%',
                  style: const TextStyle(
                    color: Color(0xFF6C63FF),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(height: 48),

              // ── Step indicators ───────────────────────────────────────────
              _StepIndicators(stage: widget.stage),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepIndicators extends StatelessWidget {
  final AnalysisStage stage;
  const _StepIndicators({required this.stage});

  static const _steps = [
    (AnalysisStage.compressing,     Icons.image_rounded,      'Preparing'),
    (AnalysisStage.extractingText,  Icons.text_snippet_rounded,'Reading'),
    (AnalysisStage.analyzingWithAI, Icons.auto_awesome_rounded,'Analyzing'),
    (AnalysisStage.saving,          Icons.save_rounded,        'Saving'),
  ];

  bool _isComplete(AnalysisStage s) => s.index < stage.index;
  bool _isActive(AnalysisStage s)   => s.index == stage.index ||
      (s == AnalysisStage.compressing && stage == AnalysisStage.compressing);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: _steps.map((step) {
        final (s, icon, label) = step;
        final done   = _isComplete(s);
        final active = _isActive(s);

        Color col = done
            ? const Color(0xFF6C63FF)
            : active
                ? Colors.white
                : const Color(0xFF3D4159);

        return Expanded(
          child: Column(
            children: [
              Icon(done ? Icons.check_circle_rounded : icon, color: col, size: 20),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      color: col, fontSize: 10, fontWeight: FontWeight.w500)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── Custom orbit painter ──────────────────────────────────────────────────────

class _OrbitPainter extends CustomPainter {
  final double t; // 0.0 – 1.0 animation value
  _OrbitPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    final trackPaint = Paint()
      ..color = const Color(0xFF2E3147)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final dotPaint = Paint()
      ..color = const Color(0xFF6C63FF)
      ..style = PaintingStyle.fill;

    // Outer orbit
    canvas.drawCircle(Offset(cx, cy), 54, trackPaint);
    final angle1 = 2 * pi * t;
    canvas.drawCircle(
        Offset(cx + 54 * cos(angle1), cy + 54 * sin(angle1)), 5, dotPaint);

    // Inner orbit (reverse)
    canvas.drawCircle(Offset(cx, cy), 36, trackPaint);
    final angle2 = 2 * pi * (1 - t * 1.6);
    canvas.drawCircle(
        Offset(cx + 36 * cos(angle2), cy + 36 * sin(angle2)), 4,
        dotPaint..color = const Color(0xFF6C63FF).withOpacity(0.5));
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => old.t != t;
}