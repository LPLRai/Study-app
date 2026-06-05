// ─────────────────────────────────────────────────────────────────────────────
// widgets/notification_panel.dart
//
// Slide-in side panel listing the user's notifications (live from Firestore).
// Group invites can be Accepted or Declined right here.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';

/// Slides a notifications panel in from the right edge of the screen.
void showNotificationPanel(BuildContext context) {
  // Opening the panel clears the unread badge.
  context.read<AppProvider>().markNotificationsSeen();
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Notifications',
    barrierColor: Colors.black.withOpacity(0.45),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, __, ___) => const Align(
      alignment: Alignment.centerRight,
      child: _NotificationPanel(),
    ),
    transitionBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(curved),
        child: child,
      );
    },
  );
}

class _NotificationPanel extends StatelessWidget {
  const _NotificationPanel();

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AppProvider>();
    final AppThemeData t = prov.appTheme;
    final screenW = MediaQuery.of(context).size.width;
    final width = (screenW * 0.86).clamp(0.0, 380.0);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        height: double.infinity,
        decoration: BoxDecoration(
          color: t.background,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            bottomLeft: Radius.circular(24),
          ),
          border: Border(left: BorderSide(color: t.cardBorder)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 24,
              offset: const Offset(-6, 0),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.notifications_rounded,
                      color: t.textPrimary, size: 22),
                  const SizedBox(width: 10),
                  Text('Notifications',
                      style: GoogleFonts.inder(
                          color: t.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                          color: t.inputBg, shape: BoxShape.circle),
                      child: Icon(Icons.close_rounded,
                          color: t.textMuted, size: 18),
                    ),
                  ),
                ]),
                Divider(color: t.divider, height: 28),
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: prov.notificationsStream(),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              "Couldn't load notifications.\nCheck your Firestore rules are published.",
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inder(
                                  color: AppColors.red, fontSize: 12, height: 1.4),
                            ),
                          ),
                        );
                      }
                      final items = snap.data ?? const [];
                      if (items.isEmpty) return _emptyState(t);
                      return ListView.separated(
                        padding: const EdgeInsets.only(top: 4, bottom: 12),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _tile(context, prov, t, items[i]),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(AppThemeData t) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration:
                  BoxDecoration(color: t.inputBg, shape: BoxShape.circle),
              child: Icon(Icons.notifications_off_rounded,
                  color: t.textMuted, size: 34),
            ),
            const SizedBox(height: 16),
            Text('No notifications yet',
                style: GoogleFonts.inder(
                    color: t.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                "You're all caught up. Group invites and updates will appear here.",
                textAlign: TextAlign.center,
                style: GoogleFonts.inder(
                    color: t.textMuted, fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
      );

  Widget _tile(BuildContext context, AppProvider prov, AppThemeData t,
      Map<String, dynamic> n) {
    final type = n['type'] as String? ?? '';
    final status = n['status'] as String? ?? 'pending';
    final groupName = n['groupName'] as String? ?? 'a group';
    final fromName = n['fromName'] as String? ?? 'Someone';
    final isInvite = type == 'group_invite';
    final isReminder = type == 'study_reminder';
    final pending = isInvite && status == 'pending';

    // Per-type icon, accent and copy.
    const reminderColor = Color(0xFFFF8C00);
    final IconData icon =
        isReminder ? Icons.notifications_active_rounded : Icons.group_add_rounded;
    final Color accent = isReminder ? reminderColor : AppColors.blue;
    final String title =
        isReminder ? 'Study reminder' : 'Group invitation';
    final String body = isReminder
        ? '$fromName is nudging you to study. Time to focus! 💪'
        : '$fromName invited you to join "$groupName"';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.widgetBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: pending ? AppColors.blue.withOpacity(0.4) : t.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: accent.withOpacity(0.15), shape: BoxShape.circle),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: GoogleFonts.inder(
                      color: t.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(body,
                  style: GoogleFonts.inder(
                      color: t.textMuted, fontSize: 11, height: 1.3)),
            ]),
          ),
          if (!pending)
            GestureDetector(
              onTap: () => prov.dismissNotification(n['id'] as String),
              child: Icon(Icons.close_rounded, color: t.textMuted, size: 18),
            ),
        ]),
        if (pending) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _btn('Decline', t.inputBg, t.textPrimary,
                  () => prov.declineInvite(n['id'] as String)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _btn('Accept', AppColors.blue, Colors.white, () {
                prov.acceptInvite(n['id'] as String, n['groupId'] as String);
              }),
            ),
          ]),
        ] else if (isInvite)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              status == 'accepted' ? '✓ Joined' : 'Declined',
              style: GoogleFonts.inder(
                  color: status == 'accepted' ? AppColors.green : t.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          ),
      ]),
    );
  }

  Widget _btn(String label, Color bg, Color fg, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          child: Text(label,
              style: GoogleFonts.inder(
                  color: fg, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      );
}
