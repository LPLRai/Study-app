import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'main_screen.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
class _T {
  // Brand
  static const primary = Color(0xFF5B5BD6);

  // Dark mode
  static const dBg         = Color(0xFF121318);
  static const dCard        = Color(0xFF18181F);
  static const dFieldFill   = Color(0xFF232329);
  static const dTextPrimary = Colors.white;
  static final dTextSub     = Colors.white.withOpacity(0.70);
  static final dBorderDef   = Colors.white.withOpacity(0.12);
  static final dShadow      = Colors.black.withOpacity(0.35);

  // Light mode
  static const lBg          = Color(0xFFF5F2F7);
  static const lCard         = Colors.white;
  static const lFieldFill    = Color(0xFFF2F0F7);
  static const lTextPrimary  = Color(0xFF1A1A22);
  static const lTextSub      = Color(0xFF6E6E78);
  static final lBorderDef    = const Color(0xFF1A1A22).withOpacity(0.12);
  static final lShadow       = Colors.black.withOpacity(0.08);
}

// ─── GetStartedPage ───────────────────────────────────────────────────────────
class GetStartedPage extends StatefulWidget {
  final bool isDark;
  final VoidCallback onToggle;
  const GetStartedPage({
    super.key,
    required this.isDark,
    required this.onToggle,
  });

  @override
  State<GetStartedPage> createState() => _GetStartedPageState();
}

class _GetStartedPageState extends State<GetStartedPage>
    with SingleTickerProviderStateMixin {

  final _formKey       = GlobalKey<FormState>();
  final _scrollCtrl    = ScrollController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl  = TextEditingController();

  String? _grade;
  String? _studyTime;
  String? _goal;
  String? _dailyTarget;
  final Set<String> _strong = {};
  final Set<String> _weak   = {};

  late final AnimationController _entryCtrl;
  late final Animation<double>    _fade;
  late final Animation<Offset>    _slide;

  // ─── Options ─────────────────────────────────────────────────────────────
  static const _grades = [
    '6th Grade', '7th Grade', '8th Grade', '9th Grade', '10th Grade',
    '+2 Science', '+2 Management', 'Bachelor', 'Masters',
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
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ─── Token helpers ────────────────────────────────────────────────────────
  bool   get d         => widget.isDark;
  Color  get _bg        => d ? _T.dBg         : _T.lBg;
  Color  get _card      => d ? _T.dCard        : _T.lCard;
  Color  get _fill      => d ? _T.dFieldFill   : _T.lFieldFill;
  Color  get _border    => d ? _T.dBorderDef   : _T.lBorderDef;
  Color  get _txtPri    => d ? _T.dTextPrimary : _T.lTextPrimary;
  Color  get _txtSub    => d ? _T.dTextSub     : _T.lTextSub;
  Color  get _shadow    => d ? _T.dShadow      : _T.lShadow;

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: SafeArea(
            child: CustomScrollView(
              controller: _scrollCtrl,
              physics: const BouncingScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 44)),
                SliverToBoxAdapter(child: _logoPlaceholder()),
                SliverToBoxAdapter(child: _mainCard()),
                SliverToBoxAdapter(child: _toggleRow()),
                const SliverToBoxAdapter(child: SizedBox(height: 48)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Logo area ────────────────────────────────────────────────────────────
  // To add your logo, replace the SizedBox below with:
  //
  //   Image.asset(
  //     'assets/images/gyan_logo.png',
  //     height: 80,
  //     color: widget.isDark ? Colors.white : const Color(0xFF5B5BD6),
  //     colorBlendMode: BlendMode.srcIn,
  //   )
  //
  Widget _logoPlaceholder() {
    return const SizedBox(height: 80); // ← swap this with Image.asset(...)
  }

  // ─── Main card ────────────────────────────────────────────────────────────
  Widget _mainCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _border, width: 1),
          boxShadow: [
            BoxShadow(
              color: _shadow,
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(22, 32, 22, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Page heading ─────────────────────────────────────────
              Center(
                child: Column(children: [
                  Text(
                    'Welcome to Gyan',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: _txtPri,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Let's personalize your study experience",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.55,
                      color: _txtSub,
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 30),
              _hr(),
              const SizedBox(height: 26),

              // ── Personal Info ─────────────────────────────────────────
              _sectionLabel('Personal Info'),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: _GyanField(
                    ctrl: _firstNameCtrl,
                    label: 'First Name',
                    labelColor: _txtSub.withOpacity(0.6),
                    labelFontSize: 14.5,
                    icon: Icons.person_outline_rounded,
                    fill: _fill, border: _border,
                    txtPri: _txtPri, txtSub: _txtSub,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _GyanField(
                    ctrl: _lastNameCtrl,
                    label: 'Last Name',
                    labelColor: _txtSub.withOpacity(0.6),
                    labelFontSize: 14.5,
                    icon: Icons.badge_outlined,
                    fill: _fill, border: _border,
                    txtPri: _txtPri, txtSub: _txtSub,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
              ]),

              const SizedBox(height: 26),
              _hr(),
              const SizedBox(height: 26),

              // ── Study Profile ─────────────────────────────────────────
              _sectionLabel('Study Profile'),
              const SizedBox(height: 14),
              _GyanDropdown(
                value: _grade,
                hint: 'Grade / Education Level',
                icon: Icons.school_outlined,
                items: _grades,
                fill: _fill, border: _border,
                txtPri: _txtPri, txtSub: _txtSub,
                onChanged: (v) => setState(() => _grade = v),
              ),
              const SizedBox(height: 12),
              _GyanDropdown(
                value: _studyTime,
                hint: 'Preferred Study Time',
                icon: Icons.schedule_outlined,
                items: _times,
                fill: _fill, border: _border,
                txtPri: _txtPri, txtSub: _txtSub,
                onChanged: (v) => setState(() => _studyTime = v),
              ),
              const SizedBox(height: 12),
              _GyanDropdown(
                value: _goal,
                hint: 'Study Goal',
                icon: Icons.flag_outlined,
                items: _goals,
                fill: _fill, border: _border,
                txtPri: _txtPri, txtSub: _txtSub,
                onChanged: (v) => setState(() => _goal = v),
              ),
              const SizedBox(height: 12),
              _GyanDropdown(
                value: _dailyTarget,
                hint: 'Daily Study Target',
                icon: Icons.timer_outlined,
                items: List.generate(8, (i) => '${i + 1} ${i + 1 == 1 ? 'Hour' : 'Hours'}'),
                fill: _fill, border: _border,
                txtPri: _txtPri, txtSub: _txtSub,
                onChanged: (v) => setState(() => _dailyTarget = v),
              ),

              const SizedBox(height: 26),
              _hr(),
              const SizedBox(height: 26),

              // ── Subjects ──────────────────────────────────────────────
              _sectionLabel('Subjects'),
              const SizedBox(height: 16),
              _ChipGroup(
                label: 'Strong Subjects',
                selected: _strong,
                accent: const Color(0xFF2DC88A),
                subjects: _subjects,
                fill: _fill, border: _border, txtSub: _txtSub,
                onTap: (s) => setState(() =>
                    _strong.contains(s) ? _strong.remove(s) : _strong.add(s)),
              ),
              const SizedBox(height: 20),
              _ChipGroup(
                label: 'Weak Subjects',
                selected: _weak,
                accent: const Color(0xFFEF5A55),
                subjects: _subjects,
                fill: _fill, border: _border, txtSub: _txtSub,
                onTap: (s) => setState(() =>
                    _weak.contains(s) ? _weak.remove(s) : _weak.add(s)),
              ),

              const SizedBox(height: 34),

              // ── CTA ────────────────────────────────────────────────────
              _CtaButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MainScreen(),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Theme toggle row ─────────────────────────────────────────────────────
  Widget _toggleRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onToggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 44,
              height: 25,
              decoration: BoxDecoration(
                color: d ? _T.primary : const Color(0xFFCCCCDD),
                borderRadius: BorderRadius.circular(13),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                alignment:
                    d ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.all(3),
                  width: 19, height: 19,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            d ? 'Dark Mode' : 'Light Mode',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _txtSub,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Shared widgets ───────────────────────────────────────────────────────
  Widget _hr() => Divider(color: _border, height: 1, thickness: 1);

  Widget _sectionLabel(String text) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.8,
          color: _txtSub.withOpacity(0.6),
        ),
      );
}

// ─── GyanField ────────────────────────────────────────────────────────────────
class _GyanField extends StatefulWidget {
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final Color fill, border, txtPri, txtSub;
  final Color? labelColor;
  final double labelFontSize;

  const _GyanField({
    required this.ctrl,
    required this.label,
    required this.icon,
    required this.fill,
    required this.border,
    required this.txtPri,
    required this.txtSub,
    this.labelColor,
    this.labelFontSize = 13.0,
    this.keyboardType,
    this.validator,
  });

  @override
  State<_GyanField> createState() => _GyanFieldState();
}

class _GyanFieldState extends State<_GyanField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final activeBorder = _focused ? _T.primary : widget.border;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: widget.fill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: activeBorder,
          width: _focused ? 1.5 : 1.0,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: _T.primary.withOpacity(0.14),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                )
              ]
            : [],
      ),
      child: Focus(
        onFocusChange: (f) => setState(() => _focused = f),
        child: TextFormField(
          controller: widget.ctrl,
          keyboardType: widget.keyboardType,
          validator: widget.validator,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: widget.txtPri,
          ),
          decoration: InputDecoration(
            labelText: widget.label,
            labelStyle: TextStyle(fontSize: widget.labelFontSize, color: widget.labelColor ?? widget.txtSub),
            floatingLabelStyle:
                const TextStyle(fontSize: 12, color: _T.primary),
            prefixIcon: Icon(
              widget.icon,
              size: 17,
              color: _focused ? _T.primary : widget.txtSub,
            ),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            errorStyle: const TextStyle(fontSize: 11),
          ),
        ),
      ),
    );
  }
}

// ─── GyanDropdown ─────────────────────────────────────────────────────────────
class _GyanDropdown extends StatelessWidget {
  final String? value;
  final String hint;
  final IconData icon;
  final List<String> items;
  final Color fill, border, txtPri, txtSub;
  final ValueChanged<String?> onChanged;

  const _GyanDropdown({
    required this.value,
    required this.hint,
    required this.icon,
    required this.items,
    required this.fill,
    required this.border,
    required this.txtPri,
    required this.txtSub,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1),
      ),
      padding: const EdgeInsets.only(left: 14, right: 4),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                hint: Row(children: [
                  Icon(icon, size: 17, color: txtSub),
                  const SizedBox(width: 10),
                  Text(hint, style: TextStyle(fontSize: 13.5, color: txtSub)),
                ]),
                isExpanded: true,
                icon: Icon(Icons.keyboard_arrow_down_rounded,
                    size: 26, color: txtSub),
                dropdownColor: isDark ? const Color(0xFF1E1E28) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                items: items
                    .map((e) => DropdownMenuItem(
                          value: e,
                          child: Text(e,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: txtPri,
                              )),
                        ))
                    .toList(),
                selectedItemBuilder: (_) => items
                    .map((e) => Row(children: [
                          Icon(icon, size: 17, color: _T.primary),
                          const SizedBox(width: 10),
                          Text(e,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: txtPri,
                              )),
                        ]))
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
          // Clear button — only visible when a value is selected
          if (value != null)
            GestureDetector(
              onTap: () => onChanged(null),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  Icons.close_rounded,
                  size: 22,
                  color: txtSub,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── ChipGroup ────────────────────────────────────────────────────────────────
class _ChipGroup extends StatelessWidget {
  final String label;
  final Set<String> selected;
  final Color accent;
  final List<String> subjects;
  final Color fill, border, txtSub;
  final ValueChanged<String> onTap;

  const _ChipGroup({
    required this.label,
    required this.selected,
    required this.accent,
    required this.subjects,
    required this.fill,
    required this.border,
    required this.txtSub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            width: 7, height: 7,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: txtSub,
              )),
          if (selected.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${selected.length}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: subjects.map((s) {
            final on = selected.contains(s);
            return GestureDetector(
              onTap: () => onTap(s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                    horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                  color: on ? accent.withOpacity(0.14) : fill,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: on ? accent.withOpacity(0.55) : border,
                    width: on ? 1.5 : 1.0,
                  ),
                ),
                child: Text(
                  s,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight:
                        on ? FontWeight.w700 : FontWeight.w400,
                    color: on ? accent : txtSub,
                  ),
                ),
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
  const _CtaButton({required this.onPressed});

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
        lowerBound: 0, upperBound: 1);
    _scale = Tween<double>(begin: 1.0, end: 0.97)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeIn));
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:  (_) => _c.forward(),
      onTapUp:    (_) { _c.reverse(); widget.onPressed(); },
      onTapCancel: () => _c.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: _T.primary,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Center(
            child: Text(
              'Get Started',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}