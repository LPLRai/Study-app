import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../constants/subjects.dart';
import '../providers/app_provider.dart';

class JoinGroupScreen extends StatefulWidget {
  const JoinGroupScreen({super.key});

  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _selectedSubjects = {};
  final Set<String> _joiningIds = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery = _searchCtrl.text.trim();
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<AppProvider>(context);
    final t = prov.appTheme;

    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── AppBar ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: t.widgetBg,
                          shape: BoxShape.circle,
                          border: Border.all(color: t.cardBorder),
                        ),
                        child: Icon(Icons.chevron_left_rounded,
                            color: t.textPrimary, size: 24),
                      ),
                    ),
                  ),
                  Text(
                    'Join a Group',
                    style: GoogleFonts.inder(
                      color: t.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ── Search Bar ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: t.inputBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: t.cardBorder),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  style: GoogleFonts.inder(color: t.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded, color: t.textMuted, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? GestureDetector(
                            onTap: () => _searchCtrl.clear(),
                            child: Icon(Icons.close_rounded, color: t.textMuted, size: 20),
                          )
                        : null,
                    hintText: 'Search groups by name...',
                    hintStyle: GoogleFonts.inder(color: t.textMuted, fontSize: 14),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Filter Subjects Chips ────────────────────────────────────────
            SizedBox(
              height: 38,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: kDefaultSubjects.length,
                itemBuilder: (ctx, index) {
                  final sub = kDefaultSubjects[index];
                  final isSelected = _selectedSubjects.contains(sub);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedSubjects.remove(sub);
                          } else {
                            _selectedSubjects.add(sub);
                          }
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.blue.withOpacity(0.15) : t.widgetBg,
                          border: Border.all(
                            color: isSelected ? AppColors.blue : t.cardBorder,
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Center(
                          child: Text(
                            sub,
                            style: GoogleFonts.inder(
                              color: isSelected ? AppColors.blue : t.textMuted,
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // ── Group List ───────────────────────────────────────────────────
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: prov.publicGroupsStream(),
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppColors.blue),
                    );
                  }

                  final allPublicGroups = snap.data ?? [];
                  final myJoinedGroupIds = prov.myGroupIds;

                  // Filter:
                  // 1. Not joined yet
                  // 2. Name matches search query
                  // 3. Has any of the selected subjects (if selected)
                  final filteredGroups = allPublicGroups.where((g) {
                    final gid = g['id'] as String? ?? '';
                    if (myJoinedGroupIds.contains(gid)) return false;

                    final name = (g['name'] as String? ?? '').toLowerCase();
                    if (_searchQuery.isNotEmpty && !name.contains(_searchQuery.toLowerCase())) {
                      return false;
                    }

                    if (_selectedSubjects.isNotEmpty) {
                      final groupSubjects = List<String>.from(g['subjects'] ?? []);
                      final matches = _selectedSubjects.any((selected) =>
                          groupSubjects.any((gs) => gs.toLowerCase() == selected.toLowerCase()));
                      if (!matches) return false;
                    }

                    return true;
                  }).toList();

                  if (filteredGroups.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.groups_outlined, color: t.textMuted, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            'No matching groups found',
                            style: GoogleFonts.inder(
                              color: t.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Try changing your search terms or filters',
                            style: GoogleFonts.inder(
                              color: t.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: filteredGroups.length,
                    itemBuilder: (ctx, index) {
                      final g = filteredGroups[index];
                      final id = g['id'] as String;
                      final name = g['name'] as String? ?? 'Study Group';
                      final desc = g['description'] as String? ?? '';
                      final ownerName = g['ownerName'] as String? ?? 'User';
                      final memberUids = List<String>.from(g['memberUids'] ?? []);
                      final memberCount = memberUids.length;
                      final groupSubjects = List<String>.from(g['subjects'] ?? []);
                      final isJoining = _joiningIds.contains(id);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: t.widgetBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: t.cardBorder),
                          boxShadow: t.widgetShadow,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: GoogleFonts.inder(
                                          color: t.textPrimary,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'By $ownerName • $memberCount member${memberCount == 1 ? '' : 's'}',
                                        style: GoogleFonts.inder(
                                          color: t.textMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // ── Join Button ──────────────────────────────
                                GestureDetector(
                                  onTap: isJoining
                                      ? null
                                      : () async {
                                          setState(() => _joiningIds.add(id));
                                          try {
                                            await prov.joinGroupRemote(id);
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  behavior: SnackBarBehavior.floating,
                                                  backgroundColor: AppColors.blue,
                                                  content: Text(
                                                    'Joined "$name"!',
                                                    style: GoogleFonts.inder(
                                                      color: Colors.white,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }
                                          } catch (e) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  behavior: SnackBarBehavior.floating,
                                                  backgroundColor: AppColors.red,
                                                  content: Text(
                                                    'Failed to join group.',
                                                    style: GoogleFonts.inder(
                                                      color: Colors.white,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }
                                          } finally {
                                            if (mounted) {
                                              setState(() => _joiningIds.remove(id));
                                            }
                                          }
                                        },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: AppColors.blue.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AppColors.blue),
                                    ),
                                    child: isJoining
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              color: AppColors.blue,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Text(
                                            'Join',
                                            style: GoogleFonts.inder(
                                              color: AppColors.blue,
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                            if (desc.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                desc,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inder(
                                  color: t.textMuted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                            if (groupSubjects.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: groupSubjects.map((sub) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      sub,
                                      style: GoogleFonts.inder(
                                        color: AppColors.blue,
                                        fontSize: 11,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
