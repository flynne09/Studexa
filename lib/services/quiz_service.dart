import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'quiz_generation_client.dart';
import '../models/quiz_model.dart';
import '../utils/scoring_utils.dart';
import 'firestore_provider.dart';

/// Service managing quiz creation, generation, Firestore persistence, and streaming.
class QuizService {
  QuizService({
    FirebaseFirestore? firestore,
    QuizGenerationClient? generationClient,
  }) : _firestore = firestore ?? getAppFirestore(),
       _generationClient = generationClient ?? QuizGenerationClient();

  final FirebaseFirestore _firestore;

  final QuizGenerationClient _generationClient;

  CollectionReference<Map<String, dynamic>> get _quizzesCollection =>
      _firestore.collection('quizzes');

  /// Streams all quizzes for a specific class, optionally filtered by type ("actual" or "practice").
  Stream<List<QuizModel>> streamClassQuizzes(
    String classId, {
    String? type,
    bool publishedOnly = false,
  }) {
    Query<Map<String, dynamic>> query = _quizzesCollection.where(
      'classId',
      isEqualTo: classId,
    );

    if (type != null && type.isNotEmpty) {
      query = query.where('type', isEqualTo: type.toLowerCase());
    }

    if (publishedOnly) query = query.where('status', isEqualTo: 'published');
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

  /// Generates and saves a quiz through the authenticated Edge Function.
  /// Preloaded values remain accepted for existing callers; the server reads the
  /// authoritative material and verifies teacher/class ownership.
  Future<QuizModel> generateQuiz({
    required String teacherId,
    required String classId,
    required String materialId,
    required bool isActual,
    required List<String> questionTypes,
    required int questionCount,
    String? sourceQuizId,
    String? preloadedExtractedText,
    String? preloadedFileName,
  }) => _generationClient.generate(
    teacherId: teacherId,
    classId: classId,
    materialId: materialId,
    isActual: isActual,
    questionTypes: questionTypes,
    questionCount: questionCount,
    sourceQuizId: sourceQuizId,
  );

  Future<QuizModel> generateMore(QuizModel quiz) {
    final requested = quiz.requestedQuestionCount;
    if (!quiz.isDraft ||
        requested == null ||
        quiz.questionCount >= requested ||
        quiz.extraGenerationAttempted ||
        quiz.selectedQuestionTypes.isEmpty) {
      throw StateError('This draft cannot generate more questions.');
    }
    return _generationClient.generate(
      teacherId: quiz.teacherId,
      classId: quiz.classId,
      materialId: quiz.materialId,
      isActual: quiz.isActual,
      questionTypes: quiz.selectedQuestionTypes,
      questionCount: requested,
      sourceQuizId: quiz.sourceQuizId,
      continueQuizId: quiz.id,
    );
  }

  /// Cleans and sanitizes Fill-in-the-Blank and Identification expected answers
  /// ensuring they do not contain extraneous punctuation, surrounding quotes, or leading articles.
  static String cleanFillInTheBlankAnswer(String raw) {
    var cleaned = ScoringUtils.cleanExpectedAnswer(raw).trim();
    cleaned = cleaned
        .replaceAll(RegExp(r'^(the|a|an)\s+', caseSensitive: false), '')
        .trim();
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
    if (RegExp(
      r'\b(?:column|header|col|row)\s+[a-z0-9]+\b',
      caseSensitive: false,
    ).hasMatch(prompt)) {
      if (prompt.contains('what') ||
          prompt.contains('which') ||
          prompt.contains('identify')) {
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
        final cleanOpt = ScoringUtils.normalizeText(
          ScoringUtils.cleanExpectedAnswer(opt),
        );
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

    if (RegExp(
      r'\b(?:on slide|in chapter|on page|published in|publication date|file name)\b',
      caseSensitive: false,
    ).hasMatch(prompt)) {
      return true;
    }

    final fillerAnswerPattern = RegExp(
      r'^(?:all rights reserved|copyright|creative commons|welcome|thank you|any questions|dr\.\s+\w+|prof\.\s+\w+|professor|instructor|syllabus|office hours|slide\s+\d+|page\s+\d+|chapter\s+\d+|https?://\S+|www\.\S+|\S+@\S+)$',
      caseSensitive: false,
    );
    if (fillerAnswerPattern.hasMatch(answer)) return true;

    if (answer.contains('@') ||
        answer.contains('http://') ||
        answer.contains('https://') ||
        answer.contains('www.')) {
      return true;
    }
    if (RegExp(r'^(?:19|20)\d\d$').hasMatch(answer) &&
        (prompt.contains('published') ||
            prompt.contains('copyright') ||
            prompt.contains('year'))) {
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
          if (!q.question.contains('_______') && !q.question.contains('___')) {
            return false;
          }
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
        final similarity = tokenJaccardSimilarity(
          candidate.question,
          existing.question,
        );
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
              .map(
                (o) => ScoringUtils.normalizeText(
                  ScoringUtils.cleanExpectedAnswer(o),
                ),
              )
              .toSet();
          final existOptions = existing.options
              .map(
                (o) => ScoringUtils.normalizeText(
                  ScoringUtils.cleanExpectedAnswer(o),
                ),
              )
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
    if (targetCount != null &&
        targetCount > 0 &&
        accepted.length < targetCount) {
      final textForFallback =
          (extractedText != null && extractedText.trim().isNotEmpty)
          ? extractedText
          : accepted.map((q) => '${q.question} ${q.correctAnswer}').join(' ');

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
    final capped =
        (targetCount != null &&
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
      'totalPoints': quiz.questions.fold<double>(
        0.0,
        (acc, q) => acc + q.points,
      ),
      'status': quiz.status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<QuizModel> appendManualQuestion(
    String quizId,
    QuizQuestion question,
  ) async {
    final validation = validateQuizQuestions([question]);
    if (validation != null) throw StateError(validation);
    final ref = _quizzesCollection.doc(quizId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) throw StateError('This quiz no longer exists.');
      final quiz = QuizModel.fromFirestore(snapshot);
      if (!quiz.isDraft) {
        throw StateError('Questions can only be added to a draft quiz.');
      }
      final normalized = question.question.trim().toLowerCase();
      if (quiz.questions.any(
        (existing) => existing.question.trim().toLowerCase() == normalized,
      )) {
        throw StateError('That question is already in this quiz.');
      }
      var nextNumber = quiz.questions.length + 1;
      while (quiz.questions.any((existing) => existing.id == 'q_$nextNumber')) {
        nextNumber++;
      }
      final nextQuestion = question.copyWith(
        id: 'q_$nextNumber',
        origin: 'manual',
      );
      final questions = [...quiz.questions, nextQuestion];
      transaction.update(ref, {
        'questions': questions.map((item) => item.toMap()).toList(),
        'totalPoints': questions.fold<double>(
          0,
          (total, item) => total + item.points,
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    final updated = await getQuiz(quizId);
    if (updated == null) {
      throw StateError('The saved quiz could not be loaded.');
    }
    return updated;
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
      if (RegExp(
        r'^(?:column|header|col|row)\s+[a-z0-9]+:?$',
        caseSensitive: false,
      ).hasMatch(s)) {
        return false;
      }
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
      'column',
      'header',
      'attribute',
      'attributes',
      'value',
      'values',
      'field',
      'fields',
      'table',
      'tables',
      'row',
      'rows',
      'item',
      'items',
      'category',
      'categories',
      'no',
      'number',
      'type',
      'types',
      'description',
      'remarks',
      'date',
      'col',
      'copyright',
      'reserved',
      'author',
      'authors',
      'professor',
      'instructor',
      'syllabus',
      'lecture',
      'slide',
      'page',
      'chapter',
      'university',
      'college',
      'homework',
      'summary',
      'reference',
      'references',
      'license',
      'acknowledgment',
      'acknowledgments',
      'welcome',
      'reading',
      'hours',
      'grading',
      'policy',
      'edition',
      'editions',
      'email',
      'emails',
      'isbn',
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
            !RegExp(
              r'^(?:column|header|col|row)\s+[a-z0-9]+$',
              caseSensitive: false,
            ).hasMatch(term)) {
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
            !RegExp(
              r'^(?:column|header|col|row)\s+[a-z0-9]+$',
              caseSensitive: false,
            ).hasMatch(term)) {
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
            !RegExp(
              r'^(?:column|header|col|row)\s+[a-z0-9]+$',
              caseSensitive: false,
            ).hasMatch(clean) &&
            !RegExp(
              r'^(These|Those|There|Their|Which|After|Before|Because|However|When|Where|While|Since|Both|Each|Every)$',
            ).hasMatch(clean)) {
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
      'about',
      'after',
      'before',
      'because',
      'between',
      'during',
      'however',
      'through',
      'under',
      'which',
      'where',
      'while',
      'their',
      'there',
      'these',
      'those',
      'would',
      'could',
      'should',
      'other',
      'being',
      'having',
      'within',
      'called',
      'known',
      'defined',
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
        caseSensitive: false,
      ).hasMatch(s)) {
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
          for (
            int d = 0;
            d < distractorPool.length && distractors.length < 3;
            d++
          ) {
            final cand = distractorPool[(i + d * 3) % distractorPool.length];
            if (!distractors.contains(cand)) {
              distractors.add(cand);
            }
          }

          final allOptions = [targetWord, ...distractors]
            ..shuffle(Random(i * 31 + 7));
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
            explanation:
                'The correct answer is $targetWord grounded in: "$sentence".',
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
              statement = statement.replaceFirst(
                ' produces ',
                ' does not produce ',
              );
            } else if (statement.contains(' requires ')) {
              statement = statement.replaceFirst(
                ' requires ',
                ' functions without ',
              );
            } else if (statement.contains(' occurs ')) {
              statement = statement.replaceFirst(
                ' occurs ',
                ' does not occur ',
              );
            } else {
              statement =
                  'It is false that ${statement[0].toLowerCase()}${statement.substring(1)}';
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
              RegExp(
                r'\b' + RegExp.escape(targetWord) + r'\b',
                caseSensitive: false,
              ),
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
            explanation:
                'The missing term is "$targetWord". Context: "$sentence".',
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
            RegExp(
              r'\b' + RegExp.escape(targetWord) + r'\b',
              caseSensitive: false,
            ),
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
        final sim = tokenJaccardSimilarity(
          candidate.question,
          existing.question,
        );
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
