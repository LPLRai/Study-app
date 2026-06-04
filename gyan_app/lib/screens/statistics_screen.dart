// ─────────────────────────────────────────────────────────────────────────────
// screens/statistics_screen.dart
//
// Full statistics window opened from the Home "Statistics" block.
//   • Range dropdown: Daily / Weekly / Monthly (opens on Daily).
//   • Activity bar graph — tap a bar to see that period's studied time.
//   • Subject breakdown as a vertical bar chart with X/Y axes + a legend,
//     with a Top 3 / Top 5 / Top 7 dropdown.
// Everything is driven by AppProvider (incl. the live session) so the numbers
// match every page and update in real time while studying.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';

enum _Range { daily, weekly, monthly }

enum _TopN { top3, top5, top7 }

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});
  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  _Range _range = _Range.daily; // opens on Daily
  _TopN _topN = _TopN.top3;
  int? _selectedBar; // tapped activity bar

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];

  DateTime get _todayStart {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime get _rangeStart {
    switch (_range) {
      case _Range.daily:
        return _todayStart;
      case _Range.weekly:
        return _todayStart.subtract(const Duration(days: 6));
      case _Range.monthly:
        return _todayStart.subtract(const Duration(days: 29));
    }
  }

  DateTime get _rangeEnd => DateTime.now().add(const Duration(seconds: 1));

  String get _rangeLabel => switch (_range) {
        _Range.daily => 'today',
        _Range.weekly => 'this week',
        _Range.monthly => 'this month',
      };

  int get _rangeDays => switch (_range) {
        _Range.daily => 1,
        _Range.weekly => 7,
        _Range.monthly => 30,
      };

  String _fmt(int seconds) {
    if (seconds <= 0) return '0m';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
    if (m > 0) return '${m}m';
    return '${seconds}s';
  }

  // ── Activity time-series ────────────────────────────────────────────────────
  List<_Bar> _seriesBars(AppProvider prov) {
    final today = _todayStart;
    switch (_range) {
      case _Range.daily:
        const labels = ['12a', '4a', '8a', '12p', '4p', '8p'];
        const tips = [
          '12am – 4am', '4am – 8am', '8am – 12pm',
          '12pm – 4pm', '4pm – 8pm', '8pm – 12am'
        ];
        return List.generate(6, (i) {
          final start = today.add(Duration(hours: i * 4));
          final end = today.add(Duration(hours: i * 4 + 4));
          return _Bar(labels[i], tips[i], prov.secondsInRange(start, end));
        });
      case _Range.weekly:
        const wl = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
        final start = today.subtract(const Duration(days: 6));
        return List.generate(7, (i) {
          final day = start.add(Duration(days: i));
          return _Bar(
            wl[(day.weekday - 1) % 7],
            _weekdays[(day.weekday - 1) % 7],
            prov.secondsInRange(day, day.add(const Duration(days: 1))),
            highlight: day == today,
          );
        });
      case _Range.monthly:
        final start = today.subtract(const Duration(days: 29));
        return List.generate(30, (i) {
          final day = start.add(Duration(days: i));
          final lbl = (i % 5 == 0 || i == 29) ? '${day.day}' : '';
          return _Bar(
            lbl,
            '${_months[day.month - 1]} ${day.day}',
            prov.secondsInRange(day, day.add(const Duration(days: 1))),
            highlight: day == today,
          );
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(builder: (context, prov, _) {
      final t = prov.appTheme;
      final totalSec = prov.secondsInRange(_rangeStart, _rangeEnd);
      final sessions = prov.sessionsInRange(_rangeStart, _rangeEnd);
      final avgPerDay =
          _range == _Range.daily ? totalSec : totalSec ~/ _rangeDays;

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
                Text('Statistics',
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
                    _summaryCard(t, totalSec, sessions, avgPerDay, prov),
                    const SizedBox(height: 16),
                    _activityCard(t, prov),
                    const SizedBox(height: 16),
                    _subjectsCard(t, prov),
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
  Widget _summaryCard(AppThemeData t, int totalSec, int sessions, int avgSec,
      AppProvider prov) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: _deco(t),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Studied $_rangeLabel',
            style: GoogleFonts.inder(color: t.textMuted, fontSize: 13)),
        const SizedBox(height: 6),
        Text(_fmt(totalSec),
            style: GoogleFonts.inder(
                color: t.textPrimary,
                fontSize: 36,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Row(children: [
          _miniStat('Sessions', '$sessions', t),
          _vDivider(t),
          _miniStat(_range == _Range.daily ? 'Total today' : 'Daily avg',
              _fmt(avgSec), t),
          _vDivider(t),
          _miniStat('All-time', _fmt(prov.totalSecondsAllTime), t),
        ]),
      ]),
    );
  }

  Widget _miniStat(String label, String value, AppThemeData t) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: GoogleFonts.inder(
                  color: t.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.inder(color: t.textMuted, fontSize: 11)),
        ]),
      );

  Widget _vDivider(AppThemeData t) =>
      Container(width: 1, height: 30, color: t.cardBorder);

  // ── Activity graph (tap a bar for its time) ─────────────────────────────────
  Widget _activityCard(AppThemeData t, AppProvider prov) {
    final bars = _seriesBars(prov);
    final maxV = bars.fold<int>(1, (m, b) => b.value > m ? b.value : m);
    const chartH = 150.0;
    final sel = (_selectedBar != null && _selectedBar! < bars.length)
        ? bars[_selectedBar!]
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: _deco(t),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Activity',
              style: GoogleFonts.inder(
                  color: t.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const Spacer(),
          if (sel != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.blue.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${sel.tooltip} · ${_fmt(sel.value)}',
                  style: GoogleFonts.inder(
                      color: AppColors.blue,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            )
          else
            Text('Tap a bar for details',
                style: GoogleFonts.inder(color: t.textMuted, fontSize: 11)),
        ]),
        const SizedBox(height: 18),
        SizedBox(
          height: chartH + 20,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(bars.length, (i) {
              final b = bars[i];
              final isZero = b.value == 0;
              final isSel = _selectedBar == i;
              final h = maxV == 0 ? 0.0 : (b.value / maxV) * chartH;
              final Color barColor = isZero
                  ? t.cardBorder
                  : isSel
                      ? AppColors.blue
                      : (b.highlight
                          ? AppColors.blue.withOpacity(0.75)
                          : AppColors.blue.withOpacity(0.45));
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      setState(() => _selectedBar = isSel ? null : i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOut,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        height: isZero ? 3 : (h < 5 ? 5 : h),
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                          border: isSel
                              ? Border.all(color: AppColors.blue, width: 2)
                              : null,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 13,
                        child: Text(b.label,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: GoogleFonts.inder(
                                color: (isSel || b.highlight)
                                    ? AppColors.blue
                                    : t.textMuted,
                                fontSize: 9)),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ]),
    );
  }

  // ── Subject breakdown — vertical bar chart with X/Y axes + legend ───────────
  Widget _subjectsCard(AppThemeData t, AppProvider prov) {
    final all = prov.subjectStats(_rangeStart, _rangeEnd);
    final n = switch (_topN) {
      _TopN.top3 => 3,
      _TopN.top5 => 5,
      _TopN.top7 => 7,
    };
    final top = all.take(n).toList();
    final totalSec = all.fold<int>(0, (s, e) => s + e.seconds);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _deco(t),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Top Subjects',
              style: GoogleFonts.inder(
                  color: t.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const Spacer(),
          _topNDropdown(t),
        ]),
        const SizedBox(height: 18),
        if (top.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text('No study data for $_rangeLabel',
                  style: GoogleFonts.inder(color: t.textMuted, fontSize: 13)),
            ),
          )
        else ...[
          _subjectBarChart(top, t),
          const SizedBox(height: 18),
          ...top.map((e) => _legendRow(e, totalSec, t)),
        ],
      ]),
    );
  }

  Widget _subjectBarChart(List<SubjectTimeStat> top, AppThemeData t) {
    final maxSec = top.first.seconds <= 0 ? 1 : top.first.seconds;
    const chartH = 150.0;
    const topPad = 4.0; // headroom above tallest bar

    Widget gridline() => Container(height: 1, color: t.cardBorder);

    return SizedBox(
      height: chartH + topPad + 22, // chart + x-axis labels
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Y-axis labels
        SizedBox(
          width: 42,
          height: chartH + topPad,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _axisLabel(_fmt(maxSec), t),
              _axisLabel(_fmt(maxSec ~/ 2), t),
              _axisLabel('0', t),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Plot area
        Expanded(
          child: Column(children: [
            SizedBox(
              height: chartH + topPad,
              child: Stack(children: [
                // gridlines (top / middle / bottom)
                Positioned(top: topPad, left: 0, right: 0, child: gridline()),
                Positioned(
                    top: topPad + chartH / 2,
                    left: 0,
                    right: 0,
                    child: gridline()),
                Positioned(bottom: 0, left: 0, right: 0, child: gridline()),
                // bars
                Padding(
                  padding: const EdgeInsets.only(top: topPad),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: top.map((e) {
                      final color = AppColors.subjectColor(e.colorIndex);
                      final h = (e.seconds / maxSec) * chartH;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 450),
                            curve: Curves.easeOut,
                            height: h < 4 ? 4 : h,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6)),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 6),
            // X-axis labels (abbreviated subject names)
            Row(
              children: top
                  .map((e) => Expanded(
                        child: Text(_abbrev(e.name),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inder(
                                color: t.textMuted, fontSize: 10)),
                      ))
                  .toList(),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _axisLabel(String s, AppThemeData t) => Text(s,
      style: GoogleFonts.inder(color: t.textMuted, fontSize: 9));

  Widget _legendRow(SubjectTimeStat e, int totalSec, AppThemeData t) {
    final color = AppColors.subjectColor(e.colorIndex);
    final pct = totalSec > 0 ? (e.seconds / totalSec * 100).round() : 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(children: [
        Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 9),
        Expanded(
          child: Text(e.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inder(color: t.textPrimary, fontSize: 13)),
        ),
        Text(_fmt(e.seconds),
            style: GoogleFonts.inder(
                color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Text('$pct%',
            style: GoogleFonts.inder(color: t.textMuted, fontSize: 12)),
      ]),
    );
  }

  String _abbrev(String name) =>
      name.length <= 6 ? name : '${name.substring(0, 5)}…';

  // ── Dropdowns ───────────────────────────────────────────────────────────────
  Widget _rangeDropdown(AppThemeData t) => _pillDropdown<_Range>(
        t,
        value: _range,
        onChanged: (v) => setState(() {
          _range = v;
          _selectedBar = null; // bar indices differ across ranges
        }),
        items: const {
          _Range.daily: 'Daily',
          _Range.weekly: 'Weekly',
          _Range.monthly: 'Monthly',
        },
      );

  Widget _topNDropdown(AppThemeData t) => _pillDropdown<_TopN>(
        t,
        value: _topN,
        onChanged: (v) => setState(() => _topN = v),
        items: const {
          _TopN.top3: 'Top 3',
          _TopN.top5: 'Top 5',
          _TopN.top7: 'Top 7',
        },
      );

  Widget _pillDropdown<T>(
    AppThemeData t, {
    required T value,
    required ValueChanged<T> onChanged,
    required Map<T, String> items,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: t.inputBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          dropdownColor: t.widgetBg,
          borderRadius: BorderRadius.circular(14),
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              color: t.textMuted, size: 20),
          style: GoogleFonts.inder(color: t.textPrimary, fontSize: 13),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
          items: items.entries
              .map((e) => DropdownMenuItem<T>(
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

class _Bar {
  final String label; // short axis label
  final String tooltip; // full description shown when tapped
  final int value;
  final bool highlight;
  const _Bar(this.label, this.tooltip, this.value, {this.highlight = false});
}
