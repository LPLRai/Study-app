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
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showProfile(context, chat, myUid),
                      child: Row(children: [
                        _miniAvatar(t, chat.otherName(myUid)),
                        const SizedBox(width: 10),
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
                                Text('${chat.subject} • tap for profile',
                                    style: GoogleFonts.inder(
                                        color: t.textMuted, fontSize: 12)),
                              ]),
                        ),
                      ]),
                    ),
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

  // ── Profile popup (tap the chat header) ───────────────────────────────────
  Widget _miniAvatar(t, String name) => Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: _accent.withOpacity(0.18), shape: BoxShape.circle),
        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: GoogleFonts.inder(
                color: _accent, fontSize: 15, fontWeight: FontWeight.bold)),
      );

  void _showProfile(BuildContext context, BuddyChat chat, String myUid) {
    final t = context.read<AppProvider>().appTheme;
    final uid = chat.otherUid(myUid);
    final name = chat.otherName(myUid);
    showModalBottomSheet(
      context: context,
      backgroundColor: t.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => FutureBuilder<Map<String, dynamic>?>(
        future: BuddyChatService.instance.fetchBuddyInfo(uid),
        builder: (context, snap) => _profileSheet(t, name, chat.subject,
            snap.data, snap.connectionState == ConnectionState.waiting),
      ),
    );
  }

  Widget _profileSheet(
      t, String name, String subject, Map<String, dynamic>? info, bool loading) {
    final grade = (info?['grade'] as String?)?.trim() ?? '';
    final goal = (info?['studyGoal'] as String?)?.trim() ?? '';
    final time = (info?['studyTime'] as String?)?.trim() ?? '';
    final strong = List<String>.from(info?['strongSubjects'] ?? const []);
    final weak = List<String>.from(info?['weakSubjects'] ?? const []);
    final best = (info?['bestStreak'] as int?) ?? 0;
    final today = (info?['todaySeconds'] as int?) ?? 0;
    final noDetails =
        time.isEmpty && goal.isEmpty && strong.isEmpty && weak.isEmpty;

    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.62),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: t.textMuted.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 18),
              Row(children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: _accent.withOpacity(0.18), shape: BoxShape.circle),
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: GoogleFonts.inder(
                          color: _accent,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inder(
                                color: t.textPrimary,
                                fontSize: 19,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 3),
                        Text(
                            grade.isEmpty
                                ? 'Study buddy • $subject'
                                : '$grade • $subject',
                            style: GoogleFonts.inder(
                                color: t.textMuted, fontSize: 12)),
                      ]),
                ),
              ]),
              const SizedBox(height: 18),
              if (loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child:
                      Center(child: CircularProgressIndicator(color: _accent)),
                )
              else if (info == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text("Couldn't load this profile.",
                      style: GoogleFonts.inder(
                          color: t.textMuted, fontSize: 13)),
                )
              else ...[
                Row(children: [
                  Expanded(
                      child: _statCard(t, 'Studied today',
                          _fmtDuration(today), Icons.today_rounded)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _statCard(
                          t,
                          'Best streak',
                          best == 1 ? '1 day' : '$best days',
                          Icons.local_fire_department_rounded)),
                ]),
                if (time.isNotEmpty)
                  _infoRow(t, Icons.schedule_rounded, 'Preferred time', time),
                if (goal.isNotEmpty)
                  _infoRow(t, Icons.flag_rounded, 'Study goal', goal),
                if (strong.isNotEmpty)
                  _subjectsBlock(
                      t, 'Strong subjects', strong, const Color(0xFF2DC88A)),
                if (weak.isNotEmpty)
                  _subjectsBlock(t, 'Improving', weak, const Color(0xFFFF8C00)),
                if (noDetails)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text("They haven't shared profile details yet.",
                        style: GoogleFonts.inder(
                            color: t.textMuted, fontSize: 12, height: 1.4)),
                  ),
              ],
            ]),
      ),
    );
  }

  Widget _statCard(t, String label, String value, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: t.widgetBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.cardBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: _accent, size: 20),
          const SizedBox(height: 8),
          Text(value,
              style: GoogleFonts.inder(
                  color: t.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.inder(color: t.textMuted, fontSize: 11)),
        ]),
      );

  Widget _infoRow(t, IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Icon(icon, size: 18, color: t.textMuted),
          const SizedBox(width: 10),
          Text(label, style: GoogleFonts.inder(color: t.textMuted, fontSize: 13)),
          const Spacer(),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inder(
                    color: t.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      );

  Widget _subjectsBlock(t, String label, List<String> subjects, Color color) =>
      Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: GoogleFonts.inder(color: t.textMuted, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: subjects
                    .map((s) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: color.withOpacity(0.5)),
                          ),
                          child: Text(s,
                              style: GoogleFonts.inder(
                                  color: color,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ))
                    .toList(),
              ),
            ]),
      );

  String _fmtDuration(int seconds) {
    if (seconds <= 0) return '0m';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
    if (m > 0) return '${m}m';
    return '${seconds}s';
  }
}
