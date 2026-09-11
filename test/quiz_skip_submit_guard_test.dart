import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:studexa/models/quiz_model.dart';
import 'package:studexa/screens/student/answer_quiz_screen.dart';

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

  group('Quiz Skip and Submission Guard Tests', () {
    final testQuiz = QuizModel(
      id: 'quiz_test_guard',
      classId: 'class_bio_101',
      teacherId: 'teacher_123',
      materialId: 'mat_123',
      title: 'Cellular Respiration Guard Test',
      type: 'practice',
      status: 'published',
      questions: const [
        QuizQuestion(
          id: 'q1',
          type: QuizQuestionType.multipleChoice,
          question: 'What is the powerhouse of the cell?',
          options: ['Mitochondria', 'Nucleus', 'Ribosome'],
          correctAnswer: 'Mitochondria',
          points: 1.0,
        ),
        QuizQuestion(
          id: 'q2',
          type: QuizQuestionType.trueFalse,
          question: 'Glycolysis occurs in mitochondria.',
          options: ['True', 'False'],
          correctAnswer: 'False',
          points: 1.0,
        ),
        QuizQuestion(
          id: 'q3',
          type: QuizQuestionType.fillInTheBlank,
          question: 'The energy molecule of the cell is ____.',
          correctAnswer: 'ATP',
          points: 1.0,
        ),
      ],
    );

    Widget createScreen() {
      return MaterialApp(
        home: AnswerQuizScreen(quiz: testQuiz),
      );
    }

    testWidgets('Skip button moves current question to the end of the round-robin queue', (tester) async {
      await tester.pumpWidget(createScreen());
      await tester.pumpAndSettle();

      // Starts on Q1
      expect(find.text('What is the powerhouse of the cell?'), findsOneWidget);
      expect(find.text('Question 1 of 3'), findsOneWidget);

      // Tap Skip on Q1
      final skipButton = find.widgetWithText(OutlinedButton, 'Skip');
      expect(skipButton, findsOneWidget);
      await tester.tap(skipButton);
      await tester.pumpAndSettle();

      // Q1 was moved to the end; Q2 is now presented
      expect(find.text('Glycolysis occurs in mitochondria.'), findsOneWidget);

      // Answer Q2
      await tester.tap(find.text('False'));
      await tester.pumpAndSettle();

      // Tap Next Question
      await tester.tap(find.text('Next Question'));
      await tester.pumpAndSettle();

      // Now on Q3
      expect(find.text('The energy molecule of the cell is ____.'), findsOneWidget);

      // Answer Q3
      await tester.enterText(find.byType(TextField), 'ATP');
      await tester.pumpAndSettle();

      // Tap Next Question
      await tester.tap(find.text('Next Question'));
      await tester.pumpAndSettle();

      // Skipped Q1 is now re-presented!
      expect(find.text('What is the powerhouse of the cell?'), findsOneWidget);

      // Verify submit state is NOT shown while skipped question is pending
      expect(find.text('Submit Quiz'), findsNothing);
      expect(find.text('Next Question'), findsOneWidget);

      // Now answer Q1
      await tester.tap(find.text('Mitochondria'));
      await tester.pumpAndSettle();

      // Submit button should now appear and be enabled
      final submitButtonFinder = find.widgetWithText(ElevatedButton, 'Submit Quiz');
      expect(submitButtonFinder, findsOneWidget);
      final enabledSubmitButton = tester.widget<ElevatedButton>(submitButtonFinder);
      expect(enabledSubmitButton.onPressed, isNotNull);
    });

    testWidgets('Submit Quiz button is disabled on last question if current question is unanswered', (tester) async {
      await tester.pumpWidget(createScreen());
      await tester.pumpAndSettle();

      // Answer Q1
      await tester.tap(find.text('Mitochondria'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next Question'));
      await tester.pumpAndSettle();

      // Answer Q2
      await tester.tap(find.text('False'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next Question'));
      await tester.pumpAndSettle();

      // On Q3 (last question), but not answered yet
      expect(find.text('The energy molecule of the cell is ____.'), findsOneWidget);
      expect(find.text('Submit Quiz'), findsOneWidget);

      // Button is disabled
      final submitBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Submit Quiz'));
      expect(submitBtn.onPressed, isNull);
      expect(find.textContaining('Answer all questions to enable submission (2 of 3 completed)'), findsOneWidget);

      // Answer Q3
      await tester.enterText(find.byType(TextField), 'ATP');
      await tester.pumpAndSettle();

      // Button is enabled
      final enabledBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Submit Quiz'));
      expect(enabledBtn.onPressed, isNotNull);
    });

    testWidgets('Tapping Next Question on end of queue with pending skipped questions routes back into unanswered question', (tester) async {
      await tester.pumpWidget(createScreen());
      await tester.pumpAndSettle();

      // Skip Q1
      await tester.tap(find.widgetWithText(OutlinedButton, 'Skip'));
      await tester.pumpAndSettle();

      // Answer Q2
      await tester.tap(find.text('False'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next Question'));
      await tester.pumpAndSettle();

      // Answer Q3
      await tester.enterText(find.byType(TextField), 'ATP');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next Question'));
      await tester.pumpAndSettle();

      // We are on skipped Q1 at the end of queue.
      expect(find.text('What is the powerhouse of the cell?'), findsOneWidget);
      expect(find.text('Next Question'), findsOneWidget);
      expect(find.text('Submit Quiz'), findsNothing);

      // Tap Next Question without answering
      await tester.tap(find.text('Next Question'));
      await tester.pumpAndSettle();

      // Routes directly back into Q1 and displays snackbar notice
      expect(find.text('What is the powerhouse of the cell?'), findsOneWidget);
      expect(find.textContaining('Returning to unanswered question'), findsOneWidget);
    });

    testWidgets('Submitting quiz displays Quiz Results dialog with both Done and Home action buttons', (tester) async {
      await tester.pumpWidget(createScreen());
      await tester.pumpAndSettle();

      // Q1: Answer
      await tester.tap(find.text('Mitochondria'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next Question'));
      await tester.pumpAndSettle();

      // Q2: Answer
      await tester.tap(find.text('False'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next Question'));
      await tester.pumpAndSettle();

      // Q3: Answer
      await tester.enterText(find.byType(TextField), 'ATP');
      await tester.pumpAndSettle();

      // Submit button is now enabled
      final submitBtn = find.widgetWithText(ElevatedButton, 'Submit Quiz');
      expect(submitBtn, findsOneWidget);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Confirm submit dialog
      expect(find.text('Submit Practice Quiz?'), findsOneWidget);
      final confirmSubmit = find.widgetWithText(ElevatedButton, 'Submit');
      await tester.tap(confirmSubmit);
      await tester.pumpAndSettle();

      // Results dialog appears
      expect(find.text('Quiz Results'), findsOneWidget);
      expect(find.text('Your Score'), findsOneWidget);

      // Verify both 'Done' and 'Home' action buttons are present and visible
      final doneBtn = find.widgetWithText(OutlinedButton, 'Done');
      final homeBtn = find.widgetWithText(ElevatedButton, 'Home');
      expect(doneBtn, findsOneWidget);
      expect(homeBtn, findsOneWidget);
    });

    testWidgets('Task 1: Question navigation indicator shows answered vs unanswered live and supports out-of-order answering', (tester) async {
      await tester.pumpWidget(createScreen());
      await tester.pumpAndSettle();

      // Verify initial unanswered state: 0 answered, 3 unanswered
      expect(find.text('0 answered'), findsOneWidget);
      expect(find.text('3 unanswered'), findsOneWidget);

      final badge1Finder = find.byKey(const ValueKey('question_badge_1'));
      final badge2Finder = find.byKey(const ValueKey('question_badge_2'));
      final badge3Finder = find.byKey(const ValueKey('question_badge_3'));

      expect(badge1Finder, findsOneWidget);
      expect(badge2Finder, findsOneWidget);
      expect(badge3Finder, findsOneWidget);

      // Check initial tooltip messages
      expect(
        find.byTooltip('Question 1: Unanswered (Current)'),
        findsOneWidget,
      );
      expect(
        find.byTooltip('Question 2: Unanswered'),
        findsOneWidget,
      );
      expect(
        find.byTooltip('Question 3: Unanswered'),
        findsOneWidget,
      );

      // ── Answer Q2 Out-of-Order ─────────────────────────────
      // Tap on Q2 badge in the strip to jump directly to Q2
      await tester.tap(badge2Finder);
      await tester.pumpAndSettle();

      expect(find.text('Glycolysis occurs in mitochondria.'), findsOneWidget);
      expect(
        find.byTooltip('Question 2: Unanswered (Current)'),
        findsOneWidget,
      );

      // Answer Q2
      await tester.tap(find.text('False'));
      await tester.pumpAndSettle();

      // Q2 should now be Answered live, Q1 & Q3 remain Unanswered
      expect(find.text('1 answered'), findsOneWidget);
      expect(find.text('2 unanswered'), findsOneWidget);
      expect(
        find.byTooltip('Question 2: Answered (Current)'),
        findsOneWidget,
      );
      expect(
        find.byTooltip('Question 1: Unanswered'),
        findsOneWidget,
      );
      expect(
        find.byTooltip('Question 3: Unanswered'),
        findsOneWidget,
      );

      // ── Answer Q3 Out-of-Order ─────────────────────────────
      // Tap on Q3 badge in the strip to jump directly to Q3
      await tester.tap(badge3Finder);
      await tester.pumpAndSettle();

      expect(find.text('The energy molecule of the cell is ____.'), findsOneWidget);
      expect(
        find.byTooltip('Question 3: Unanswered (Current)'),
        findsOneWidget,
      );

      // Type answer for Q3
      await tester.enterText(find.byType(TextField), 'ATP');
      await tester.pumpAndSettle();

      // Q3 is now Answered live
      expect(find.text('2 answered'), findsOneWidget);
      expect(find.text('1 unanswered'), findsOneWidget);
      expect(
        find.byTooltip('Question 3: Answered (Current)'),
        findsOneWidget,
      );
      expect(
        find.byTooltip('Question 2: Answered'),
        findsOneWidget,
      );
      expect(
        find.byTooltip('Question 1: Unanswered'),
        findsOneWidget,
      );

      // ── Answer Q1 Out-of-Order ─────────────────────────────
      // Tap on Q1 badge in the strip
      await tester.tap(badge1Finder);
      await tester.pumpAndSettle();

      expect(find.text('What is the powerhouse of the cell?'), findsOneWidget);
      expect(
        find.byTooltip('Question 1: Unanswered (Current)'),
        findsOneWidget,
      );

      // Answer Q1
      await tester.tap(find.text('Mitochondria'));
      await tester.pumpAndSettle();

      // All questions are now answered
      expect(find.text('3 answered'), findsOneWidget);
      expect(find.text('0 unanswered'), findsOneWidget);
      expect(
        find.byTooltip('Question 1: Answered (Current)'),
        findsOneWidget,
      );
      expect(
        find.byTooltip('Question 2: Answered'),
        findsOneWidget,
      );
      expect(
        find.byTooltip('Question 3: Answered'),
        findsOneWidget,
      );

      // ── Grid View Modal Test ───────────────────────────────
      await tester.tap(find.text('Grid View'));
      await tester.pumpAndSettle();

      expect(find.text('Question Overview'), findsOneWidget);
      expect(find.text('Answered (3)'), findsOneWidget);
      expect(find.text('Unanswered (0)'), findsOneWidget);

      // Close modal
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();
    });
  });
}
