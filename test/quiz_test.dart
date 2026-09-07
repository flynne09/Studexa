import 'package:flutter_test/flutter_test.dart';
import 'package:studexa/models/quiz_model.dart';
import 'package:studexa/services/quiz_service.dart';
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
}
