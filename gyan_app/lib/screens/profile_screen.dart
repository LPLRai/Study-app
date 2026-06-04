// ─────────────────────────────────────────────────────────────────────────────
// screens/profile_screen.dart
//
// Overhauled profile tab:
//   • Stats are plain text (no boxed cards).
//   • Info fields are borderless text in view mode — the input boxes only
//     appear while editing.
//   • Weekly study-time bar graph (last 7 days), no chart dependency.
//   • Quiz / Answer-Sheet shortcuts removed.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../providers/app_provider.dart';
import '../widgets/sign_out_dialog.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _editMode = false;

  // Matches the new nav-bar accent for a cohesive look.
  static const _accent = Color(0xFF7C5CFF);
  static const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  late TextEditingController _nameCtrl;
  late TextEditingController _gradeCtrl;
  late TextEditingController _goalCtrl;

  @override
  void initState() {
    super.initState();
    final user = context.read<AppProvider>().user;
    _nameCtrl = TextEditingController(text: user.name);
    _gradeCtrl = TextEditingController(text: user.grade);
    _goalCtrl = TextEditingController(text: user.dailyStudyGoalHours.toString());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _gradeCtrl.dispose();
    _goalCtrl.dispose();
    super.dispose();
  }

  void _toggleEdit(AppProvider prov) {
    if (_editMode) {
      prov.updateUser(
        name: _nameCtrl.text.trim().isEmpty ? 'User' : _nameCtrl.text.trim(),
        grade: _gradeCtrl.text.trim(),
        dailyStudyGoalHours:
            int.tryParse(_goalCtrl.text) ?? prov.user.dailyStudyGoalHours,
      );
    } else {
      _nameCtrl.text = prov.user.name;
      _gradeCtrl.text = prov.user.grade;
      _goalCtrl.text = prov.user.dailyStudyGoalHours.toString();
    }
    setState(() => _editMode = !_editMode);
  }

  Future<void> _pickProfileImage(AppProvider prov) async {
    if (!_editMode) return;
    try {
      final picked = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (picked == null) return;
      final docsDir = await getApplicationDocumentsDirectory();
      final destPath = p.join(docsDir.path,
          'profile_${DateTime.now().millisecondsSinceEpoch}${p.extension(picked.path)}');
      await File(picked.path).copy(destPath);
      await prov.updateUser(profileImagePath: destPath);
    } on PlatformException catch (e) {
      debugPrint('Image picker error: $e');
    }
  }

  void _signOut() => confirmSignOut(context);

  /// Study minutes for each of the last 7 days (oldest first).
  List<int> _weeklyMinutes(AppProvider prov) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return List.generate(7, (i) {
      final day = today.subtract(Duration(days: 6 - i));
      return prov.secondsInRange(day, day.add(const Duration(days: 1))) ~/ 60;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(builder: (ctx, prov, _) {
      final t = prov.appTheme;
      final user = prov.user;
      final imgPath = user.profileImagePath;
      final totalMin = prov.totalMinutesAllTime; // session-derived, accurate
      final totalHrs = totalMin / 60;

      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Top bar ────────────────────────────────────────────────
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Profile',
                  style: GoogleFonts.inder(
                      color: t.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              GestureDetector(
                onTap: () => _toggleEdit(prov),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _editMode ? _accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: _editMode
                        ? null
                        : Border.all(color: t.textMuted.withOpacity(0.4)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_editMode ? Icons.check_rounded : Icons.edit_rounded,
                        size: 15,
                        color: _editMode ? Colors.white : t.textPrimary),
                    const SizedBox(width: 6),
                    Text(_editMode ? 'Save' : 'Edit',
                        style: GoogleFonts.inder(
                            color: _editMode ? Colors.white : t.textPrimary,
                            fontSize: 13)),
                  ]),
                ),
              ),
            ]),

            const SizedBox(height: 24),

            // ── Profile picture ────────────────────────────────────────
            Center(
              child: GestureDetector(
                onTap: () => _pickProfileImage(prov),
                child: Stack(alignment: Alignment.bottomRight, children: [
                  Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: t.widgetBg,
                      border: Border.all(
                          color: _editMode ? _accent : t.cardBorder,
                          width: _editMode ? 2 : 1),
                    ),
                    child: ClipOval(
                      child: imgPath != null && File(imgPath).existsSync()
                          ? Image.file(File(imgPath), fit: BoxFit.cover)
                          : Icon(Icons.person_rounded,
                              color: t.textMuted, size: 52),
                    ),
                  ),
                  if (_editMode)
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                          color: _accent, shape: BoxShape.circle),
                      child: const Icon(Icons.camera_alt_rounded,
                          color: Colors.white, size: 16),
                    ),
                ]),
              ),
            ),

            const SizedBox(height: 20),

            // ── Identity / editable info ───────────────────────────────
            if (_editMode) ...[
              _editField(
                  label: 'Full Name',
                  icon: Icons.person_outline_rounded,
                  controller: _nameCtrl,
                  t: t),
              const SizedBox(height: 12),
              _editField(
                  label: 'Grade / Year',
                  icon: Icons.school_outlined,
                  controller: _gradeCtrl,
                  t: t),
              const SizedBox(height: 12),
              _editField(
                  label: 'Daily Study Goal (hours)',
                  icon: Icons.flag_outlined,
                  controller: _goalCtrl,
                  t: t,
                  inputType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
            ] else ...[
              Center(
                child: Column(children: [
                  Text(user.name,
                      style: GoogleFonts.inder(
                          color: t.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(
                    user.grade.trim().isEmpty
                        ? 'Add your grade'
                        : user.grade,
                    style:
                        GoogleFonts.inder(color: t.textMuted, fontSize: 14),
                  ),
                ]),
              ),
            ],

            const SizedBox(height: 32),

            // ── Study Profile (from the Getting Started onboarding) ─────
            _sectionLabel('Study Profile', t),
            const SizedBox(height: 8),
            _statRow(
                'Grade / Education Level',
                user.grade.trim().isEmpty ? '—' : user.grade,
                t),
            _statRow(
                'Preferred Study Time',
                (prov.profileStudyTime?.trim().isNotEmpty ?? false)
                    ? prov.profileStudyTime!
                    : '—',
                t),
            _statRow(
                'Study Goal',
                (prov.profileGoal?.trim().isNotEmpty ?? false)
                    ? prov.profileGoal!
                    : '—',
                t),
            _statRow(
                'Daily Study Target',
                '${user.dailyStudyGoalHours}h',
                t,
                last: true),
            const SizedBox(height: 16),
            _subjectChips(
                'Strong Subjects', prov.profileStrongSubjects, AppColors.green, t),
            const SizedBox(height: 14),
            _subjectChips(
                'Weak Subjects', prov.profileWeakSubjects, AppColors.red, t),

            const SizedBox(height: 30),

            // ── Statistics (text only) ─────────────────────────────────
            _sectionLabel('Statistics', t),
            const SizedBox(height: 8),
            _statRow(
                'Total Study Time',
                totalHrs < 1 ? '${totalMin}m' : '${totalHrs.toStringAsFixed(1)}h',
                t),
            _statRow('Sessions Completed', '${prov.totalSessionsCount}', t),
            _statRow('Current Streak', '${prov.currentStreakDays} days', t),
            _statRow('Best Streak', '${prov.bestStreakDays} days', t),
            _statRow('Daily Goal', '${user.dailyStudyGoalHours}h', t,
                last: true),

            const SizedBox(height: 30),

            // ── Weekly graph ───────────────────────────────────────────
            _sectionLabel('This Week', t),
            const SizedBox(height: 14),
            _weeklyChart(_weeklyMinutes(prov), t),

            const SizedBox(height: 32),

            // ── Sign out ───────────────────────────────────────────────
            GestureDetector(
              onTap: _signOut,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppColors.red.withOpacity(0.45), width: 1.2),
                ),
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.logout_rounded,
                      color: AppColors.red, size: 20),
                  const SizedBox(width: 10),
                  Text('Sign Out',
                      style: GoogleFonts.inder(
                          color: AppColors.red,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
          ]),
        ),
      );
    });
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _sectionLabel(String text, t) => Text(
        text,
        style: GoogleFonts.inder(
            color: t.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
      );

  /// Borderless editable field — only used while in edit mode.
  Widget _editField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    required t,
    TextInputType inputType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) =>
      Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: t.inputBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _accent.withOpacity(0.6), width: 1.3),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: GoogleFonts.inder(color: t.textMuted, fontSize: 11)),
          const SizedBox(height: 4),
          Row(children: [
            Icon(icon, color: t.textMuted, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: inputType,
                inputFormatters: inputFormatters,
                autofocus: false,
                style:
                    GoogleFonts.inder(color: t.textPrimary, fontSize: 16),
                decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero),
              ),
            ),
          ]),
        ]),
      );

  /// A plain text stat line: label on the left, value on the right.
  Widget _statRow(String label, String value, t, {bool last = false}) =>
      Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label,
                style: GoogleFonts.inder(color: t.textMuted, fontSize: 14)),
            Text(value,
                style: GoogleFonts.inder(
                    color: t.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
          ]),
        ),
        if (!last) Divider(height: 1, color: t.divider),
      ]);

  /// A labelled row of subject chips (used for the strong / weak subjects
  /// captured during onboarding). Falls back to a muted placeholder when empty.
  Widget _subjectChips(String label, List<String> items, Color accent, t) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
                width: 7,
                height: 7,
                decoration:
                    BoxDecoration(color: accent, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(label,
                style: GoogleFonts.inder(color: t.textMuted, fontSize: 14)),
          ]),
          const SizedBox(height: 10),
          items.isEmpty
              ? Text('None selected',
                  style: GoogleFonts.inder(
                      color: t.textMuted.withOpacity(0.5), fontSize: 13))
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: items
                      .map((s) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: accent.withOpacity(0.4), width: 1),
                            ),
                            child: Text(s,
                                style: GoogleFonts.inder(
                                    color: accent,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600)),
                          ))
                      .toList(),
                ),
        ],
      );

  /// Lightweight bar chart of the last 7 days of study minutes.
  Widget _weeklyChart(List<int> minutes, t) {
    final maxMins = minutes.fold<int>(0, (m, v) => v > m ? v : m);
    final totalMins = minutes.fold<int>(0, (s, v) => s + v);
    final todayIdx = minutes.length - 1;

    if (totalMins == 0) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        child: Text('No study time logged this week',
            style: GoogleFonts.inder(color: t.textMuted, fontSize: 13)),
      );
    }

    const maxBarHeight = 90.0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return SizedBox(
      height: 144,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(minutes.length, (i) {
          final mins = minutes[i];
          final frac = maxMins == 0 ? 0.0 : mins / maxMins;
          final day = today.subtract(Duration(days: 6 - i));
          final isToday = i == todayIdx;

          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  mins == 0 ? '' : _fmtShort(mins),
                  style: GoogleFonts.inder(
                      color: isToday ? _accent : t.textMuted, fontSize: 9),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 4 + frac * maxBarHeight,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: isToday ? _accent : _accent.withOpacity(0.30),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(6), bottom: Radius.circular(2)),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _weekdayLabels[day.weekday - 1],
                  style: GoogleFonts.inder(
                      color: isToday ? t.textPrimary : t.textMuted,
                      fontSize: 11,
                      fontWeight:
                          isToday ? FontWeight.bold : FontWeight.normal),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  String _fmtShort(int mins) =>
      mins < 60 ? '${mins}m' : '${(mins / 60).toStringAsFixed(1)}h';
}
