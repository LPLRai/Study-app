// ─────────────────────────────────────────────────────────────────────────────
// screens/getstarted_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/app_provider.dart';
import 'auth_screen.dart';
import '../services/firebase_service.dart';

// ─── GetStartedPage ───────────────────────────────────────────────────────────
class GetStartedPage extends StatefulWidget {
  const GetStartedPage({super.key});

  @override
  State<GetStartedPage> createState() => _GetStartedPageState();
}

class _GetStartedPageState extends State<GetStartedPage>
    with SingleTickerProviderStateMixin {

  final _formKey    = GlobalKey<FormState>();
  final _scrollCtrl = ScrollController();

  bool _attempted = false;
  bool _isDark = false;

  String? _grade;
  String? _studyTime;
  String? _goal;
  String? _dailyTarget;
  final Set<String> _strong = {};
  final Set<String> _weak   = {};

  late final AnimationController _entryCtrl;
  late final Animation<double>   _fade;
  late final Animation<Offset>   _slide;

  // ─── Dynamic Theme Getters ─────────────────────────────────────────────────
  Color get primary     => const Color(0xFF5B5BD6);
  Color get bg          => _isDark ? const Color(0xFF121318) : const Color(0xFFF5F2F7);
  Color get card        => _isDark ? const Color(0xFF18181F) : Colors.white;
  Color get fieldFill   => _isDark ? const Color(0xFF22222B) : const Color(0xFFF2F0F7);
  Color get textPrimary => _isDark ? Colors.white : const Color(0xFF1A1A22);
  Color get textSub     => _isDark ? const Color(0xFF9898A5) : const Color(0xFF6E6E78);
  Color get borderDef   => _isDark ? Colors.white.withOpacity(0.08) : const Color(0xFF1A1A22).withOpacity(0.12);
  Color get shadow      => _isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.08);

  // ─── Options ──────────────────────────────────────────────────────────────
  static const _grades = [
    '6th Grade', '7th Grade', '8th Grade', '9th Grade', '10th Grade',
    '11th Grade', '12th Grade', 'Bachelor',
  ];

  static const _times  = ['Morning', 'Afternoon', 'Evening', 'Late Night', 'Flexible'];
  static const _goals  = [
    'Improve Grades', 'Build Consistency',
    'Prepare for Exams', 'Learn Faster',
  ];
  static const _subjects = [
    'Mathematics', 'Physics', 'Chemistry', 'Biology',
    'English', 'Nepali', 'Social Studies',
    'Computer Science', 'Accounts', 'Economics', 'History',
  ];

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 650))
      ..forward();
    _fade  = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: SafeArea(
            child: CustomScrollView(
              controller: _scrollCtrl,
              physics: const BouncingScrollPhysics(),
              slivers: [
                // Top Action Bar with theme switcher
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 14, top: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(
                          _isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                          color: textPrimary,
                          size: 20,
                        ),
                        Switch(
                          value: _isDark,
                          activeColor: primary,
                          onChanged: (v) => setState(() => _isDark = v),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: _logoPlaceholder()),
                SliverToBoxAdapter(child: _mainCard()),
                const SliverToBoxAdapter(child: SizedBox(height: 48)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _logoPlaceholder() {
  return Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Center(
      child: SvgPicture.asset(
        'assets/icon/gyam.svg',
        width: 90,
        height: 90,
        colorFilter: ColorFilter.mode(
          _isDark ? Colors.white : const Color(0xFF5B5BD6),
          BlendMode.srcIn,
        ),
      ),
    ),
  );
}

  // ─── Main card ────────────────────────────────────────────────────────────
  Widget _mainCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Container(
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderDef, width: 1),
          boxShadow: [
            BoxShadow(color: shadow, blurRadius: 28, offset: const Offset(0, 8)),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(22, 32, 22, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  "Let's personalize your study experience",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, height: 1.55, color: textSub),
                ),
              ),
              const SizedBox(height: 28),
              _hr(),
              const SizedBox(height: 26),

              // ── Study Profile ──────────────────────────────────────────
              _sectionLabel('Study Profile'),
              const SizedBox(height: 14),

              _RequiredLabel(
                label: 'Grade / Education Level',
                show: _attempted && _grade == null,
                textSub: textSub,
              ),
              const SizedBox(height: 6),
              _GyanDropdown(
                value: _grade, hint: 'Grade / Education Level',
                icon: Icons.school_outlined, items: _grades,
                onChanged: (v) => setState(() => _grade = v),
                primary: primary, textPrimary: textPrimary, textSub: textSub,
                fieldFill: fieldFill, borderDef: borderDef,
              ),
              const SizedBox(height: 12),
             
             
              _RequiredLabel(
                label: 'Preferred Study Time',
                show: _attempted && _studyTime == null,
                textSub: textSub,
              ),
              const SizedBox(height: 6),
              _GyanDropdown(
                value: _studyTime, hint: 'Preferred Study Time',
                icon: Icons.schedule_outlined, items: _times,
                onChanged: (v) => setState(() => _studyTime = v),
                primary: primary, textPrimary: textPrimary, textSub: textSub,
                fieldFill: fieldFill, borderDef: borderDef,
              ),
              const SizedBox(height: 12),

              _RequiredLabel(
                label: 'Study Goal',
                show: _attempted && _goal == null,
                textSub: textSub,
              ),
              const SizedBox(height: 6),
              _GyanDropdown(
                value: _goal, hint: 'Study Goal',
                icon: Icons.flag_outlined, items: _goals,
                onChanged: (v) => setState(() => _goal = v),
                primary: primary, textPrimary: textPrimary, textSub: textSub,
                fieldFill: fieldFill, borderDef: borderDef,
              ),
              const SizedBox(height: 12),

              _RequiredLabel(
                label: 'Daily Study Target',
                show: _attempted && _dailyTarget == null,
                textSub: textSub,
              ),
              const SizedBox(height: 6),
              _GyanDropdown(
                value: _dailyTarget, hint: 'Daily Study Target',
                icon: Icons.timer_outlined,
                items: List.generate(
                    8, (i) => '${i + 1} ${i + 1 == 1 ? 'Hour' : 'Hours'}'),
                onChanged: (v) => setState(() => _dailyTarget = v),
                primary: primary, textPrimary: textPrimary, textSub: textSub,
                fieldFill: fieldFill, borderDef: borderDef,
              ),

              const SizedBox(height: 26),
              _hr(),
              const SizedBox(height: 26),

              // ── Subjects ───────────────────────────────────────────────
              _sectionLabel('Subjects'),
              const SizedBox(height: 16),
              _ChipGroup(
                label: 'Strong Subjects',
                selected: _strong, excluded: _weak,
                accent: const Color(0xFF2DC88A), subjects: _subjects,
                onTap: (s) => setState(() =>
                    _strong.contains(s) ? _strong.remove(s) : _strong.add(s)),
                textSub: textSub, borderDef: borderDef, fieldFill: fieldFill,
              ),
              const SizedBox(height: 20),
              _ChipGroup(
                label: 'Weak Subjects',
                selected: _weak, excluded: _strong,
                accent: const Color(0xFFEF5A55), subjects: _subjects,
                onTap: (s) => setState(() =>
                    _weak.contains(s) ? _weak.remove(s) : _weak.add(s)),
                textSub: textSub, borderDef: borderDef, fieldFill: fieldFill,
              ),

              const SizedBox(height: 34),
              _CtaButton(onPressed: _onGetStarted, primary: primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hr() => Divider(color: borderDef, height: 1, thickness: 1);

  Widget _sectionLabel(String text) => Center(
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w900,
            letterSpacing: 2.6, color: textPrimary, height: 1.0,
          ),
        ),
      );

  // ─── Validate & show preview sheet ────────────────────────────────────────
  void _onGetStarted() {
    setState(() => _attempted = true);
    final formValid = _formKey.currentState!.validate();
    final missing = <String>[];
    if (_grade == null)       missing.add('Grade / Education Level');
    if (_studyTime == null)   missing.add('Preferred Study Time');
    if (_goal == null)        missing.add('Study Goal');
    if (_dailyTarget == null) missing.add('Daily Study Target');

    if (!formValid || missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(missing.isNotEmpty
              ? 'Please fill: ${missing.join(', ')}'
              : 'Please fix the errors above'),
          backgroundColor: const Color(0xFFEF5A55),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PreviewSheet(
        grade: _grade,
        studyTime: _studyTime, goal: _goal,
        dailyTarget: _dailyTarget,
        strong: _strong, weak: _weak,
        onConfirm: _saveAndContinue,
        isDark: _isDark,
        primary: primary, card: card, textPrimary: textPrimary,
        textSub: textSub, borderDef: borderDef, fieldFill: fieldFill,
      ),
    );
  }

    // ─── Save profile then go to AuthScreen (login) ───────────────────────────
  Future<void> _saveAndContinue() async {
    Navigator.pop(context); // close the preview sheet

    final hoursStr = _dailyTarget?.split(' ').first ?? '1';
    final hours    = int.tryParse(hoursStr) ?? 1;

    if (mounted) {
      final prov = context.read<AppProvider>();
      await prov.updateUser(
        grade: _grade,
        dailyStudyGoalHours: hours,
        studyTime: _studyTime,
        studyGoal: _goal,
        strongSubjects: _strong.toList(),
        weakSubjects: _weak.toList(),
      );
      await _saveProfilePrefs();

      // ── Save to Firebase directly (user has a UID from registration) ──
      final uid = FirebaseService.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseService.instance.saveOnboardingProfile(
          uid: uid,
          userData: prov.user.toJson(),
        );
      }
    }

    if (!mounted) return;

    // Navigate to the login screen and show a reminder to verify their email.
    // Use pushReplacement so the back button doesn't return here.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );

    // Show the snackbar after the new route has mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            '✅ Profile saved! Please verify your email before logging in.',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      );
    });
  }

  Future<void> _saveProfilePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_studyTime',  _studyTime  ?? '');
    await prefs.setString('profile_goal',       _goal       ?? '');
    await prefs.setStringList('profile_strong', _strong.toList());
    await prefs.setStringList('profile_weak',   _weak.toList());
    await prefs.setBool('onboarding_complete',   true);
  }
}

// ─── Preview Bottom Sheet ─────────────────────────────────────────────────────
class _PreviewSheet extends StatelessWidget {
  final String? grade, studyTime, goal, dailyTarget;
  final Set<String> strong, weak;
  final VoidCallback onConfirm;
  final bool isDark;
  final Color primary, card, textPrimary, textSub, borderDef, fieldFill;

  const _PreviewSheet({
    required this.grade,
    required this.studyTime, required this.goal,
    required this.dailyTarget,
    required this.strong, required this.weak,
    required this.onConfirm,
    required this.isDark,
    required this.primary, required this.card, required this.textPrimary,
    required this.textSub, required this.borderDef, required this.fieldFill,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF18181F) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: borderDef,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(children: [
                Text('Review Your Profile',
                    style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800,
                      color: textPrimary,
                    )),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(Icons.close_rounded, size: 22, color: textSub),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
              child: Text(
                'Make sure everything looks right before continuing.',
                style: TextStyle(fontSize: 12.5, color: textSub),
              ),
            ),
            Divider(color: borderDef, height: 1),
            Expanded(
              child: ListView(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                children: [
                  _previewSection('Study Profile', [
                    _previewRow(Icons.school_outlined,    'Grade / Education Level', grade      ?? '—'),
                    _previewRow(Icons.schedule_outlined,  'Preferred Study Time',    studyTime  ?? '—'),
                    _previewRow(Icons.flag_outlined,      'Study Goal',              goal       ?? '—'),
                    _previewRow(Icons.timer_outlined,     'Daily Study Target',      dailyTarget ?? '—'),
                  ]),
                  const SizedBox(height: 20),
                  _previewSection('Subjects', [
                    _chipPreviewRow('Strong Subjects', strong, const Color(0xFF2DC88A)),
                    const SizedBox(height: 10),
                    _chipPreviewRow('Weak Subjects',   weak,   const Color(0xFFEF5A55)),
                  ]),
                  const SizedBox(height: 28),
                  _CtaButton(
                      label: 'Looks Good — Continue',
                      onPressed: onConfirm,
                      primary: primary),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Center(
                      child: Text('Go back and edit',
                          style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500,
                            color: textSub,
                          )),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewSection(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(),
            style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
              color: textSub.withOpacity(0.6),
            )),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: fieldFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderDef, width: 1),
          ),
          child: Column(children: rows),
        ),
      ],
    );
  }

  Widget _previewRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Icon(icon, size: 16, color: primary),
        const SizedBox(width: 12),
        Expanded(child: Text(label,
            style: TextStyle(fontSize: 13, color: textSub))),
        Text(value,
            style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: textPrimary,
            )),
      ]),
    );
  }

  Widget _chipPreviewRow(String label, Set<String> items, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(children: [
            Container(
                width: 7, height: 7,
                decoration:
                    BoxDecoration(color: accent, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600,
                  color: textSub,
                )),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: items.isEmpty
              ? Text('None selected',
                  style: TextStyle(
                      fontSize: 12.5, color: textSub.withOpacity(0.5)))
              : Wrap(
                  spacing: 6, runSpacing: 6,
                  children: items
                      .map((s) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: accent.withOpacity(0.4), width: 1),
                            ),
                            child: Text(s,
                                style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600,
                                  color: accent,
                                )),
                          ))
                      .toList(),
                ),
        ),
      ],
    );
  }
}

// ─── Required label ───────────────────────────────────────────────────────────
class _RequiredLabel extends StatelessWidget {
  final String label;
  final bool show;
  final Color textSub;
  const _RequiredLabel(
      {required this.label, required this.textSub, this.show = false});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(label,
          style: TextStyle(
            fontSize: 12.5, fontWeight: FontWeight.w600,
            color: textSub,
          )),
      const SizedBox(width: 4),
      AnimatedOpacity(
        opacity: show ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: const Text('* Required',
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: Color(0xFFEF5A55),
            )),
      ),
    ]);
  }
}

// ─── GyanDropdown ─────────────────────────────────────────────────────────────
class _GyanDropdown extends StatelessWidget {
  final String? value;
  final String hint;
  final IconData icon;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final Color primary, textPrimary, textSub, fieldFill, borderDef;

  const _GyanDropdown({
    required this.value, required this.hint,
    required this.icon, required this.items,
    required this.onChanged,
    required this.primary, required this.textPrimary, required this.textSub,
    required this.fieldFill, required this.borderDef,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: fieldFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderDef, width: 1),
      ),
      padding: const EdgeInsets.only(left: 14, right: 4),
      child: Row(children: [
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              hint: Row(children: [
                Icon(icon, size: 17, color: textSub),
                const SizedBox(width: 10),
                Text(hint,
                    style: TextStyle(fontSize: 13.5, color: textSub)),
              ]),
              isExpanded: true,
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  size: 26, color: textSub),
              dropdownColor: fieldFill,
              borderRadius: BorderRadius.circular(14),
              items: items
                  .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(e,
                            style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500,
                              color: textPrimary,
                            )),
                      ))
                  .toList(),
              // ✅ Fixed: .toList() chained directly, no stray comma
              selectedItemBuilder: (_) => items
                  .map((e) => Row(children: [
                        Icon(icon, size: 17, color: primary),
                        const SizedBox(width: 10),
                        Text(e,
                            style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600,
                              color: textPrimary,
                            )),
                      ]))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
        if (value != null)
          GestureDetector(
            onTap: () => onChanged(null),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.close_rounded, size: 22, color: textSub),
            ),
          ),
      ]),
    );
  }
}

// ─── ChipGroup ────────────────────────────────────────────────────────────────
class _ChipGroup extends StatelessWidget {
  final String label;
  final Set<String> selected;
  final Set<String> excluded;
  final Color accent;
  final List<String> subjects;
  final ValueChanged<String> onTap;
  final Color textSub, borderDef, fieldFill;

  const _ChipGroup({
    required this.label, required this.selected,
    required this.accent, required this.subjects,
    required this.onTap, this.excluded = const {},
    required this.textSub, required this.borderDef, required this.fieldFill,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
              width: 7, height: 7,
              decoration:
                  BoxDecoration(color: accent, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: textSub,
              )),
          if (selected.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('${selected.length}',
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: accent,
                  )),
            ),
          ],
        ]),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: subjects.map((s) {
            final on       = selected.contains(s);
            final disabled = excluded.contains(s);
            return GestureDetector(
              onTap: disabled ? null : () => onTap(s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                    horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                  color: disabled
                      ? borderDef.withOpacity(0.08)
                      : on
                          ? accent.withOpacity(0.14)
                          : fieldFill,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: disabled
                        ? borderDef.withOpacity(0.4)
                        : on
                            ? accent.withOpacity(0.55)
                            : borderDef,
                    width: on ? 1.5 : 1.0,
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(s,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight:
                            on ? FontWeight.w700 : FontWeight.w400,
                        color: disabled
                            ? textSub.withOpacity(0.35)
                            : on
                                ? accent
                                : textSub,
                        decoration: disabled
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        decorationColor: textSub.withOpacity(0.35),
                      )),
                  if (disabled) ...[
                    const SizedBox(width: 5),
                    Icon(Icons.block_rounded,
                        size: 11, color: textSub.withOpacity(0.35)),
                  ],
                ]),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ─── CTA Button ───────────────────────────────────────────────────────────────
class _CtaButton extends StatefulWidget {
  final VoidCallback onPressed;
  final String label;
  final Color primary;
  const _CtaButton({
    required this.onPressed,
    required this.primary,
    this.label = 'Get Started',
  });

  @override
  State<_CtaButton> createState() => _CtaButtonState();
}

class _CtaButtonState extends State<_CtaButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 90),
        lowerBound: 0,
        upperBound: 1);
    _scale = Tween<double>(begin: 1.0, end: 0.97)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeIn));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:   (_) => _c.forward(),
      onTapUp:     (_) { _c.reverse(); widget.onPressed(); },
      onTapCancel: ()  => _c.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: widget.primary,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Center(
            child: Text(widget.label,
                style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700,
                  color: Colors.white, letterSpacing: 0.2,
                )),
          ),
        ),
      ),
    );
  }
}