// ─────────────────────────────────────────────────────────────────────────────
// screens/profile_screen.dart
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

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _editMode = false;

  late TextEditingController _nameCtrl;
  late TextEditingController _gradeCtrl;
  late TextEditingController _goalCtrl;

  @override
  void initState() {
    super.initState();
    final user = context.read<AppProvider>().user;
    _nameCtrl  = TextEditingController(text: user.name);
    _gradeCtrl = TextEditingController(text: user.grade);
    _goalCtrl  = TextEditingController(text: user.dailyStudyGoalHours.toString());
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
        name:                _nameCtrl.text.trim().isEmpty ? 'User' : _nameCtrl.text.trim(),
        grade:               _gradeCtrl.text.trim(),
        dailyStudyGoalHours: int.tryParse(_goalCtrl.text) ?? prov.user.dailyStudyGoalHours,
      );
    } else {
      _nameCtrl.text  = prov.user.name;
      _gradeCtrl.text = prov.user.grade;
      _goalCtrl.text  = prov.user.dailyStudyGoalHours.toString();
    }
    setState(() => _editMode = !_editMode);
  }

  Future<void> _pickProfileImage(AppProvider prov) async {
    if (!_editMode) return;
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (picked == null) return;
      final docsDir  = await getApplicationDocumentsDirectory();
      final destPath = p.join(docsDir.path, 'profile_${DateTime.now().millisecondsSinceEpoch}${p.extension(picked.path)}');
      await File(picked.path).copy(destPath);
      await prov.updateUser(profileImagePath: destPath);
    } on PlatformException catch (e) {
      debugPrint('Image picker error: $e');
    }
  }

  void _signOut() async {
    await context.read<AppProvider>().signOutUser();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(builder: (ctx, prov, _) {
      final t        = prov.appTheme;
      final user     = prov.user;
      final imgPath  = user.profileImagePath;
      final totalHrs = user.totalMinutesStudied / 60;

      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Top bar ────────────────────────────────────────────────
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Profile', style: GoogleFonts.inder(color: t.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
              GestureDetector(
                onTap: () => _toggleEdit(prov),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color:        _editMode ? AppColors.blue : t.widgetBg,
                    borderRadius: BorderRadius.circular(8),
                    border:       _editMode ? null : Border.all(color: t.cardBorder),
                  ),
                  child: Text(_editMode ? 'Save' : 'Edit',
                      style: GoogleFonts.inder(color: _editMode ? Colors.white : t.textPrimary, fontSize: 13)),
                ),
              ),
            ]),

            const SizedBox(height: 26),

            // ── Profile picture ────────────────────────────────────────
            Center(
              child: GestureDetector(
                onTap: () => _pickProfileImage(prov),
                child: Stack(alignment: Alignment.bottomRight, children: [
                  Container(
                    width: 110, height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle, color: t.widgetBg,
                      border: Border.all(color: AppColors.blue.withOpacity(0.4), width: 2.5),
                    ),
                    child: ClipOval(
                      child: imgPath != null && File(imgPath).existsSync()
                          ? Image.file(File(imgPath), fit: BoxFit.cover)
                          : Icon(Icons.person_rounded, color: t.textMuted, size: 56),
                    ),
                  ),
                  if (_editMode)
                    Container(
                      width: 32, height: 32,
                      decoration: const BoxDecoration(color: AppColors.blue, shape: BoxShape.circle),
                      child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                    ),
                ]),
              ),
            ),

            const SizedBox(height: 28),

            // ── Info fields ────────────────────────────────────────────
            _infoField(label: 'Full Name',                icon: Icons.person_outline_rounded,  controller: _nameCtrl,  enabled: _editMode, t: t),
            const SizedBox(height: 10),
            _infoField(label: 'Grade / Year',             icon: Icons.school_outlined,          controller: _gradeCtrl, enabled: _editMode, t: t),
            const SizedBox(height: 10),
            _infoField(label: 'Daily Study Goal (hours)', icon: Icons.flag_outlined,            controller: _goalCtrl,  enabled: _editMode, t: t,
                inputType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly]),

            const SizedBox(height: 20),

            // ── Light / Dark mode toggle — only visible in edit mode ────
            if (_editMode) ...[
              _themeTile(prov, t),
              const SizedBox(height: 20),
            ],

            // ── All-time stats ─────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: BoxDecoration(color: t.widgetBg, borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('All-Time Stats', style: GoogleFonts.inder(color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _statCol(value: totalHrs < 1 ? '${user.totalMinutesStudied}m' : '${totalHrs.toStringAsFixed(1)}h', label: 'Total Hours', t: t),
                  Container(height: 36, width: 1, color: t.divider),
                  _statCol(value: '${user.totalSessions}', label: 'Sessions', t: t),
                  Container(height: 36, width: 1, color: t.divider),
                  _statCol(value: '${user.bestStreak}', label: 'Best Streak', t: t),
                ]),
              ]),
            ),

            const SizedBox(height: 18),

            // ── AI tools ───────────────────────────────────────────────
            _aiRow(
              // MODULE: Answer Sheet Analyser — put (answer_sheet_icon) path here
              icon: Icons.document_scanner_rounded, iconColor: AppColors.green,
              label: 'Answer Sheet Analyzer', sublabel: 'Upload & get AI feedback',
              t: t, onTap: () {/* TODO: navigate to AnswerSheetAnalyserScreen */},
            ),
            const SizedBox(height: 10),
            _aiRow(
              // MODULE: Make a Quiz — put (quiz_icon) path here
              icon: Icons.quiz_rounded, iconColor: AppColors.yellow,
              label: 'Make a Quiz', sublabel: 'AI generates questions for you',
              t: t, onTap: () {/* TODO: navigate to MakeQuizScreen */},
            ),

            const SizedBox(height: 14),

            // ── Sign out ───────────────────────────────────────────────
            GestureDetector(
              onTap: _signOut,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color:        t.widgetBg,
                  borderRadius: BorderRadius.circular(12),
                  border:       Border.all(color: AppColors.red.withOpacity(0.4), width: 1.2),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.logout_rounded, color: AppColors.red, size: 20),
                  const SizedBox(width: 10),
                  Text('Sign Out', style: GoogleFonts.inder(color: AppColors.red, fontSize: 15, fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
          ]),
        ),
      );
    });
  }

  // ── Light / Dark mode toggle tile ─────────────────────────────────────────
  Widget _themeTile(AppProvider prov, t) {
    final isDark = prov.isDarkMode;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color:        t.widgetBg,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: AppColors.blue.withOpacity(0.4), width: 1.2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Appearance', style: GoogleFonts.inder(color: t.textMuted, fontSize: 12)),
        const SizedBox(height: 12),
        // Two tappable mode cards side by side
        Row(children: [
          // Dark mode card
          Expanded(
            child: GestureDetector(
              onTap: () => prov.setDarkMode(true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color:        isDark ? AppColors.blue.withOpacity(0.18) : t.inputBg,
                  borderRadius: BorderRadius.circular(10),
                  border:       isDark
                      ? Border.all(color: AppColors.blue, width: 2)
                      : Border.all(color: t.cardBorder),
                ),
                child: Column(children: [
                  Icon(Icons.dark_mode_rounded,
                      color: isDark ? AppColors.blue : t.textMuted, size: 28),
                  const SizedBox(height: 6),
                  Text('Dark', style: GoogleFonts.inder(
                      color:      isDark ? AppColors.blue : t.textMuted,
                      fontSize:   13,
                      fontWeight: isDark ? FontWeight.bold : FontWeight.normal)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Light mode card
          Expanded(
            child: GestureDetector(
              onTap: () => prov.setDarkMode(false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color:        !isDark ? AppColors.blue.withOpacity(0.12) : t.inputBg,
                  borderRadius: BorderRadius.circular(10),
                  border:       !isDark
                      ? Border.all(color: AppColors.blue, width: 2)
                      : Border.all(color: t.cardBorder),
                ),
                child: Column(children: [
                  Icon(Icons.light_mode_rounded,
                      color: !isDark ? AppColors.blue : t.textMuted, size: 28),
                  const SizedBox(height: 6),
                  Text('Light', style: GoogleFonts.inder(
                      color:      !isDark ? AppColors.blue : t.textMuted,
                      fontSize:   13,
                      fontWeight: !isDark ? FontWeight.bold : FontWeight.normal)),
                ]),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _infoField({
    required String label, required IconData icon,
    required TextEditingController controller, required bool enabled,
    required t,
    TextInputType inputType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) =>
      Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color:        t.widgetBg,
          borderRadius: BorderRadius.circular(12),
          border:       enabled
              ? Border.all(color: AppColors.blue.withOpacity(0.6), width: 1.3)
              : Border.all(color: t.cardBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.inder(color: t.textMuted, fontSize: 11)),
          const SizedBox(height: 4),
          Row(children: [
            Icon(icon, color: t.textMuted, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller:      controller,
                enabled:         enabled,
                keyboardType:    inputType,
                inputFormatters: inputFormatters,
                style: GoogleFonts.inder(color: t.textPrimary, fontSize: 16),
                decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
              ),
            ),
          ]),
        ]),
      );

  Widget _statCol({required String value, required String label, required t}) =>
      Column(children: [
        Text(value, style: GoogleFonts.inder(color: t.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: GoogleFonts.inder(color: t.textMuted, fontSize: 11), textAlign: TextAlign.center),
      ]);

  Widget _aiRow({required IconData icon, required Color iconColor, required String label,
      required String sublabel, required t, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color:        t.widgetBg,
            borderRadius: BorderRadius.circular(12),
            border:       Border.all(color: iconColor.withOpacity(0.5), width: 1.3),
          ),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: iconColor.withOpacity(0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: iconColor.withOpacity(0.5))),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: GoogleFonts.inder(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
              Text(sublabel, style: GoogleFonts.inder(color: t.textMuted, fontSize: 12)),
            ]),
          ]),
        ),
      );
}
