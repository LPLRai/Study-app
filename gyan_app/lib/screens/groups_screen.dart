import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../constants/subjects.dart';
import '../providers/app_provider.dart';
import 'group_detail_screen.dart';
import 'join_group_screen.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  List<Map<String, dynamic>>? _groups;
  bool _loading = false;
  int _lastTabIndex = -1;

  void _toast(BuildContext ctx, String msg, {bool error = false}) {
    ScaffoldMessenger.of(ctx)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppColors.red : AppColors.blue,
        content: Text(msg,
            style: GoogleFonts.inder(color: Colors.white, fontSize: 13)),
      ));
  }

  Future<void> _loadGroups(AppProvider prov) async {
    if (_loading) return;
    setState(() {
      _loading = true;
    });
    try {
      final list = await prov.myGroupsStream().first.timeout(const Duration(seconds: 8));
      if (mounted) {
        setState(() {
          _groups = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _groups ??= [];
          _loading = false;
        });
      }
    }
  }

  void _showCreateSheet(BuildContext ctx, AppProvider prov) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final t = prov.appTheme;
    bool isPublic = true;
    final Set<String> selectedSubjects = {};

    showModalBottomSheet(
      context: ctx,
      backgroundColor: t.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Create a Group',
                        style: GoogleFonts.inder(
                            color: t.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    GestureDetector(
                      onTap: () => Navigator.pop(sheetCtx),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                            color: t.inputBg, shape: BoxShape.circle),
                        child: Icon(Icons.close_rounded,
                            color: t.textMuted, size: 18),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text('You can create up to 5 groups.',
                      style: GoogleFonts.inder(color: t.textMuted, fontSize: 12)),
                  const SizedBox(height: 18),

                  // ── Group type ──────────────────────────────────────────
                  Text('Group Type',
                      style: GoogleFonts.inder(
                          color: t.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(children: [
                    _TypeChip(
                      label: 'Public',
                      icon: Icons.public_rounded,
                      selected: isPublic,
                      color: AppColors.green,
                      t: t,
                      onTap: () => setSheetState(() => isPublic = true),
                    ),
                    const SizedBox(width: 10),
                    _TypeChip(
                      label: 'Private',
                      icon: Icons.lock_rounded,
                      selected: !isPublic,
                      color: AppColors.red,
                      t: t,
                      onTap: () => setSheetState(() => isPublic = false),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    isPublic
                        ? 'Anyone can find and join this group.'
                        : 'Only invited members can join.',
                    style: GoogleFonts.inder(color: t.textMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 16),

                  // ── Group name ──────────────────────────────────────────
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
                    decoration: InputDecoration(
                        hintText: 'e.g. Study Squad',
                        hintStyle: GoogleFonts.inder(color: t.textMuted),
                        filled: true,
                        fillColor: t.inputBg,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 13),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none)),
                  ),
                  const SizedBox(height: 14),

                  // ── Description ─────────────────────────────────────────
                  Text('Description (optional)',
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
                    decoration: InputDecoration(
                        hintText: 'What is this group about?',
                        hintStyle: GoogleFonts.inder(color: t.textMuted),
                        filled: true,
                        fillColor: t.inputBg,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 13),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none)),
                  ),
                  const SizedBox(height: 16),

                  // ── Subjects ─────────────────────────────────────────────
                  Text('What are you planning to study?',
                      style: GoogleFonts.inder(
                          color: t.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: kDefaultSubjects.map((s) {
                      final on = selectedSubjects.contains(s);
                      return GestureDetector(
                        onTap: () => setSheetState(() =>
                            on ? selectedSubjects.remove(s) : selectedSubjects.add(s)),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: on
                                ? AppColors.blue.withOpacity(0.15)
                                : t.inputBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: on
                                  ? AppColors.blue.withOpacity(0.55)
                                  : t.cardBorder,
                              width: on ? 1.5 : 1.0,
                            ),
                          ),
                          child: Text(s,
                              style: GoogleFonts.inder(
                                color: on ? AppColors.blue : t.textMuted,
                                fontSize: 12,
                                fontWeight:
                                    on ? FontWeight.w700 : FontWeight.normal,
                              )),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // ── Create button ───────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) return;
                        final desc = descCtrl.text.trim();
                        final res = await prov.createGroupRemote(
                          name,
                          description: desc,
                          isPublic: isPublic,
                          subjects: selectedSubjects.toList(),
                        );
                        if (!ctx.mounted) return;
                        Navigator.pop(sheetCtx);
                        if (res == 'ok') {
                          _toast(ctx, 'Group "$name" created!');
                          _loadGroups(prov); // Refresh the list!
                        } else if (res == 'limit') {
                          _toast(ctx,
                              "You've reached the limit of 5 groups",
                              error: true);
                        } else {
                          _toast(ctx,
                              'Could not create group (are you online?)',
                              error: true);
                        }
                      },
                      child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          decoration: BoxDecoration(
                              color: AppColors.blue,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.blue.withOpacity(0.35),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                )
                              ]),
                          child: Text('Create Group',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inder(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600))),
                    ),
                  ),
                ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AppProvider>();
    final currentTab = prov.currentTabIndex;

    // Refresh groups when coming to the tab (index 3)
    if (currentTab == 3 && _lastTabIndex != 3) {
      _groups = null; // reset to show spinner
      _loadGroups(prov);
    }
    _lastTabIndex = currentTab;

    final t = prov.appTheme;
    final groups = _groups ?? const [];
    final loading = _loading || _groups == null;

    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Stack(alignment: Alignment.center, children: [
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => prov.switchTab(0),
                child: Icon(Icons.chevron_left_rounded,
                    color: t.textPrimary, size: 28),
              ),
            ),
            Text('Groups',
                style: GoogleFonts.inder(
                    color: t.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
          ]),
        ),
        Expanded(
          child: loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.blue))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Your Groups',
                            style: GoogleFonts.inder(
                                color: t.textMuted, fontSize: 14)),
                        const SizedBox(height: 10),
                        if (groups.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                                color: t.widgetBg,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: t.cardBorder),
                                boxShadow: t.widgetShadow),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: AppColors.blue.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.groups_rounded,
                                      color: AppColors.blue, size: 32),
                                ),
                                const SizedBox(height: 12),
                                Text('No groups yet',
                                    style: GoogleFonts.inder(
                                        color: t.textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text('Create a group to study with friends',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inder(
                                        color: t.textMuted, fontSize: 13)),
                              ],
                            ),
                          )
                        else
                          ...groups.map((g) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _groupTile(context, t, g),
                              )),
                        const SizedBox(height: 14),

                        // ── Create a Group button ────────────────────────
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _showCreateSheet(context, prov),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: AppColors.blue.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: AppColors.blue.withOpacity(0.45),
                                  width: 1.5),
                            ),
                            child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    alignment: Alignment.center,
                                    decoration: const BoxDecoration(
                                      color: AppColors.blue,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.add_rounded,
                                        color: Colors.white, size: 16),
                                  ),
                                  const SizedBox(width: 10),
                                  Text('Create a Group',
                                      style: GoogleFonts.inder(
                                          color: AppColors.blue,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600)),
                                ]),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // ── Join Group button ────────────────────────────
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const JoinGroupScreen()),
                            );
                            _loadGroups(prov);
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: AppColors.blue.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: AppColors.blue.withOpacity(0.45),
                                  width: 1.5),
                            ),
                            child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    alignment: Alignment.center,
                                    decoration: const BoxDecoration(
                                      color: AppColors.blue,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                        Icons.group_add_rounded,
                                        color: Colors.white,
                                        size: 14),
                                  ),
                                  const SizedBox(width: 10),
                                  Text('Join a Group',
                                      style: GoogleFonts.inder(
                                          color: AppColors.blue,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600)),
                                ]),
                          ),
                        ),
                      ]),
                ),
        ),
      ]),
    );
  }

  Widget _groupTile(BuildContext ctx, t, Map<String, dynamic> g) {
    final name = g['name'] as String? ?? 'Group';
    final ownerUid = g['ownerUid'] as String? ?? '';
    final description = g['description'] as String? ?? '';
    final memberCount = (g['memberUids'] as List?)?.length ?? 1;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        await Navigator.of(ctx).push(MaterialPageRoute(
            builder: (_) => GroupDetailScreen(
                  groupId: g['id'] as String,
                  groupName: name,
                  ownerUid: ownerUid,
                  description: description,
                )));
        final prov = ctx.read<AppProvider>();
        _loadGroups(prov);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
            color: t.widgetBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.cardBorder),
            boxShadow: t.widgetShadow),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
                color: AppColors.blue.withOpacity(0.13),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.groups_rounded,
                color: AppColors.blue, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inder(
                        color: t.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 3),
                if (description.isNotEmpty) ...[
                  Text(description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          GoogleFonts.inder(color: t.textMuted, fontSize: 12)),
                  const SizedBox(height: 2),
                ],
                Text(
                    '$memberCount member${memberCount == 1 ? '' : 's'}',
                    style:
                        GoogleFonts.inder(color: t.textMuted, fontSize: 12)),
              ])),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: t.textMuted, size: 22),
        ]),
      ),
    );
  }
}

// ─── Type Chip (Public / Private) ─────────────────────────────────────────────
class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.t,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final dynamic t;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.15) : t.inputBg,
            border: Border.all(color: selected ? color : t.cardBorder),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon,
                size: 16, color: selected ? color : t.textMuted),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.inder(
                    color: selected ? color : t.textMuted,
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.normal)),
          ]),
        ),
      ),
    );
  }
}
