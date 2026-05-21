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
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen>
    with SingleTickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────────
  File? _image;
  bool _analyzing = false;
  AnalysisStage _stage = AnalysisStage.compressing;
  double _progress = 0.0;

  final _subjectCtrl   = TextEditingController();
  final _gradeCtrl     = TextEditingController();
  final _totalCtrl     = TextEditingController(text: '100');
  final _passingCtrl   = TextEditingController(text: '40');
  final _answerKeyCtrl = TextEditingController();
  final _formKey       = GlobalKey<FormState>();
  final _picker        = ImagePicker();
  final _service       = AnswerSheetService();

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
  }

  @override
  void dispose() {
    _thumbAnim.dispose();
    _subjectCtrl.dispose();
    _gradeCtrl.dispose();
    _totalCtrl.dispose();
    _passingCtrl.dispose();
    _answerKeyCtrl.dispose();
    super.dispose();
  }

  // ── Image selection ────────────────────────────────────────────────────────

  Future<void> _pick(ImageSource source) async {
    Navigator.pop(context);
    final picked = await _picker.pickImage(source: source, imageQuality: 95);
    if (picked == null) return;
    setState(() => _image = File(picked.path));
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
    if (_image == null) {
      _snack('Please select an answer sheet image first');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();

    final params = AnalysisParameters(
      subject:      _subjectCtrl.text.trim(),
      gradeLevel:   _gradeCtrl.text.trim().isEmpty ? 'General' : _gradeCtrl.text.trim(),
      totalMarks:   int.tryParse(_totalCtrl.text) ?? 100,
      passingMarks: int.tryParse(_passingCtrl.text) ?? 40,
      answerKey:    _answerKeyCtrl.text.trim().isEmpty ? null : _answerKeyCtrl.text.trim(),
    );

    setState(() {
      _analyzing = true;
      _progress  = 0;
      _stage     = AnalysisStage.compressing;
    });

    try {
      final result = await _service.analyzeAnswerSheet(
        _image!,
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
            appBar: AppBar(
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
                    _ImagePickerCard(
                      image: _image,
                      thumbScale: _thumbScale,
                      onTap: () => _showPickerSheet(t),
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
                        child: _Field(
                          controller: _gradeCtrl,
                          label: 'Grade / Level',
                          hint: 'e.g. Grade 10',
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
                    const SizedBox(height: 12),

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

class _ImagePickerCard extends StatelessWidget {
  final File? image;
  final Animation<double> thumbScale;
  final VoidCallback onTap;
  final dynamic t;

  const _ImagePickerCard({
    required this.image,
    required this.thumbScale,
    required this.onTap,
    required this.t,
  });

  static const _accent = Color(0xFF5865F2);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
              color: image != null ? _accent : t.cardBorder,
              width: 1.5,
            ),
            boxShadow: t.widgetShadow,
          ),
          child: image == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.upload_file_rounded, size: 48, color: _accent),
                    const SizedBox(height: 12),
                    Text('Tap to upload answer sheet',
                        style: GoogleFonts.inder(
                            color: t.textMuted,
                            fontSize: 15,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text('Camera or gallery',
                        style: GoogleFonts.inder(color: t.textMuted, fontSize: 12)),
                  ],
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(image!, fit: BoxFit.cover),
                      Positioned(
                        bottom: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.65),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_rounded, size: 13, color: Colors.white),
                              SizedBox(width: 4),
                              Text('Change',
                                  style: TextStyle(color: Colors.white, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
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