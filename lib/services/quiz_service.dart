import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/gemini_config.dart';
import '../models/quiz_model.dart';
import '../utils/scoring_utils.dart';
import 'firestore_provider.dart';

/// Service managing quiz creation, generation, Firestore persistence, and streaming.
class QuizService {
  QuizService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? getAppFirestore();

  final FirebaseFirestore _firestore;

  /// Optional global or teacher-provided Gemini API key
  static String? globalGeminiApiKey;

  CollectionReference<Map<String, dynamic>> get _quizzesCollection =>
      _firestore.collection('quizzes');

  CollectionReference<Map<String, dynamic>> get _materialsCollection =>
      _firestore.collection('materials');

  /// Streams all quizzes for a specific class, optionally filtered by type ("actual" or "practice").
  Stream<List<QuizModel>> streamClassQuizzes(String classId, {String? type}) {
    Query<Map<String, dynamic>> query =
        _quizzesCollection.where('classId', isEqualTo: classId);

    if (type != null && type.isNotEmpty) {
      query = query.where('type', isEqualTo: type.toLowerCase());
    }

    return query.snapshots().map((snapshot) {
      final list = snapshot.docs
          .map((doc) => QuizModel.fromFirestore(doc))
          .toList();
      // Sort in-memory by createdAt descending
      list.sort((a, b) {
        if (a.createdAt == null && b.createdAt == null) return 0;
        if (a.createdAt == null) return 1;
        if (b.createdAt == null) return -1;
        return b.createdAt!.compareTo(a.createdAt!);
      });
      return list;
    });
  }

  /// Streams all quizzes created by a specific teacher.
  Stream<List<QuizModel>> streamTeacherQuizzes(String teacherId) {
    return _quizzesCollection
        .where('teacherId', isEqualTo: teacherId)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => QuizModel.fromFirestore(doc))
          .toList();
      list.sort((a, b) {
        if (a.createdAt == null && b.createdAt == null) return 0;
        if (a.createdAt == null) return 1;
        if (b.createdAt == null) return -1;
        return b.createdAt!.compareTo(a.createdAt!);
      });
      return list;
    });
  }

  /// Streams a single quiz by ID in real time.
  Stream<QuizModel?> streamQuiz(String quizId) {
    return _quizzesCollection.doc(quizId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return QuizModel.fromFirestore(doc);
    });
  }

  /// Fetches a single quiz by ID.
  Future<QuizModel?> getQuiz(String quizId) async {
    final doc = await _quizzesCollection.doc(quizId).get();
    if (!doc.exists) return null;
    return QuizModel.fromFirestore(doc);
  }

  /// Generates a quiz from a study material.
  /// First attempts Google Gemini AI (if an API key is available), then automatically
  /// falls back to Studexa's built-in concept engine if no API key is provided or offline.
  Future<QuizModel> generateQuiz({
    required String teacherId,
    required String classId,
    required String materialId,
    required bool isActual,
    required List<String> questionTypes,
    required int questionCount,
    String? sourceQuizId,
    String? geminiApiKey,
    String? preloadedExtractedText,
    String? preloadedFileName,
  }) async {
    if (teacherId.isEmpty) {
      throw ArgumentError('Teacher ID is required to generate a quiz.');
    }
    if (classId.isEmpty) {
      throw ArgumentError('A class must be selected to generate a quiz.');
    }
    if (materialId.isEmpty) {
      throw ArgumentError('A study material must be selected to generate a quiz.');
    }

    String extractedText = (preloadedExtractedText ?? '').trim();
    String fileName = (preloadedFileName ?? '').trim();

    if (extractedText.isEmpty) {
      // Retrieve material to access extractedText
      final matDoc = await _materialsCollection.doc(materialId).get();
      if (!matDoc.exists) {
        throw StateError('Study material not found.');
      }

      final matData = matDoc.data() ?? {};
      extractedText = (matData['extractedText'] as String? ?? '').trim();
      fileName = (matData['fileName'] as String? ?? 'Study Material');
    }

    if (extractedText.isEmpty) {
      throw StateError(
        'The selected study material has not completed text extraction or contains no readable text.',
      );
    }
    if (fileName.isEmpty) {
      fileName = 'Study Material';
    }

    final apiKey = geminiApiKey ??
        (GeminiConfig.apiKey.isNotEmpty ? GeminiConfig.apiKey : null) ??
        globalGeminiApiKey ??
        const String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

    List<QuizQuestion>? questions;
    String method = 'fallback';

    if (apiKey.trim().isNotEmpty) {
      try {
        questions = await callGeminiApi(
          apiKey: apiKey.trim(),
          extractedText: extractedText,
          questionTypes: questionTypes,
          questionCount: questionCount,
          isActual: isActual,
        );
        if (questions != null && questions.isNotEmpty) {
          method = 'gemini';
        }
      } catch (e) {
        debugPrint('Gemini AI synthesis failed, falling back: $e');
      }
    }

    // If Gemini was not used or did not return questions, use local concept generator
    questions ??= generateLocalFallbackQuestions(
      extractedText: extractedText,
      questionTypes: questionTypes,
      questionCount: questionCount,
      isActual: isActual,
    );

    // Validate questions, prune redundant/duplicate questions, and ensure targetCount
    questions = validateAndDeduplicateQuestions(
      questions,
      targetCount: questionCount,
      extractedText: extractedText,
      questionTypes: questionTypes,
      isActual: isActual,
    );

    final cleanName = fileName.replaceAll(RegExp(r'\.[^/.]+$'), '');
    final title = isActual ? '$cleanName - Exam' : '$cleanName - Practice Quiz';
    final totalPoints =
        questions.fold<double>(0.0, (acc, q) => acc + q.points);

    final quizDoc = _quizzesCollection.doc();
    final newQuiz = QuizModel(
      id: quizDoc.id,
      classId: classId,
      teacherId: teacherId,
      materialId: materialId,
      type: isActual ? 'actual' : 'practice',
      title: title,
      status: 'draft',
      generationMethod: method,
      sourceQuizId: sourceQuizId,
      questions: questions,
      totalPoints: totalPoints,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await quizDoc.set({
      ...newQuiz.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return newQuiz;
  }

  /// Attempts to generate questions via Google Gemini API (gemini-1.5-flash).
  /// For question counts > 15, chunks text and batches requests (10-12 per call)
  /// with distinct text slicing and anti-redundancy directives.
  static Future<List<QuizQuestion>?> callGeminiApi({
    required String apiKey,
    required String extractedText,
    required List<String> questionTypes,
    required int questionCount,
    required bool isActual,
    String? sourceQuizContext,
  }) async {
    if (apiKey.trim().isEmpty) return null;

    final targetCount = questionCount > 0 ? questionCount : 10;

    // If targetCount <= 15, a single request is optimal and fast
    if (targetCount <= 15) {
      return _callGeminiSingleBatch(
        apiKey: apiKey,
        extractedText: extractedText,
        questionTypes: questionTypes,
        batchCount: targetCount,
        isActual: isActual,
        sourceQuizContext: sourceQuizContext,
        batchIndex: 0,
        totalBatches: 1,
      );
    }

    // For 30 to 50 questions: partition into batches of 10 to 12 questions
    const batchSize = 10;
    final numBatches = (targetCount / batchSize).ceil();
    final allQuestions = <QuizQuestion>[];

    // Divide text into overlapping chunks so each batch assesses distinct sections
    final textLength = extractedText.length;
    final chunkSize = (textLength / numBatches).ceil();

    final batchFutures = <Future<List<QuizQuestion>?>>[];

    for (int b = 0; b < numBatches; b++) {
      final questionsForThisBatch = (b == numBatches - 1)
          ? (targetCount - (b * batchSize))
          : batchSize;

      int start = b * chunkSize;
      if (start > 0 && start > 200) start -= 200; // 200 char overlap
      int end = min(textLength, (b + 1) * chunkSize + 200);
      if (start >= end) start = 0;

      final chunkText =
          textLength > 1000 ? extractedText.substring(start, end) : extractedText;

      batchFutures.add(
        _callGeminiSingleBatch(
          apiKey: apiKey,
          extractedText: chunkText,
          questionTypes: questionTypes,
          batchCount: questionsForThisBatch,
          isActual: isActual,
          sourceQuizContext: sourceQuizContext,
          batchIndex: b,
          totalBatches: numBatches,
        ),
      );
    }

    try {
      final results = await Future.wait(batchFutures);
      for (final batchList in results) {
        if (batchList != null && batchList.isNotEmpty) {
          allQuestions.addAll(batchList);
        }
      }
    } catch (e) {
      debugPrint('Gemini batched generation error: $e');
    }

    return allQuestions.isNotEmpty ? allQuestions : null;
  }

  /// Handles a single batch HTTP request to Google Gemini API
  static Future<List<QuizQuestion>?> _callGeminiSingleBatch({
    required String apiKey,
    required String extractedText,
    required List<String> questionTypes,
    required int batchCount,
    required bool isActual,
    String? sourceQuizContext,
    required int batchIndex,
    required int totalBatches,
  }) async {
    final model = GeminiConfig.modelName.isNotEmpty
        ? GeminiConfig.modelName
        : 'gemini-1.5-flash';
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=${apiKey.trim()}',
    );

    final batchNote = totalBatches > 1
        ? 'BATCH ${batchIndex + 1} OF $totalBatches: Focus strictly on key concepts and definitions found in THIS section. Do NOT repeat questions from other sections.'
        : '';

    final systemInstruction = '''
You are an expert academic assessment designer for Studexa.
Your primary objective is to evaluate student mastery of CORE CONCEPTS, KEY DEFINITIONS, and FUNDAMENTAL MECHANISMS from the provided study material.

MANDATORY ASSESSMENT DIRECTIVES:
1. CORE CONCEPTS & DEFINITIONS FIRST:
   - Identify the central principles, key definitions, primary mechanisms, and functional relationships in the material.
   - Every question must assess a core concept that an instructor would legitimately evaluate on a comprehensive final exam.
2. STRICTLY FORBID IRRELEVANT, FILLER & NON-ACADEMIC CONTENT:
   - NEVER generate questions from, and completely ignore:
     a) Copyright notices, license text, and "all rights reserved" (e.g. "© 2024", "Creative Commons", "All rights reserved").
     b) Author, professor, or instructor details: names, academic titles, departments, affiliations, email addresses, phone numbers, and author bios.
     c) Document metadata: file names, slide numbers ("Slide 1", "Slide 10"), page numbers, dates of publication, semesters, edition numbers, and timestamps.
     d) Boilerplate phrases and lecture transitions: "Welcome to...", "In this lecture...", "Today we will discuss...", "As seen in the previous slide...", "Thank you for listening", "Any questions?", "Summary of today's class", "References", "Further Reading", "Acknowledgments".
     e) Administrative & course management content: course codes (e.g. "CS 101", "BIO 204"), prerequisites, grading policies, office hours, exam schedules, syllabus policies, submission guidelines, homework assignments, or platform links.
   - Questions and answers MUST test substantive academic concepts, theories, principles, processes, or core mechanisms only.
3. STRICTLY FORBID TABLE/COLUMN HEADERS & STRUCTURAL LABELS:
   - NEVER generate questions based on table or column headers, table row numbers, or data grid structural labels (e.g., 'Column A', 'Column B', 'Header 1', 'Header 2', 'Attribute', 'Value', 'No.', 'Field', 'Item', 'Category', 'Description', 'Remarks', 'Date', 'Type').
   - NEVER ask what a column, row, or header is named, what is listed under a specific column/header, or test the visual layout/structure of tables, charts, or diagrams.
   - When the study material includes tables, focus EXCLUSIVELY on the academic concepts, facts, mechanisms, and relationships described within the table cells — NOT the table structure itself.
   - NEVER produce answer choices or distractors that are column headers or structural labels (e.g. options like 'A. Column A', 'B. Header 1', 'C. Attribute', 'D. Value' are strictly forbidden).
4. PLAUSIBLE, CATEGORICALLY PARALLEL DISTRACTORS:
   - For multipleChoice questions, all 3 incorrect distractors MUST be plausible, academically meaningful terms in the EXACT SAME conceptual category/domain as the correct answer.
   - NEVER produce joke, nonsensical, or obviously absurd options.
5. FACTUAL GROUNDING:
   - Every question, answer option, and explanation must be 100% grounded in and verifiable against the provided text. Do not invent or assume unstated facts.
6. ANTI-REDUNDANCY:
   - Every question MUST test a DIFFERENT concept, definition, or mechanism.
   - NEVER generate duplicate questions, rephrased copies of another question, or questions with identical stems or answers.
7. QUESTION FORMAT CONSTRAINTS:
   - multipleChoice: Provide exactly 4 options labeled 'A.', 'B.', 'C.', 'D.'. correctAnswer must match the full option string (e.g. 'A. Mitochondria').
   - trueFalse: options must be exactly ['True', 'False']. correctAnswer must be either 'True' or 'False'. Negations must test a core concept or mechanism, not trivial phrasing tricks.
   - fillInTheBlank: The question stem MUST contain exactly one blank indicated by '_______' (7 underscores). The blank MUST target a single, specific, unambiguous key term (1 to 2 words maximum; such as a proper noun, technical term, or core domain vocabulary word, e.g. 'Mitochondria', 'Virtual Memory', 'Polymorphism'). The sentence must provide rich and complete context so that ONLY that single specific term makes logical sense. NEVER blank out generic verbs, adjectives, or filler words. The correctAnswer MUST be the exact word or 2-word term that fills the blank, with NO surrounding quotation marks, punctuation, or leading articles ('the', 'a', 'an') unless strictly part of a formal proper name.
   - identification: The question provides a clear, precise definition or functional description WITHOUT giving away the term in the prompt. correctAnswer is the exact term.
   - enumeration: The question asks to list 2 to 5 specific items, stages, components, or characteristics. enumerationAnswers must be an array of strings representing the expected items. correctAnswer must be a comma-separated list of those items.
${!isActual && sourceQuizContext != null && sourceQuizContext.isNotEmpty ? "8. DISTINCT PHRASING FOR PRACTICE: A reference Actual Quiz is provided. Do NOT copy question sentences verbatim. Test the SAME core concepts using scenario-based framing, inverse questions, or applied contexts." : ""}

$batchNote

STRICT JSON OUTPUT SCHEMA:
You MUST respond strictly with valid JSON conforming to this schema:
{
  "questions": [
    {
      "id": "b${batchIndex}_q_1",
      "type": "multipleChoice",
      "question": "Clear question testing a core concept",
      "options": ["A. ...", "B. ...", "C. ...", "D. ..."],
      "correctAnswer": "A. ...",
      "enumerationAnswers": [],
      "explanation": "Clear pedagogical explanation grounded in the text",
      "points": 1.0
    }
  ]
}
''';

    final userContent = '''
STUDY MATERIAL EXTRACTED TEXT:
${extractedText.length > 20000 ? extractedText.substring(0, 20000) : extractedText}

${(!isActual && sourceQuizContext != null && sourceQuizContext.isNotEmpty) ? "REFERENCE ACTUAL QUIZ CONTEXT:\n$sourceQuizContext\n" : ""}

Generate exactly $batchCount unique questions testing core concepts and definitions matching the specified types and strict JSON schema.
''';

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': '$systemInstruction\n\n$userContent'}
              ]
            }
          ],
          'generationConfig': {
            'responseMimeType': 'application/json',
            'temperature': 0.3,
          },
        }),
      ).timeout(const Duration(seconds: 35));

      if (response.statusCode != 200) {
        debugPrint(
            'Gemini API batch $batchIndex responded with status ${response.statusCode}: ${response.body}');
        return null;
      }

      final responseJson = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = responseJson['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) return null;

      final parts = candidates[0]['content']?['parts'] as List<dynamic>?;
      final textOutput =
          parts != null && parts.isNotEmpty ? parts[0]['text'] as String? : null;
      if (textOutput == null || textOutput.trim().isEmpty) return null;

      final parsed = jsonDecode(textOutput) as Map<String, dynamic>;
      final rawQuestions = parsed['questions'] as List<dynamic>?;
      if (rawQuestions == null || rawQuestions.isEmpty) return null;

      final questions = <QuizQuestion>[];
      for (int i = 0; i < rawQuestions.length; i++) {
        final qMap = rawQuestions[i] as Map<String, dynamic>;
        final typeStr = (qMap['type'] as String? ?? 'multipleChoice');
        final qType = QuizQuestionType.fromString(typeStr);

        final rawOptions = qMap['options'];
        final optionsList = (rawOptions is List)
            ? rawOptions.map((o) => o.toString()).toList()
            : <String>[];

        final rawEnum = qMap['enumerationAnswers'];
        final enumList = (rawEnum is List)
            ? rawEnum.map((e) => e.toString()).toList()
            : <String>[];

        var rawAnswer = (qMap['correctAnswer'] as String?) ?? '';
        if (qType == QuizQuestionType.fillInTheBlank ||
            qType == QuizQuestionType.identification) {
          rawAnswer = cleanFillInTheBlankAnswer(rawAnswer);
        }

        final qCandidate = QuizQuestion(
          id: 'b${batchIndex}_q_${i + 1}',
          type: qType,
          question: (qMap['question'] as String?) ?? 'Question ${i + 1}',
          options: optionsList,
          correctAnswer: rawAnswer,
          enumerationAnswers: enumList,
          explanation: (qMap['explanation'] as String?) ?? '',
          points: (qMap['points'] as num?)?.toDouble() ?? 1.0,
        );
        if (!isTableHeaderQuestion(qCandidate) && !isFillerOrBoilerplateQuestion(qCandidate)) {
          questions.add(qCandidate);
        }
      }

      return questions.isNotEmpty ? questions : null;
    } catch (e) {
      debugPrint('Gemini batch $batchIndex generation error: $e');
      return null;
    }
  }

  /// Cleans and sanitizes Fill-in-the-Blank and Identification expected answers
  /// ensuring they do not contain extraneous punctuation, surrounding quotes, or leading articles.
  static String cleanFillInTheBlankAnswer(String raw) {
    var cleaned = ScoringUtils.cleanExpectedAnswer(raw).trim();
    cleaned = cleaned.replaceAll(RegExp(r'^(the|a|an)\s+', caseSensitive: false), '').trim();
    bool changed = true;
    while (changed) {
      final prev = cleaned;
      cleaned = cleaned.replaceAll(RegExp(r'''^["']|["']$'''), '').trim();
      cleaned = cleaned.replaceAll(RegExp(r'[\.,;:!]$'), '').trim();
      changed = cleaned != prev;
    }
    return cleaned;
  }

  /// Detects whether a question tests table/column structural headers or has a
  /// structural label as its expected answer or options.
  static bool isTableHeaderQuestion(QuizQuestion q) {
    final prompt = q.question.toLowerCase().trim();
    final answer = ScoringUtils.normalizeText(
      ScoringUtils.cleanExpectedAnswer(q.correctAnswer),
    );

    // Prompt tests table/column structure
    final tablePromptPattern = RegExp(
      r'\b(in\s+(?:the\s+)?(?:table|column|row)|which\s+column|what\s+is\s+(?:the\s+)?(?:header|column|attribute)|listed\s+in\s+column|under\s+column|title\s+of\s+column)\b',
      caseSensitive: false,
    );
    if (tablePromptPattern.hasMatch(prompt)) return true;

    // Prompt asks about Column A, Header 1, etc.
    if (RegExp(r'\b(?:column|header|col|row)\s+[a-z0-9]+\b', caseSensitive: false).hasMatch(prompt)) {
      if (prompt.contains('what') || prompt.contains('which') || prompt.contains('identify')) {
        return true;
      }
    }

    // Answer is a structural header
    final structuralAnswerPattern = RegExp(
      r'^(?:column\s+[a-z0-9]+|header\s+[a-z0-9]+|row\s+[a-z0-9]+|col\s+[a-z0-9]+|attribute|attributes|value|values|field|fields|no\.?|num\.?|number|description|remarks|category|type)$',
      caseSensitive: false,
    );
    if (structuralAnswerPattern.hasMatch(answer)) return true;

    // Options contain purely structural labels (e.g. MCQ options: Column A, Column B...)
    if (q.type == QuizQuestionType.multipleChoice) {
      int structuralOptions = 0;
      for (final opt in q.options) {
        final cleanOpt = ScoringUtils.normalizeText(ScoringUtils.cleanExpectedAnswer(opt));
        if (structuralAnswerPattern.hasMatch(cleanOpt)) {
          structuralOptions++;
        }
      }
      if (structuralOptions >= 2) return true;
    }

    return false;
  }

  /// Detects whether a question tests trivial, filler, or non-academic content
  /// such as copyright notices, author/instructor info, slide/page metadata,
  /// lecture boilerplate ("Welcome to...", "Thank you..."), or administrative syllabus policies.
  static bool isFillerOrBoilerplateQuestion(QuizQuestion q) {
    final prompt = q.question.toLowerCase().trim();
    final answer = ScoringUtils.normalizeText(
      ScoringUtils.cleanExpectedAnswer(q.correctAnswer),
    );

    final fillerPromptPattern = RegExp(
      r'(?:\b(?:copyright|all\s+rights\s+reserved|creative\s+commons|licensed\s+under|authors?|written\s+by|who\s+is\s+the\s+author|who\s+is\s+the\s+instructor|who\s+is\s+the\s+professor|instructors?|emails?|office\s+hours|syllabus|grading\s+policy|course\s+code|prerequisite|homework\s+assignment|due\s+date|welcome\s+to|in\s+this\s+lecture|today\x27s\s+lecture|previous\s+slide|next\s+slide|thank\s+you\s+for\s+(?:listening|attending)|summary\s+of\s+today|slide\s+\d+|page\s+\d+|figure\s+\d+|table\s+\d+|chapter\s+\d+|\d+(?:st|nd|rd|th)?\s+edition|edition|references|acknowledgments?)\b|any\s+questions\?)',
      caseSensitive: false,
    );
    if (fillerPromptPattern.hasMatch(prompt)) return true;

    if (RegExp(r'\b(?:on slide|in chapter|on page|published in|publication date|file name)\b', caseSensitive: false).hasMatch(prompt)) {
      return true;
    }

    final fillerAnswerPattern = RegExp(
      r'^(?:all rights reserved|copyright|creative commons|welcome|thank you|any questions|dr\.\s+\w+|prof\.\s+\w+|professor|instructor|syllabus|office hours|slide\s+\d+|page\s+\d+|chapter\s+\d+|https?://\S+|www\.\S+|\S+@\S+)$',
      caseSensitive: false,
    );
    if (fillerAnswerPattern.hasMatch(answer)) return true;

    if (answer.contains('@') || answer.contains('http://') || answer.contains('https://') || answer.contains('www.')) {
      return true;
    }
    if (RegExp(r'^(?:19|20)\d\d$').hasMatch(answer) &&
        (prompt.contains('published') || prompt.contains('copyright') || prompt.contains('year'))) {
      return true;
    }

    return false;
  }

  /// Computes the word-level Jaccard similarity coefficient between two strings.
  /// Ignores case, punctuation, and short words (< 2 chars).
  /// Returns a value in [0.0, 1.0].
  static double tokenJaccardSimilarity(String a, String b) {
    Set<String> tokenize(String input) {
      return input
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
          .split(RegExp(r'\s+'))
          .map((w) => w.trim())
          .where((w) => w.length >= 2)
          .toSet();
    }

    final setA = tokenize(a);
    final setB = tokenize(b);

    if (setA.isEmpty && setB.isEmpty) return 1.0;
    if (setA.isEmpty || setB.isEmpty) return 0.0;

    final intersectionSize = setA.intersection(setB).length;
    final unionSize = setA.union(setB).length;

    if (unionSize == 0) return 0.0;
    return intersectionSize / unionSize;
  }

  /// Validates each question for structural integrity and removes duplicate or
  /// nearly identical questions (Jaccard similarity > 0.70 or same answer with similarity > 0.45).
  /// If deduplication leaves fewer than [targetCount], backfills with fresh questions
  /// from the fallback generator so the requested count is always fulfilled.
  static List<QuizQuestion> validateAndDeduplicateQuestions(
    List<QuizQuestion> questions, {
    int? targetCount,
    String? extractedText,
    List<String>? questionTypes,
    bool isActual = false,
  }) {
    if (questions.isEmpty) {
      if (targetCount != null &&
          targetCount > 0 &&
          extractedText != null &&
          extractedText.isNotEmpty) {
        return generateLocalFallbackQuestions(
          extractedText: extractedText,
          questionTypes: questionTypes ?? [],
          questionCount: targetCount,
          isActual: isActual,
        );
      }
      return [];
    }

    final accepted = <QuizQuestion>[];

    bool isSingleQuestionValid(QuizQuestion q) {
      if (q.question.trim().isEmpty || q.correctAnswer.trim().isEmpty) {
        return false;
      }
      if (isTableHeaderQuestion(q) || isFillerOrBoilerplateQuestion(q)) {
        return false;
      }
      switch (q.type) {
        case QuizQuestionType.multipleChoice:
          if (q.options.length < 2) return false;
          final cleanAns = ScoringUtils.normalizeText(
            ScoringUtils.cleanExpectedAnswer(q.correctAnswer),
          );
          final hasMatch = q.options.any((opt) {
            final cleanOpt = ScoringUtils.normalizeText(
              ScoringUtils.cleanExpectedAnswer(opt),
            );
            return cleanOpt == cleanAns || cleanOpt.contains(cleanAns);
          });
          if (!hasMatch) return false;
          break;
        case QuizQuestionType.trueFalse:
          final cleanTf = q.correctAnswer.trim().toLowerCase();
          if (cleanTf != 'true' && cleanTf != 'false') return false;
          break;
        case QuizQuestionType.fillInTheBlank:
          if (q.correctAnswer.trim().length < 2) return false;
          if (!q.question.contains('_______') && !q.question.contains('___')) return false;
          final fibWords = q.correctAnswer.trim().split(RegExp(r'\s+'));
          if (fibWords.length > 3) return false;
          break;
        case QuizQuestionType.identification:
          if (q.correctAnswer.trim().length < 2) return false;
          break;
        case QuizQuestionType.enumeration:
          if (q.enumerationAnswers.isEmpty && q.correctAnswer.trim().isEmpty) {
            return false;
          }
          break;
      }
      return true;
    }

    bool isDuplicate(QuizQuestion candidate, List<QuizQuestion> currentList) {
      final candNormPrompt = candidate.question.trim().toLowerCase();
      final candNormAnswer = ScoringUtils.normalizeText(
        ScoringUtils.cleanExpectedAnswer(candidate.correctAnswer),
      );

      for (final existing in currentList) {
        final existNormPrompt = existing.question.trim().toLowerCase();
        final existNormAnswer = ScoringUtils.normalizeText(
          ScoringUtils.cleanExpectedAnswer(existing.correctAnswer),
        );

        // Exact prompt match
        if (candNormPrompt == existNormPrompt) return true;

        // High token similarity
        final similarity =
            tokenJaccardSimilarity(candidate.question, existing.question);
        if (similarity > 0.70) return true;

        // Same answer with moderate token similarity
        if (candNormAnswer.isNotEmpty &&
            candNormAnswer == existNormAnswer &&
            similarity > 0.45) {
          return true;
        }

        // Exact same MCQ options
        if (candidate.type == QuizQuestionType.multipleChoice &&
            existing.type == QuizQuestionType.multipleChoice &&
            candidate.options.length == existing.options.length) {
          final candOptions = candidate.options
              .map((o) => ScoringUtils.normalizeText(
                  ScoringUtils.cleanExpectedAnswer(o)))
              .toSet();
          final existOptions = existing.options
              .map((o) => ScoringUtils.normalizeText(
                  ScoringUtils.cleanExpectedAnswer(o)))
              .toSet();
          if (candOptions.containsAll(existOptions)) {
            return true;
          }
        }
      }
      return false;
    }

    for (final q in questions) {
      if (!isSingleQuestionValid(q)) continue;
      if (isDuplicate(q, accepted)) continue;
      accepted.add(q);
    }

    // Backfill if below targetCount
    if (targetCount != null && targetCount > 0 && accepted.length < targetCount) {
      final textForFallback =
          (extractedText != null && extractedText.trim().isNotEmpty)
              ? extractedText
              : accepted
                  .map((q) => '${q.question} ${q.correctAnswer}')
                  .join(' ');

      if (textForFallback.trim().isNotEmpty) {
        final backfillCandidates = generateLocalFallbackQuestions(
          extractedText: textForFallback,
          questionTypes: questionTypes ?? [],
          questionCount: targetCount * 2 + 10,
          isActual: isActual,
        );

        for (final candidate in backfillCandidates) {
          if (accepted.length >= targetCount) break;
          if (!isSingleQuestionValid(candidate)) continue;
          if (isDuplicate(candidate, accepted)) continue;
          accepted.add(candidate);
        }
      }
    }

    // Cap at targetCount if exceeded
    final capped = (targetCount != null &&
            targetCount > 0 &&
            accepted.length > targetCount)
        ? accepted.sublist(0, targetCount)
        : accepted;

    // Renumber IDs sequentially
    return List<QuizQuestion>.generate(capped.length, (idx) {
      final orig = capped[idx];
      return QuizQuestion(
        id: 'q_${idx + 1}',
        type: orig.type,
        question: orig.question,
        options: orig.options,
        correctAnswer: orig.correctAnswer,
        enumerationAnswers: orig.enumerationAnswers,
        explanation: orig.explanation,
        points: orig.points,
      );
    });
  }

  /// Updates an existing quiz with teacher edits.
  Future<void> updateQuiz(QuizModel quiz) async {
    await _quizzesCollection.doc(quiz.id).update({
      'title': quiz.title,
      'questions': quiz.questions.map((q) => q.toMap()).toList(),
      'totalPoints':
          quiz.questions.fold<double>(0.0, (acc, q) => acc + q.points),
      'status': quiz.status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Validates a list of questions to ensure each question is complete and pedagogical.
  /// Returns null if all questions are valid, or a descriptive error string if invalid.
  static String? validateQuizQuestions(List<QuizQuestion> questions) {
    if (questions.isEmpty) {
      return 'Quiz must have at least one question.';
    }

    for (int i = 0; i < questions.length; i++) {
      final q = questions[i];
      final num = i + 1;

      if (q.question.trim().isEmpty) {
        return 'Question #$num prompt cannot be empty.';
      }
      if (q.correctAnswer.trim().isEmpty) {
        return 'Question #$num must have a correct answer.';
      }

      switch (q.type) {
        case QuizQuestionType.multipleChoice:
          if (q.options.length < 2) {
            return 'Question #$num (Multiple Choice) must have at least 2 options.';
          }
          final normAnswer = ScoringUtils.normalizeText(
            ScoringUtils.cleanExpectedAnswer(q.correctAnswer),
          );
          final hasMatchingOption = q.options.any((opt) {
            final normOpt = ScoringUtils.normalizeText(
              ScoringUtils.cleanExpectedAnswer(opt),
            );
            return normOpt == normAnswer || normOpt.contains(normAnswer);
          });
          if (!hasMatchingOption) {
            return 'Question #$num correct answer must match one of the options.';
          }
          break;

        case QuizQuestionType.trueFalse:
          final cleanAns = q.correctAnswer.trim().toLowerCase();
          if (cleanAns != 'true' && cleanAns != 'false') {
            return 'Question #$num (True/False) answer must be True or False.';
          }
          break;

        case QuizQuestionType.fillInTheBlank:
          if (q.correctAnswer.trim().length < 2) {
            return 'Question #$num missing blank answer term.';
          }
          break;

        case QuizQuestionType.identification:
          if (q.correctAnswer.trim().length < 2) {
            return 'Question #$num missing identification term.';
          }
          break;

        case QuizQuestionType.enumeration:
          if (q.enumerationAnswers.isEmpty && q.correctAnswer.trim().isEmpty) {
            return 'Question #$num (Enumeration) must have expected answers.';
          }
          break;
      }
    }
    return null;
  }

  /// Publishes a Practice Quiz, making it available to enrolled students.
  Future<void> publishQuiz(String quizId, {QuizModel? quiz}) async {
    if (quiz != null) {
      final validationError = validateQuizQuestions(quiz.questions);
      if (validationError != null) {
        throw StateError(validationError);
      }
    }
    await _quizzesCollection.doc(quizId).update({
      'status': 'published',
      'publishedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Finalizes an Actual Quiz as a reference exam.
  Future<void> finalizeQuiz(String quizId, {QuizModel? quiz}) async {
    if (quiz != null) {
      final validationError = validateQuizQuestions(quiz.questions);
      if (validationError != null) {
        throw StateError(validationError);
      }
    }
    await _quizzesCollection.doc(quizId).update({
      'status': 'finalized',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Deletes a quiz.
  Future<void> deleteQuiz(String quizId) async {
    await _quizzesCollection.doc(quizId).delete();
  }

  /// Deterministic local question generator that extracts high-accuracy questions
  /// across all 5 types targeting core concepts, definitions, and key mechanisms.
  /// Generates 10, 30, or 50 distinct questions with multi-angle templates and
  /// zero duplicate stems (verified with token Jaccard similarity <= 0.70).
  static List<QuizQuestion> generateLocalFallbackQuestions({
    required String extractedText,
    required List<String> questionTypes,
    required int questionCount,
    required bool isActual,
  }) {
    final parsedTypes = (questionTypes.isNotEmpty)
        ? questionTypes.map(QuizQuestionType.fromString).toList()
        : [
            QuizQuestionType.multipleChoice,
            QuizQuestionType.trueFalse,
            QuizQuestionType.fillInTheBlank,
            QuizQuestionType.identification,
            QuizQuestionType.enumeration,
          ];

    // 1. Sentence and clause splitting with academic sanitization
    final rawSentences = extractedText
        .split(RegExp(r'(?<=[.!?])\s+|\n+|;\s+'))
        .map((s) => s.trim().replaceAll(RegExp(r'\s+'), ' '))
        .where((s) => s.length >= 25 && s.length <= 280)
        .toList();

    // Filter out trivia, formatting artifacts, metadata, and lecture boilerplate
    final metadataRegex = RegExp(
      r'(?:\b(?:course|syllabus|page\s+\d+|figure\s+\d+|table\s+\d+|chapter\s+\d+|slide\s+\d+|\d+(?:st|nd|rd|th)?\s+edition|edition|copyright|all\s+rights\s+reserved|creative\s+commons|license|licensed\s+under|emails?|authors?|https?://\S+|www\.\S+|isbn|instructor|university|college|professor|lecture\s+\d+|homework|due\s+date|welcome\s+to|in\s+this\s+lecture|thank\s+you\s+for\s+(?:listening|attending)|summary\s+of\s+today|references|further\s+reading|acknowledgments?|office\s+hours|grading\s+policy|fall\s+\d{4}|spring\s+\d{4}|summer\s+\d{4}|column\s+[a-z0-9]+|header\s+[a-z0-9]+|row\s+[a-z0-9]+)\b|any\s+questions\?|attribute\s*\||no\.\s+name\b|[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})',
      caseSensitive: false,
    );

    final cleanSentences = rawSentences.where((s) {
      if (metadataRegex.hasMatch(s)) return false;
      if (RegExp(r'^(?:column|header|col|row)\s+[a-z0-9]+:?$', caseSensitive: false).hasMatch(s)) return false;
      if (s.endsWith('?')) return false;
      if (RegExp(r'^\d+\.?\s*$').hasMatch(s)) return false;
      return true;
    }).toList();

    const fallbackCoreSentences = [
      'Cellular respiration produces ATP by oxidizing glucose molecules in eukaryotic cells.',
      'Mitochondria are double-membraned organelles known as the powerhouse of the cell.',
      'Glycolysis occurs in the cytoplasm and breaks down glucose into two molecules of pyruvate.',
      'The citric acid cycle takes place inside the mitochondrial matrix.',
      'Adenosine triphosphate serves as the primary energy currency for cellular reactions.',
      'Photosynthesis converts light energy into chemical energy stored in carbohydrates.',
      'Enzymes are biological catalysts that lower activation energy without being consumed.',
      'Deoxyribonucleic acid stores genetic instructions within the cell nucleus.',
      'Ribosomes are macromolecular machines responsible for biological protein synthesis.',
      'The endoplasmic reticulum facilitates protein folding and transport in eukaryotic cells.',
      'Chloroplasts contain chlorophyll pigments that absorb sunlight during photosynthesis.',
      'The cell membrane maintains homeostasis through selective membrane permeability.',
      'Algorithms are step-by-step computational procedures designed to solve specific problems.',
      'Data structures organize and store information efficiently for algorithmic processing.',
      'Object-oriented programming utilizes encapsulation, inheritance, and polymorphism.',
      'Relational databases organize structured data into related tables with primary keys.',
    ];

    final sentencesPool = cleanSentences.length >= 8
        ? cleanSentences
        : [...cleanSentences, ...fallbackCoreSentences];

    // Structural blacklist to prevent column/table labels, metadata, and filler words from becoming candidate terms
    const structuralBlacklist = {
      'column', 'header', 'attribute', 'attributes', 'value', 'values',
      'field', 'fields', 'table', 'tables', 'row', 'rows', 'item', 'items',
      'category', 'categories', 'no', 'number', 'type', 'types',
      'description', 'remarks', 'date', 'col',
      'copyright', 'reserved', 'author', 'authors', 'professor', 'instructor', 'syllabus',
      'lecture', 'slide', 'page', 'chapter', 'university', 'college', 'homework',
      'summary', 'reference', 'references', 'license', 'acknowledgment',
      'acknowledgments', 'welcome', 'reading', 'hours', 'grading', 'policy',
      'edition', 'editions', 'email', 'emails', 'isbn',
    };

    // 2. Extract defined concepts and key academic terms
    final defRegex = RegExp(
      r'([A-Z][a-zA-Z0-9\s\-]{2,30})\s+(?:is defined as|refers to|is a|is an|are defined as|is known as|is called|serves as|functions as|consists of)\s+([^.!?]+)',
      caseSensitive: false,
    );
    final colonDefRegex = RegExp(
      r'^([A-Z][a-zA-Z0-9\s\-]{2,30}):\s+([A-Z][^.!?]+)',
    );

    final candidateTerms = <String>[];
    final conceptDefinitions = <String, String>{};

    for (final s in sentencesPool) {
      final m = defRegex.firstMatch(s);
      if (m != null) {
        final term = m.group(1)?.trim() ?? '';
        final def = m.group(2)?.trim() ?? '';
        if (term.length >= 3 &&
            def.length >= 8 &&
            !candidateTerms.contains(term) &&
            !structuralBlacklist.contains(term.toLowerCase()) &&
            !RegExp(r'^(?:column|header|col|row)\s+[a-z0-9]+$', caseSensitive: false).hasMatch(term)) {
          candidateTerms.add(term);
          conceptDefinitions[term] = def;
        }
      }
      final cm = colonDefRegex.firstMatch(s);
      if (cm != null) {
        final term = cm.group(1)?.trim() ?? '';
        final def = cm.group(2)?.trim() ?? '';
        if (term.length >= 3 &&
            def.length >= 8 &&
            !candidateTerms.contains(term) &&
            !structuralBlacklist.contains(term.toLowerCase()) &&
            !RegExp(r'^(?:column|header|col|row)\s+[a-z0-9]+$', caseSensitive: false).hasMatch(term)) {
          candidateTerms.add(term);
          conceptDefinitions[term] = def;
        }
      }
    }

    // Extract significant capitalized academic terms from sentences
    for (final s in sentencesPool) {
      final words = s.split(' ');
      for (int i = 0; i < words.length; i++) {
        final clean = words[i].replaceAll(RegExp(r'[^a-zA-Z]'), '');
        if (clean.length >= 4 &&
            words[i].startsWith(RegExp(r'[A-Z]')) &&
            !candidateTerms.contains(clean) &&
            !structuralBlacklist.contains(clean.toLowerCase()) &&
            !RegExp(r'^(?:column|header|col|row)\s+[a-z0-9]+$', caseSensitive: false).hasMatch(clean) &&
            !RegExp(r'^(These|Those|There|Their|Which|After|Before|Because|However|When|Where|While|Since|Both|Each|Every)$')
                .hasMatch(clean)) {
          candidateTerms.add(clean);
        }
      }
    }

    // Plausible academic domain terms for fallback distractors (ensuring domain parallelism, never "Concept 1")
    const academicDomainDistractors = [
      'Mitochondria',
      'Ribosome',
      'Chloroplast',
      'Nucleus',
      'Enzyme',
      'Glucose',
      'ATP',
      'Cytoplasm',
      'Endoplasmic Reticulum',
      'Golgi Apparatus',
      'Glycolysis',
      'Phosphorylation',
      'Algorithm',
      'Compiler',
      'Database',
      'Encryption',
      'Firewall',
      'Inheritance',
      'Kernel',
      'Polymorphism',
      'Recursion',
      'Protocol',
      'Stack',
      'Variable',
    ];

    for (final term in academicDomainDistractors) {
      if (!candidateTerms.contains(term)) {
        candidateTerms.add(term);
      }
    }

    // Stopwords for keyword filtering
    const stopwords = {
      'about', 'after', 'before', 'because', 'between', 'during',
      'however', 'through', 'under', 'which', 'where', 'while',
      'their', 'there', 'these', 'those', 'would', 'could', 'should',
      'other', 'being', 'having', 'within', 'called', 'known', 'defined',
    };

    List<String> getKeywordsForSentence(String s) {
      final words = <String>[];
      for (final t in candidateTerms) {
        if (s.toLowerCase().contains(t.toLowerCase())) {
          words.add(t);
        }
      }
      if (words.isEmpty) {
        final parts = s.split(' ');
        for (final w in parts) {
          final clean = w.replaceAll(RegExp(r'[^a-zA-Z]'), '');
          if (clean.length >= 5 &&
              !stopwords.contains(clean.toLowerCase()) &&
              !RegExp(r'^\d+$').hasMatch(clean)) {
            words.add(clean);
          }
        }
      }
      if (words.isEmpty) {
        words.add(candidateTerms.first);
      }
      return words;
    }

    // 3. Score sentences by pedagogical density
    final scoredSentences = sentencesPool.map((s) {
      double score = 5.0;
      if (defRegex.hasMatch(s) || colonDefRegex.hasMatch(s)) score += 10.0;
      if (RegExp(
              r'\b(produces|synthesizes|catalyzes|regulates|converts|generates|membrane|pathway|reaction|structure|process)\b',
              caseSensitive: false)
          .hasMatch(s)) {
        score += 4.0;
      }
      if (s.length >= 45 && s.length <= 180) score += 3.0;
      return MapEntry(s, score);
    }).toList();

    scoredSentences.sort((a, b) => b.value.compareTo(a.value));
    final rankedSentences = scoredSentences.map((e) => e.key).toList();

    final questions = <QuizQuestion>[];
    final targetCount = questionCount > 0 ? questionCount : 10;

    int attempts = 0;
    final maxAttempts = max(400, targetCount * 15);

    while (questions.length < targetCount && attempts < maxAttempts) {
      attempts++;
      final currentTypeIndex = questions.length % parsedTypes.length;
      final qType = parsedTypes[currentTypeIndex];
      final typeCount = questions.where((q) => q.type == qType).length;
      final offset = typeCount + (attempts - 1);
      final i = offset;
      final sentenceIndex = offset % rankedSentences.length;
      final round = offset ~/ rankedSentences.length;
      final angle = round % 5;
      final sentence = rankedSentences[sentenceIndex];

      final keywords = getKeywordsForSentence(sentence);
      final targetWord = keywords[(round + offset) % keywords.length];

      QuizQuestion? candidate;

      switch (qType) {
        case QuizQuestionType.multipleChoice:
          String displaySentence = sentence;
          if (sentence.toLowerCase().contains(targetWord.toLowerCase())) {
            displaySentence = sentence.replaceFirst(
              RegExp(RegExp.escape(targetWord), caseSensitive: false),
              '_______',
            );
          } else {
            displaySentence = '$sentence (_______)';
          }

          // Build distractors from candidate terms
          final distractorPool = candidateTerms
              .where((t) => t.toLowerCase() != targetWord.toLowerCase())
              .toSet()
              .toList();

          if (distractorPool.length < 3) {
            for (final fallback in academicDomainDistractors) {
              if (fallback.toLowerCase() != targetWord.toLowerCase() &&
                  !distractorPool.contains(fallback)) {
                distractorPool.add(fallback);
              }
            }
          }

          final distractors = <String>[];
          for (int d = 0; d < distractorPool.length && distractors.length < 3; d++) {
            final cand = distractorPool[(i + d * 3) % distractorPool.length];
            if (!distractors.contains(cand)) {
              distractors.add(cand);
            }
          }

          final allOptions = [targetWord, ...distractors]..shuffle(Random(i * 31 + 7));
          const letters = ['A', 'B', 'C', 'D'];
          final formattedOptions = List<String>.generate(
            allOptions.length,
            (idx) => '${letters[idx]}. ${allOptions[idx]}',
          );
          final correctIdx = allOptions.indexOf(targetWord);
          final correctAnswer = formattedOptions[correctIdx];

          String mcqPrompt;
          switch (angle) {
            case 0:
              mcqPrompt = isActual
                  ? 'Fill in the blank: $displaySentence'
                  : 'Practice Question: Based on the reading, complete the statement: "$displaySentence"';
              break;
            case 1:
              mcqPrompt = isActual
                  ? 'In the context of the study material, which term correctly completes:\n"$displaySentence"?'
                  : 'Concept Check: Which term belongs in the blank below?\n"$displaySentence"';
              break;
            case 2:
              mcqPrompt = isActual
                  ? 'Which of the following concepts is directly described in the statement:\n"$displaySentence"?'
                  : 'Review Question: Complete this fundamental principle:\n"$displaySentence"';
              break;
            case 3:
              mcqPrompt = isActual
                  ? 'Select the correct concept that fits the blank below:\n"$displaySentence"'
                  : 'Self-Assessment: Choose the term that accurately completes the statement:\n"$displaySentence"';
              break;
            default:
              mcqPrompt = isActual
                  ? 'Which term accurately matches this statement:\n"$displaySentence"?'
                  : 'Practice Question: Select the correct term:\n"$displaySentence"';
              break;
          }

          candidate = QuizQuestion(
            id: 'q_${questions.length + 1}',
            type: QuizQuestionType.multipleChoice,
            question: mcqPrompt,
            options: formattedOptions,
            correctAnswer: correctAnswer,
            explanation: 'The correct answer is $targetWord grounded in: "$sentence".',
            points: 1.0,
          );
          break;

        case QuizQuestionType.trueFalse:
          final isTrue = (i + round) % 2 == 0;
          String statement = sentence;
          if (!isTrue) {
            if (statement.contains(' is ')) {
              statement = statement.replaceFirst(' is ', ' is not ');
            } else if (statement.contains(' are ')) {
              statement = statement.replaceFirst(' are ', ' are not ');
            } else if (statement.contains(' can ')) {
              statement = statement.replaceFirst(' can ', ' cannot ');
            } else if (statement.contains(' produces ')) {
              statement = statement.replaceFirst(' produces ', ' does not produce ');
            } else if (statement.contains(' requires ')) {
              statement = statement.replaceFirst(' requires ', ' functions without ');
            } else if (statement.contains(' occurs ')) {
              statement = statement.replaceFirst(' occurs ', ' does not occur ');
            } else {
              statement = 'It is false that ${statement[0].toLowerCase()}${statement.substring(1)}';
            }
          }

          String tfPrompt;
          switch (angle) {
            case 0:
              tfPrompt = isActual
                  ? 'Determine whether the following statement is True or False:\n"$statement"'
                  : 'Concept Check: Is the following statement accurate?\n"$statement"';
              break;
            case 1:
              tfPrompt = isActual
                  ? 'Fact Check: Evaluate the validity of this statement from the reading:\n"$statement"'
                  : 'True or False: Consider the following assertion:\n"$statement"';
              break;
            case 2:
              tfPrompt = isActual
                  ? 'Assess the factual correctness of this statement based on the material:\n"$statement"'
                  : 'Quick Quiz: Is this statement True or False?\n"$statement"';
              break;
            case 3:
              tfPrompt = isActual
                  ? 'Statement Evaluation (True/False):\n"$statement"'
                  : 'Verify this fact from the text:\n"$statement"';
              break;
            default:
              tfPrompt = isActual
                  ? 'True or False: $statement'
                  : 'Review Check: True or False: "$statement"';
              break;
          }

          candidate = QuizQuestion(
            id: 'q_${questions.length + 1}',
            type: QuizQuestionType.trueFalse,
            question: tfPrompt,
            options: const ['True', 'False'],
            correctAnswer: isTrue ? 'True' : 'False',
            explanation: isTrue
                ? 'Verified directly from the material: "$sentence".'
                : 'False. The actual material states: "$sentence".',
            points: 1.0,
          );
          break;

        case QuizQuestionType.fillInTheBlank:
          String blankPrompt;
          if (sentence.toLowerCase().contains(targetWord.toLowerCase())) {
            blankPrompt = sentence.replaceFirst(
              RegExp(r'\b' + RegExp.escape(targetWord) + r'\b', caseSensitive: false),
              '_______',
            );
            if (!blankPrompt.contains('_______')) {
              blankPrompt = sentence.replaceFirst(
                RegExp(RegExp.escape(targetWord), caseSensitive: false),
                '_______',
              );
            }
          } else {
            blankPrompt = '$sentence (_______)';
          }

          String fibPrompt;
          switch (angle) {
            case 0:
              fibPrompt = isActual
                  ? 'Complete the statement: $blankPrompt'
                  : 'Fill in the missing term from the lesson: $blankPrompt';
              break;
            case 1:
              fibPrompt = isActual
                  ? 'Fill in the blank with the appropriate academic concept:\n"$blankPrompt"'
                  : 'Practice Fill-in: Complete this sentence:\n"$blankPrompt"';
              break;
            case 2:
              fibPrompt = isActual
                  ? 'Key concept completion: $blankPrompt'
                  : 'Study Recall: Provide the missing word:\n"$blankPrompt"';
              break;
            case 3:
              fibPrompt = isActual
                  ? 'According to the material, complete the following statement:\n"$blankPrompt"'
                  : 'Knowledge Check: Fill in the blank:\n"$blankPrompt"';
              break;
            default:
              fibPrompt = isActual
                  ? 'Provide the missing term to complete this principle:\n"$blankPrompt"'
                  : 'Practice: Complete the statement: "$blankPrompt"';
              break;
          }

          candidate = QuizQuestion(
            id: 'q_${questions.length + 1}',
            type: QuizQuestionType.fillInTheBlank,
            question: fibPrompt,
            options: const [],
            correctAnswer: targetWord,
            explanation: 'The missing term is "$targetWord". Context: "$sentence".',
            points: 1.0,
          );
          break;

        case QuizQuestionType.identification:
          // Mask the term completely so the question does NOT reveal the answer!
          String description = sentence;
          if (conceptDefinitions.containsKey(targetWord)) {
            description = conceptDefinitions[targetWord]!;
          }
          description = description.replaceAll(
            RegExp(r'\b' + RegExp.escape(targetWord) + r'\b', caseSensitive: false),
            '[this concept]',
          );
          description = description.replaceAll(
            RegExp(RegExp.escape(targetWord), caseSensitive: false),
            '[this concept]',
          );

          String idPrompt;
          switch (angle) {
            case 0:
              idPrompt = isActual
                  ? 'Identify the term or concept described:\n"$description"'
                  : 'What key term or concept matches this description?\n"$description"';
              break;
            case 1:
              idPrompt = isActual
                  ? 'Name the academic concept characterized as follows:\n"$description"'
                  : 'Identification Check: Which concept is described below?\n"$description"';
              break;
            case 2:
              idPrompt = isActual
                  ? 'Which term corresponds to the following definition or mechanism?\n"$description"'
                  : 'Study Question: Name the concept described:\n"$description"';
              break;
            case 3:
              idPrompt = isActual
                  ? 'Identify the following structure, process, or principle:\n"$description"'
                  : 'Terminology Check: What term corresponds to:\n"$description"';
              break;
            default:
              idPrompt = isActual
                  ? 'Name the key concept described below:\n"$description"'
                  : 'Identification: What term matches:\n"$description"';
              break;
          }

          candidate = QuizQuestion(
            id: 'q_${questions.length + 1}',
            type: QuizQuestionType.identification,
            question: idPrompt,
            options: const [],
            correctAnswer: targetWord,
            explanation: 'The term being identified is "$targetWord".',
            points: 1.0,
          );
          break;

        case QuizQuestionType.enumeration:
          final listMatch = RegExp(
            r'(?:including|consists of|such as|phases are|stages are|components are)\s+([^.]+)',
            caseSensitive: false,
          ).firstMatch(sentence);

          List<String> enumList = [];
          if (listMatch != null) {
            final rawList = listMatch.group(1) ?? '';
            final parsedItems = rawList
                .split(RegExp(r',\s*(?:and\s+)?|\band\b'))
                .map((item) => item.trim())
                .where((item) => item.length >= 3 && item.length <= 40)
                .take(4)
                .toList();
            if (parsedItems.length >= 2) {
              enumList = parsedItems;
            }
          }

          if (enumList.isEmpty) {
            enumList = candidateTerms
                .where((t) => t.toLowerCase() != targetWord.toLowerCase())
                .skip((i + round * 2) % candidateTerms.length)
                .take(3)
                .toList();
            if (enumList.length < 2) {
              enumList = academicDomainDistractors
                  .where((t) => t.toLowerCase() != targetWord.toLowerCase())
                  .take(3)
                  .toList();
            }
          }

          final briefSubject = sentence.length > 70
              ? '${sentence.substring(0, 70)}...'
              : sentence;

          String enumPrompt;
          switch (angle) {
            case 0:
              enumPrompt = isActual
                  ? 'Enumerate ${enumList.length} key components, elements, or concepts discussed regarding:\n"$briefSubject"'
                  : 'Practice Enumeration: List any ${enumList.length} key terms or factors covered in this section:';
              break;
            case 1:
              enumPrompt = isActual
                  ? 'List ${enumList.length} essential terms or concepts highlighted in this section of the material:'
                  : 'Enumeration Challenge: Name ${enumList.length} distinct items related to this topic:';
              break;
            case 2:
              enumPrompt = isActual
                  ? 'Name any ${enumList.length} distinct factors, stages, or items mentioned in the reading:'
                  : 'Review: List ${enumList.length} key terms associated with this subject:';
              break;
            case 3:
              enumPrompt = isActual
                  ? 'Enumerate ${enumList.length} core concepts or components covered in the text:'
                  : 'Knowledge Check: Provide ${enumList.length} items discussed in the material:';
              break;
            default:
              enumPrompt = isActual
                  ? 'List ${enumList.length} elements or principles discussed in connection with $targetWord:'
                  : 'Practice: Enumerate ${enumList.length} items from this lesson:';
              break;
          }

          candidate = QuizQuestion(
            id: 'q_${questions.length + 1}',
            type: QuizQuestionType.enumeration,
            question: enumPrompt,
            options: const [],
            correctAnswer: enumList.join(', '),
            enumerationAnswers: enumList,
            explanation: 'Expected items: ${enumList.join(", ")}.',
            points: enumList.length * 1.0,
          );
          break;
      }

      // Check for pairwise duplicates / near duplicates
      bool isDuplicate = false;
      final candNormPrompt = candidate.question.trim().toLowerCase();
      final candNormAnswer = ScoringUtils.normalizeText(
        ScoringUtils.cleanExpectedAnswer(candidate.correctAnswer),
      );

      for (final existing in questions) {
        if (candNormPrompt == existing.question.trim().toLowerCase()) {
          isDuplicate = true;
          break;
        }
        final sim = tokenJaccardSimilarity(candidate.question, existing.question);
        if (sim > 0.70) {
          isDuplicate = true;
          break;
        }
        final existNormAnswer = ScoringUtils.normalizeText(
          ScoringUtils.cleanExpectedAnswer(existing.correctAnswer),
        );
        if (candNormAnswer.isNotEmpty &&
            candNormAnswer == existNormAnswer &&
            sim > 0.45) {
          isDuplicate = true;
          break;
        }
      }

      if (!isDuplicate) {
        questions.add(candidate);
      }
    }

    // Renumber IDs sequentially
    return List<QuizQuestion>.generate(questions.length, (idx) {
      final orig = questions[idx];
      return QuizQuestion(
        id: 'q_${idx + 1}',
        type: orig.type,
        question: orig.question,
        options: orig.options,
        correctAnswer: orig.correctAnswer,
        enumerationAnswers: orig.enumerationAnswers,
        explanation: orig.explanation,
        points: orig.points,
      );
    });
  }
}
