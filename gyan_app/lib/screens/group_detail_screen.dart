// ─────────────────────────────────────────────────────────────────────────────
// screens/group_detail_screen.dart
//
// Real-time group view (Firestore):
//   • Podium leaderboard (#1 centred, crown; only top-3 names) with a
//     Daily / Weekly / All-time dropdown and animated bars.
//   • If "you" aren't top-3, your row is shown at its real rank with an arrow.
//   • Member blocks that light up (orange) while studying and show that day's
//     studied time, with different icons for studying vs idle.
//   • Owner/members can invite by email (in-app invite via notifications).
//
// Times come from each member's live Firestore doc, published by their app.
// "All-time" is scoped to since-join (total − baseline-at-join).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';

enum _LbRange { daily, weekly, allTime }

const _orange = Color(0xFFFF8C00);
const _gold = Color(0xFFFFD54A);
const _silver = Color(0xFFBFC6D1);
const _bronze = Color(0xFFCD8B5A);

class GroupDetailScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  const GroupDetailScreen(
      {super.key, required this.groupId, required this.groupName});
  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  _LbRange _range = _LbRange.daily;

  String _fmt(int seconds) {
    if (seconds <= 0) return '0m';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
    if (m > 0) return '${m}m';
    return '${seconds}s';
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppColors.red : AppColors.blue,
        content: Text(msg,
            style: GoogleFonts.inder(color: Colors.white, fontSize: 13)),
      ));
  }

  void _showInvite(AppProvider prov, AppThemeData t) {
    final emailCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: t.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Invite to "${widget.groupName}"',
                  style: GoogleFonts.inder(
                      color: t.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('They get an in-app invite to accept or decline.',
                  style: GoogleFonts.inder(color: t.textMuted, fontSize: 12)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                    child: TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: GoogleFonts.inder(color: t.textPrimary),
                  decoration: InputDecoration(
                      hintText: 'member@email.com',
                      hintStyle: GoogleFonts.inder(color: t.textMuted),
                      filled: true,
                      fillColor: t.inputBg,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none)),
                )),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () async {
                    final email = emailCtrl.text.trim();
                    if (email.isEmpty) return;
                    final res = await prov.inviteByEmail(
                        widget.groupId, widget.groupName, email);
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    switch (res) {
                      case 'invited':
                        _toast('Invite sent to $email');
                        break;
                      case 'already':
                        _toast('They are already a member', error: true);
                        break;
                      case 'no_account':
                        _toast(
                            'No app account for that email — needs email invite',
                            error: true);
                        break;
                      default:
                        _toast('Could not send invite', error: true);
                    }
                  },
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 13),
                      decoration: BoxDecoration(
                          color: AppColors.blue,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text('Invite',
                          style: GoogleFonts.inder(
                              color: Colors.white, fontSize: 14))),
                ),
              ]),
            ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(builder: (context, prov, _) {
      final t = prov.appTheme;
      final myUid = prov.currentUid;

      return Scaffold(
        backgroundColor: t.background,
        body: SafeArea(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: prov.groupMembersStream(widget.groupId),
            builder: (context, snap) {
              final raw = snap.data ?? const [];
              final members = raw.map((m) {
                final uid = m['uid'] as String?;
                final isMe = uid != null && uid == myUid;
                final total = (m['totalSeconds'] as num?)?.toInt() ?? 0;
                final baseline = (m['baseline'] as num?)?.toInt() ?? 0;
                final daily = isMe
                    ? prov.todayStudiedSeconds
                    : (m['dailySeconds'] as num?)?.toInt() ?? 0;
                final week = (m['weekSeconds'] as num?)?.toInt() ?? 0;
                final allTime = isMe
                    ? math.max(0, prov.totalSecondsAllTime - baseline)
                    : math.max(0, total - baseline);
                final status = isMe
                    ? prov.studyStatus
                    : ((m['status'] as String?) ??
                        ((m['studying'] as bool? ?? false)
                            ? 'studying'
                            : 'idle'));
                return _MemberView(
                  name: (m['name'] as String?) ?? 'User',
                  isMe: isMe,
                  status: status,
                  daily: daily,
                  weekly: week,
                  allTime: allTime,
                );
              }).toList()
                ..sort((a, b) => b.timeFor(_range).compareTo(a.timeFor(_range)));

              final myRank = members.indexWhere((m) => m.isMe) + 1;

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(widget.groupName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inder(
                                        color: t.textPrimary,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold)),
                                Text('${members.length} members',
                                    style: GoogleFonts.inder(
                                        color: t.textMuted, fontSize: 12)),
                              ]),
                        ),
                        GestureDetector(
                          onTap: () => _showInvite(prov, t),
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                                color: AppColors.blue.withOpacity(0.15),
                                shape: BoxShape.circle),
                            child: const Icon(Icons.person_add_alt_1_rounded,
                                color: AppColors.blue, size: 20),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      if (snap.connectionState == ConnectionState.waiting)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 60),
                          child: Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.blue)),
                        )
                      else ...[
                        _leaderboardCard(t, members, myRank),
                        const SizedBox(height: 18),
                        Text('Members',
                            style: GoogleFonts.inder(
                                color: t.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        _membersGrid(t, members),
                      ],
                    ]),
              );
            },
          ),
        ),
      );
    });
  }

  Widget _leaderboardCard(
      AppThemeData t, List<_MemberView> members, int myRank) {
    final maxTime =
        members.isEmpty ? 1 : math.max(1, members.first.timeFor(_range));
    final topInRank = myRank >= 1 && myRank <= 3;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.blue.withOpacity(t.isDark ? 0.16 : 0.10),
            t.widgetBg,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.cardBorder),
        boxShadow: t.widgetShadow,
      ),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.leaderboard_rounded,
              color: AppColors.blue, size: 20),
          const SizedBox(width: 8),
          Text('Leaderboard',
              style: GoogleFonts.inder(
                  color: t.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const Spacer(),
          _rangeDropdown(t),
        ]),
        const SizedBox(height: 20),
        SizedBox(
          height: 262,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
                child: members.length > 1
                    ? _podiumItem(t, members[1], 2, maxTime)
                    : const SizedBox.shrink()),
            Expanded(
                child: members.isNotEmpty
                    ? _podiumItem(t, members[0], 1, maxTime)
                    : const SizedBox.shrink()),
            Expanded(
                child: members.length > 2
                    ? _podiumItem(t, members[2], 3, maxTime)
                    : const SizedBox.shrink()),
          ]),
        ),
        if (!topInRank && myRank >= 1) ...[
          const SizedBox(height: 16),
          _yourRankRow(t, members[myRank - 1], myRank),
        ],
      ]),
    );
  }

  Widget _podiumItem(AppThemeData t, _MemberView m, int rank, int maxTime) {
    final color = rank == 1 ? _gold : (rank == 2 ? _silver : _bronze);
    final time = m.timeFor(_range);
    const maxBarH = 105.0;
    final barH = (time / maxTime * maxBarH).clamp(34.0, maxBarH);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        if (rank == 1)
          const Text('👑', style: TextStyle(fontSize: 24))
        else
          const SizedBox(height: 24),
        const SizedBox(height: 4),
        _avatar(t, m, color, size: rank == 1 ? 56 : 46),
        const SizedBox(height: 6),
        Text(m.isMe ? 'You' : m.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.inder(
                color: m.isMe ? AppColors.blue : t.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(_fmt(time),
            style: GoogleFonts.inder(color: t.textMuted, fontSize: 11)),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          height: barH,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color, color.withOpacity(0.55)],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          ),
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: 6),
          child: Text('$rank',
              style: GoogleFonts.inder(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }

  Widget _yourRankRow(AppThemeData t, _MemberView m, int rank) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.blue.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.blue, width: 1.4),
      ),
      child: Row(children: [
        const Icon(Icons.subdirectory_arrow_right_rounded,
            color: AppColors.blue, size: 20),
        const SizedBox(width: 6),
        SizedBox(
          width: 34,
          child: Text('#$rank',
              style: GoogleFonts.inder(
                  color: AppColors.blue,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
        ),
        _avatar(t, m, AppColors.blue, size: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Text('You',
              style: GoogleFonts.inder(
                  color: t.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
        ),
        if (m.studying)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(Icons.bolt_rounded, color: _orange, size: 18),
          ),
        Text(_fmt(m.timeFor(_range)),
            style: GoogleFonts.inder(
                color: t.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _membersGrid(AppThemeData t, List<_MemberView> members) {
    return LayoutBuilder(builder: (_, c) {
      final w = (c.maxWidth - 12) / 2;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: members
            .map((m) => SizedBox(width: w, child: _memberBlock(t, m)))
            .toList(),
      );
    });
  }

  Widget _memberBlock(AppThemeData t, _MemberView m) {
    // Status visuals: studying=orange, short break=green, long break=purple,
    // paused/idle=muted (not lit).
    late final Color c;
    late final IconData icon;
    late final String label;
    late final bool lit;
    switch (m.status) {
      case 'studying':
        c = _orange;
        icon = Icons.menu_book_rounded;
        label = 'Studying now';
        lit = true;
        break;
      case 'short_break':
        c = AppColors.green;
        icon = Icons.local_cafe_rounded;
        label = 'Short break';
        lit = true;
        break;
      case 'long_break':
        c = const Color(0xFF9B59B6);
        icon = Icons.nightlight_round;
        label = 'Long break';
        lit = true;
        break;
      case 'paused':
        c = t.textMuted;
        icon = Icons.pause_circle_outline_rounded;
        label = 'Paused';
        lit = false;
        break;
      default:
        c = t.textMuted;
        icon = Icons.bedtime_rounded;
        label = 'Idle';
        lit = false;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: lit ? c.withOpacity(0.12) : t.widgetBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: lit ? c : t.cardBorder, width: lit ? 1.6 : 1),
        boxShadow:
            lit ? [BoxShadow(color: c.withOpacity(0.25), blurRadius: 14)] : t.widgetShadow,
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: lit
                ? c.withOpacity(0.2)
                : (t.isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
          ),
          child: Icon(icon, color: lit ? c : t.textMuted, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.isMe ? '${m.name} (You)' : m.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inder(
                    color: t.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Row(children: [
              if (m.studying) ...[
                const Icon(Icons.bolt_rounded, color: _orange, size: 13),
                const SizedBox(width: 2),
              ],
              Flexible(
                child: Text(_fmt(m.daily),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inder(
                        color: lit ? c : t.textMuted,
                        fontSize: 12,
                        fontWeight: lit ? FontWeight.w600 : FontWeight.normal)),
              ),
            ]),
            Text(label,
                style: GoogleFonts.inder(
                    color: lit ? c : t.textMuted, fontSize: 9)),
          ]),
        ),
      ]),
    );
  }

  Widget _avatar(AppThemeData t, _MemberView m, Color ring, {double size = 46}) {
    final initial = m.name.isNotEmpty ? m.name[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ring.withOpacity(0.18),
        border: Border.all(
            color: m.studying ? _orange : ring, width: m.studying ? 2.6 : 2),
        boxShadow: m.studying
            ? [BoxShadow(color: _orange.withOpacity(0.5), blurRadius: 10)]
            : null,
      ),
      child: Text(initial,
          style: GoogleFonts.inder(
              color: t.textPrimary,
              fontSize: size * 0.4,
              fontWeight: FontWeight.bold)),
    );
  }

  Widget _rangeDropdown(AppThemeData t) {
    const items = {
      _LbRange.daily: 'Daily',
      _LbRange.weekly: 'Weekly',
      _LbRange.allTime: 'All-time',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: t.inputBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_LbRange>(
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
              .map((e) => DropdownMenuItem<_LbRange>(
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
}

class _MemberView {
  final String name;
  final bool isMe;
  final String status; // studying | paused | short_break | long_break | idle
  final int daily;
  final int weekly;
  final int allTime;
  const _MemberView({
    required this.name,
    required this.isMe,
    required this.status,
    required this.daily,
    required this.weekly,
    required this.allTime,
  });

  bool get studying => status == 'studying';
  bool get onBreak => status == 'short_break' || status == 'long_break';

  int timeFor(_LbRange r) => switch (r) {
        _LbRange.daily => daily,
        _LbRange.weekly => weekly,
        _LbRange.allTime => allTime,
      };
}
