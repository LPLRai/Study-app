// lib/screens/upload_screen.dart
//
// Themed: uses AppProvider.appTheme for dark/light mode support.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/answer_sheet_service.dart';
import '../widgets/analyzing_overlay.dart';
import 'result_screen.dart';

class UploadScreen extends StatefulWidget {
  /// When embedded inside the AI Features tab the screen's own AppBar is
  /// hidden, since the host provides a shared header + toggle.
  final bool embedded;

  const UploadScreen({super.key, this.embedded = false});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen>
    with SingleTickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────────
  final List<File> _images = [];
  String? _selectedGrade;
  String _strictness = 'moderate';
  bool _analyzing = false;
  AnalysisStage _stage = AnalysisStage.compressing;
  double _progress = 0.0;

  final _subjectCtrl   = TextEditingController();
  final _totalCtrl     = TextEditingController(text: '100');
  final _passingCtrl   = TextEditingController(text: '40');
  final _answerKeyCtrl = TextEditingController();
  final _formKey       = GlobalKey<FormState>();
  final _picker        = ImagePicker();
  final _service       = AnswerSheetService();

  static const _grades = [
    '6th Grade', '7th Grade', '8th Grade', '9th Grade', '10th Grade',
    '11th Grade', '12th Grade', 'Bachelor',
  ];

  late final AnimationController _thumbAnim;
  late final Animation<double> _thumbScale;

  static const _accent = Color(0xFF5865F2);

  @override
  void initState() {
    super.initState();
    _thumbAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _thumbScale = Tween<double>(begin: 1, end: 0.96)
        .animate(CurvedAnimation(parent: _thumbAnim, curve: Curves.easeInOut));

    // Default the grade to the user's saved profile grade
    final userGrade = context.read<AppProvider>().user.grade;
    if (userGrade.isNotEmpty) {
      _selectedGrade = userGrade;
    }
  }

  @override
  void dispose() {
    _thumbAnim.dispose();
    _subjectCtrl.dispose();
    _totalCtrl.dispose();
    _passingCtrl.dispose();
    _answerKeyCtrl.dispose();
    super.dispose();
  }

  // ── Image selection ────────────────────────────────────────────────────────

  Future<void> _pick(ImageSource source) async {
    Navigator.pop(context);
    if (source == ImageSource.gallery) {
      final pickedList = await _picker.pickMultiImage(imageQuality: 95);
      if (pickedList.isNotEmpty) {
        setState(() {
          for (var picked in pickedList) {
            if (_images.length < 5) {
              _images.add(File(picked.path));
            }
          }
        });
      }
    } else {
      final picked = await _picker.pickImage(source: source, imageQuality: 95);
      if (picked == null) return;
      setState(() {
        if (_images.length < 5) {
          _images.add(File(picked.path));
        }
      });
    }
  }

  void _showPickerSheet(dynamic t) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SourceSheet(onPick: _pick, t: t),
    );
  }

  // ── Analysis ───────────────────────────────────────────────────────────────

  Future<void> _startAnalysis() async {
    if (_images.isEmpty) {
      _snack('Please select at least one answer sheet page first');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();

    final params = AnalysisParameters(
      subject:      _subjectCtrl.text.trim(),
      gradeLevel:   _selectedGrade ?? 'General',
      totalMarks:   int.tryParse(_totalCtrl.text) ?? 100,
      passingMarks: int.tryParse(_passingCtrl.text) ?? 40,
      answerKey:    _answerKeyCtrl.text.trim().isEmpty ? null : _answerKeyCtrl.text.trim(),
      strictness:   _strictness,
    );

    setState(() {
      _analyzing = true;
      _progress  = 0;
      _stage     = AnalysisStage.compressing;
    });

    try {
      final result = await _service.analyzeAnswerSheet(
        _images,
        params: params,
        onProgress: (stage, progress) {
          if (!mounted) return;
          setState(() { _stage = stage; _progress = progress; });
        },
      );
      if (!mounted) return;
      setState(() => _analyzing = false);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ResultScreen(result: result, params: params),
        ),
      );
    } on AnalysisException catch (e) {
      setState(() => _analyzing = false);
      _snack(e.message);
    } catch (e, stack) {
      setState(() => _analyzing = false);
      debugPrint('❌ ANALYSIS ERROR: $e');
      debugPrint('❌ STACK: $stack');
      _snack(e.toString());
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(builder: (context, prov, _) {
      final t = prov.appTheme;

      return Stack(
        children: [
          Scaffold(
            backgroundColor: t.background,
            appBar: widget.embedded
                ? null
                : AppBar(
                    backgroundColor: t.background,
                    elevation: 0,
                    title: Text(
                      'Answer Sheet Analyzer',
                      style: GoogleFonts.inder(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                    ),
                    centerTitle: false,
                    iconTheme: IconThemeData(color: t.textPrimary),
                  ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Image picker card ──────────────────────────────────
                    _MultiImagePickerCard(
                      images: _images,
                      thumbScale: _thumbScale,
                      onAddTap: () => _showPickerSheet(t),
                      onRemoveTap: (index) {
                        setState(() {
                          _images.removeAt(index);
                        });
                      },
                      t: t,
                    ),

                    const SizedBox(height: 28),

                    // ── Parameters ─────────────────────────────────────────
                    _SectionLabel('Evaluation Parameters', t: t),
                    const SizedBox(height: 14),
                    _Field(
                      controller: _subjectCtrl,
                      label: 'Subject *',
                      hint: 'e.g. Mathematics, Biology',
                      t: t,
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Subject is required' : null,
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: _DropdownField(
                          value: _selectedGrade,
                          label: 'Grade / Level',
                          hint: 'Select',
                          items: _grades,
                          onChanged: (v) {
                            setState(() {
                              _selectedGrade = v;
                            });
                          },
                          t: t,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          controller: _totalCtrl,
                          label: 'Total Marks',
                          hint: '100',
                          keyboardType: TextInputType.number,
                          t: t,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          controller: _passingCtrl,
                          label: 'Pass Marks',
                          hint: '40',
                          keyboardType: TextInputType.number,
                          t: t,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),

                    _SectionLabel('Grading Strictness', t: t),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _StrictnessChip(
                          label: 'Lenient',
                          value: 'lenient',
                          selected: _strictness == 'lenient',
                          onTap: () => setState(() => _strictness = 'lenient'),
                          t: t,
                        ),
                        const SizedBox(width: 8),
                        _StrictnessChip(
                          label: 'Moderate',
                          value: 'moderate',
                          selected: _strictness == 'moderate',
                          onTap: () => setState(() => _strictness = 'moderate'),
                          t: t,
                        ),
                        const SizedBox(width: 8),
                        _StrictnessChip(
                          label: 'Strict',
                          value: 'strict',
                          selected: _strictness == 'strict',
                          onTap: () => setState(() => _strictness = 'strict'),
                          t: t,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    _SectionLabel('Answer Key (optional)', t: t),
                    const SizedBox(height: 8),
                    _Field(
                      controller: _answerKeyCtrl,
                      label: 'Paste expected answers',
                      hint: 'e.g. Q1: Newton\'s first law states…',
                      maxLines: 4,
                      t: t,
                    ),

                    const SizedBox(height: 32),

                    // ── Analyze button ─────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _analyzing ? null : _startAnalysis,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: _accent.withOpacity(0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Analyze Answer Sheet',
                          style: GoogleFonts.inder(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Analyzing overlay ──────────────────────────────────────────────
          if (_analyzing)
            AnalyzingOverlay(stage: _stage, progress: _progress),
        ],
      );
    });
  }
}

// ─── Sub-widgets ─────────────────────────────────────────────────────────────

class _MultiImagePickerCard extends StatelessWidget {
  final List<File> images;
  final Animation<double> thumbScale;
  final VoidCallback onAddTap;
  final Function(int) onRemoveTap;
  final dynamic t;

  const _MultiImagePickerCard({
    required this.images,
    required this.thumbScale,
    required this.onAddTap,
    required this.onRemoveTap,
    required this.t,
  });

  static const _accent = Color(0xFF5865F2);

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return GestureDetector(
        onTap: onAddTap,
        child: AnimatedBuilder(
          animation: thumbScale,
          builder: (_, child) =>
              Transform.scale(scale: thumbScale.value, child: child),
          child: Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: t.widgetBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: t.cardBorder,
                width: 1.5,
              ),
              boxShadow: t.widgetShadow,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.upload_file_rounded, size: 48, color: _accent),
                const SizedBox(height: 12),
                Text('Tap to upload answer sheet pages',
                    style: GoogleFonts.inder(
                        color: t.textMuted,
                        fontSize: 15,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text('Up to 5 pages • Camera or gallery',
                    style: GoogleFonts.inder(color: t.textMuted, fontSize: 12)),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Answer Sheet Pages',
              style: GoogleFonts.inder(
                color: t.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${images.length} / 5',
                style: GoogleFonts.inder(
                  color: _accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: images.length + (images.length < 5 ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == images.length) {
                return GestureDetector(
                  onTap: onAddTap,
                  child: Container(
                    width: 120,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: t.widgetBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: t.cardBorder,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_rounded, color: _accent, size: 28),
                        const SizedBox(height: 8),
                        Text(
                          'Add Page',
                          style: GoogleFonts.inder(
                            color: t.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final image = images[index];
              return Container(
                width: 120,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: t.cardBorder, width: 1),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(image, fit: BoxFit.cover),
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.7),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: const [0.6, 1.0],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: Text(
                          'Page ${index + 1}',
                          style: GoogleFonts.inder(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: () => onRemoveTap(index),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withOpacity(0.65),
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final dynamic t;
  const _SectionLabel(this.text, {required this.t});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.inder(
        color: t.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? Function(String?)? validator;
  final dynamic t;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.t,
    this.keyboardType,
    this.maxLines = 1,
    this.validator,
  });

  static const _accent = Color(0xFF5865F2);

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      style: GoogleFonts.inder(color: t.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.inder(color: _accent, fontSize: 13),
        hintStyle: GoogleFonts.inder(color: t.textMuted, fontSize: 13),
        filled: true,
        fillColor: t.inputBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
      ),
    );
  }
}

class _SourceSheet extends StatelessWidget {
  final Future<void> Function(ImageSource) onPick;
  final dynamic t;
  const _SourceSheet({required this.onPick, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.widgetBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: t.textMuted.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text('Select Image Source',
              style: GoogleFonts.inder(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
          const SizedBox(height: 16),
          _SheetOption(
            icon: Icons.camera_alt_rounded,
            label: 'Take a Photo',
            onTap: () => onPick(ImageSource.camera),
            t: t,
          ),
          _SheetOption(
            icon: Icons.photo_library_rounded,
            label: 'Choose from Gallery',
            onTap: () => onPick(ImageSource.gallery),
            t: t,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  final String? value;
  final String label;
  final String hint;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final dynamic t;

  const _DropdownField({
    required this.value,
    required this.label,
    required this.hint,
    required this.items,
    required this.onChanged,
    required this.t,
  });

  static const _accent = Color(0xFF5865F2);

  @override
  Widget build(BuildContext context) {
    final dropdownItems = List<String>.from(items);
    if (value != null && value!.isNotEmpty && !dropdownItems.contains(value)) {
      dropdownItems.add(value!);
    }

    return DropdownButtonFormField<String>(
      value: value,
      items: dropdownItems
          .map((e) => DropdownMenuItem(
                value: e,
                child: Text(
                  e.replaceAll(' Grade', ''),
                  style: GoogleFonts.inder(fontSize: 12),
                ),
              ))
          .toList(),
      onChanged: onChanged,
      dropdownColor: t.inputBg,
      isExpanded: true,
      icon: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: t.textMuted),
      style: GoogleFonts.inder(color: t.textPrimary, fontSize: 12),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.inder(color: _accent, fontSize: 12),
        hintStyle: GoogleFonts.inder(color: t.textMuted, fontSize: 12),
        filled: true,
        fillColor: t.inputBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accent, width: 1.5),
        ),
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final dynamic t;
  const _SheetOption({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.t,
  });

  static const _accent = Color(0xFF5865F2);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: _accent, size: 22),
            ),
            const SizedBox(width: 16),
            Text(label,
                style: GoogleFonts.inder(
                    color: t.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _StrictnessChip extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;
  final dynamic t;

  const _StrictnessChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
    required this.t,
  });

  Color get _color => switch (value) {
        'lenient'  => const Color(0xFF57F287),
        'moderate' => const Color(0xFFFAA61A),
        _          => const Color(0xFFED4245),
      };

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? _color.withOpacity(0.15) : t.inputBg,
            border: Border.all(color: selected ? _color : t.cardBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inder(
              color: selected ? _color : t.textMuted,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}