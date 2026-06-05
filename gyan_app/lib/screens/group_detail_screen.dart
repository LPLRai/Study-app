// ─────────────────────────────────────────────────────────────────────────────
// screens/group_detail_screen.dart
//
// Real-time group view (Firestore):
//   • Podium leaderboard with Daily / Weekly / All-time range.
//   • Member blocks that light up while studying — tap any member to see their
//     profile (rank, class, subjects, goal, studied time…) and nudge them.
//   • Group leader: sticky + FAB to add members, info panel to edit name /
//     description, remove members, or delete the group.
//   • Members: info panel to view everyone and leave the group.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';

enum _LbRange { daily, weekly, allTime }

const _orange = Color(0xFFFF8C00);
const _purple = Color(0xFF9B59B6);
const _gold = Color(0xFFFFD54A);
const _silver = Color(0xFFBFC6D1);
const _bronze = Color(0xFFCD8B5A);

/// Visual treatment for a member status (shared by the grid and profile sheet).
typedef _StatusVisual = ({Color color, IconData icon, String label, bool lit});

_StatusVisual _statusVisual(String status, AppThemeData t) {
  switch (status) {
    case 'studying':
      return (color: _orange, icon: Icons.menu_book_rounded, label: 'Studying now', lit: true);
    case 'short_break':
      return (color: AppColors.green, icon: Icons.local_cafe_rounded, label: 'Short break', lit: true);
    case 'long_break':
      return (color: _purple, icon: Icons.nightlight_round, label: 'Long break', lit: true);
    case 'paused':
      return (color: t.textMuted, icon: Icons.pause_circle_outline_rounded, label: 'Paused', lit: false);
    default:
      return (color: t.textMuted, icon: Icons.bedtime_rounded, label: 'Idle', lit: false);
  }
}

class GroupDetailScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String ownerUid;
  final String description;

  const GroupDetailScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.ownerUid,
    required this.description,
  });

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  _LbRange _range = _LbRange.daily;
  bool _showInfoPanel = false;

  // Resolved member profiles, cached so the profile popup loads once per member
  // and shows static data (never re-fetches while open).
  final Map<String, Map<String, dynamic>> _profileCache = {};

  // Live group fields — refreshed from the group-doc stream each build, falling
  // back to the values passed in so there's no first-frame flash.
  late String _name = widget.groupName;
  late String _description = widget.description;
  late String _ownerUid = widget.ownerUid;
  bool _isOwner = false;

  // ── Formatting helpers ──────────────────────────────────────────────────────
  String _fmt(int seconds) {
    if (seconds <= 0) return '0m';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
    if (m > 0) return '${m}m';
    return '${seconds}s';
  }

  String _date(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
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

  // ── Add member (owner, from FAB) ────────────────────────────────────────────
  void _showInvite(AppProvider prov, AppThemeData t) {
    final emailCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: t.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHeader(t, Icons.person_add_rounded, 'Add Member',
                    'Send an in-app invite', sheetCtx),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(
                      child: TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: GoogleFonts.inder(color: t.textPrimary),
                    decoration: _fieldDecoration(t, 'member@email.com'),
                  )),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () async {
                      final email = emailCtrl.text.trim();
                      if (email.isEmpty) return;
                      final res = await prov.inviteByEmail(
                          widget.groupId, _name, email);
                      if (!sheetCtx.mounted) return;
                      Navigator.pop(sheetCtx);
                      switch (res) {
                        case 'invited':
                          _toast('Invite sent to $email');
                          break;
                        case 'already':
                          _toast('Already a member', error: true);
                          break;
                        case 'no_account':
                          _toast('No app account for that email', error: true);
                          break;
                        default:
                          _toast('Could not send invite', error: true);
                      }
                    },
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 13),
                        decoration: BoxDecoration(
                            color: AppColors.blue,
                            borderRadius: BorderRadius.circular(10)),
                        child: Text('Invite',
                            style: GoogleFonts.inder(
                                color: Colors.white, fontSize: 14))),
                  ),
                ]),
              ]),
        ),
      ),
    );
  }

  // ── Edit group info (owner, from info panel) ────────────────────────────────
  void _showEditGroup(AppProvider prov, AppThemeData t) {
    final nameCtrl = TextEditingController(text: _name);
    final descCtrl = TextEditingController(text: _description);
    showModalBottomSheet(
      context: context,
      backgroundColor: t.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHeader(t, Icons.edit_rounded, 'Edit Group',
                    'Update name & description', sheetCtx),
                const SizedBox(height: 18),
                Text('Group Name',
                    style: GoogleFonts.inder(
                        color: t.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  style: GoogleFonts.inder(color: t.textPrimary),
                  textCapitalization: TextCapitalization.words,
                  decoration: _fieldDecoration(t, 'Group name'),
                ),
                const SizedBox(height: 14),
                Text('Description',
                    style: GoogleFonts.inder(
                        color: t.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                  controller: descCtrl,
                  style: GoogleFonts.inder(color: t.textPrimary),
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: _fieldDecoration(t, 'What is this group about?'),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) {
                      _toast('Group name cannot be empty', error: true);
                      return;
                    }
                    await prov.updateGroupInfo(
                        widget.groupId, name, descCtrl.text.trim());
                    if (!sheetCtx.mounted) return;
                    Navigator.pop(sheetCtx);
                    _toast('Group updated');
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                        color: AppColors.blue,
                        borderRadius: BorderRadius.circular(12)),
                    child: Text('Save Changes',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inder(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
        ),
      ),
    );
  }

  // ── Member profile popup (everyone) ─────────────────────────────────────────
  Future<void> _showMemberProfile(
      AppProvider prov, AppThemeData t, _MemberView m, int rank) async {
    // Load the member's profile exactly once, then cache it — the popup shows
    // static data and never reloads while it is open.
    Map<String, dynamic>? profile = _profileCache[m.uid];
    if (profile == null) {
      profile = await prov
          .fetchUserProfile(m.uid)
          .timeout(const Duration(seconds: 6), onTimeout: () => null);
      if (!mounted) return;
      if (profile != null) _profileCache[m.uid] = profile;
    }
    if (!mounted) return;

    final vis = _statusVisual(m.status, t);
    final grade = (profile?['grade'] as String?)?.trim() ?? '';
    final goal = (profile?['studyGoal'] as String?)?.trim() ?? '';
    final time = (profile?['studyTime'] as String?)?.trim() ?? '';
    final strong = List<String>.from(profile?['strongSubjects'] ?? const []);
    final weak = List<String>.from(profile?['weakSubjects'] ?? const []);
    final hasAny = grade.isNotEmpty ||
        goal.isNotEmpty ||
        time.isNotEmpty ||
        strong.isNotEmpty ||
        weak.isNotEmpty;

    showModalBottomSheet(
      context: context,
      backgroundColor: t.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) {
        final maxH = MediaQuery.of(sheetCtx).size.height * 0.5;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: t.textMuted.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Header: avatar + name + rank/status
                  Row(children: [
                    _avatar(t, m, vis.color, size: 54),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.isMe ? '${m.name} (You)' : m.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inder(
                                    color: t.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                    color: AppColors.blue.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(6)),
                                child: Text('Rank #$rank',
                                    style: GoogleFonts.inder(
                                        color: AppColors.blue,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                              ),
                              const SizedBox(width: 8),
                              Icon(vis.icon, size: 13, color: vis.color),
                              const SizedBox(width: 3),
                              Text(vis.label,
                                  style: GoogleFonts.inder(
                                      color: vis.color, fontSize: 11)),
                            ]),
                          ]),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  // Studied-time stat cards
                  Row(children: [
                    Expanded(
                        child: _statCard(t, 'Today', _fmt(m.daily),
                            Icons.today_rounded)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _statCard(t, 'Total studied',
                            _fmt(m.allTime), Icons.timelapse_rounded)),
                  ]),
                  const SizedBox(height: 10),
                  // Profile details — pre-loaded once, rendered statically.
                  if (grade.isNotEmpty)
                    _infoRow(t, Icons.school_rounded, 'Class', grade),
                  if (goal.isNotEmpty)
                    _infoRow(t, Icons.flag_rounded, 'Study goal', goal),
                  if (time.isNotEmpty)
                    _infoRow(t, Icons.schedule_rounded, 'Preferred time', time),
                  if (strong.isNotEmpty)
                    _subjectsBlock(t, Icons.thumb_up_alt_rounded, 'Strengths',
                        strong, AppColors.green),
                  if (weak.isNotEmpty)
                    _subjectsBlock(t, Icons.trending_up_rounded, 'Improving',
                        weak, _orange),
                  if (!hasAny)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                          "This member hasn't shared profile details yet.",
                          style: GoogleFonts.inder(
                              color: t.textMuted, fontSize: 12, height: 1.4)),
                    ),
                  const SizedBox(height: 12),
                  Divider(color: t.divider, height: 1),
                  const SizedBox(height: 12),
                  // Footer: joined date + notify button
                  Row(children: [
                    Icon(Icons.calendar_today_rounded,
                        size: 13, color: t.textMuted),
                    const SizedBox(width: 6),
                    Text(
                        m.joined != null
                            ? 'Joined ${_date(m.joined!)}'
                            : 'Member',
                        style: GoogleFonts.inder(
                            color: t.textMuted, fontSize: 12)),
                    const Spacer(),
                    if (!m.isMe)
                      GestureDetector(
                        onTap: () async {
                          await prov.sendStudyReminder(m.uid);
                          if (!sheetCtx.mounted) return;
                          Navigator.pop(sheetCtx);
                          _toast('Reminder sent to ${m.name} 🔔');
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.blue,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                  color: AppColors.blue.withOpacity(0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3)),
                            ],
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.notifications_active_rounded,
                                color: Colors.white, size: 16),
                            const SizedBox(width: 6),
                            Text('Notify to study',
                                style: GoogleFonts.inder(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                  ]),
                ]),
          ),
        );
      },
    );
  }

  // ── Confirm dialog ──────────────────────────────────────────────────────────
  Future<bool> _confirm(String title, String body, String actionLabel) async {
    final t = context.read<AppProvider>().appTheme;
    return (await showDialog<bool>(
          context: context,
          builder: (dCtx) => AlertDialog(
            backgroundColor: t.widgetBg,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Text(title,
                style: GoogleFonts.inder(
                    color: t.textPrimary, fontWeight: FontWeight.bold)),
            content: Text(body,
                style: GoogleFonts.inder(color: t.textMuted, fontSize: 14)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx, false),
                child: Text('Cancel',
                    style: GoogleFonts.inder(color: AppColors.blue)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dCtx, true),
                child: Text(actionLabel,
                    style: GoogleFonts.inder(
                        color: AppColors.red, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        )) ??
        false;
  }

  Future<void> _leaveGroup(AppProvider prov) async {
    final ok = await _confirm('Leave Group',
        'Are you sure you want to leave "$_name"?', 'Leave');
    if (!ok) return;
    await prov.leaveGroupRemote(widget.groupId);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _deleteGroup(AppProvider prov) async {
    final ok = await _confirm('Delete Group',
        'This will permanently delete "$_name" for all members.', 'Delete');
    if (!ok) return;
    await prov.deleteGroupRemote(widget.groupId);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _kickMember(
      AppProvider prov, String memberUid, String memberName) async {
    final ok = await _confirm(
        'Remove Member', 'Remove $memberName from "$_name"?', 'Remove');
    if (!ok) return;
    await prov.kickMember(widget.groupId, memberUid);
    _toast('$memberName removed');
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(builder: (context, prov, _) {
      final t = prov.appTheme;
      final myUid = prov.currentUid;
      final panelWidth =
          math.min(310.0, MediaQuery.of(context).size.width * 0.88);

      return Scaffold(
        backgroundColor: t.background,
        body: SafeArea(
          child: StreamBuilder<Map<String, dynamic>?>(
            stream: prov.groupStream(widget.groupId),
            builder: (context, gSnap) {
              // Refresh cached live fields (fall back to constructor values).
              final g = gSnap.data;
              _name = (g?['name'] as String?) ?? widget.groupName;
              _description =
                  (g?['description'] as String?) ?? widget.description;
              _ownerUid = (g?['ownerUid'] as String?) ?? widget.ownerUid;
              _isOwner = myUid != null && myUid == _ownerUid;

              return StreamBuilder<List<Map<String, dynamic>>>(
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
                      uid: uid ?? '',
                      name: (m['name'] as String?) ?? 'User',
                      isMe: isMe,
                      status: status,
                      daily: daily,
                      weekly: week,
                      allTime: allTime,
                      joined: (m['joinedAt'] as Timestamp?)?.toDate(),
                    );
                  }).toList()
                    ..sort((a, b) =>
                        b.timeFor(_range).compareTo(a.timeFor(_range)));

                  final myRank = members.indexWhere((m) => m.isMe) + 1;
                  final loading =
                      snap.connectionState == ConnectionState.waiting;

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // ── Main content ──────────────────────────────────────
                      Column(children: [
                        _topBar(t, members.length),
                        Expanded(
                          child: loading
                              ? const Center(
                                  child: CircularProgressIndicator(
                                      color: AppColors.blue))
                              : SingleChildScrollView(
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 12, 16, 100),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _leaderboardCard(t, members, myRank),
                                        const SizedBox(height: 20),
                                        Text('Members',
                                            style: GoogleFonts.inder(
                                                color: t.textPrimary,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 12),
                                        _membersGrid(t, members, prov),
                                      ]),
                                ),
                        ),
                      ]),

                      // ── Backdrop ──────────────────────────────────────────
                      IgnorePointer(
                        ignoring: !_showInfoPanel,
                        child: AnimatedOpacity(
                          opacity: _showInfoPanel ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 220),
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _showInfoPanel = false),
                            child:
                                Container(color: Colors.black.withOpacity(0.45)),
                          ),
                        ),
                      ),

                      // ── Sliding info panel ────────────────────────────────
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 270),
                        curve: Curves.easeOutCubic,
                        right: _showInfoPanel ? 0 : -(panelWidth + 30),
                        top: 0,
                        bottom: 0,
                        width: panelWidth,
                        child: _infoPanel(t, members, prov),
                      ),

                      // ── Sticky FAB (owner only; hidden while panel open) ──
                      if (_isOwner && !loading && !_showInfoPanel)
                        Positioned(
                          bottom: 24,
                          right: 20,
                          child: _ownerFab(prov, t),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      );
    });
  }

  // ── Top bar ─────────────────────────────────────────────────────────────────
  Widget _topBar(AppThemeData t, int memberCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 0),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(Icons.chevron_left_rounded,
                color: t.textPrimary, size: 28),
          ),
        ),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inder(
                        color: t.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                Text('$memberCount member${memberCount == 1 ? '' : 's'}',
                    style: GoogleFonts.inder(color: t.textMuted, fontSize: 12)),
              ]),
        ),
        GestureDetector(
          onTap: () => setState(() => _showInfoPanel = true),
          behavior: HitTestBehavior.opaque,
          child: Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
                color: t.widgetBg,
                shape: BoxShape.circle,
                border: Border.all(color: t.cardBorder),
                boxShadow: t.widgetShadow),
            child: const Icon(Icons.info_outline_rounded,
                color: AppColors.blue, size: 22),
          ),
        ),
      ]),
    );
  }

  // ── Owner FAB ───────────────────────────────────────────────────────────────
  Widget _ownerFab(AppProvider prov, AppThemeData t) {
    return GestureDetector(
      onTap: () => _showInvite(prov, t),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.blue,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: AppColors.blue.withOpacity(0.5),
                blurRadius: 18,
                offset: const Offset(0, 6)),
          ],
        ),
        child:
            const Icon(Icons.person_add_rounded, color: Colors.white, size: 24),
      ),
    );
  }

  // ── Info panel ──────────────────────────────────────────────────────────────
  Widget _infoPanel(
      AppThemeData t, List<_MemberView> members, AppProvider prov) {
    final studyingCount = members.where((m) => m.studying).length;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: t.widgetBg,
          borderRadius:
              const BorderRadius.horizontal(left: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.20),
                blurRadius: 28,
                offset: const Offset(-8, 0)),
          ],
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(18, 18, 14, 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.blue.withOpacity(t.isDark ? 0.22 : 0.10),
                      AppColors.blue.withOpacity(0.0),
                    ],
                  ),
                  borderRadius:
                      const BorderRadius.only(topLeft: Radius.circular(24)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: AppColors.blue.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.groups_rounded,
                            color: AppColors.blue, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Group Info',
                            style: GoogleFonts.inder(
                                color: t.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5)),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _showInfoPanel = false),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                              color: t.inputBg, shape: BoxShape.circle),
                          child: Icon(Icons.close_rounded,
                              color: t.textMuted, size: 18),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Text(_name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inder(
                                color: t.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                      ),
                      // Edit button — owner only
                      if (_isOwner)
                        GestureDetector(
                          onTap: () => _showEditGroup(prov, t),
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                                color: AppColors.blue.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(9)),
                            child: const Icon(Icons.edit_rounded,
                                color: AppColors.blue, size: 16),
                          ),
                        ),
                    ]),
                    if (_description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(_description,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inder(
                              color: t.textMuted, fontSize: 13, height: 1.4)),
                    ],
                  ],
                ),
              ),

              // Stat pills
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
                child: Row(children: [
                  _statPill(Icons.people_alt_rounded,
                      '${members.length} members', AppColors.blue, t),
                  const SizedBox(width: 8),
                  if (studyingCount > 0)
                    _statPill(Icons.bolt_rounded, '$studyingCount studying',
                        _orange, t),
                ]),
              ),

              Divider(color: t.divider, height: 1, indent: 16, endIndent: 16),

              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 16, 8),
                child: Text('Members',
                    style: GoogleFonts.inder(
                        color: t.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.4)),
              ),

              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  itemCount: members.length,
                  itemBuilder: (_, i) =>
                      _memberInfoRow(t, members[i], i + 1, prov),
                ),
              ),

              Divider(color: t.divider, height: 1, indent: 16, endIndent: 16),

              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: _isOwner
                    ? _panelActionBtn('Delete Group',
                        Icons.delete_forever_rounded, () => _deleteGroup(prov))
                    : _panelActionBtn('Leave Group', Icons.logout_rounded,
                        () => _leaveGroup(prov)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statPill(IconData icon, String label, Color color, AppThemeData t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 5),
        Text(label,
            style: GoogleFonts.inder(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _memberInfoRow(
      AppThemeData t, _MemberView m, int rank, AppProvider prov) {
    final isLeader = m.uid == _ownerUid;
    final initial = m.name.isNotEmpty ? m.name[0].toUpperCase() : '?';
    final Color roleColor = isLeader ? _gold : AppColors.blue;

    return GestureDetector(
      onTap: () => _showMemberProfile(prov, t, m, rank),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
            color: t.inputBg, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: roleColor.withOpacity(0.14),
              border: Border.all(
                  color: m.studying ? _orange : roleColor.withOpacity(0.4),
                  width: 1.5),
              boxShadow: m.studying
                  ? [BoxShadow(color: _orange.withOpacity(0.30), blurRadius: 8)]
                  : null,
            ),
            child: Center(
              child: Text(initial,
                  style: GoogleFonts.inder(
                      color: t.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.isMe ? '${m.name} (You)' : m.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inder(
                          color: t.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: roleColor.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(5)),
                      child: Text(isLeader ? '👑 Leader' : 'Member',
                          style: GoogleFonts.inder(
                              color: roleColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ),
                    if (m.studying) ...[
                      const SizedBox(width: 5),
                      const Icon(Icons.bolt_rounded, color: _orange, size: 12),
                      Text('Studying',
                          style:
                              GoogleFonts.inder(color: _orange, fontSize: 10)),
                    ],
                  ]),
                ]),
          ),
          // Remove (owner only, not self)
          if (_isOwner && !m.isMe)
            GestureDetector(
              onTap: () => _kickMember(prov, m.uid, m.name),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: AppColors.red.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.person_remove_rounded,
                    color: AppColors.red, size: 16),
              ),
            )
          else
            Icon(Icons.chevron_right_rounded, color: t.textMuted, size: 18),
        ]),
      ),
    );
  }

  Widget _panelActionBtn(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.red.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.red.withOpacity(0.30), width: 1.5),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: AppColors.red, size: 18),
          const SizedBox(width: 8),
          Text(label,
              style: GoogleFonts.inder(
                  color: AppColors.red,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ── Profile-sheet helpers ───────────────────────────────────────────────────
  Widget _statCard(AppThemeData t, String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.widgetBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.cardBorder),
      ),
      child: Row(children: [
        Icon(icon, color: AppColors.blue, size: 18),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: GoogleFonts.inder(
                  color: t.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          Text(label,
              style: GoogleFonts.inder(color: t.textMuted, fontSize: 10)),
        ]),
      ]),
    );
  }

  Widget _infoRow(AppThemeData t, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: t.textMuted),
        const SizedBox(width: 10),
        SizedBox(
          width: 116,
          child: Text(label,
              style: GoogleFonts.inder(color: t.textMuted, fontSize: 13)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inder(
                  color: t.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _subjectsBlock(AppThemeData t, IconData icon, String label,
      List<String> items, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: t.textMuted),
        const SizedBox(width: 10),
        SizedBox(
          width: 116,
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(label,
                style: GoogleFonts.inder(color: t.textMuted, fontSize: 13)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: items
                .map((s) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color.withOpacity(0.25)),
                      ),
                      child: Text(s,
                          style: GoogleFonts.inder(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ))
                .toList(),
          ),
        ),
      ]),
    );
  }

  // ── Shared sheet widgets ────────────────────────────────────────────────────
  Widget _sheetHeader(AppThemeData t, IconData icon, String title,
      String subtitle, BuildContext sheetCtx) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: AppColors.blue.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: AppColors.blue, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: GoogleFonts.inder(
                  color: t.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.bold)),
          Text(subtitle,
              style: GoogleFonts.inder(color: t.textMuted, fontSize: 12)),
        ]),
      ),
      GestureDetector(
        onTap: () => Navigator.pop(sheetCtx),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: t.inputBg, shape: BoxShape.circle),
          child: Icon(Icons.close_rounded, color: t.textMuted, size: 18),
        ),
      ),
    ]);
  }

  InputDecoration _fieldDecoration(AppThemeData t, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inder(color: t.textMuted),
      filled: true,
      fillColor: t.inputBg,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    );
  }

  // ── Leaderboard ─────────────────────────────────────────────────────────────
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

  Widget _membersGrid(
      AppThemeData t, List<_MemberView> members, AppProvider prov) {
    return LayoutBuilder(builder: (_, c) {
      final w = (c.maxWidth - 12) / 2;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (int i = 0; i < members.length; i++)
            SizedBox(
                width: w, child: _memberBlock(t, members[i], i + 1, prov)),
        ],
      );
    });
  }

  Widget _memberBlock(
      AppThemeData t, _MemberView m, int rank, AppProvider prov) {
    final vis = _statusVisual(m.status, t);
    final c = vis.color;
    final lit = vis.lit;

    return GestureDetector(
      onTap: () => _showMemberProfile(prov, t, m, rank),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: lit ? c.withOpacity(0.12) : t.widgetBg,
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: lit ? c : t.cardBorder, width: lit ? 1.6 : 1),
          boxShadow: lit
              ? [BoxShadow(color: c.withOpacity(0.25), blurRadius: 14)]
              : t.widgetShadow,
        ),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: lit
                  ? c.withOpacity(0.2)
                  : (t.isDark
                      ? Colors.white10
                      : Colors.black.withOpacity(0.05)),
            ),
            child: Icon(vis.icon, color: lit ? c : t.textMuted, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                              fontWeight:
                                  lit ? FontWeight.w600 : FontWeight.normal)),
                    ),
                  ]),
                  Text(vis.label,
                      style: GoogleFonts.inder(
                          color: lit ? c : t.textMuted, fontSize: 9)),
                ]),
          ),
        ]),
      ),
    );
  }

  Widget _avatar(AppThemeData t, _MemberView m, Color ring,
      {double size = 46}) {
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

// ── Data model ──────────────────────────────────────────────────────────────────
class _MemberView {
  final String uid;
  final String name;
  final bool isMe;
  final String status; // studying | paused | short_break | long_break | idle
  final int daily;
  final int weekly;
  final int allTime;
  final DateTime? joined;

  const _MemberView({
    required this.uid,
    required this.name,
    required this.isMe,
    required this.status,
    required this.daily,
    required this.weekly,
    required this.allTime,
    required this.joined,
  });

  bool get studying => status == 'studying';

  int timeFor(_LbRange r) => switch (r) {
        _LbRange.daily => daily,
        _LbRange.weekly => weekly,
        _LbRange.allTime => allTime,
      };
}
