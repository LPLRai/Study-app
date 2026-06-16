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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../providers/app_provider.dart';
import '../widgets/sign_out_dialog.dart';
import '../widgets/profile_avatar.dart';
import 'admin_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _editMode = false;

  // Unified app accent (matches the theme accent everywhere).
  static const _accent = Color(0xFF5865F2);
  static const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  late TextEditingController _nameCtrl;
  String? _selectedGrade;
  String? _selectedGoal;
  String? _selectedDailyTarget;
  final Set<String> _strong = {};
  final Set<String> _weak   = {};
  bool _isStudyBuddy = false; // Study Buddy opt-in

  static const _grades = [
    '6th Grade', '7th Grade', '8th Grade', '9th Grade', '10th Grade',
    '11th Grade', '12th Grade', 'Bachelor',
  ];

  static const _goals = [
    'Improve Grades', 'Build Consistency',
    'Prepare for Exams', 'Learn Faster',
  ];

  static const _subjectsList = [
    'Mathematics', 'Physics', 'Chemistry', 'Biology',
    'English', 'Nepali', 'Social Studies',
    'Computer Science', 'Accounts', 'Economics', 'History',
  ];

  @override
  void initState() {
    super.initState();
    final user = context.read<AppProvider>().user;
    _nameCtrl = TextEditingController(text: user.name);
    _selectedGrade = user.grade.isEmpty ? null : user.grade;
    _selectedGoal = user.studyGoal.isEmpty ? null : user.studyGoal;
    _selectedDailyTarget = '${user.dailyStudyGoalHours} ${user.dailyStudyGoalHours == 1 ? 'Hour' : 'Hours'}';
    _strong.addAll(user.strongSubjects);
    _weak.addAll(user.weakSubjects);
    _isStudyBuddy = user.helpSubjects.isNotEmpty;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _toggleEdit(AppProvider prov) {
    if (_editMode) {
      final hoursStr = _selectedDailyTarget?.split(' ').first ?? '4';
      final hours = int.tryParse(hoursStr) ?? 4;
      prov.updateUser(
        name: _nameCtrl.text.trim().isEmpty ? 'User' : _nameCtrl.text.trim(),
        grade: _selectedGrade ?? '',
        dailyStudyGoalHours: hours,
        studyGoal: _selectedGoal ?? '',
        strongSubjects: _strong.toList(),
        weakSubjects: _weak.toList(),
      );
      // Save the Study Buddy opt-in (after updateUser, so strong subjects are set).
      prov.setStudyBuddy(_isStudyBuddy,
          subjects: _isStudyBuddy ? _strong.toList() : const <String>[]);
    } else {
      final user = prov.user;
      _nameCtrl.text = user.name;
      _selectedGrade = user.grade.isEmpty ? null : user.grade;
      _selectedGoal = user.studyGoal.isEmpty ? null : user.studyGoal;
      _selectedDailyTarget = '${user.dailyStudyGoalHours} ${user.dailyStudyGoalHours == 1 ? 'Hour' : 'Hours'}';
      _strong.clear();
      _strong.addAll(user.strongSubjects);
      _weak.clear();
      _weak.addAll(user.weakSubjects);
      _isStudyBuddy = user.helpSubjects.isNotEmpty;
    }
    setState(() => _editMode = !_editMode);
  }

  // Lets the user pick one of the developer-curated avatars bundled with the
  // app (assets/avatars/, listed in constants/avatars.dart — no backend).
  void _showAvatarPicker(AppProvider prov) {
    final t = prov.appTheme;
    final avatars = prov.avatarOptions;
    showModalBottomSheet(
      context: context,
      backgroundColor: t.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final current = prov.user.profileImagePath;
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text('Choose your avatar',
                        style: GoogleFonts.inder(
                            color: t.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                        icon: Icon(Icons.close_rounded, color: t.textPrimary),
                        onPressed: () => Navigator.pop(ctx)),
                  ]),
                  const SizedBox(height: 2),
                  Text('Tap a picture to set it as your profile photo.',
                      style:
                          GoogleFonts.inder(color: t.textMuted, fontSize: 13)),
                  const SizedBox(height: 18),
                  // Centered, evenly-aligned grid (5 per row → tidy 2 rows of 5).
                  LayoutBuilder(builder: (_, c) {
                    const cols = 5;
                    const gap = 12.0;
                    final size = (c.maxWidth - gap * (cols - 1)) / cols;
                    return Wrap(
                      spacing: gap,
                      runSpacing: 14,
                      alignment: WrapAlignment.center,
                      children: avatars.map((path) {
                        final selected = path == current;
                        return GestureDetector(
                          onTap: () {
                            prov.setProfileAvatar(path);
                            Navigator.pop(ctx);
                          },
                          child: Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  width: size,
                                  height: size,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: t.widgetBg,
                                    border: Border.all(
                                        color: selected
                                            ? AppColors.blue
                                            : t.cardBorder,
                                        width: selected ? 3 : 1.5),
                                    boxShadow: selected
                                        ? [
                                            BoxShadow(
                                                color: AppColors.blue
                                                    .withOpacity(0.4),
                                                blurRadius: 10)
                                          ]
                                        : null,
                                  ),
                                  child: ClipOval(
                                    child: Image.asset(path,
                                        fit: BoxFit.cover,
                                        width: size,
                                        height: size,
                                        alignment: Alignment.center,
                                        errorBuilder: (_, __, ___) => Icon(
                                            Icons.person_rounded,
                                            color: t.textMuted,
                                            size: size * 0.45)),
                                  ),
                                ),
                                if (selected)
                                  Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                        color: AppColors.blue,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: t.background, width: 2)),
                                    child: const Icon(Icons.check_rounded,
                                        color: Colors.white, size: 13),
                                  ),
                              ]),
                        );
                      }).toList(),
                    );
                  }),
                ]),
          ),
        );
      },
    );
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

            // ── Profile picture (only editable while in edit mode) ─────
            Center(
              child: GestureDetector(
                onTap: _editMode ? () => _showAvatarPicker(prov) : null,
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
                      child: profileImageChild(imgPath,
                          icon: Icons.person_rounded,
                          color: t.textMuted,
                          iconSize: 52),
                    ),
                  ),
                  // Edit badge appears only in edit mode — makes it clear the
                  // picture can only be changed after tapping "Edit".
                  if (_editMode)
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                          color: _accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: t.background, width: 2)),
                      child: const Icon(Icons.edit_rounded,
                          color: Colors.white, size: 16),
                    ),
                ]),
              ),
            ),

            const SizedBox(height: 20),

            // ── Identity / editable info ───────────────────────────────
            if (_editMode) ...[
              _editField(
                  label: 'Username',
                  icon: Icons.person_outline_rounded,
                  controller: _nameCtrl,
                  t: t),
              const SizedBox(height: 12),
              _editDropdown(
                label: 'Grade / Education Level',
                icon: Icons.school_outlined,
                value: _selectedGrade,
                items: _grades,
                onChanged: (v) => setState(() => _selectedGrade = v),
                t: t,
              ),
              const SizedBox(height: 12),
              _editDropdown(
                label: 'Study Goal',
                icon: Icons.flag_outlined,
                value: _selectedGoal,
                items: _goals,
                onChanged: (v) => setState(() => _selectedGoal = v),
                t: t,
              ),
              const SizedBox(height: 12),
              _editDropdown(
                label: 'Daily Study Target',
                icon: Icons.timer_outlined,
                value: _selectedDailyTarget,
                items: List.generate(
                    8, (i) => '${i + 1} ${i + 1 == 1 ? 'Hour' : 'Hours'}'),
                onChanged: (v) => setState(() => _selectedDailyTarget = v),
                t: t,
              ),
              const SizedBox(height: 20),
              _chipSelector(
                label: 'Strong Subjects',
                selected: _strong,
                excluded: _weak,
                accent: const Color(0xFF2DC88A),
                t: t,
              ),
              const SizedBox(height: 16),
              _chipSelector(
                label: 'Weak Subjects',
                selected: _weak,
                excluded: _strong,
                accent: const Color(0xFFEF5A55),
                t: t,
              ),
              const SizedBox(height: 18),
              // ── Study Buddy opt-in ───────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                decoration: BoxDecoration(
                  color: t.inputBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _isStudyBuddy ? _accent : t.cardBorder),
                ),
                child: Row(children: [
                  Icon(Icons.volunteer_activism_outlined,
                      color: _isStudyBuddy ? _accent : t.textMuted, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Be a Study Buddy',
                              style: GoogleFonts.inder(
                                  color: t.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 3),
                          Text(
                              'Help peers in your grade (or one below) who are '
                              'weak in your strong subjects. You accept or '
                              'decline each request.',
                              style: GoogleFonts.inder(
                                  color: t.textMuted,
                                  fontSize: 11,
                                  height: 1.35)),
                        ]),
                  ),
                  Switch(
                    value: _isStudyBuddy,
                    activeColor: _accent,
                    onChanged: (v) => setState(() => _isStudyBuddy = v),
                  ),
                ]),
              ),
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

            // ── Study Info (from onboarding) ─────────────────────────────────
            if (user.studyTime.isNotEmpty || user.studyGoal.isNotEmpty) ...[
              _sectionLabel('Study Info', t),
              const SizedBox(height: 8),
              if (user.studyTime.isNotEmpty)
                _statRow('Preferred Study Time', user.studyTime, t),
              if (user.studyGoal.isNotEmpty)
                _statRow('Study Goal', user.studyGoal, t, last: true),
              const SizedBox(height: 30),
            ],

            // ── Subjects (from onboarding) ───────────────────────────────────
            if (user.strongSubjects.isNotEmpty || user.weakSubjects.isNotEmpty) ...[
              _sectionLabel('My Subjects', t),
              const SizedBox(height: 12),
              if (user.strongSubjects.isNotEmpty)
                _subjectChips('Strong', user.strongSubjects, const Color(0xFF2DC88A), t),
              if (user.weakSubjects.isNotEmpty) ...[
                const SizedBox(height: 14),
                _subjectChips('Weak', user.weakSubjects, const Color(0xFFEF5A55), t),
              ],
              const SizedBox(height: 30),
            ],

            // ── Statistics (text only) ─────────────────────────────────────────
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

            // ── Admin Panel (only shown to eligible admins) ────────────
            if (prov.isAdmin) ...[
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AdminScreen())),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [_accent, Color(0xFF5865F2)]),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                          color: _accent.withOpacity(0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 6)),
                    ],
                  ),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.shield_rounded,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 10),
                        Text('Admin Panel',
                            style: GoogleFonts.inder(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold)),
                      ]),
                ),
              ),
              const SizedBox(height: 14),
            ],

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
        /// Displays a row of coloured subject chips (used for strong / weak).
  Widget _subjectChips(String label, List<String> items, Color accent, t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(label,
              style: GoogleFonts.inder(
                  color: t.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: items
              .map((s) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: accent.withOpacity(0.4), width: 1),
                    ),
                    child: Text(s,
                        style: GoogleFonts.inder(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: accent)),
                  ))
              .toList(),
        ),
      ],
    );
  }

  /// Dropdown editor for study info fields.
  Widget _editDropdown({
    required String label,
    required IconData icon,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required t,
  }) {
    final dropdownItems = List<String>.from(items);
    if (value != null && value.isNotEmpty && !dropdownItems.contains(value)) {
      dropdownItems.add(value);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: t.inputBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withOpacity(0.6), width: 1.3),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: GoogleFonts.inder(color: t.textMuted, fontSize: 11)),
        const SizedBox(height: 2),
        Row(children: [
          Icon(icon, color: t.textMuted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                hint: Text('Select $label',
                    style: GoogleFonts.inder(color: t.textMuted, fontSize: 15)),
                isExpanded: true,
                isDense: true,
                icon: Icon(Icons.keyboard_arrow_down_rounded,
                    size: 22, color: t.textMuted),
                dropdownColor: t.inputBg,
                borderRadius: BorderRadius.circular(14),
                items: dropdownItems
                    .map((e) => DropdownMenuItem(
                          value: e,
                          child: Text(e,
                              style: GoogleFonts.inder(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: t.textPrimary,
                              )),
                        ))
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  /// Chip selector for subjects inside edit mode.
  Widget _chipSelector({
    required String label,
    required Set<String> selected,
    required Set<String> excluded,
    required Color accent,
    required t,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(label,
              style: GoogleFonts.inder(
                  color: t.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          if (selected.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('${selected.length}',
                  style: GoogleFonts.inder(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  )),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _subjectsList.map((s) {
            final on = selected.contains(s);
            final disabled = excluded.contains(s);
            return GestureDetector(
              onTap: disabled
                  ? null
                  : () {
                      setState(() {
                        if (on) {
                          selected.remove(s);
                        } else {
                          selected.add(s);
                        }
                      });
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: disabled
                      ? t.cardBorder.withOpacity(0.1)
                      : on
                          ? accent.withOpacity(0.14)
                          : t.inputBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: disabled
                        ? t.cardBorder.withOpacity(0.4)
                        : on
                            ? accent.withOpacity(0.6)
                            : t.cardBorder,
                    width: on ? 1.5 : 1.0,
                  ),
                ),
                child: Text(s,
                    style: GoogleFonts.inder(
                      fontSize: 12,
                      fontWeight: on ? FontWeight.bold : FontWeight.normal,
                      color: disabled
                          ? t.textMuted.withOpacity(0.4)
                          : on
                              ? accent
                              : t.textPrimary,
                    )),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
