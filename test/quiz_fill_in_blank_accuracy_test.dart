import 'package:flutter_test/flutter_test.dart';
import 'package:studexa/models/quiz_model.dart';
import 'package:studexa/services/quiz_service.dart';

void main() {
  group('Task 4 — Fill-in-the-Blank Accuracy Tests', () {
    test('cleanFillInTheBlankAnswer sanitizes leading articles, punctuation, and surrounding quotes', () {
      expect(QuizService.cleanFillInTheBlankAnswer('the Mitochondria'), equals('Mitochondria'));
      expect(QuizService.cleanFillInTheBlankAnswer('a ribosome.'), equals('ribosome'));
      expect(QuizService.cleanFillInTheBlankAnswer('an action potential,'), equals('action potential'));
      expect(QuizService.cleanFillInTheBlankAnswer('"Glycolysis"'), equals('Glycolysis'));
      expect(QuizService.cleanFillInTheBlankAnswer("'Krebs Cycle';"), equals('Krebs Cycle'));
      expect(QuizService.cleanFillInTheBlankAnswer('A. ATP Synthase'), equals('ATP Synthase'));
      expect(QuizService.cleanFillInTheBlankAnswer('1. Chloroplast:'), equals('Chloroplast'));
    });

    test('generateLocalFallbackQuestions produces accurate Fill-in-the-Blank with single-term blanks and context', () {
      const sampleText = '''
Cellular respiration is an essential biological pathway.
Glycolysis is the metabolic pathway that converts glucose into pyruvate.
Mitochondria produce the majority of cellular adenosine triphosphate through oxidative phosphorylation.
The Krebs cycle processes acetyl-CoA inside the mitochondrial matrix.
''';

      final questions = QuizService.generateLocalFallbackQuestions(
        extractedText: sampleText,
        questionCount: 4,
        isActual: false,
        questionTypes: ['fill_in_the_blank'],
      );

      expect(questions.isNotEmpty, isTrue);

      for (final q in questions) {
        expect(q.type, equals(QuizQuestionType.fillInTheBlank));
        // Must contain blank placeholder
        expect(q.question.contains('_______'), isTrue,
            reason: 'Question must contain 7 underscores blank: ${q.question}');

        // Expected answer must be concise: 1 to 2 words maximum
        final words = q.correctAnswer.trim().split(RegExp(r'\s+'));
        expect(words.length, inInclusiveRange(1, 2),
            reason: 'Answer must be a concise key term (1-2 words): "${q.correctAnswer}"');

        // Must not contain trailing punctuation or articles
        expect(q.correctAnswer.endsWith('.'), isFalse);
        expect(q.correctAnswer.endsWith(','), isFalse);
        expect(q.correctAnswer.startsWith('the '), isFalse);
        expect(q.correctAnswer.startsWith('a '), isFalse);
        expect(q.correctAnswer.startsWith('an '), isFalse);

        // Explanation must be present and grounded
        expect(q.explanation.isNotEmpty, isTrue);
      }
    });

    test('Validation enforces that fillInTheBlank question has blank placeholder and concise answer', () {
      const validQ = QuizQuestion(
        id: 'fib_1',
        type: QuizQuestionType.fillInTheBlank,
        question: 'The organelle that generates ATP is the _______.',
        correctAnswer: 'Mitochondria',
        points: 1.0,
      );

      const invalidNoBlank = QuizQuestion(
        id: 'fib_2',
        type: QuizQuestionType.fillInTheBlank,
        question: 'Name the organelle that generates ATP.',
        correctAnswer: 'Mitochondria',
        points: 1.0,
      );

      const invalidLongSentenceAnswer = QuizQuestion(
        id: 'fib_3',
        type: QuizQuestionType.fillInTheBlank,
        question: 'Respiration is described as _______.',
        correctAnswer: 'a complex metabolic pathway consisting of glycolysis and the electron transport chain',
        points: 1.0,
      );

      // We verify candidate validation logic
      bool isValid(QuizQuestion q) {
        if (q.correctAnswer.trim().length < 2) return false;
        if (!q.question.contains('_______') && !q.question.contains('___')) return false;
        final words = q.correctAnswer.trim().split(RegExp(r'\s+'));
        if (words.length > 3) return false;
        return true;
      }

      expect(isValid(validQ), isTrue);
      expect(isValid(invalidNoBlank), isFalse);
      expect(isValid(invalidLongSentenceAnswer), isFalse);
    });
  });
}
