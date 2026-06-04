import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/study_session_model.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/profile_modal.dart';
import '../widgets/notification_panel.dart';
import 'statistics_screen.dart';
import 'streak_calendar_screen.dart';
import 'sessions_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  // Warm "fire" accent for completed streak days.
  static const Color _fire = Color(0xFFFF8C00);

  String _greeting() {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return 'Good morning,';
    if (h >= 12 && h < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  String _fmtTime(int minutes) => '${minutes ~/ 60}h ${minutes % 60}m';

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(builder: (context, prov, _) {
      final t = prov.appTheme;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(context, prov, t),
              const SizedBox(height: 22),
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const StreakCalendarScreen())),
                child: _streakCard(prov, t),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const SessionsScreen())),
                    child: _sessionsDoneBlock(prov, t),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const StatisticsScreen())),
                    child: _statisticsBlock(prov, t),
                  ),
                ),
              ]),
              const SizedBox(height: 26),
              _label('Recent Session', t),
              const SizedBox(height: 10),
              if (prov.recentSessions.isEmpty)
                _emptyRecent(t)
              else
                ...prov.recentSessions.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _recentTile(context, prov, s, t),
                    )),
            ],
          ),
        ),
      );
    });
  }

  // ── Header: avatar + greeting/name on the left, bell on the right ──────────
  Widget _header(BuildContext context, AppProvider prov, AppThemeData t) {
    final imgPath = prov.user.profileImagePath;
    final hasImage = imgPath != null && File(imgPath).existsSync();

    return Row(children: [
      // Profile picture — beside the greeting. Tap to open the profile card.
      GestureDetector(
        onTap: () {
          showMenu(
            context: context,
            position: const RelativeRect.fromLTRB(16, 80, 16, 0),
            color: Colors.transparent,
            elevation: 0,
            items: [
              const PopupMenuItem(
                enabled: false,
                padding: EdgeInsets.zero,
                child: ProfileModal(),
              ),
            ],
          );
        },
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: t.widgetBg,
            border: Border.all(color: t.cardBorder, width: 1.5),
          ),
          child: ClipOval(
            child: hasImage
                ? Image.file(File(imgPath), fit: BoxFit.cover)
                : Icon(Icons.person_rounded, color: t.textMuted, size: 28),
          ),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_greeting(),
              style: GoogleFonts.inder(color: t.textMuted, fontSize: 14)),
          const SizedBox(height: 2),
          Row(children: [
            Flexible(
              child: Text(
                prov.user.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inder(
                    color: t.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 6),
            const Text('👋', style: TextStyle(fontSize: 20)),
          ]),
        ]),
      ),
      const SizedBox(width: 12),
      // Notification bell — opens the side panel.
      GestureDetector(
        onTap: () => showNotificationPanel(context),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: t.widgetBg,
            border: Border.all(color: t.cardBorder, width: 1.5),
          ),
          child: Icon(Icons.notifications_none_rounded,
              color: t.textPrimary, size: 24),
        ),
      ),
    ]);
  }

  // ── Daily streak — current week (Mon–Sun) ──────────────────────────────────
  Widget _streakCard(AppProvider prov, AppThemeData t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final days = List.generate(7, (i) => monday.add(Duration(days: i)));
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: _cardDeco(t),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Daily Streaks',
              style: GoogleFonts.inder(
                  color: t.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.bold)),
          const Spacer(),
          // Current streak chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _fire.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.local_fire_department_rounded,
                  color: _fire, size: 16),
              const SizedBox(width: 4),
              Text('${prov.currentStreakDays}',
                  style: GoogleFonts.inder(
                      color: _fire, fontSize: 13, fontWeight: FontWeight.bold)),
            ]),
          ),
          const SizedBox(width: 8),
          Icon(Icons.north_east_rounded, color: t.textMuted, size: 15),
        ]),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (int i = 0; i < 7; i++)
              _dayCell(prov, t, letters[i], days[i], today),
          ],
        ),
      ]),
    );
  }

  Widget _dayCell(AppProvider prov, AppThemeData t, String letter,
      DateTime date, DateTime today) {
    final studied = prov.didStudyOn(date);
    final isToday = _sameDay(date, today);
    final isFuture = date.isAfter(today);
    const double sz = 38;

    Widget badge;
    if (studied) {
      // Completed — fire.
      badge = Container(
        width: sz,
        height: sz,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _fire.withOpacity(0.18),
          border: Border.all(color: _fire, width: 1.6),
        ),
        child: const Icon(Icons.local_fire_department_rounded,
            color: _fire, size: 20),
      );
    } else if (isFuture) {
      // Yet to come — empty.
      badge = Container(
        width: sz,
        height: sz,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: t.inputBg,
          border: Border.all(color: t.cardBorder),
        ),
      );
    } else if (isToday) {
      // Today, not done yet — pending highlight (no "miss" until the day ends).
      badge = Container(
        width: sz,
        height: sz,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.blue.withOpacity(0.12),
          border: Border.all(color: AppColors.blue, width: 1.6),
        ),
        child: const Icon(Icons.circle, color: AppColors.blue, size: 8),
      );
    } else {
      // Missed — x.
      badge = Container(
        width: sz,
        height: sz,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.red.withOpacity(0.10),
          border: Border.all(color: AppColors.red.withOpacity(0.5)),
        ),
        child: Icon(Icons.close_rounded,
            color: AppColors.red.withOpacity(0.9), size: 18),
      );
    }

    return Column(children: [
      Text(letter,
          style: GoogleFonts.inder(
              color: isToday ? AppColors.blue : t.textMuted,
              fontSize: 12,
              fontWeight: isToday ? FontWeight.bold : FontWeight.normal)),
      const SizedBox(height: 8),
      badge,
    ]);
  }

  // ── Stat blocks ────────────────────────────────────────────────────────────
  Widget _sessionsDoneBlock(AppProvider prov, AppThemeData t) => Container(
        height: 174,
        padding: const EdgeInsets.all(16),
        decoration: _cardDeco(t),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: AppColors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.menu_book_rounded,
                  color: AppColors.green, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Sessions Done',
                  style: GoogleFonts.inder(
                      color: t.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.north_east_rounded, color: t.textMuted, size: 15),
          ]),
          const Spacer(),
          Text('${prov.todaySessionCount}',
              style: GoogleFonts.inder(
                  color: t.textPrimary,
                  fontSize: 40,
                  fontWeight: FontWeight.bold)),
          Text('today',
              style: GoogleFonts.inder(color: t.textMuted, fontSize: 11)),
        ]),
      );

  Widget _statisticsBlock(AppProvider prov, AppThemeData t) => Container(
        height: 174,
        padding: const EdgeInsets.all(16),
        decoration: _cardDeco(t),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: AppColors.blue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.bar_chart_rounded,
                  color: AppColors.blue, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Statistics',
                  style: GoogleFonts.inder(
                      color: t.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.north_east_rounded, color: t.textMuted, size: 15),
          ]),
          const Spacer(),
          Text(_fmtTime(prov.todayStudiedMinutes),
              style: GoogleFonts.inder(
                  color: t.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          Text('studied today',
              style: GoogleFonts.inder(color: t.textMuted, fontSize: 11)),
          const SizedBox(height: 10),
          SizedBox(height: 40, child: _miniBars(prov, t)),
        ]),
      );

  // Last-7-days mini bar chart (today is the right-most, highlighted bar).
  Widget _miniBars(AppProvider prov, AppThemeData t) {
    final now = DateTime.now();
    final base = DateTime(now.year, now.month, now.day);
    final vals = List.generate(
        7, (i) => prov.minutesStudiedOn(base.subtract(Duration(days: 6 - i))));
    final maxV = vals.fold<int>(1, (m, v) => v > m ? v : m);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(7, (i) {
        final isToday = i == 6;
        final h = 5.0 + (vals[i] / maxV) * 33.0;
        return Container(
          width: 8,
          height: h,
          decoration: BoxDecoration(
            color: vals[i] == 0
                ? t.cardBorder
                : (isToday ? AppColors.blue : AppColors.blue.withOpacity(0.45)),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  // ── Recent sessions (tap → open subject in Timer) ──────────────────────────
  Widget _recentTile(BuildContext context, AppProvider prov,
      StudySessionModel s, AppThemeData t) {
    final color = AppColors.subjectColor(s.colorIndex);
    final h12 = s.startTime.hour % 12 == 0 ? 12 : s.startTime.hour % 12;
    final period = s.startTime.hour < 12 ? 'AM' : 'PM';
    final time =
        '${h12.toString().padLeft(2, '0')}:${s.startTime.minute.toString().padLeft(2, '0')} $period';

    return GestureDetector(
      onTap: () => prov.openSubjectFromSession(s),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: _cardDeco(t),
        child: Row(children: [
          Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.subjectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inder(
                      color: t.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              Text(time,
                  style: GoogleFonts.inder(color: t.textMuted, fontSize: 11)),
            ]),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withOpacity(0.4))),
            child: Text('${s.durationMinutes} min',
                style: GoogleFonts.inder(
                    color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          // Affordance: tap resumes this subject in the Timer.
          Icon(Icons.play_circle_fill_rounded, color: color, size: 26),
        ]),
      ),
    );
  }

  Widget _emptyRecent(AppThemeData t) => Container(
        padding: const EdgeInsets.all(18),
        decoration: _cardDeco(t),
        child: Center(
          child: Text('No sessions yet. Start studying!',
              style: GoogleFonts.inder(color: t.textMuted)),
        ),
      );

  // ── Shared bits ──────────────────────────────────────────────────────────
  Widget _label(String text, AppThemeData t) =>
      Text(text, style: GoogleFonts.inder(color: t.textMuted, fontSize: 14));

  BoxDecoration _cardDeco(AppThemeData t) => BoxDecoration(
        color: t.widgetBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.cardBorder, width: 1),
        boxShadow: t.widgetShadow,
      );
}
