import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../providers/app_provider.dart';
import 'group_detail_screen.dart';

class GroupsScreen extends StatelessWidget {
  const GroupsScreen({super.key});

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

  void _showCreateSheet(BuildContext ctx, AppProvider prov) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final t = prov.appTheme;
    showModalBottomSheet(
      context: ctx,
      backgroundColor: t.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      // Use the sheet's own context for viewInsets — fixes keyboard-covers-field bug
      builder: (sheetCtx) => Padding(
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
                // Group name
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
                // Description
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
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) return;
                      final desc = descCtrl.text.trim();
                      final res = await prov.createGroupRemote(name,
                          description: desc);
                      if (!ctx.mounted) return;
                      Navigator.pop(sheetCtx);
                      if (res == 'ok') {
                        _toast(ctx, 'Group "$name" created!');
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(builder: (ctx, prov, _) {
      final t = prov.appTheme;
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
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: prov.myGroupsStream(),
              builder: (context, snap) {
                final groups = snap.data ?? const [];
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Your Groups',
                            style: GoogleFonts.inder(
                                color: t.textMuted, fontSize: 14)),
                        const SizedBox(height: 10),
                        if (snap.connectionState == ConnectionState.waiting)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.blue)),
                          )
                        else if (groups.isEmpty)
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
                                child: _groupTile(ctx, t, g),
                              )),
                        const SizedBox(height: 14),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _showCreateSheet(ctx, prov),
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
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
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
                      ]),
                );
              },
            ),
          ),
        ]),
      );
    });
  }

  Widget _groupTile(BuildContext ctx, t, Map<String, dynamic> g) {
    final name = g['name'] as String? ?? 'Group';
    final ownerUid = g['ownerUid'] as String? ?? '';
    final description = g['description'] as String? ?? '';
    final memberCount = (g['memberUids'] as List?)?.length ?? 1;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(ctx).push(MaterialPageRoute(
          builder: (_) => GroupDetailScreen(
                groupId: g['id'] as String,
                groupName: name,
                ownerUid: ownerUid,
                description: description,
              ))),
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
