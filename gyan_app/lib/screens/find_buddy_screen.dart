// ─────────────────────────────────────────────────────────────────────────────
// screens/find_buddy_screen.dart
//
// Learner picks a subject they're WEAK in, then sees opted-in helpers in their
// grade (or one above) and sends a help request. Pushed from Groups → Buddies.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../providers/app_provider.dart';
import '../services/buddy_chat_service.dart';

class FindBuddyScreen extends StatefulWidget {
  const FindBuddyScreen({super.key});

  @override
  State<FindBuddyScreen> createState() => _FindBuddyScreenState();
}

class _FindBuddyScreenState extends State<FindBuddyScreen> {
  static const _accent = Color(0xFF5865F2);
  String? _subject;
  List<Map<String, dynamic>>? _results;
  bool _loading = false;
  final Set<String> _requested = {}; // uids we've already asked this session

  Future<void> _search(AppProvider prov, String subject) async {
    setState(() {
      _subject = subject;
      _loading = true;
      _results = null;
    });
    final res = await BuddyChatService.instance.searchHelpers(
      subject: subject,
      myGrade: prov.user.grade,
      myUid: prov.currentUid ?? '',
    );
    if (mounted) setState(() {
      _results = res;
      _loading = false;
    });
  }

  Future<void> _ask(AppProvider prov, Map<String, dynamic> helper) async {
    final res = await BuddyChatService.instance.requestHelp(
      learnerUid: prov.currentUid ?? '',
      learnerName: prov.user.name,
      learnerGrade: prov.user.grade,
      helperUid: helper['uid'] as String,
      helperName: helper['name'] as String,
      helperGrade: helper['grade'] as String,
      subject: _subject!,
    );
    if (!mounted) return;
    if (res == 'sent') setState(() => _requested.add(helper['uid'] as String));
    _toast(
      res == 'sent'
          ? 'Request sent to ${helper['name']}'
          : res == 'exists'
              ? 'You already have a buddy for $_subject'
              : "Couldn't send the request",
      error: res != 'sent',
    );
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppColors.red : AppColors.green,
        content: Text(msg,
            style: GoogleFonts.inder(color: Colors.white, fontSize: 13)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AppProvider>();
    final t = prov.appTheme;
    final weak = prov.user.weakSubjects;

    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 16, 0),
            child: Stack(alignment: Alignment.center, children: [
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.chevron_left_rounded,
                        color: t.textPrimary, size: 28),
                  ),
                ),
              ),
              Text('Find a Study Buddy',
                  style: GoogleFonts.inder(
                      color: t.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            ]),
          ),
          Expanded(
            child: weak.isEmpty
                ? _empty(t,
                    'Add the subjects you want to improve in your Profile, then come back to find a buddy.')
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      Text("Which subject do you need help with?",
                          style: GoogleFonts.inder(
                              color: t.textMuted, fontSize: 13)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: weak.map((s) {
                          final sel = s == _subject;
                          return GestureDetector(
                            onTap: () => _search(prov, s),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 9),
                              decoration: BoxDecoration(
                                color: sel
                                    ? _accent
                                    : t.inputBg,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: sel ? _accent : t.cardBorder),
                              ),
                              child: Text(s,
                                  style: GoogleFonts.inder(
                                      color: sel ? Colors.white : t.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      if (_loading)
                        const Center(
                            child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(color: _accent),
                        ))
                      else if (_subject != null && (_results?.isEmpty ?? false))
                        _empty(t,
                            'No helpers for $_subject in your grade yet. Check back later.')
                      else if (_results != null)
                        ..._results!.map((h) => _helperCard(prov, t, h)),
                    ],
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _helperCard(AppProvider prov, t, Map<String, dynamic> h) {
    final strong = (h['strongSubjects'] as List).cast<String>();
    final asked = _requested.contains(h['uid']);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.widgetBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.cardBorder),
      ),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: _accent.withOpacity(0.15), shape: BoxShape.circle),
          child: Text(
              (h['name'] as String).isNotEmpty
                  ? (h['name'] as String)[0].toUpperCase()
                  : '?',
              style: GoogleFonts.inder(
                  color: _accent, fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(h['name'] as String,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inder(
                    color: t.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
                '${h['grade']} • strong in ${strong.isEmpty ? '—' : strong.take(3).join(', ')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inder(color: t.textMuted, fontSize: 11)),
          ]),
        ),
        const SizedBox(width: 8),
        asked
            ? Text('Sent',
                style: GoogleFonts.inder(
                    color: AppColors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.w600))
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _ask(prov, h),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                      color: _accent, borderRadius: BorderRadius.circular(20)),
                  child: Text('Ask',
                      style: GoogleFonts.inder(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
              ),
      ]),
    );
  }

  Widget _empty(t, String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(msg,
              textAlign: TextAlign.center,
              style:
                  GoogleFonts.inder(color: t.textMuted, fontSize: 13, height: 1.4)),
        ),
      );
}
