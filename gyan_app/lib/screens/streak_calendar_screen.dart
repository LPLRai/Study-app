// ─────────────────────────────────────────────────────────────────────────────
// screens/streak_calendar_screen.dart
//
// Opened from the Home "Daily Streaks" block.
//   • Current streak, best streak, total days studied.
//   • A Google-calendar-style month grid that can page through any month
//     (past or future). Days with a qualifying session are highlighted and
//     show how long was studied; other days look like a normal calendar.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';

class StreakCalendarScreen extends StatefulWidget {
  const StreakCalendarScreen({super.key});
  @override
  State<StreakCalendarScreen> createState() => _StreakCalendarScreenState();
}

class _StreakCalendarScreenState extends State<StreakCalendarScreen> {
  late DateTime _month; // first day of the visible month

  static const _fire = Color(0xFFFF8C00);
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  static const _weekdayHeaders = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _month = DateTime(n.year, n.month, 1);
  }

  void _shiftMonth(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta, 1));

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _shortDur(int seconds) {
    if (seconds <= 0) return '';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return m > 0 ? '${h}h${m}' : '${h}h';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(builder: (context, prov, _) {
      final t = prov.appTheme;
      final studied = prov.studiedDays; // computed once
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      return Scaffold(
        backgroundColor: t.background,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ────────────────────────────────────────────
                Row(children: [
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
                  Text('Streak',
                      style: GoogleFonts.inder(
                          color: t.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 12),

                // ── Stat cards ────────────────────────────────────────
                Row(children: [
                  _statCard(t, Icons.local_fire_department_rounded, _fire,
                      '${prov.currentStreakDays}', 'Current streak'),
                  const SizedBox(width: 12),
                  _statCard(t, Icons.emoji_events_rounded, AppColors.yellow,
                      '${prov.bestStreakDays}', 'Best streak'),
                  const SizedBox(width: 12),
                  _statCard(t, Icons.event_available_rounded, AppColors.green,
                      '${prov.totalStudiedDays}', 'Days studied'),
                ]),
                const SizedBox(height: 20),

                // ── Calendar card ─────────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
                  decoration: _deco(t),
                  child: Column(children: [
                    // month navigator
                    Row(children: [
                      _navBtn(t, Icons.chevron_left_rounded,
                          () => _shiftMonth(-1)),
                      Expanded(
                        child: Text(
                          '${_monthNames[_month.month - 1]} ${_month.year}',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inder(
                              color: t.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      _navBtn(t, Icons.chevron_right_rounded,
                          () => _shiftMonth(1)),
                    ]),
                    const SizedBox(height: 12),
                    // weekday headers
                    Row(
                      children: _weekdayHeaders
                          .map((d) => Expanded(
                                child: Center(
                                  child: Text(d,
                                      style: GoogleFonts.inder(
                                          color: t.textMuted, fontSize: 12)),
                                ),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 6),
                    _grid(prov, t, studied, today),
                  ]),
                ),
                const SizedBox(height: 16),

                // ── Legend ────────────────────────────────────────────
                Row(children: [
                  _legendDot(_fire, 'Studied', t),
                  const SizedBox(width: 18),
                  _legendRing(AppColors.blue, 'Today', t),
                ]),
              ],
            ),
          ),
        ),
      );
    });
  }

  // ── Calendar grid ───────────────────────────────────────────────────────────
  Widget _grid(AppProvider prov, AppThemeData t, Set<DateTime> studied,
      DateTime today) {
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    final leading = _month.weekday - 1; // Monday-first offset
    final cells = leading + daysInMonth;
    final rows = (cells / 7).ceil();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows * 7,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisExtent: 50,
      ),
      itemBuilder: (_, i) {
        final dayNum = i - leading + 1;
        if (dayNum < 1 || dayNum > daysInMonth) return const SizedBox.shrink();
        final day = DateTime(_month.year, _month.month, dayNum);
        final isStudied = studied.contains(day);
        final isToday = _sameDay(day, today);
        final isFuture = day.isAfter(today);
        final secs = isStudied
            ? prov.secondsInRange(day, day.add(const Duration(days: 1)))
            : 0;

        return _dayCell(t, dayNum, isStudied, isToday, isFuture, secs);
      },
    );
  }

  Widget _dayCell(AppThemeData t, int dayNum, bool studied, bool isToday,
      bool isFuture, int secs) {
    final numberColor = studied
        ? _fire
        : isToday
            ? AppColors.blue
            : isFuture
                ? t.textMuted.withOpacity(0.5)
                : t.textPrimary;

    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: studied ? _fire.withOpacity(0.16) : Colors.transparent,
            border: isToday
                ? Border.all(color: AppColors.blue, width: 1.6)
                : studied
                    ? Border.all(color: _fire.withOpacity(0.6))
                    : null,
          ),
          child: Text('$dayNum',
              style: GoogleFonts.inder(
                  color: numberColor,
                  fontSize: 13,
                  fontWeight:
                      (studied || isToday) ? FontWeight.bold : FontWeight.normal)),
        ),
        if (studied)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(_shortDur(secs),
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: GoogleFonts.inder(color: _fire, fontSize: 8)),
          ),
      ],
    );
  }

  // ── Bits ────────────────────────────────────────────────────────────────────
  Widget _statCard(AppThemeData t, IconData icon, Color color, String value,
      String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: _deco(t),
        child: Column(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(value,
              style: GoogleFonts.inder(
                  color: t.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: GoogleFonts.inder(color: t.textMuted, fontSize: 10)),
        ]),
      ),
    );
  }

  Widget _navBtn(AppThemeData t, IconData icon, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: t.inputBg, shape: BoxShape.circle),
          child: Icon(icon, color: t.textPrimary, size: 22),
        ),
      );

  Widget _legendDot(Color color, String label, AppThemeData t) => Row(children: [
        Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
                color: color.withOpacity(0.16),
                shape: BoxShape.circle,
                border: Border.all(color: color.withOpacity(0.6)))),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.inder(color: t.textMuted, fontSize: 12)),
      ]);

  Widget _legendRing(Color color, String label, AppThemeData t) =>
      Row(children: [
        Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 1.6))),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.inder(color: t.textMuted, fontSize: 12)),
      ]);

  BoxDecoration _deco(AppThemeData t) => BoxDecoration(
        color: t.widgetBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.cardBorder),
        boxShadow: t.widgetShadow,
      );
}
