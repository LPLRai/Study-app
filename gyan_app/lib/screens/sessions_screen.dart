// ─────────────────────────────────────────────────────────────────────────────
// screens/sessions_screen.dart
//
// Opened from the Home "Sessions Done" block.
//   • Daily / Weekly / Monthly dropdown.
//   • Headline session count + total time + average session length.
//   • A donut chart of study time per subject, with a colour legend that also
//     shows each subject's session count, time and share.
// Driven by AppProvider (incl. the live session) so it updates in real time.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';

enum _Range { daily, weekly, monthly }

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});
  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  _Range _range = _Range.daily;

  DateTime get _todayStart {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime get _rangeStart => switch (_range) {
        _Range.daily => _todayStart,
        _Range.weekly => _todayStart.subtract(const Duration(days: 6)),
        _Range.monthly => _todayStart.subtract(const Duration(days: 29)),
      };

  DateTime get _rangeEnd => DateTime.now().add(const Duration(seconds: 1));

  String get _rangeLabel => switch (_range) {
        _Range.daily => 'today',
        _Range.weekly => 'this week',
        _Range.monthly => 'this month',
      };

  String _fmt(int seconds) {
    if (seconds <= 0) return '0m';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
    if (m > 0) return '${m}m';
    return '${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(builder: (context, prov, _) {
      final t = prov.appTheme;
      final stats = prov.subjectStats(_rangeStart, _rangeEnd);
      final counts = prov.subjectSessionCounts(_rangeStart, _rangeEnd);
      final totalSessions = prov.sessionsInRange(_rangeStart, _rangeEnd);
      final totalSec = stats.fold<int>(0, (s, e) => s + e.seconds);
      final avgSec = totalSessions > 0 ? totalSec ~/ totalSessions : 0;

      final slices = _buildSlices(stats, counts, t);

      return Scaffold(
        backgroundColor: t.background,
        body: SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.chevron_left_rounded,
                        color: t.textPrimary, size: 28),
                  ),
                ),
                const SizedBox(width: 2),
                Text('Sessions',
                    style: GoogleFonts.inder(
                        color: t.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                _rangeDropdown(t),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _summaryCard(t, totalSessions, totalSec, avgSec, stats.length),
                    const SizedBox(height: 16),
                    _donutCard(t, slices, totalSec, totalSessions),
                  ],
                ),
              ),
            ),
          ]),
        ),
      );
    });
  }

  // ── Summary ─────────────────────────────────────────────────────────────────
  Widget _summaryCard(AppThemeData t, int sessions, int totalSec, int avgSec,
      int subjects) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: _deco(t),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$sessions',
              style: GoogleFonts.inder(
                  color: t.textPrimary,
                  fontSize: 40,
                  fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(sessions == 1 ? 'session $_rangeLabel' : 'sessions $_rangeLabel',
                style: GoogleFonts.inder(color: t.textMuted, fontSize: 14)),
          ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          _miniStat('Total time', _fmt(totalSec), t),
          _vDivider(t),
          _miniStat('Avg / session', _fmt(avgSec), t),
          _vDivider(t),
          _miniStat('Subjects', '$subjects', t),
        ]),
      ]),
    );
  }

  Widget _miniStat(String label, String value, AppThemeData t) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: GoogleFonts.inder(
                  color: t.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.inder(color: t.textMuted, fontSize: 11)),
        ]),
      );

  Widget _vDivider(AppThemeData t) =>
      Container(width: 1, height: 30, color: t.cardBorder);

  // ── Donut + legend ──────────────────────────────────────────────────────────
  Widget _donutCard(
      AppThemeData t, List<_Slice> slices, int totalSec, int totalSessions) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _deco(t),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Time by Subject',
            style: GoogleFonts.inder(
                color: t.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 18),
        if (slices.isEmpty || totalSec <= 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Column(children: [
                Icon(Icons.donut_large_rounded, color: t.textMuted, size: 40),
                const SizedBox(height: 12),
                Text('No sessions $_rangeLabel yet',
                    style:
                        GoogleFonts.inder(color: t.textMuted, fontSize: 13)),
              ]),
            ),
          )
        else ...[
          Center(
            child: SizedBox(
              width: 190,
              height: 190,
              child: Stack(alignment: Alignment.center, children: [
                CustomPaint(
                  size: const Size(190, 190),
                  painter: _DonutPainter(slices, totalSec, t.cardBorder),
                ),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_fmt(totalSec),
                      style: GoogleFonts.inder(
                          color: t.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                  Text('total',
                      style:
                          GoogleFonts.inder(color: t.textMuted, fontSize: 11)),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          ...slices.map((s) => _legendRow(s, totalSec, t)),
        ],
      ]),
    );
  }

  Widget _legendRow(_Slice s, int totalSec, AppThemeData t) {
    final pct = totalSec > 0 ? (s.seconds / totalSec * 100).round() : 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(
            width: 12,
            height: 12,
            decoration:
                BoxDecoration(color: s.color, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inder(color: t.textPrimary, fontSize: 13)),
            Text('${s.sessions} session${s.sessions == 1 ? '' : 's'}',
                style: GoogleFonts.inder(color: t.textMuted, fontSize: 11)),
          ]),
        ),
        Text(_fmt(s.seconds),
            style: GoogleFonts.inder(
                color: t.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text('$pct%',
              textAlign: TextAlign.right,
              style: GoogleFonts.inder(color: t.textMuted, fontSize: 12)),
        ),
      ]),
    );
  }

  // ── Slice building (top 6 + Other) ──────────────────────────────────────────
  List<_Slice> _buildSlices(
      List<SubjectTimeStat> stats, Map<String, int> counts, AppThemeData t) {
    const maxSlices = 6;
    final slices = <_Slice>[];
    if (stats.length <= maxSlices) {
      for (final e in stats) {
        if (e.seconds <= 0) continue;
        slices.add(_Slice(e.name, AppColors.subjectColor(e.colorIndex),
            e.seconds, counts[e.name] ?? 0));
      }
    } else {
      for (final e in stats.take(maxSlices - 1)) {
        slices.add(_Slice(e.name, AppColors.subjectColor(e.colorIndex),
            e.seconds, counts[e.name] ?? 0));
      }
      final rest = stats.skip(maxSlices - 1);
      final restSec = rest.fold<int>(0, (a, e) => a + e.seconds);
      final restCnt = rest.fold<int>(0, (a, e) => a + (counts[e.name] ?? 0));
      if (restSec > 0) {
        slices.add(_Slice('Other', t.textMuted, restSec, restCnt));
      }
    }
    return slices;
  }

  Widget _rangeDropdown(AppThemeData t) {
    const items = {
      _Range.daily: 'Daily',
      _Range.weekly: 'Weekly',
      _Range.monthly: 'Monthly',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: t.inputBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_Range>(
          value: _range,
          isDense: true,
          dropdownColor: t.widgetBg,
          borderRadius: BorderRadius.circular(14),
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              color: t.textMuted, size: 20),
          style: GoogleFonts.inder(color: t.textPrimary, fontSize: 13),
          onChanged: (v) {
            if (v != null) setState(() => _range = v);
          },
          items: items.entries
              .map((e) => DropdownMenuItem<_Range>(
                    value: e.key,
                    child: Text(e.value,
                        style: GoogleFonts.inder(
                            color: t.textPrimary, fontSize: 13)),
                  ))
              .toList(),
        ),
      ),
    );
  }

  BoxDecoration _deco(AppThemeData t) => BoxDecoration(
        color: t.widgetBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.cardBorder),
        boxShadow: t.widgetShadow,
      );
}

class _Slice {
  final String name;
  final Color color;
  final int seconds;
  final int sessions;
  const _Slice(this.name, this.color, this.seconds, this.sessions);
}

class _DonutPainter extends CustomPainter {
  final List<_Slice> slices;
  final int totalSec;
  final Color trackColor;
  const _DonutPainter(this.slices, this.totalSec, this.trackColor);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 30.0;
    final rect = Rect.fromLTWH(
        stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);

    // background track
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    if (totalSec <= 0) return;
    const gap = 0.045; // radians of spacing between slices
    double start = -math.pi / 2;
    for (final s in slices) {
      if (s.seconds <= 0) continue;
      final sweep = (s.seconds / totalSec) * (2 * math.pi);
      final draw = (sweep - gap).clamp(0.0, 2 * math.pi);
      canvas.drawArc(
        rect,
        start + gap / 2,
        draw,
        false,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.totalSec != totalSec || old.slices != slices;
}
