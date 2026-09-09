import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:studexa/models/quiz_model.dart';
import 'package:studexa/services/quiz_service.dart';
import 'package:studexa/utils/document_text_extractor.dart';
import 'package:studexa/utils/scoring_utils.dart';

void main() {
  group('QuizModel and QuizQuestion Tests', () {
    test('QuizQuestionType string conversion and aliases', () {
      expect(
        QuizQuestionType.fromString('multiple_choice'),
        QuizQuestionType.multipleChoice,
      );
      expect(
        QuizQuestionType.fromString('mcq'),
        QuizQuestionType.multipleChoice,
      );
      expect(
        QuizQuestionType.fromString('True/False'),
        QuizQuestionType.trueFalse,
      );
      expect(
        QuizQuestionType.fromString('fill_blank'),
        QuizQuestionType.fillInTheBlank,
      );
      expect(
        QuizQuestionType.fromString('Identification'),
        QuizQuestionType.identification,
      );
      expect(
        QuizQuestionType.fromString('enumeration'),
        QuizQuestionType.enumeration,
      );
    });

    test('QuizQuestion serializes and deserializes properly', () {
      const question = QuizQuestion(
        id: 'q_1',
        type: QuizQuestionType.multipleChoice,
        question: 'What is the powerhouse of the cell?',
        options: ['A. Nucleus', 'B. Mitochondria', 'C. Ribosome'],
        correctAnswer: 'B. Mitochondria',
        explanation: 'Mitochondria generates ATP.',
        points: 2.0,
      );

      final map = question.toMap();
      expect(map['id'], 'q_1');
      expect(map['type'], 'multiple_choice');
      expect(map['options'].length, 3);
      expect(map['points'], 2.0);

      final reconstructed = QuizQuestion.fromMap(map);
      expect(reconstructed.id, question.id);
      expect(reconstructed.type, QuizQuestionType.multipleChoice);
      expect(reconstructed.question, question.question);
      expect(reconstructed.options, question.options);
      expect(reconstructed.correctAnswer, question.correctAnswer);
      expect(reconstructed.points, 2.0);
    });

    test('QuizModel serializes and deserializes correctly', () {
      final quiz = QuizModel(
        id: 'quiz_123',
        classId: 'class_abc',
        teacherId: 'teacher_xyz',
        materialId: 'mat_456',
        type: 'practice',
        title: 'Cellular Biology Practice Quiz',
        status: 'published',
        generationMethod: 'gemini',
        questions: const [
          QuizQuestion(
            id: 'q_1',
            type: QuizQuestionType.trueFalse,
            question: 'ATP provides energy for cells.',
            options: ['True', 'False'],
            correctAnswer: 'True',
            points: 1.0,
          ),
          QuizQuestion(
            id: 'q_2',
            type: QuizQuestionType.enumeration,
            question: 'List three cellular components:',
            enumerationAnswers: ['Nucleus', 'Mitochondria', 'Cytoplasm'],
            points: 3.0,
          ),
        ],
        totalPoints: 4.0,
      );

      expect(quiz.isPractice, true);
      expect(quiz.isActual, false);
      expect(quiz.isPublished, true);
      expect(quiz.isGeminiGenerated, true);
      expect(quiz.questionCount, 2);
      expect(quiz.totalPoints, 4.0);

      final map = quiz.toMap();
      expect(map['classId'], 'class_abc');
      expect(map['teacherId'], 'teacher_xyz');
      expect(map['materialId'], 'mat_456');
      expect(map['status'], 'published');
      expect(map['questions'].length, 2);

      final reconstructed = QuizModel.fromMap(map, id: 'quiz_123');
      expect(reconstructed.id, 'quiz_123');
      expect(reconstructed.title, quiz.title);
      expect(reconstructed.questions.length, 2);
      expect(reconstructed.questions[1].type, QuizQuestionType.enumeration);
      expect(reconstructed.questions[1].enumerationAnswers.length, 3);
    });

    test('QuizModel copyWith preserves immutability and updates fields', () {
      const original = QuizModel(
        id: 'q1',
        classId: 'c1',
        teacherId: 't1',
        materialId: 'm1',
        type: 'actual',
        title: 'Original Title',
        status: 'draft',
      );

      final updated = original.copyWith(
        title: 'Updated Exam Title',
        status: 'finalized',
      );

      expect(original.title, 'Original Title');
      expect(original.status, 'draft');
      expect(updated.title, 'Updated Exam Title');
      expect(updated.status, 'finalized');
      expect(updated.id, 'q1');
      expect(updated.classId, 'c1');
    });
  });

  group('QuizService Local Fallback Generator Tests', () {
    const sampleText =
        'Cellular respiration is defined as the metabolic process that cells use to convert biochemical energy from nutrients into ATP. '
        'Mitochondria are double-membraned organelles known as the powerhouse of the cell. '
        'Glycolysis occurs in the cytoplasm and breaks down glucose into pyruvate. '
        'The citric acid cycle takes place inside the mitochondrial matrix. '
        'Photosynthesis converts light energy into chemical energy stored in carbohydrates. '
        'Enzymes are biological catalysts that speed up chemical reactions without being consumed.';

    test('Generates requested number of questions across all 5 types', () {
      final questions = QuizService.generateLocalFallbackQuestions(
        extractedText: sampleText,
        questionTypes: [
          'Multiple Choice',
          'True/False',
          'Fill-in-the-Blank',
          'Identification',
          'Enumeration',
        ],
        questionCount: 10,
        isActual: true,
      );

      expect(questions.length, 10);

      // Verify all 5 types are present
      final types = questions.map((q) => q.type).toSet();
      expect(types.contains(QuizQuestionType.multipleChoice), true);
      expect(types.contains(QuizQuestionType.trueFalse), true);
      expect(types.contains(QuizQuestionType.fillInTheBlank), true);
      expect(types.contains(QuizQuestionType.identification), true);
      expect(types.contains(QuizQuestionType.enumeration), true);

      // Verify MCQ structure
      final mcq = questions.firstWhere(
        (q) => q.type == QuizQuestionType.multipleChoice,
      );
      expect(mcq.options.length, 4);
      expect(mcq.correctAnswer.isNotEmpty, true);

      // Verify True/False structure
      final tf = questions.firstWhere(
        (q) => q.type == QuizQuestionType.trueFalse,
      );
      expect(tf.options, ['True', 'False']);
      expect(['True', 'False'].contains(tf.correctAnswer), true);

      // Verify Enumeration structure
      final en = questions.firstWhere(
        (q) => q.type == QuizQuestionType.enumeration,
      );
      expect(en.enumerationAnswers.isNotEmpty, true);
      expect(en.points >= 1.0, true);
    });

    test('Generates distinct phrasing for Practice Quiz vs Actual Quiz', () {
      final actualQuestions = QuizService.generateLocalFallbackQuestions(
        extractedText: sampleText,
        questionTypes: ['Multiple Choice'],
        questionCount: 2,
        isActual: true,
      );

      final practiceQuestions = QuizService.generateLocalFallbackQuestions(
        extractedText: sampleText,
        questionTypes: ['Multiple Choice'],
        questionCount: 2,
        isActual: false,
      );

      expect(actualQuestions.first.question.startsWith('Fill in the blank'), true);
      expect(practiceQuestions.first.question.contains('Practice Question'), true);
    });

    test('Accuracy: Filters metadata, masks identification answers, and generates plausible distractors', () {
      const complexText = '''
Course: BIO 101 - Fall 2026. Page 14 of 95. Copyright 2026 University.
Instructor: Dr. Smith. Welcome to lecture 4.
Cellular respiration is defined as the biochemical pathway that cells use to convert nutrients into ATP.
Mitochondria: The double-membraned organelle responsible for ATP synthesis.
Glycolysis occurs in the cytoplasm and breaks down glucose into pyruvate.
The citric acid cycle takes place inside the mitochondrial matrix.
''';

      final questions = QuizService.generateLocalFallbackQuestions(
        extractedText: complexText,
        questionTypes: [
          'Multiple Choice',
          'Identification',
          'True/False',
          'Fill-in-the-Blank',
        ],
        questionCount: 4,
        isActual: true,
      );

      // 1. Verify metadata was filtered out of all questions
      for (final q in questions) {
        expect(q.question.contains('Course: BIO 101'), false);
        expect(q.question.contains('Page 14'), false);
        expect(q.question.contains('Copyright'), false);
        expect(q.question.contains('Dr. Smith'), false);
      }

      // 2. Verify Multiple Choice has plausible options, no "Concept 1"
      final mcq = questions.firstWhere((q) => q.type == QuizQuestionType.multipleChoice);
      for (final opt in mcq.options) {
        expect(opt.contains('Concept 1'), false);
        expect(opt.contains('Concept 2'), false);
        expect(opt.contains('Concept 3'), false);
      }

      // 3. Verify Identification prompt does NOT reveal the correctAnswer
      final ident = questions.firstWhere((q) => q.type == QuizQuestionType.identification);
      expect(ident.question.toLowerCase().contains(ident.correctAnswer.toLowerCase()), false);
    });
  });

  group('Quiz Evaluation & Scoring Integration Tests', () {
    test('Evaluates Fill-in-the-Blank and Identification with typo tolerance', () {
      const q = QuizQuestion(
        id: 'q_fib',
        type: QuizQuestionType.fillInTheBlank,
        question: 'Name the organelle: _______',
        correctAnswer: 'Mitochondria',
        points: 1.0,
      );

      // Exact match
      expect(ScoringUtils.isFreeTextMatch('mitochondria', q.correctAnswer), true);
      // Typo tolerance (1 typo in 12-char word)
      expect(ScoringUtils.isFreeTextMatch('mitokondria', q.correctAnswer), true);
      // Completely wrong
      expect(ScoringUtils.isFreeTextMatch('ribosome', q.correctAnswer), false);
    });

    test('Evaluates Enumeration with partial credit and extra non-penalizing items', () {
      const q = QuizQuestion(
        id: 'q_enum',
        type: QuizQuestionType.enumeration,
        question: 'Enumerate stages of respiration:',
        enumerationAnswers: ['Glycolysis', 'Krebs Cycle', 'Electron Transport'],
        points: 3.0,
      );

      // All 3 correct out of order + 1 extra incorrect item
      final result = ScoringUtils.scoreEnumeration(
        studentItems: ['Krebs Cycle', 'Electron Transport', 'Glycolysis', 'Photosynthesis'],
        expectedItems: q.enumerationAnswers,
        totalPoints: q.points,
      );

      expect(result.isFullyCorrect, true);
      expect(result.earnedPoints, 3.0);
      expect(result.found.length, 3);
      expect(result.missing.isEmpty, true);
      expect(result.extra, ['Photosynthesis']);

      // Partial match: 2 out of 3
      final partialResult = ScoringUtils.scoreEnumeration(
        studentItems: ['Glycolysis', 'Krebs Cycle'],
        expectedItems: q.enumerationAnswers,
        totalPoints: q.points,
      );

      expect(partialResult.isFullyCorrect, false);
      expect(partialResult.earnedPoints, 2.0);
      expect(partialResult.found.length, 2);
      expect(partialResult.missing, ['Electron Transport']);
    });
  });

  group('DocumentTextExtractor & AI Resiliency Tests', () {
    test('Extracts plain text correctly from TXT bytes', () async {
      const originalText = 'Photosynthesis converts solar energy into chemical energy stored in glucose.';
      final bytes = Uint8List.fromList(utf8.encode(originalText));

      final result = await DocumentTextExtractor.extractText(
        bytes: bytes,
        extension: 'txt',
      );

      expect(result, originalText);
    });

    test('Case-insensitive extension handling for documents', () async {
      const originalText = 'Cellular biology notes.';
      final bytes = Uint8List.fromList(utf8.encode(originalText));

      final result = await DocumentTextExtractor.extractText(
        bytes: bytes,
        extension: '.TXT',
      );

      expect(result, originalText);
    });

    test('Throws on unsupported file extensions', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);

      expect(
        () => DocumentTextExtractor.extractText(bytes: bytes, extension: 'exe'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('QuizService.callGeminiApi returns null gracefully when apiKey is empty', () async {
      final result = await QuizService.callGeminiApi(
        apiKey: '',
        extractedText: 'Sample text',
        questionTypes: ['multipleChoice'],
        questionCount: 5,
        isActual: false,
      );

      expect(result, isNull);
    });
  });

  group('QuizService Validation Tests (Issue 1 & 4)', () {
    test('validateQuizQuestions returns null for valid questions across types', () {
      final questions = [
        const QuizQuestion(
          id: 'q1',
          type: QuizQuestionType.multipleChoice,
          question: 'What organelle synthesizes ATP?',
          options: ['A. Nucleus', 'B. Mitochondria', 'C. Ribosome'],
          correctAnswer: 'B. Mitochondria',
        ),
        const QuizQuestion(
          id: 'q2',
          type: QuizQuestionType.trueFalse,
          question: 'Photosynthesis occurs in chloroplasts.',
          options: ['True', 'False'],
          correctAnswer: 'True',
        ),
        const QuizQuestion(
          id: 'q3',
          type: QuizQuestionType.fillInTheBlank,
          question: 'The powerhouse of the cell is _______',
          correctAnswer: 'Mitochondria',
        ),
        const QuizQuestion(
          id: 'q4',
          type: QuizQuestionType.enumeration,
          question: 'List three stages of respiration:',
          enumerationAnswers: ['Glycolysis', 'Krebs Cycle', 'ETC'],
          correctAnswer: 'Glycolysis, Krebs Cycle, ETC',
        ),
      ];

      final error = QuizService.validateQuizQuestions(questions);
      expect(error, isNull);
    });

    test('validateQuizQuestions catches empty questions list', () {
      final error = QuizService.validateQuizQuestions([]);
      expect(error, contains('must have at least one question'));
    });

    test('validateQuizQuestions catches blank prompt or blank answer', () {
      final emptyPrompt = [
        const QuizQuestion(
          id: 'q1',
          type: QuizQuestionType.fillInTheBlank,
          question: '   ',
          correctAnswer: 'Cell',
        ),
      ];
      expect(QuizService.validateQuizQuestions(emptyPrompt), contains('prompt cannot be empty'));

      final emptyAnswer = [
        const QuizQuestion(
          id: 'q1',
          type: QuizQuestionType.identification,
          question: 'What is the cell powerhouse?',
          correctAnswer: '',
        ),
      ];
      expect(QuizService.validateQuizQuestions(emptyAnswer), contains('must have a correct answer'));
    });

    test('validateQuizQuestions catches MCQ with invalid options or mismatching answer', () {
      final noMatchingOption = [
        const QuizQuestion(
          id: 'q1',
          type: QuizQuestionType.multipleChoice,
          question: 'What organelle synthesizes ATP?',
          options: ['A. Nucleus', 'B. Ribosome'],
          correctAnswer: 'C. Mitochondria',
        ),
      ];
      expect(
        QuizService.validateQuizQuestions(noMatchingOption),
        contains('must match one of the options'),
      );
    });

    test('validateQuizQuestions catches invalid True/False answer', () {
      final invalidTF = [
        const QuizQuestion(
          id: 'q1',
          type: QuizQuestionType.trueFalse,
          question: 'Mitochondria make ATP.',
          options: ['True', 'False'],
          correctAnswer: 'Maybe',
        ),
      ];
      expect(
        QuizService.validateQuizQuestions(invalidTF),
        contains('must be True or False'),
      );
    });
  });

  group('QuizService Accuracy & Redundant Question Prevention Tests (Issues 1 & 2)', () {
    test('tokenJaccardSimilarity calculates word overlap ignoring punctuation and case', () {
      // Identical
      expect(
        QuizService.tokenJaccardSimilarity(
          'What is the powerhouse of the cell?',
          'WHAT IS THE POWERHOUSE OF THE CELL?',
        ),
        1.0,
      );

      // Disjoint
      expect(
        QuizService.tokenJaccardSimilarity(
          'Photosynthesis converts light into glucose.',
          'Database algorithms utilize binary search trees.',
        ),
        0.0,
      );

      // Highly similar (> 0.70)
      final simHigh = QuizService.tokenJaccardSimilarity(
        'What organelle is the powerhouse of the cell?',
        'Which organelle is the powerhouse of the cell?',
      );
      expect(simHigh > 0.70, true);

      // Distinct concepts (< 0.40)
      final simLow = QuizService.tokenJaccardSimilarity(
        'Glycolysis occurs in the cytoplasm and breaks down glucose.',
        'Mitochondria are double-membraned organelles known as the powerhouse of the cell.',
      );
      expect(simLow < 0.40, true);
    });

    test('validateAndDeduplicateQuestions prunes duplicates, drops invalid, and backfills to targetCount', () {
      const validQ1 = QuizQuestion(
        id: 'orig_1',
        type: QuizQuestionType.multipleChoice,
        question: 'Which organelle is the powerhouse of the cell?',
        options: ['A. Mitochondria', 'B. Nucleus', 'C. Ribosome', 'D. Chloroplast'],
        correctAnswer: 'A. Mitochondria',
      );

      // Exact prompt duplicate
      const duplicateExact = QuizQuestion(
        id: 'orig_2',
        type: QuizQuestionType.multipleChoice,
        question: 'Which organelle is the powerhouse of the cell?',
        options: ['A. Mitochondria', 'B. Nucleus', 'C. Ribosome', 'D. Chloroplast'],
        correctAnswer: 'A. Mitochondria',
      );

      // Near duplicate (> 0.70 similarity)
      const duplicateNear = QuizQuestion(
        id: 'orig_3',
        type: QuizQuestionType.multipleChoice,
        question: 'Which organelle is the powerhouse of the cell structure?',
        options: ['A. Mitochondria', 'B. Nucleus', 'C. Ribosome', 'D. Chloroplast'],
        correctAnswer: 'A. Mitochondria',
      );

      // Structurally invalid question (empty prompt)
      const invalidEmptyPrompt = QuizQuestion(
        id: 'orig_4',
        type: QuizQuestionType.trueFalse,
        question: '   ',
        options: ['True', 'False'],
        correctAnswer: 'True',
      );

      final input = [validQ1, duplicateExact, duplicateNear, invalidEmptyPrompt];

      const sampleMaterial =
          'Cellular respiration produces ATP in eukaryotic cells. '
          'Mitochondria are the powerhouse of the cell. '
          'Glycolysis occurs in the cytoplasm. '
          'The citric acid cycle occurs inside the mitochondrial matrix. '
          'Photosynthesis converts light into chemical energy. '
          'Enzymes are biological catalysts.';

      // Request targetCount: 5 with backfilling
      final result = QuizService.validateAndDeduplicateQuestions(
        input,
        targetCount: 5,
        extractedText: sampleMaterial,
      );

      // 1. Target count fulfilled
      expect(result.length, 5);

      // 2. All questions are valid
      final validationError = QuizService.validateQuizQuestions(result);
      expect(validationError, isNull);

      // 3. No duplicates among questions
      for (int i = 0; i < result.length; i++) {
        for (int j = i + 1; j < result.length; j++) {
          final sim = QuizService.tokenJaccardSimilarity(
            result[i].question,
            result[j].question,
          );
          expect(
            sim <= 0.70,
            true,
            reason: 'Questions #${i + 1} and #${j + 1} are too similar: sim=$sim',
          );
        }
      }

      // 4. Sequential IDs
      expect(result[0].id, 'q_1');
      expect(result[1].id, 'q_2');
      expect(result[2].id, 'q_3');
      expect(result[3].id, 'q_4');
      expect(result[4].id, 'q_5');
    });

    test('Generates 10, 30, and 50 questions with ZERO duplicate stems and Jaccard similarity <= 0.70', () {
      const richLectureText = '''
Cellular respiration produces ATP by oxidizing glucose molecules in eukaryotic cells.
Mitochondria are double-membraned organelles known as the powerhouse of the cell.
Glycolysis occurs in the cytoplasm and breaks down glucose into two molecules of pyruvate.
The citric acid cycle takes place inside the mitochondrial matrix.
Adenosine triphosphate serves as the primary energy currency for cellular reactions.
Photosynthesis converts light energy into chemical energy stored in carbohydrates.
Enzymes are biological catalysts that lower activation energy without being consumed.
Deoxyribonucleic acid stores genetic instructions within the cell nucleus.
Ribosomes are macromolecular machines responsible for biological protein synthesis.
The endoplasmic reticulum facilitates protein folding and transport in eukaryotic cells.
Chloroplasts contain chlorophyll pigments that absorb sunlight during photosynthesis.
The cell membrane maintains homeostasis through selective membrane permeability.
''';

      for (final count in [10, 30, 50]) {
        final questions = QuizService.generateLocalFallbackQuestions(
          extractedText: richLectureText,
          questionTypes: [
            'Multiple Choice',
            'True/False',
            'Fill-in-the-Blank',
            'Identification',
            'Enumeration',
          ],
          questionCount: count,
          isActual: true,
        );

        // 1. Exactly requested count returned
        expect(
          questions.length,
          count,
          reason: 'Expected exactly $count questions for count=$count',
        );

        // 2. All questions pass pedagogical validation
        final error = QuizService.validateQuizQuestions(questions);
        expect(
          error,
          isNull,
          reason: 'Validation failed for count=$count: $error',
        );

        // 3. ZERO duplicate stems: All pairwise Jaccard similarities <= 0.70
        for (int i = 0; i < questions.length; i++) {
          for (int j = i + 1; j < questions.length; j++) {
            final sim = QuizService.tokenJaccardSimilarity(
              questions[i].question,
              questions[j].question,
            );
            expect(
              sim <= 0.70,
              true,
              reason: 'Pairwise duplicate in $count-question set: Q${i + 1} vs Q${j + 1} (sim=$sim)\nQ1: "${questions[i].question}"\nQ2: "${questions[j].question}"',
            );
          }
        }

        // 4. All 5 question types are present
        final presentTypes = questions.map((q) => q.type).toSet();
        expect(presentTypes.contains(QuizQuestionType.multipleChoice), true);
        expect(presentTypes.contains(QuizQuestionType.trueFalse), true);
        expect(presentTypes.contains(QuizQuestionType.fillInTheBlank), true);
        expect(presentTypes.contains(QuizQuestionType.identification), true);
        expect(presentTypes.contains(QuizQuestionType.enumeration), true);
      }
    });
  });
}
