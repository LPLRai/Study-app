// ─────────────────────────────────────────────────────────────────────────────
// screens/quiz_screen.dart
// AI-powered Quiz Generator — Gemini + Groq
// Themed: uses AppProvider.appTheme for dark/light mode
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';

final _kGeminiKey = dotenv.env['GEMINI_KEY'] ?? '';
final _kGroqKey   = dotenv.env['GROQ_KEY'] ?? '';

// ─────────────────────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────────────────────
class QuizQuestion {
  final String question;
  final List<String> options;
  final int answerIndex;
  final String explanation;
  int? selectedIndex;

  QuizQuestion({
    required this.question,
    required this.options,
    required this.answerIndex,
    required this.explanation,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> j) => QuizQuestion(
        question:    j['question']    as String,
        options:     List<String>.from(j['options'] as List),
        answerIndex: (j['answer']     as num).toInt(),
        explanation: j['explanation'] as String? ?? '',
      );

  bool get isAnswered  => selectedIndex != null;
  bool get isCorrect   => selectedIndex == answerIndex;
}

// ─────────────────────────────────────────────────────────────────────────────
// Quiz service
// ─────────────────────────────────────────────────────────────────────────────
class _QuizService {
  static String _buildPrompt(
      String topic, String notes, String difficulty, int count) {
    final guide = {
      'easy':   'basic recall and definitions',
      'medium': 'applying and connecting concepts',
      'hard':   'analysis, inference, and synthesis',
    };
    final notesSection = notes.isNotEmpty
        ? '\n\nAdditional notes from the student:\n<notes>\n$notes\n</notes>'
        : '';
    return 'Generate $count ${difficulty.toUpperCase()} multiple-choice '
        'questions on the topic "$topic" for a Grade 10 student following '
        'the NEB (Nepal Education Board) curriculum.\n'
        'Difficulty style: ${guide[difficulty]}.\n'
        'Questions must strictly match the NEB Grade 10 syllabus depth, '
        'scope, and style.$notesSection\n\n'
        'Return ONLY a JSON array, no markdown:\n'
        '[{"question":"...","options":["A","B","C","D"],'
        '"answer":0,"explanation":"..."}]\n\n'
        'Rules: exactly 4 options, "answer" is the 0-based index of the '
        'correct option.';
  }

  static Future<List<QuizQuestion>> generateGemini(
      String topic, String notes, String difficulty, int count) async {
    final prompt = _buildPrompt(topic, notes, difficulty, count);
    final res = await http.post(
      Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/'
          'gemini-2.0-flash:generateContent?key=$_kGeminiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'generationConfig': {'responseMimeType': 'application/json'},
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
      }),
    );
    if (res.statusCode != 200) {
      final err = jsonDecode(res.body);
      throw Exception(err['error']?['message'] ?? 'Gemini error ${res.statusCode}');
    }
    final data  = jsonDecode(res.body);
    final text  = data['candidates'][0]['content']['parts'][0]['text'] as String;
    final clean = text.replaceAll('```json', '').replaceAll('```', '').trim();
    return (jsonDecode(clean) as List)
        .map((e) => QuizQuestion.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<QuizQuestion>> generateGroq(
      String topic, String notes, String difficulty, int count) async {
    final prompt = _buildPrompt(topic, notes, difficulty, count);
    final res = await http.post(
      Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $_kGroqKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'llama-3.3-70b-versatile',
        'messages': [
          {
            'role': 'system',
            'content': 'Return ONLY a valid JSON array. No markdown, no extra text.',
          },
          {'role': 'user', 'content': prompt},
        ],
        'response_format': {'type': 'json_object'},
        'max_tokens': 2000,
      }),
    );
    if (res.statusCode != 200) {
      final err = jsonDecode(res.body);
      throw Exception(err['error']?['message'] ?? 'Groq error ${res.statusCode}');
    }
    final data   = jsonDecode(res.body);
    final text   = data['choices'][0]['message']['content'] as String;
    final parsed = jsonDecode(text);
    final list   = parsed is List
        ? parsed
        : (parsed['questions'] ?? parsed[parsed.keys.first]) as List;
    return list
        .map((e) => QuizQuestion.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────
class QuizScreen extends StatefulWidget {
  /// When embedded inside the AI Features tab the screen's own AppBar is
  /// hidden, since the host provides a shared header + toggle.
  final bool embedded;

  const QuizScreen({super.key, this.embedded = false});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final _topicCtrl  = TextEditingController();
  final _notesCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();

  // Provider is fixed to Gemini now that the in-app selector has been removed.
  final String _provider = 'gemini';
  String _difficulty = 'easy';
  int    _qCount     = 5;

  bool   _loading   = false;
  String _error     = '';
  List<QuizQuestion> _questions = [];
  bool   _quizDone  = false;

  // Fixed accent colours — these never change with theme
  static const _blue   = Color(0xFF5865F2);
  static const _green  = Color(0xFF57F287);
  static const _red    = Color(0xFFED4245);

  @override
  void dispose() {
    _topicCtrl.dispose();
    _notesCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Color get _diffColor => switch (_difficulty) {
        'easy'   => const Color(0xFF57F287),
        'medium' => const Color(0xFFFAA61A),
        _        => const Color(0xFFED4245),
      };

  Future<void> _generate() async {
    final topic = _topicCtrl.text.trim();
    if (topic.isEmpty) {
      setState(() => _error = 'Please enter a topic.');
      return;
    }
    setState(() { _loading = true; _error = ''; _questions = []; _quizDone = false; });
    try {
      final qs = _provider == 'gemini'
          ? await _QuizService.generateGemini(
              topic, _notesCtrl.text.trim(), _difficulty, _qCount)
          : await _QuizService.generateGroq(
              topic, _notesCtrl.text.trim(), _difficulty, _qCount);
      setState(() { _questions = qs; _loading = false; });
      await Future.delayed(const Duration(milliseconds: 100));
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
      );
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  void _pick(int qIdx, int optIdx) {
    final q = _questions[qIdx];
    if (q.isAnswered) return;
    setState(() {
      q.selectedIndex = optIdx;
      if (_questions.every((q) => q.isAnswered)) _quizDone = true;
    });
  }

  int get _correct => _questions.where((q) => q.isCorrect).length;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(builder: (context, prov, _) {
      final t = prov.appTheme;

      return Scaffold(
        backgroundColor: t.background,
        appBar: widget.embedded
            ? null
            : AppBar(
                backgroundColor: t.background,
                elevation: 0,
                title: Text('Quiz Generator',
                    style: GoogleFonts.inder(
                        color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                iconTheme: IconThemeData(color: t.textPrimary),
              ),
        body: SingleChildScrollView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

            // ── Topic ────────────────────────────────────────────────────
            _SectionCard(
              title: 'Topic',
              t: t,
              child: _StyledField(
                controller: _topicCtrl,
                hint: 'e.g. Photosynthesis, Newton\'s Laws, World War II…',
                maxLines: 1,
                t: t,
              ),
            ),

            const SizedBox(height: 12),

            // ── Notes ────────────────────────────────────────────────────
            _SectionCard(
              title: 'Your Notes (optional)',
              t: t,
              child: _StyledField(
                controller: _notesCtrl,
                hint: 'Paste your notes here to personalise the quiz…',
                maxLines: 5,
                t: t,
              ),
            ),

            const SizedBox(height: 12),

            // ── Difficulty ───────────────────────────────────────────────
            _SectionCard(
              title: 'Difficulty',
              t: t,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  _DiffChip(label: 'Easy',   d: 'easy',   selected: _difficulty == 'easy',
                      onTap: () => setState(() => _difficulty = 'easy'),   t: t),
                  const SizedBox(width: 8),
                  _DiffChip(label: 'Medium', d: 'medium', selected: _difficulty == 'medium',
                      onTap: () => setState(() => _difficulty = 'medium'), t: t),
                  const SizedBox(width: 8),
                  _DiffChip(label: 'Hard',   d: 'hard',   selected: _difficulty == 'hard',
                      onTap: () => setState(() => _difficulty = 'hard'),   t: t),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  Text('Questions:', style: GoogleFonts.inder(color: t.textMuted, fontSize: 13)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor:   _blue,
                        inactiveTrackColor: t.inputBg,
                        thumbColor:         _blue,
                        overlayColor:       _blue.withOpacity(0.2),
                      ),
                      child: Slider(
                        value: _qCount.toDouble(),
                        min: 3, max: 10, divisions: 7,
                        onChanged: (v) => setState(() => _qCount = v.toInt()),
                      ),
                    ),
                  ),
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(8)),
                    alignment: Alignment.center,
                    child: Text('$_qCount',
                        style: GoogleFonts.inder(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ]),
            ),

            const SizedBox(height: 20),

            // ── Generate button ──────────────────────────────────────────
            ElevatedButton(
              onPressed: _loading ? null : _generate,
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                disabledBackgroundColor: _blue.withOpacity(0.4),
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _loading
                  ? const SizedBox(height: 20, width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2))
                  : Text('Generate Quiz',
                      style: GoogleFonts.inder(
                          color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            ),

            // ── Error ────────────────────────────────────────────────────
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _red.withOpacity(0.12),
                  border: Border.all(color: _red.withOpacity(0.4)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_error, style: GoogleFonts.inder(color: _red, fontSize: 13)),
              ),
            ],

            // ── Questions ────────────────────────────────────────────────
            if (_questions.isNotEmpty) ...[
              const SizedBox(height: 28),
              Row(children: [
                Text('Quiz',
                    style: GoogleFonts.inder(
                        color: t.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _diffColor.withOpacity(0.15),
                    border: Border.all(color: _diffColor.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _difficulty[0].toUpperCase() + _difficulty.substring(1),
                    style: GoogleFonts.inder(
                        color: _diffColor, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              ...List.generate(_questions.length, (i) => _QuestionCard(
                q: _questions[i],
                index: i,
                total: _questions.length,
                onPick: (optIdx) => _pick(i, optIdx),
                t: t,
              )),
            ],

            // ── Score ────────────────────────────────────────────────────
            if (_quizDone) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: t.widgetBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _green.withOpacity(0.3)),
                  boxShadow: t.widgetShadow,
                ),
                child: Column(children: [
                  Text(
                    '$_correct / ${_questions.length}',
                    style: GoogleFonts.inder(
                        color: _green, fontSize: 42, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text('correct answers',
                      style: GoogleFonts.inder(color: t.textMuted, fontSize: 14)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() { _questions = []; _quizDone = false; }),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _blue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    ),
                    child: Text('Try Again',
                        style: GoogleFonts.inder(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
              const SizedBox(height: 40),
            ],

          ]),
        ),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Question card widget
// ─────────────────────────────────────────────────────────────────────────────
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.q,
    required this.index,
    required this.total,
    required this.onPick,
    required this.t,
  });

  final QuizQuestion q;
  final int index, total;
  final void Function(int) onPick;
  final dynamic t;

  static const _blue  = Color(0xFF5865F2);
  static const _green = Color(0xFF57F287);
  static const _red   = Color(0xFFED4245);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.widgetBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.cardBorder),
        boxShadow: t.widgetShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Question ${index + 1} of $total',
            style: GoogleFonts.inder(color: t.textMuted, fontSize: 12)),
        const SizedBox(height: 8),
        Text(q.question,
            style: GoogleFonts.inder(
                color: t.textPrimary, fontSize: 15,
                fontWeight: FontWeight.w600, height: 1.5)),
        const SizedBox(height: 14),
        ...List.generate(q.options.length, (i) {
          final isSelected = q.selectedIndex == i;
          final isCorrect  = i == q.answerIndex;
          final answered   = q.isAnswered;

          Color borderColor = t.cardBorder;
          Color bgColor     = t.inputBg;
          Color textColor   = t.textPrimary;

          if (answered) {
            if (isCorrect) {
              borderColor = _green;
              bgColor     = _green.withOpacity(0.12);
              textColor   = _green;
            } else if (isSelected) {
              borderColor = _red;
              bgColor     = _red.withOpacity(0.12);
              textColor   = _red;
            }
          } else if (isSelected) {
            borderColor = _blue;
            bgColor     = _blue.withOpacity(0.12);
            textColor   = t.textPrimary;
          }

          return GestureDetector(
            onTap: () => onPick(i),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: bgColor,
                border: Border.all(color: borderColor),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(q.options[i],
                  style: GoogleFonts.inder(color: textColor, fontSize: 14, height: 1.5)),
            ),
          );
        }),

        if (q.isAnswered && q.explanation.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _blue.withOpacity(0.08),
              border: Border(left: BorderSide(color: _blue, width: 3)),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
            ),
            child: Text(q.explanation,
                style: GoogleFonts.inder(
                    color: t.isDark ? Colors.lightBlueAccent : const Color(0xFF3B5BDB),
                    fontSize: 13, height: 1.6)),
          ),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper widgets
// ─────────────────────────────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, required this.t});
  final String title;
  final Widget child;
  final dynamic t;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.widgetBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.cardBorder),
        boxShadow: t.widgetShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: GoogleFonts.inder(
                color: t.textMuted, fontSize: 12,
                fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

class _StyledField extends StatelessWidget {
  const _StyledField({
    required this.controller,
    required this.hint,
    required this.t,
    this.maxLines = 1,
  });
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final dynamic t;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      style: GoogleFonts.inder(color: t.textPrimary, fontSize: 14),
      cursorColor: const Color(0xFF5865F2),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inder(color: t.textMuted, fontSize: 13),
        filled: true,
        fillColor: t.inputBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: t.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: t.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF5865F2), width: 1.5),
        ),
      ),
    );
  }
}

class _DiffChip extends StatelessWidget {
  const _DiffChip({
    required this.label,
    required this.d,
    required this.selected,
    required this.onTap,
    required this.t,
  });
  final String label, d;
  final bool selected;
  final VoidCallback onTap;
  final dynamic t;

  Color get _color => switch (d) {
        'easy'   => const Color(0xFF57F287),
        'medium' => const Color(0xFFFAA61A),
        _        => const Color(0xFFED4245),
      };

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? _color.withOpacity(0.15) : t.inputBg,
            border: Border.all(color: selected ? _color : t.cardBorder),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: GoogleFonts.inder(
                  color: selected ? _color : t.textMuted,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
        ),
      ),
    );
  }
}