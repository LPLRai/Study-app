// ─────────────────────────────────────────────────────────────────────────────
// widgets/buddies_view.dart
//
// The "Buddies" half of the Groups tab: incoming help requests (you're the
// helper), your active buddy chats, and outgoing pending requests. Plus a
// "Find a buddy" entry. Tapping any item opens the BuddyChatScreen.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/buddy_chat_model.dart';
import '../providers/app_provider.dart';
import '../screens/buddy_chat_screen.dart';
import '../screens/find_buddy_screen.dart';
import '../services/buddy_chat_service.dart';

class BuddiesView extends StatelessWidget {
  const BuddiesView({super.key});

  static const _accent = Color(0xFF5865F2);

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AppProvider>();
    final t = prov.appTheme;
    final myUid = prov.currentUid ?? '';

    return StreamBuilder<List<BuddyChat>>(
      stream: BuddyChatService.instance.myChatsStream(myUid),
      builder: (context, snap) {
        final all = snap.data ?? const <BuddyChat>[];
        final incoming =
            all.where((c) => c.isPending && c.amHelper(myUid)).toList();
        final active = all.where((c) => c.isActive).toList();
        final outgoing =
            all.where((c) => c.isPending && !c.amHelper(myUid)).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // Find a buddy
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const FindBuddyScreen())),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: _accent.withOpacity(0.45), width: 1.5),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.search_rounded, color: _accent, size: 20),
                  const SizedBox(width: 8),
                  Text('Find a Study Buddy',
                      style: GoogleFonts.inder(
                          color: _accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
            const SizedBox(height: 20),

            if (incoming.isNotEmpty) ...[
              _label(t, 'Requests for you'),
              ...incoming.map((c) => _tile(context, t, myUid, c, badge: true)),
              const SizedBox(height: 18),
            ],
            if (active.isNotEmpty) ...[
              _label(t, 'Your buddies'),
              ...active.map((c) => _tile(context, t, myUid, c)),
              const SizedBox(height: 18),
            ],
            if (outgoing.isNotEmpty) ...[
              _label(t, 'Waiting to be accepted'),
              ...outgoing.map((c) => _tile(context, t, myUid, c)),
            ],

            if (incoming.isEmpty && active.isEmpty && outgoing.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Center(
                  child: Column(children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: _accent.withOpacity(0.10),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.volunteer_activism_rounded,
                          color: _accent, size: 30),
                    ),
                    const SizedBox(height: 12),
                    Text('No buddies yet',
                        style: GoogleFonts.inder(
                            color: t.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                          'Find a peer who is strong in a subject you want to improve, or turn on "Be a Study Buddy" in your Profile to get requests.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inder(
                              color: t.textMuted, fontSize: 12, height: 1.4)),
                    ),
                  ]),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _label(t, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: GoogleFonts.inder(color: t.textMuted, fontSize: 14)),
      );

  Widget _tile(BuildContext context, t, String myUid, BuddyChat c,
      {bool badge = false}) {
    final name = c.otherName(myUid);
    final preview = c.isPending
        ? (c.amHelper(myUid)
            ? 'Wants help with ${c.subject}'
            : 'Waiting for $name to accept')
        : (c.lastMessage.isEmpty ? 'Tap to open' : c.lastMessage);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => BuddyChatScreen(chat: c))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.widgetBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: badge ? _accent.withOpacity(0.5) : t.cardBorder),
        ),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: _accent.withOpacity(0.15), shape: BoxShape.circle),
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: GoogleFonts.inder(
                    color: _accent, fontSize: 17, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$name • ${c.subject}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inder(
                          color: t.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          GoogleFonts.inder(color: t.textMuted, fontSize: 12)),
                ]),
          ),
          if (badge)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                  color: _accent, borderRadius: BorderRadius.circular(10)),
              child: Text('NEW',
                  style: GoogleFonts.inder(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            )
          else
            Icon(Icons.chevron_right_rounded, color: t.textMuted, size: 20),
        ]),
      ),
    );
  }
}
