import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:studexa/models/quiz_model.dart';
import 'package:studexa/screens/student/answer_quiz_screen.dart';
import 'package:studexa/services/assignment_service.dart';

void setupMockFirebase() {
  TestWidgetsFlutterBinding.ensureInitialized();
  MethodChannelFirebase.appInstances['[DEFAULT]'] = MethodChannelFirebaseApp(
    '[DEFAULT]',
    const FirebaseOptions(
      apiKey: 'mock-key',
      appId: 'mock-id',
      messagingSenderId: 'mock-sender',
      projectId: 'studexa-test',
      storageBucket: 'studexa-test.appspot.com',
    ),
  );
  MethodChannelFirebase.isCoreInitialized = true;
}

void main() {
  setUpAll(() {
    setupMockFirebase();
  });

  group('Student Quiz Attempt Limits & Shuffle Tests', () {
    final testQuiz = QuizModel(
      id: 'quiz_attempts_test',
      classId: 'class_bio_101',
      teacherId: 'teacher_123',
      materialId: 'mat_123',
      title: 'Cellular Respiration Quiz',
      type: 'practice',
      status: 'published',
      questions: const [
        QuizQuestion(
          id: 'q1',
          type: QuizQuestionType.multipleChoice,
          question: 'Question One: What is ATP?',
          options: ['A', 'B', 'C', 'D'],
          correctAnswer: 'A',
          points: 1.0,
        ),
        QuizQuestion(
          id: 'q2',
          type: QuizQuestionType.trueFalse,
          question: 'Question Two: Glycolysis requires oxygen.',
          options: ['True', 'False'],
          correctAnswer: 'False',
          points: 1.0,
        ),
        QuizQuestion(
          id: 'q3',
          type: QuizQuestionType.fillInTheBlank,
          question: 'Question Three: Mitochondria is the ____.',
          correctAnswer: 'Powerhouse',
          points: 1.0,
        ),
      ],
    );

    testWidgets('Attempt 1 renders questions in original order and supports round-robin skip', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AnswerQuizScreen(
          quiz: testQuiz,
          attemptNumber: 1,
        ),
      ));
      await tester.pumpAndSettle();

      // Starts on Question 1
      expect(find.text('Question One: What is ATP?'), findsOneWidget);
      expect(find.text('Question 1 of 3'), findsOneWidget);

      // Verify Skip button exists and works
      final skipBtn = find.widgetWithText(OutlinedButton, 'Skip');
      expect(skipBtn, findsOneWidget);
      await tester.tap(skipBtn);
      await tester.pumpAndSettle();

      // Q1 was requeued to end, Q2 is now shown
      expect(find.text('Question Two: Glycolysis requires oxygen.'), findsOneWidget);
      expect(find.text('Question 1 of 3'), findsOneWidget);
    });

    testWidgets('Attempt 2 shuffles question order while preserving round-robin skip', (tester) async {
      // Use seeded Random to ensure deterministic shuffle that swaps order
      final seededRandom = Random(42);
      await tester.pumpWidget(MaterialApp(
        home: AnswerQuizScreen(
          quiz: testQuiz,
          attemptNumber: 2,
          random: seededRandom,
        ),
      ));
      await tester.pumpAndSettle();

      // Verify that question order is shuffled (first question displayed is NOT Q1)
      final hasQ1First = find.text('Question One: What is ATP?').evaluate().isNotEmpty;
      final hasQ2First = find.text('Question Two: Glycolysis requires oxygen.').evaluate().isNotEmpty;
      final hasQ3First = find.text('Question Three: Mitochondria is the ____.').evaluate().isNotEmpty;

      // Exactly one of the questions should be displayed
      expect(hasQ1First || hasQ2First || hasQ3First, isTrue);
      // Under Seed 42 with 3 items, the order is [q3, q1, q2] or [q2, q3, q1]
      expect(hasQ1First, isFalse, reason: 'Attempt 2 should shuffle and not start with Question One');

      // Verify skip works on shuffled attempt 2
      final skipBtn = find.widgetWithText(OutlinedButton, 'Skip');
      expect(skipBtn, findsOneWidget);
      await tester.tap(skipBtn);
      await tester.pumpAndSettle();

      // Advances to next shuffled question
      expect(find.text('Question 1 of 3'), findsOneWidget);
    });

    testWidgets('Attempt 3 visibly blocks quiz and displays Maximum Attempts Reached screen', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AnswerQuizScreen(
          quiz: testQuiz,
          attemptNumber: 3,
        ),
      ));
      await tester.pumpAndSettle();

      // Verify blocked screen UI elements
      expect(find.text('Maximum Attempts Reached'), findsOneWidget);
      expect(
        find.text('You have reached the maximum 2 attempts for this practice quiz. Further attempts are not permitted.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(ElevatedButton, 'Return to Class'), findsOneWidget);

      // Verify NO question inputs, options, or skip buttons are shown
      expect(find.text('Question One: What is ATP?'), findsNothing);
      expect(find.text('Question Two: Glycolysis requires oxygen.'), findsNothing);
      expect(find.text('Question Three: Mitochondria is the ____.'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Skip'), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Submit Quiz'), findsNothing);
    });

    test('QuizUnavailableException provides clear message for attempt limits', () {
      const ex = QuizUnavailableException('You have reached the maximum 2 attempts for this practice quiz.');
      expect(ex.message, contains('maximum 2 attempts'));
      expect(ex.toString(), 'You have reached the maximum 2 attempts for this practice quiz.');
    });
  });
}
