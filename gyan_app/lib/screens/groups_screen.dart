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
    final t = prov.appTheme;
    showModalBottomSheet(
      context: ctx,
      backgroundColor: t.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Create a Group',
                    style: GoogleFonts.inder(
                        color: t.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
                IconButton(
                    icon: Icon(Icons.close, color: t.textPrimary),
                    onPressed: () => Navigator.pop(ctx)),
              ]),
              const SizedBox(height: 6),
              Text('You can create up to 5 groups.',
                  style: GoogleFonts.inder(color: t.textMuted, fontSize: 12)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                    child: TextField(
                  controller: nameCtrl,
                  style: GoogleFonts.inder(color: t.textPrimary),
                  decoration: InputDecoration(
                      hintText: 'Group name',
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
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    final res = await prov.createGroupRemote(name);
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (res == 'ok') {
                      _toast(ctx, 'Group "$name" created');
                    } else if (res == 'limit') {
                      _toast(ctx, "You've reached the limit of 5 groups",
                          error: true);
                    } else {
                      _toast(ctx, 'Could not create group (are you online?)',
                          error: true);
                    }
                  },
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 13),
                      decoration: BoxDecoration(
                          color: AppColors.blue,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text('Create',
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
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                                color: t.widgetBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: t.cardBorder),
                                boxShadow: t.widgetShadow),
                            child: Center(
                                child: Text(
                                    'No groups yet — tap "Create a Group" below',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inder(
                                        color: t.textMuted, fontSize: 13))),
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
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            decoration: BoxDecoration(
                              color: AppColors.blue.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: AppColors.blue.withOpacity(0.5),
                                  width: 1.5),
                            ),
                            child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.add_rounded,
                                      color: AppColors.blue, size: 20),
                                  const SizedBox(width: 8),
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
    final members = (g['memberUids'] as List?)?.length ?? 1;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(ctx).push(MaterialPageRoute(
          builder: (_) =>
              GroupDetailScreen(groupId: g['id'] as String, groupName: name))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
            color: t.widgetBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.cardBorder),
            boxShadow: t.widgetShadow),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: AppColors.blue.withOpacity(0.15), shape: BoxShape.circle),
            child: const Icon(Icons.groups_rounded,
                color: AppColors.blue, size: 22),
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
                Text('Tap to open · $members member${members == 1 ? '' : 's'}',
                    style:
                        GoogleFonts.inder(color: t.textMuted, fontSize: 12)),
              ])),
          Icon(Icons.chevron_right_rounded, color: t.textMuted, size: 22),
        ]),
      ),
    );
  }
}
