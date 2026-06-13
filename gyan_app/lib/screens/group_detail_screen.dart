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

import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../constants/subjects.dart';
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
  bool _isPublic = true;
  List<String> _groupSubjects = [];

  // Static snapshot of member profiles. "me" is re-derived live on every
  // build() from the provider so the timer always shows the correct time.
  List<_MemberView> _members = [];
  bool _loading = true;

  // My total-seconds at the moment I joined this group (the "baseline").
  // Stored once after _loadOnce so build() can compute my current delta live.
  int _myBaseline = 0;

  // Live stream that patches other members' status / time fields in real-time
  // so their glow / studying indicator updates without a manual refresh.
  StreamSubscription<List<Map<String, dynamic>>>? _membersSub;

  // Local timer that ticks every second to update other members' running study times in real-time.
  Timer? _rebuildTimer;

  @override
  void initState() {
    super.initState();
    _loadOnce();
    _startMembersStream();
    _startRebuildTimer();
  }

  @override
  void dispose() {
    _membersSub?.cancel();
    _rebuildTimer?.cancel();
    super.dispose();
  }

  void _startRebuildTimer() {
    _rebuildTimer?.cancel();
    _rebuildTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      // Rebuild if any member is currently studying.
      final anyStudying = _members.any((m) => m.studying);
      if (anyStudying) {
        setState(() {});
      }
    });
  }

  /// Subscribes to the Firestore members subcollection and live-patches
  /// other members' status and time fields so their glow updates in real-time.
  void _startMembersStream() {
    final prov = context.read<AppProvider>();
    final myUid = prov.currentUid;
    _membersSub?.cancel();
    _membersSub = prov.groupMembersStream(widget.groupId).listen((rawList) {
      if (!mounted) return;
      bool changed = false;
      for (final raw in rawList) {
        final uid = raw['uid'] as String?;
        if (uid == null || uid == myUid) continue; // skip self — computed live
        final idx = _members.indexWhere((m) => m.uid == uid);
        if (idx == -1) continue; // not in snapshot yet; _loadOnce handles it
        final existing = _members[idx];

        final newStatus = (raw['status'] as String?) ??
            ((raw['studying'] as bool? ?? false) ? 'studying' : 'idle');
        final rawTotal   = (raw['totalSeconds']  as num?)?.toInt() ?? 0;
        final rawBaseline = (raw['baseline']     as num?)?.toInt() ?? 0;
        final rawDaily   = (raw['dailySeconds']  as num?)?.toInt() ?? 0;
        final rawWeekly  = (raw['weekSeconds']   as num?)?.toInt() ?? 0;

        final allTimeFiltered = math.max(0, rawTotal - rawBaseline);
        final dailyFiltered = (rawBaseline >= rawTotal - rawDaily)
            ? math.max(0, rawTotal - rawBaseline)
            : rawDaily;
        final weekFiltered = (rawBaseline >= rawTotal - rawWeekly)
            ? math.max(0, rawTotal - rawBaseline)
            : rawWeekly;

        final updatedAtRaw = raw['updatedAt'];
        DateTime? newUpdatedAt;
        if (updatedAtRaw is Timestamp) {
          newUpdatedAt = updatedAtRaw.toDate();
        } else if (updatedAtRaw is DateTime) {
          newUpdatedAt = updatedAtRaw;
        }

        // Only rebuild if something actually changed.
        if (existing.status == newStatus &&
            existing.daily   == dailyFiltered &&
            existing.weekly  == weekFiltered &&
            existing.allTime == allTimeFiltered &&
            existing.updatedAt == newUpdatedAt) continue;

        _members[idx] = _MemberView(
          uid:     existing.uid,
          name:    existing.name,
          isMe:    false,
          status:  newStatus,
          daily:   dailyFiltered,
          weekly:  weekFiltered,
          allTime: allTimeFiltered,
          joined:  existing.joined,
          updatedAt: newUpdatedAt,
        );
        changed = true;
      }
      if (changed) setState(() {});
    });
  }

  Future<void> _loadOnce() async {
    final prov = context.read<AppProvider>();
    final myUid = prov.currentUid;
    try {
      final gSnap = await FirebaseFirestore.instance
          .collection('study_groups')
          .doc(widget.groupId)
          .get()
          .timeout(const Duration(seconds: 10));
      List<String> memberUids = [];
      if (gSnap.exists) {
        final g = gSnap.data();
        if (g != null) {
          _name = (g['name'] as String?) ?? widget.groupName;
          _description = (g['description'] as String?) ?? widget.description;
          _ownerUid = (g['ownerUid'] as String?) ?? widget.ownerUid;
          _isOwner = myUid != null && myUid == _ownerUid;
          _isPublic = (g['isPublic'] as bool?) ?? true;
          _groupSubjects = List<String>.from(g['subjects'] ?? []);
          memberUids = List<String>.from(g['memberUids'] ?? []);
        }
      }

      final rawSnap = await FirebaseFirestore.instance
          .collection('study_groups')
          .doc(widget.groupId)
          .collection('members')
          .get()
          .timeout(const Duration(seconds: 10));
      
      final List<Map<String, dynamic>> raw = rawSnap.docs
          .map((d) => {'uid': d.id, ...d.data()})
          .toList();
      final List<Map<String, dynamic>> rawMutable = List<Map<String, dynamic>>.from(raw);
      final Set<String> existingUids = rawMutable.map((m) => m['uid'] as String?).whereType<String>().toSet();

      // Self-healing database repair: if current user is missing from members subcollection, write it
      if (myUid != null && memberUids.contains(myUid) && !existingUids.contains(myUid)) {
        await prov.joinGroupRemote(widget.groupId);
        try {
          final freshRawSnap = await FirebaseFirestore.instance
              .collection('study_groups')
              .doc(widget.groupId)
              .collection('members')
              .get()
              .timeout(const Duration(seconds: 5));
          final freshRaw = freshRawSnap.docs
              .map((d) => {'uid': d.id, ...d.data()})
              .toList();
          rawMutable.clear();
          rawMutable.addAll(freshRaw);
          existingUids.clear();
          existingUids.addAll(rawMutable.map((m) => m['uid'] as String?).whereType<String>());
        } catch (_) {}
      }

      for (final uid in memberUids) {
        if (!existingUids.contains(uid)) {
          final isMe = uid == myUid;
          final profile = await prov.fetchUserProfile(uid).timeout(const Duration(seconds: 3), onTimeout: () => null);
          rawMutable.add({
            'uid': uid,
            'name': profile?['name'] ?? 'User',
            'status': 'idle',
            'studying': false,
            'dailySeconds': 0,
            'weekSeconds': 0,
            'totalSeconds': isMe ? prov.totalSecondsAllTime : 0,
            'baseline': isMe ? prov.totalSecondsAllTime : 0,
            'joinedAt': null,
          });
        }
      }

      _members = _buildMembers(rawMutable, prov, myUid);
    } catch (_) {/* keep whatever we have; just stop the spinner */}
    if (mounted) setState(() => _loading = false);
  }

  List<_MemberView> _buildMembers(
      List<Map<String, dynamic>> raw, AppProvider prov, String? myUid) {
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    final endBound = now.add(const Duration(seconds: 1));

    return raw.map((m) {
      final uid = m['uid'] as String?;
      final isMe = uid != null && uid == myUid;
      final total = (m['totalSeconds'] as num?)?.toInt() ?? 0;
      final baseline = (m['baseline'] as num?)?.toInt() ?? 0;

      // Store my baseline once so build() can recompute live on every frame.
      if (isMe) _myBaseline = baseline;

      final overallAllTime = isMe ? prov.totalSecondsAllTime : total;

      final overallDaily = isMe
          ? prov.todayStudiedSeconds
          : ((m['dailySeconds'] as num?)?.toInt() ?? 0);

      final overallWeek = isMe
          ? prov.secondsInRange(weekStart, endBound)
          : ((m['weekSeconds'] as num?)?.toInt() ?? 0);

      // Daily time studied after joining the group
      final dailyFiltered = (baseline >= overallAllTime - overallDaily)
          ? math.max(0, overallAllTime - baseline)
          : overallDaily;

      // Weekly time studied after joining the group
      final weekFiltered = (baseline >= overallAllTime - overallWeek)
          ? math.max(0, overallAllTime - baseline)
          : overallWeek;

      // All-time time studied after joining the group
      final allTimeFiltered = math.max(0, overallAllTime - baseline);

      final status = isMe
          ? prov.studyStatus
          : ((m['status'] as String?) ??
              ((m['studying'] as bool? ?? false) ? 'studying' : 'idle'));

      final updatedAtRaw = m['updatedAt'];
      DateTime? updatedAt;
      if (updatedAtRaw is Timestamp) {
        updatedAt = updatedAtRaw.toDate();
      } else if (updatedAtRaw is DateTime) {
        updatedAt = updatedAtRaw;
      }

      return _MemberView(
        uid: uid ?? '',
        name: (m['name'] as String?) ?? 'User',
        isMe: isMe,
        status: status,
        daily: dailyFiltered,
        weekly: weekFiltered,
        allTime: allTimeFiltered,
        joined: (m['joinedAt'] as Timestamp?)?.toDate(),
        updatedAt: updatedAt,
      );
    }).toList();
  }

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
    bool localIsPublic = _isPublic;
    final Set<String> localSubjects = Set<String>.from(_groupSubjects);

    showModalBottomSheet(
      context: context,
      backgroundColor: t.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sheetHeader(t, Icons.edit_rounded, 'Edit Group',
                      'Update group information', sheetCtx),
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
                  const SizedBox(height: 14),

                  // ── Group Type Toggle ──────────────────────────────
                  Text('Group Type',
                      style: GoogleFonts.inder(
                          color: t.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setSheetState(() => localIsPublic = true),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: localIsPublic ? AppColors.green.withOpacity(0.15) : t.inputBg,
                            border: Border.all(color: localIsPublic ? AppColors.green : t.cardBorder),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.public_rounded,
                                size: 16, color: localIsPublic ? AppColors.green : t.textMuted),
                            const SizedBox(width: 6),
                            Text('Public',
                                style: GoogleFonts.inder(
                                    color: localIsPublic ? AppColors.green : t.textMuted,
                                    fontSize: 13,
                                    fontWeight: localIsPublic ? FontWeight.w700 : FontWeight.normal)),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setSheetState(() => localIsPublic = false),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: !localIsPublic ? AppColors.red.withOpacity(0.15) : t.inputBg,
                            border: Border.all(color: !localIsPublic ? AppColors.red : t.cardBorder),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.lock_rounded,
                                size: 16, color: !localIsPublic ? AppColors.red : t.textMuted),
                            const SizedBox(width: 6),
                            Text('Private',
                                style: GoogleFonts.inder(
                                    color: !localIsPublic ? AppColors.red : t.textMuted,
                                    fontSize: 13,
                                    fontWeight: !localIsPublic ? FontWeight.w700 : FontWeight.normal)),
                          ]),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    localIsPublic
                        ? 'Anyone can find and join this group.'
                        : 'Only invited members can join.',
                    style: GoogleFonts.inder(color: t.textMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 14),

                  // ── Subjects Picker ────────────────────────────────
                  Text('What are you planning to study?',
                      style: GoogleFonts.inder(
                          color: t.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: kDefaultSubjects.map((sub) {
                      final isSelected = localSubjects.contains(sub);
                      return GestureDetector(
                        onTap: () {
                          setSheetState(() {
                            if (isSelected) {
                              localSubjects.remove(sub);
                            } else {
                              localSubjects.add(sub);
                            }
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.blue.withOpacity(0.15) : t.inputBg,
                            border: Border.all(
                              color: isSelected ? AppColors.blue : t.cardBorder,
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(
                            sub,
                            style: GoogleFonts.inder(
                              color: isSelected ? AppColors.blue : t.textMuted,
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  GestureDetector(
                    onTap: () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        _toast('Group name cannot be empty', error: true);
                        return;
                      }
                      await prov.updateGroupInfo(
                        widget.groupId,
                        name,
                        descCtrl.text.trim(),
                        isPublic: localIsPublic,
                        subjects: localSubjects.toList(),
                      );
                      if (!sheetCtx.mounted) return;
                      Navigator.pop(sheetCtx);
                      // Reflect the edit immediately on the static screen.
                      if (mounted) {
                        setState(() {
                          _name = name;
                          _description = descCtrl.text.trim();
                          _isPublic = localIsPublic;
                          _groupSubjects = localSubjects.toList();
                        });
                      }
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
      ),
    );
  }

  // ── Member profile popup (everyone) ─────────────────────────────────────────
  Future<void> _showMemberProfile(
      AppProvider prov, AppThemeData t, _MemberView m, int rank) async {
    // 1. Refresh once upon opening
    await _loadOnce();

    _MemberView activeMember = m;
    final index = _members.indexWhere((x) => x.uid == m.uid);
    if (index != -1) {
      activeMember = _members[index];
    }

    // Load the member's profile exactly once, then cache it — the popup shows
    // static data and never reloads while it is open.
    Map<String, dynamic>? profile = _profileCache[activeMember.uid];
    if (profile == null) {
      profile = await prov
          .fetchUserProfile(activeMember.uid)
          .timeout(const Duration(seconds: 6), onTimeout: () => null);
      if (!mounted) return;
      if (profile != null) _profileCache[activeMember.uid] = profile;
    }
    if (!mounted) return;

    final vis = _statusVisual(activeMember.status, t);
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

    await showModalBottomSheet(
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
                    _avatar(t, activeMember, vis.color, size: 54),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(activeMember.isMe ? '${activeMember.name} (You)' : activeMember.name,
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
                        child: _statCard(t, 'Today', _fmt(activeMember.daily),
                            Icons.today_rounded)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _statCard(t, 'Total studied',
                            _fmt(activeMember.allTime), Icons.timelapse_rounded)),
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
                        activeMember.joined != null
                            ? 'Joined ${_date(activeMember.joined!)}'
                            : 'Member',
                        style: GoogleFonts.inder(
                            color: t.textMuted, fontSize: 12)),
                    const Spacer(),
                    if (!activeMember.isMe)
                      GestureDetector(
                        onTap: () async {
                          await prov.sendStudyReminder(activeMember.uid);
                          if (!sheetCtx.mounted) return;
                          Navigator.pop(sheetCtx);
                          _toast('Reminder sent to ${activeMember.name} 🔔');
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

    // 2. Refresh again when they click off (dismiss)
    _loadOnce();
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
    // Drop them from the static snapshot right away.
    if (mounted) setState(() => _members.removeWhere((m) => m.uid == memberUid));
    _toast('$memberName removed');
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // watch() so that provider changes (timer ticks, studyStatus, etc.) trigger
    // a rebuild and "me" always shows the current live time/status.
    final prov = context.watch<AppProvider>();
    final t = prov.appTheme;
    final panelWidth =
        math.min(310.0, MediaQuery.of(context).size.width * 0.88);

    // Recompute "me" live on every frame so the timer updates without a refresh.
    final now = DateTime.now();
    final weekStart =
        DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    final endBound = now.add(const Duration(seconds: 1));

    final members = _members.map((m) {
      if (m.isMe) {
        final overallAllTime = prov.totalSecondsAllTime;
        final overallDaily   = prov.todayStudiedSeconds;
        final overallWeek    = prov.secondsInRange(weekStart, endBound);
        final dailyFiltered  = (_myBaseline >= overallAllTime - overallDaily)
            ? math.max(0, overallAllTime - _myBaseline)
            : overallDaily;
        final weekFiltered   = (_myBaseline >= overallAllTime - overallWeek)
            ? math.max(0, overallAllTime - _myBaseline)
            : overallWeek;
        final allTimeFiltered = math.max(0, overallAllTime - _myBaseline);
        return _MemberView(
          uid:     m.uid,
          name:    m.name,
          isMe:    true,
          status:  prov.studyStatus,
          daily:   dailyFiltered,
          weekly:  weekFiltered,
          allTime: allTimeFiltered,
          joined:  m.joined,
          updatedAt: m.updatedAt,
        );
      } else {
        // Friend is studying: calculate live elapsed seconds since last Firestore publish (updatedAt)
        int extra = 0;
        if (m.studying && m.updatedAt != null) {
          final diff = DateTime.now().difference(m.updatedAt!).inSeconds;
          if (diff > 0) {
            extra = diff;
          }
        }
        return _MemberView(
          uid:     m.uid,
          name:    m.name,
          isMe:    false,
          status:  m.status,
          daily:   m.daily + extra,
          weekly:  m.weekly + extra,
          allTime: m.allTime + extra,
          joined:  m.joined,
          updatedAt: m.updatedAt,
        );
      }
    }).toList()
      ..sort((a, b) => b.timeFor(_range).compareTo(a.timeFor(_range)));

    final myRank = members.indexWhere((m) => m.isMe) + 1;
    final loading = _loading;

    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: Builder(
          builder: (context) {
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
                              : RefreshIndicator(
                                  color: AppColors.blue,
                                  onRefresh: _loadOnce,
                                  child: SingleChildScrollView(
                                    physics: const AlwaysScrollableScrollPhysics(),
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
              ),
            ),
          );
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
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _statPill(Icons.people_alt_rounded,
                        '${members.length} members', AppColors.blue, t),
                    _statPill(
                        _isPublic ? Icons.public_rounded : Icons.lock_rounded,
                        _isPublic ? 'Public' : 'Private',
                        _isPublic ? AppColors.green : AppColors.red,
                        t),
                    if (studyingCount > 0)
                      _statPill(Icons.bolt_rounded, '$studyingCount studying',
                          _orange, t),
                  ],
                ),
              ),

              if (_groupSubjects.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Planning to Study',
                          style: GoogleFonts.inder(
                              color: t.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _groupSubjects.map((sub) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.blue.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              sub,
                              style: GoogleFonts.inder(
                                color: AppColors.blue,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],

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
    final prov = context.read<AppProvider>();

    return GestureDetector(
      onTap: () => _showMemberProfile(prov, t, m, rank),
      behavior: HitTestBehavior.opaque,
      child: Padding(
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
      ),
    );
  }

  Widget _yourRankRow(AppThemeData t, _MemberView m, int rank) {
    final prov = context.read<AppProvider>();
    return GestureDetector(
      onTap: () => _showMemberProfile(prov, t, m, rank),
      behavior: HitTestBehavior.opaque,
      child: Container(
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
      ),
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
  final DateTime? updatedAt;

  const _MemberView({
    required this.uid,
    required this.name,
    required this.isMe,
    required this.status,
    required this.daily,
    required this.weekly,
    required this.allTime,
    required this.joined,
    this.updatedAt,
  });

  bool get studying => status == 'studying';

  int timeFor(_LbRange r) => switch (r) {
        _LbRange.daily => daily,
        _LbRange.weekly => weekly,
        _LbRange.allTime => allTime,
      };
}
