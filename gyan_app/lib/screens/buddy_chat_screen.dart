// ─────────────────────────────────────────────────────────────────────────────
// screens/buddy_chat_screen.dart
//
// One Study-Buddy thread. Helper can Accept/Decline a pending request here;
// once active, both can message (text only). Pushed on top of the Groups tab.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../models/buddy_chat_model.dart';
import '../providers/app_provider.dart';
import '../services/buddy_chat_service.dart';

class BuddyChatScreen extends StatefulWidget {
  final BuddyChat chat;
  const BuddyChatScreen({super.key, required this.chat});

  @override
  State<BuddyChatScreen> createState() => _BuddyChatScreenState();
}

class _BuddyChatScreenState extends State<BuddyChatScreen> {
  final _ctrl = TextEditingController();
  static const _accent = Color(0xFF5865F2);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send(AppProvider prov, BuddyChat chat) async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    await BuddyChatService.instance.sendMessage(chat,
        senderUid: prov.currentUid ?? '',
        senderName: prov.user.name,
        text: text);
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.read<AppProvider>();
    final t = prov.appTheme;
    final myUid = prov.currentUid ?? '';

    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: StreamBuilder<BuddyChat?>(
          stream: BuddyChatService.instance.chatStream(widget.chat.id),
          initialData: widget.chat,
          builder: (context, chatSnap) {
            final chat = chatSnap.data ?? widget.chat;
            final amHelper = chat.amHelper(myUid);
            return Column(children: [
              // ── Header ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 16, 6),
                child: Row(children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.chevron_left_rounded,
                          color: t.textPrimary, size: 28),
                    ),
                  ),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(chat.otherName(myUid),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inder(
                                  color: t.textPrimary,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold)),
                          Text('${chat.subject} • help',
                              style: GoogleFonts.inder(
                                  color: t.textMuted, fontSize: 12)),
                        ]),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded, color: t.textMuted),
                    color: t.widgetBg,
                    onSelected: (v) async {
                      if (v == 'leave') {
                        await BuddyChatService.instance.leave(chat.id);
                        if (context.mounted) Navigator.of(context).pop();
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                          value: 'leave',
                          child: Text('Leave chat',
                              style: GoogleFonts.inder(
                                  color: AppColors.red, fontSize: 13))),
                    ],
                  ),
                ]),
              ),
              Divider(color: t.divider, height: 1),

              // ── Messages ─────────────────────────────────────────────
              Expanded(
                child: StreamBuilder<List<BuddyMessage>>(
                  stream: BuddyChatService.instance.messagesStream(chat.id),
                  builder: (context, snap) {
                    final msgs = snap.data ?? const <BuddyMessage>[];
                    if (msgs.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Text(
                              chat.isActive
                                  ? 'Say hello and ask your question 👋'
                                  : 'No messages yet.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inder(
                                  color: t.textMuted, fontSize: 13)),
                        ),
                      );
                    }
                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      itemCount: msgs.length,
                      itemBuilder: (_, i) =>
                          _bubble(t, msgs[i], msgs[i].senderUid == myUid),
                    );
                  },
                ),
              ),

              // ── Footer: accept/decline, waiting, or composer ─────────
              _footer(prov, t, chat, amHelper, myUid),
            ]);
          },
        ),
      ),
    );
  }

  Widget _bubble(t, BuddyMessage m, bool mine) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: mine ? _accent : t.widgetBg,
          borderRadius: BorderRadius.circular(14),
          border: mine ? null : Border.all(color: t.cardBorder),
        ),
        child: Text(m.text,
            style: GoogleFonts.inder(
                color: mine ? Colors.white : t.textPrimary,
                fontSize: 14,
                height: 1.3)),
      ),
    );
  }

  Widget _footer(
      AppProvider prov, t, BuddyChat chat, bool amHelper, String myUid) {
    if (chat.status == 'closed' || chat.status == 'declined') {
      return _banner(t,
          chat.status == 'closed' ? 'This chat has ended.' : 'Request declined.');
    }
    if (chat.isPending) {
      if (amHelper) {
        // Helper decides.
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
          child: Row(children: [
            Expanded(
              child: _actionBtn('Decline', t.inputBg, t.textPrimary, () async {
                await BuddyChatService.instance
                    .respond(chat, false, myName: prov.user.name);
              }),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _actionBtn('Accept', AppColors.green, Colors.white,
                  () async {
                await BuddyChatService.instance
                    .respond(chat, true, myName: prov.user.name);
              }),
            ),
          ]),
        );
      }
      return _banner(t, 'Waiting for ${chat.otherName(myUid)} to accept…');
    }
    // active → composer
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      decoration: BoxDecoration(
          color: t.background,
          border: Border(top: BorderSide(color: t.divider))),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            minLines: 1,
            maxLines: 4,
            style: GoogleFonts.inder(color: t.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Message…',
              hintStyle: GoogleFonts.inder(color: t.textMuted, fontSize: 14),
              filled: true,
              fillColor: t.inputBg,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _send(prov, chat),
          child: Container(
            width: 44,
            height: 44,
            decoration:
                const BoxDecoration(color: _accent, shape: BoxShape.circle),
            child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
          ),
        ),
      ]),
    );
  }

  Widget _banner(t, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        color: t.widgetBg,
        child: Text(text,
            textAlign: TextAlign.center,
            style: GoogleFonts.inder(color: t.textMuted, fontSize: 13)),
      );

  Widget _actionBtn(String label, Color bg, Color fg, VoidCallback onTap) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          alignment: Alignment.center,
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
          child: Text(label,
              style: GoogleFonts.inder(
                  color: fg, fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      );
}
