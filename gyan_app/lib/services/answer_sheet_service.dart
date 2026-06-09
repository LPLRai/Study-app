// lib/services/answer_sheet_service.dart
//
// FULL PIPELINE (all hidden from the user — they just tap "Analyze"):
//
//   File  ──► [compress + JPG encode, isolate]
//         ──► [OCR Space API  →  raw text]
//         ──► [Groq LLM       →  AIFeedback JSON]
//         ──► [Firestore batch write]
//         ──► AnalysisResult
//
// NOTE: Firebase Storage upload is skipped for now.
//       imageUrl is stored as '' and can be wired up later.

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enums & simple data classes
// ─────────────────────────────────────────────────────────────────────────────

enum AnalysisStage {
  compressing,     // "Preparing…"
  extractingText,  // "Reading your answers…"
  analyzingWithAI, // "AI is evaluating…"
  saving,          // "Saving results…"
  done,
}

class AnalysisParameters {
  final String subject;
  final String gradeLevel;
  final int totalMarks;
  final int passingMarks;
  final String? answerKey;
  final String? rubric;
  final String strictness;

  const AnalysisParameters({
    required this.subject,
    required this.gradeLevel,
    required this.totalMarks,
    required this.passingMarks,
    this.answerKey,
    this.rubric,
    this.strictness = 'moderate',
  });
}

class AnalysisResult {
  final String docId;
  final AIFeedback feedback;
  final String imageUrl;
  const AnalysisResult({
    required this.docId,
    required this.feedback,
    required this.imageUrl,
  });
}

class AnalysisException implements Exception {
  final String message;
  const AnalysisException(this.message);
  @override
  String toString() => 'AnalysisException: $message';
}

// ─────────────────────────────────────────────────────────────────────────────
// AnswerSheetService
// ─────────────────────────────────────────────────────────────────────────────

class AnswerSheetService {
  static String get _ocrApiKey  => dotenv.env['OCR_API_KEY']    ?? '';
  static String get _groqApiKey => dotenv.env['GROQ_API_KEY_2'] ?? '';
  static const String _groqModel = 'llama-3.3-70b-versatile';

  final _db   = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ── Public entry point ────────────────────────────────────────────────────

  Future<AnalysisResult> analyzeAnswerSheet(
    List<File> imageFiles, {
    required AnalysisParameters params,
    void Function(AnalysisStage, double)? onProgress,
  }) async {
    if (imageFiles.isEmpty) {
      throw const AnalysisException('No images selected for analysis');
    }
    final sessionId = const Uuid().v4();
    final List<String> pageTexts = [];

    for (int i = 0; i < imageFiles.length; i++) {
      // Progress calculation for each image
      // Compression: starts at 0.05 + i * (0.20 / total)
      final double compressProgress = 0.05 + (i * 0.20 / imageFiles.length);
      onProgress?.call(AnalysisStage.compressing, compressProgress);
      final Uint8List imgBytes = await _compressToJpg(imageFiles[i]);

      // OCR: starts at 0.25 + i * (0.40 / total)
      final double ocrProgress = 0.25 + (i * 0.40 / imageFiles.length);
      onProgress?.call(AnalysisStage.extractingText, ocrProgress);
      final String ocrText = await _performOCR(imgBytes);

      pageTexts.add('--- Page ${i + 1} ---\n$ocrText');
    }

    onProgress?.call(AnalysisStage.analyzingWithAI, 0.70);
    final String combinedOcrText = pageTexts.join('\n\n');
    final AIFeedback feedback = await _getGroqFeedback(combinedOcrText, params);

    onProgress?.call(AnalysisStage.saving, 0.90);
    final String docId = await _saveToFirestore(
      sessionId:     sessionId,
      imageUrl:      '', // Storage skipped — wire up later
      extractedText: combinedOcrText,
      feedback:      feedback,
      params:        params,
      pageCount:     imageFiles.length,
    );

    onProgress?.call(AnalysisStage.done, 1.0);
    return AnalysisResult(docId: docId, feedback: feedback, imageUrl: '');
  }

  // ── Stage 1 – JPG compression (isolate, zero UI jank) ────────────────────

  Future<Uint8List> _compressToJpg(File file) async {
    final raw = await file.readAsBytes();
    return compute(_compressIsolate, raw);
  }

  static Uint8List _compressIsolate(Uint8List rawBytes) {
    img.Image? image = img.decodeImage(rawBytes);
    if (image == null) throw AnalysisException('Cannot decode image');

    const int maxSide = 1800;
    if (image.width > maxSide || image.height > maxSide) {
      image = image.width >= image.height
          ? img.copyResize(image,
              width: maxSide, interpolation: img.Interpolation.average)
          : img.copyResize(image,
              height: maxSide, interpolation: img.Interpolation.average);
    }

    image = img.adjustColor(image, contrast: 1.12, brightness: 1.03);
    return Uint8List.fromList(img.encodeJpg(image, quality: 90));
  }

  // ── Stage 2 – OCR Space API ──────────────────────────────────────────────

  Future<String> _performOCR(Uint8List imageBytes) async {
    final b64 = base64Encode(imageBytes);
    final res = await http.post(
      Uri.parse('https://api.ocr.space/parse/image'),
      headers: {'apikey': _ocrApiKey},
      body: {
        'base64Image':       'data:image/jpeg;base64,$b64',
        'language':          'eng',
        'isTable':           'true',
        'detectOrientation': 'true',
        'scale':             'true',
        'OCREngine':         '2',
        'filetype':          'jpg',
      },
    );

    if (res.statusCode != 200) {
      throw AnalysisException('OCR HTTP ${res.statusCode}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['IsErroredOnProcessing'] == true) {
      throw AnalysisException(
          (json['ErrorMessage'] as List?)?.join(', ') ?? 'OCR failed');
    }
    final results = json['ParsedResults'] as List? ?? [];
    if (results.isEmpty) return '[No text detected — try a clearer photo]';
    return results
        .map((r) => (r as Map)['ParsedText'] as String? ?? '')
        .join('\n')
        .trim();
  }

  // ── Stage 3 – Groq LLM ───────────────────────────────────────────────────

  Future<AIFeedback> _getGroqFeedback(
      String ocrText, AnalysisParameters params) async {
    const system = '''
You are an expert academic evaluator. Your job is to analyze OCR text from student answer sheets and provide highly accurate, actionable, and fair grading feedback.
Return ONLY a valid JSON object matching the schema the user provides.
No markdown fences. No prose outside JSON. No trailing commas.

OCR ERROR HANDLING & INTENT RECONSTRUCTION (CRITICAL):
- The input answer text is extracted via OCR and is highly prone to errors, missing characters, typos, run-together words, or weird spacing (e.g. "neutns secnd ly" instead of "Newton's second law", or "photsnthsis" instead of "photosynthesis").
- BEFORE grading, compare the student's answer with subject expectations or the provided Answer Key. Intelligently reconstruct what the student intended to write.
- NEVER penalize the student for spelling, grammar, punctuation, transcription, or OCR mistakes. Grade the conceptual understanding demonstrated. If they got the core concept right, award full marks (or near full marks depending on strictness).

GRADING STRICTNESS GUIDELINES:
1. "lenient": Focus entirely on conceptual correctness. Ignore spelling, syntax, incomplete wording, or bad formatting. Award full marks if the student has the correct core idea.
2. "moderate": Balanced grading. Expect main points and core details to be present, but allow synonyms and phrasing variations. Award partial marks generously.
3. "strict": Rigorous grading. Check for precise terms, steps, formulas, or definitions as expected in standard textbooks or the answer key. Deduct for vague details.

NO ARTIFICIAL MARKS CAPPING:
- Do NOT artificially restrict, cap, or limit the student's marks (e.g. capping at 60%). If the student answers a question correctly, award full marks (up to 100% of the question's value). Be fair and objective.

COMPLETENESS & QUESTION BREAKDOWN:
- Identify EVERY question in the answer sheet. Do not skip or combine questions.
- For each question in the breakdown:
  1. Reconstruct the clean, corrected text of the student's answer in 'detectedAnswer' (do not just copy-paste raw OCR errors).
  2. For 'maxScore', allocate marks so that the sum of 'maxScore' for all questions in the breakdown exactly equals the total marks provided.
  3. 'feedback' must be highly specific, actionable, and detail-oriented. Explain exactly what was correct, what key terms or formulas were missing or wrong, and how to improve. Avoid generic praise like "Well done".
''';

    final user = '''
### EXTRACTED ANSWER SHEET (OCR)
$ocrText

### EVALUATION PARAMETERS
Subject      : ${params.subject}
Grade/Level  : ${params.gradeLevel}
Total Marks  : ${params.totalMarks}
Passing Marks: ${params.passingMarks}
Strictness   : ${params.strictness.toUpperCase()}
${params.answerKey != null ? 'Answer Key:\n${params.answerKey}\n' : ''}${params.rubric != null ? 'Rubric:\n${params.rubric}\n' : ''}

### EVALUATION INSTRUCTIONS
1. Reconstruct the OCR text to understand the student's intended answers, resolving any character/spelling errors.
2. Identify EVERY question on the sheet. Ensure 'questionBreakdown' has exactly one entry per question, in order.
3. Distribute the total marks (${params.totalMarks}) among all questions. The sum of 'maxScore' across all questions MUST equal ${params.totalMarks}.
4. Grade each question according to the strictness level (${params.strictness.toUpperCase()}). Do not artificially cap the overall score or individual question scores.
5. In 'questionBreakdown', make sure 'detectedAnswer' is the clean, reconstructed student answer. 'feedback' must explain exactly what was correct/incorrect/missing and how to improve for that question specifically.
6. Provide a highly specific list of topics/concepts for revision in 'recommendedTopics'. Do NOT write broad subjects (e.g., do not write "Biology" or "Physics"). Instead, list micro-concepts (e.g., "Reactions of Mitochondria in Cellular Respiration", "Applying Newton's Second Law to Friction").
7. Ensure 'estimatedMarks' is equal to the sum of all 'scoreAwarded' values, and 'overallScore' equals (estimatedMarks / ${params.totalMarks}) * 100.

### RESPOND ONLY WITH THIS JSON SCHEMA
{
  "overallScore": <0-100 (percentage)>,
  "estimatedMarks": <estimated marks score based on performance out of ${params.totalMarks}>,
  "grade": "<A|B|C|D|F>",
  "passed": <true|false based on estimatedMarks vs passingMarks ${params.passingMarks}>,
  "summary": "<2-3 sentence overall assessment>",
  "strengths": ["<point>"],
  "improvements": ["<point>"],
  "questionBreakdown": [
    {
      "questionNumber": <int>,
      "detectedAnswer": "<student snippet>",
      "scoreAwarded": <number>,
      "maxScore": <number>,
      "feedback": "<specific detailed feedback>"
    }
  ],
  "skillsAssessment": {
    "comprehension": <0-10>,
    "accuracy": <0-10>,
    "presentation": <0-10>,
    "completeness": <0-10>
  },
  "recommendedTopics": ["<specific subtopic>"],
  "teacherNote": "<brief note>"
}
''';

    final res = await http.post(
      Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $_groqApiKey',
        'Content-Type':  'application/json',
      },
      body: jsonEncode({
        'model':       _groqModel,
        'temperature': 0.2,
        // Large budget so multi-question sheets are never truncated mid-JSON
        // (the old 3500 cap was cutting off the questionBreakdown array).
        'max_tokens':  8000,
        'response_format': {'type': 'json_object'},
        'messages': [
          {'role': 'system', 'content': system},
          {'role': 'user',   'content': user},
        ],
      }),
    );

    if (res.statusCode != 200) {
      throw AnalysisException('Groq ${res.statusCode}: ${res.body}');
    }

    final data  = jsonDecode(res.body) as Map<String, dynamic>;
    final raw   = (data['choices'] as List).first['message']['content'] as String;
    final clean = raw.replaceAll(RegExp(r'```json|```'), '').trim();

    try {
      return AIFeedback.fromJson(
        jsonDecode(clean) as Map<String, dynamic>,
        totalMarks: params.totalMarks,
        passingMarks: params.passingMarks,
      );
    } catch (e) {
      throw AnalysisException('Parse error: $e\n---\n$clean');
    }
  }

  // ── Stage 4 – Firestore ───────────────────────────────────────────────────

  Future<String> _saveToFirestore({
    required String sessionId,
    required String imageUrl,
    required String extractedText,
    required AIFeedback feedback,
    required AnalysisParameters params,
    int pageCount = 1,
  }) async {
    final uid   = _auth.currentUser?.uid ?? 'anonymous';
    final batch = _db.batch();

    batch.set(
      _db.collection('answer_sheet_analyses').doc(sessionId),
      {
        'sessionId':      sessionId,
        'uid':            uid,
        'createdAt':      FieldValue.serverTimestamp(),
        'imageUrl':       imageUrl,
        'subject':        params.subject,
        'gradeLevel':     params.gradeLevel,
        'totalMarks':     params.totalMarks,
        'passingMarks':   params.passingMarks,
        'strictness':     params.strictness,
        'extractedText':  extractedText,
        'feedback':       feedback.toJson(),
        'overallScore':   feedback.overallScore,
        'estimatedMarks': feedback.estimatedMarks,
        'grade':          feedback.grade,
        'passed':         feedback.passed,
        'pageCount':      pageCount,
      },
    );

    batch.set(
      _db.collection('users').doc(uid).collection('analyses').doc(sessionId),
      {
        'sessionId':    sessionId,
        'subject':      params.subject,
        'grade':        feedback.grade,
        'overallScore': feedback.overallScore,
        'passed':       feedback.passed,
        'createdAt':    FieldValue.serverTimestamp(),
        'pageCount':    pageCount,
        'strictness':   params.strictness,
      },
    );

    await batch.commit();
    return sessionId;
  }

  // ── Public helpers ────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getHistory({int limit = 20}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return [];
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('analyses')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
  }

  Future<Map<String, dynamic>?> getDetail(String sessionId) async {
    final doc =
        await _db.collection('answer_sheet_analyses').doc(sessionId).get();
    return doc.data();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

class AIFeedback {
  final double overallScore;
  final double estimatedMarks;
  final String grade;
  final bool passed;
  final String summary;
  final List<String> strengths;
  final List<String> improvements;
  final List<QuestionFeedback> questionBreakdown;
  final SkillsAssessment skillsAssessment;
  final List<String> recommendedTopics;
  final String teacherNote;

  const AIFeedback({
    required this.overallScore,
    required this.estimatedMarks,
    required this.grade,
    required this.passed,
    required this.summary,
    required this.strengths,
    required this.improvements,
    required this.questionBreakdown,
    required this.skillsAssessment,
    required this.recommendedTopics,
    required this.teacherNote,
  });

  factory AIFeedback.fromJson(Map<String, dynamic> j, {int? totalMarks, int? passingMarks}) {
    final rawBreakdown = (j['questionBreakdown'] as List? ?? [])
        .map((q) => QuestionFeedback.fromJson(q as Map<String, dynamic>))
        .toList();

    double calculatedAwarded = 0;
    double calculatedMax = 0;
    for (final q in rawBreakdown) {
      calculatedAwarded += q.scoreAwarded;
      calculatedMax += q.maxScore;
    }

    double overallScore = (j['overallScore'] as num?)?.toDouble() ?? 0.0;
    double estimatedMarks = (j['estimatedMarks'] as num?)?.toDouble() ?? 0.0;
    bool passed = j['passed'] as bool? ?? false;
    String grade = j['grade'] as String? ?? 'F';

    if (calculatedMax > 0) {
      overallScore = (calculatedAwarded / calculatedMax) * 100.0;
      if (totalMarks != null) {
        estimatedMarks = (calculatedAwarded / calculatedMax) * totalMarks;
      } else {
        estimatedMarks = calculatedAwarded;
      }
      if (passingMarks != null) {
        passed = estimatedMarks >= passingMarks;
      } else {
        passed = j['passed'] as bool? ?? (estimatedMarks >= 40.0);
      }

      if (overallScore >= 90.0) {
        grade = 'A';
      } else if (overallScore >= 80.0) {
        grade = 'B';
      } else if (overallScore >= 70.0) {
        grade = 'C';
      } else if (overallScore >= 60.0) {
        grade = 'D';
      } else {
        grade = 'F';
      }
    }

    return AIFeedback(
      overallScore:      overallScore,
      estimatedMarks:    estimatedMarks,
      grade:             grade,
      passed:            passed,
      summary:           j['summary'] as String? ?? '',
      strengths:         List<String>.from(j['strengths']    ?? []),
      improvements:      List<String>.from(j['improvements'] ?? []),
      questionBreakdown: rawBreakdown,
      skillsAssessment: SkillsAssessment.fromJson(
          j['skillsAssessment'] as Map<String, dynamic>? ?? {}),
      recommendedTopics: List<String>.from(j['recommendedTopics'] ?? []),
      teacherNote:       j['teacherNote'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'overallScore':      overallScore,
        'estimatedMarks':    estimatedMarks,
        'grade':             grade,
        'passed':            passed,
        'summary':           summary,
        'strengths':         strengths,
        'improvements':      improvements,
        'questionBreakdown': questionBreakdown.map((q) => q.toJson()).toList(),
        'skillsAssessment':  skillsAssessment.toJson(),
        'recommendedTopics': recommendedTopics,
        'teacherNote':       teacherNote,
      };
}

class QuestionFeedback {
  final int questionNumber;
  final String detectedAnswer;
  final double scoreAwarded;
  final double maxScore;
  final String feedback;

  const QuestionFeedback({
    required this.questionNumber,
    required this.detectedAnswer,
    required this.scoreAwarded,
    required this.maxScore,
    required this.feedback,
  });

  factory QuestionFeedback.fromJson(Map<String, dynamic> j) =>
      QuestionFeedback(
        questionNumber: j['questionNumber'] as int,
        detectedAnswer: j['detectedAnswer'] as String? ?? '',
        scoreAwarded:   (j['scoreAwarded'] as num).toDouble(),
        maxScore:       (j['maxScore']     as num).toDouble(),
        feedback:       j['feedback']      as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'questionNumber': questionNumber,
        'detectedAnswer': detectedAnswer,
        'scoreAwarded':   scoreAwarded,
        'maxScore':       maxScore,
        'feedback':       feedback,
      };
}

class SkillsAssessment {
  final double comprehension;
  final double accuracy;
  final double presentation;
  final double completeness;

  const SkillsAssessment({
    required this.comprehension,
    required this.accuracy,
    required this.presentation,
    required this.completeness,
  });

  factory SkillsAssessment.fromJson(Map<String, dynamic> j) =>
      SkillsAssessment(
        comprehension: (j['comprehension'] as num?)?.toDouble() ?? 0,
        accuracy:      (j['accuracy']      as num?)?.toDouble() ?? 0,
        presentation:  (j['presentation']  as num?)?.toDouble() ?? 0,
        completeness:  (j['completeness']  as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'comprehension': comprehension,
        'accuracy':      accuracy,
        'presentation':  presentation,
        'completeness':  completeness,
      };
}