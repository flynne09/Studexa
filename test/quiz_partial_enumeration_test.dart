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

  group('Task 3 — Partial Enumeration Progress and Submission Tests', () {
    final testQuiz = QuizModel(
      id: 'quiz_partial_enum_test',
      classId: 'class_bio_101',
      teacherId: 'teacher_101',
      materialId: 'mat_101',
      title: 'Cellular Respiration Partial Credit Test',
      type: 'practice',
      status: 'published',
      questions: const [
        QuizQuestion(
          id: 'q1',
          type: QuizQuestionType.multipleChoice,
          question: 'Where does glycolysis occur?',
          options: ['Cytoplasm', 'Mitochondria', 'Nucleus'],
          correctAnswer: 'Cytoplasm',
          points: 1.0,
        ),
        QuizQuestion(
          id: 'q2',
          type: QuizQuestionType.enumeration,
          question: 'Enumerate the three stages of respiration:',
          enumerationAnswers: ['Glycolysis', 'Krebs Cycle', 'Electron Transport Chain'],
          points: 3.0,
        ),
        QuizQuestion(
          id: 'q3',
          type: QuizQuestionType.trueFalse,
          question: 'ATP synthase produces ATP.',
          options: ['True', 'False'],
          correctAnswer: 'True',
          points: 1.0,
        ),
      ],
    );

    testWidgets('Student enters 1 of 3 enumeration items, proceeds, and submits quiz receiving partial credit', (tester) async {
      final assignmentService = AssignmentService(useFirestore: false);

      await tester.pumpWidget(
        MaterialApp(
          home: AnswerQuizScreen(
            quiz: testQuiz,
            attemptNumber: 1,
            assignmentService: assignmentService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Q1: Answer correctly ('Cytoplasm')
      expect(find.text('Where does glycolysis occur?'), findsOneWidget);
      await tester.tap(find.text('Cytoplasm'));
      await tester.pumpAndSettle();

      // Advance to Q2 (Enumeration)
      await tester.tap(find.text('Next Question'));
      await tester.pumpAndSettle();

      expect(find.text('Enumerate the three stages of respiration:'), findsOneWidget);

      // Enter only 1 item: 'Glycolysis'
      await tester.enterText(
        find.widgetWithText(TextField, 'Type item and tap Add...'),
        'Glycolysis',
      );
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // Verify chip and partial credit guidance
      expect(find.text('Glycolysis'), findsWidgets);
      expect(find.text('1 item added — partial credit enabled'), findsOneWidget);

      // Verify Q2 is recognized as Answered in the live progress strip
      expect(find.text('2 answered'), findsOneWidget);
      expect(find.text('1 unanswered'), findsOneWidget);

      // Proceed to Q3 — must NOT be blocked by any validation
      await tester.tap(find.text('Next Question'));
      await tester.pumpAndSettle();

      expect(find.text('ATP synthase produces ATP.'), findsOneWidget);

      // Q3: Answer correctly ('True')
      await tester.tap(find.text('True'));
      await tester.pumpAndSettle();

      // Verify all 3 questions are recognized as answered
      expect(find.text('3 answered'), findsOneWidget);
      expect(find.text('0 unanswered'), findsOneWidget);

      // Submit quiz — button must be active and not blocked
      final submitButton = find.widgetWithText(ElevatedButton, 'Submit Quiz');
      expect(submitButton, findsOneWidget);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // Confirm in dialog
      final confirmSubmit = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Submit'),
      );
      expect(confirmSubmit, findsOneWidget);
      await tester.tap(confirmSubmit);
      await tester.pumpAndSettle();

      // Results dialog should appear
      expect(find.text('Quiz Results'), findsOneWidget);

      // Total earned: 1.0 (Q1) + 1.0 (Q2: 1/3 of 3.0 pts) + 1.0 (Q3) = 3.0 / 5
      expect(find.text('3.0 / 5'), findsOneWidget);
      expect(find.text('60%'), findsOneWidget);

      // Review breakdown displays partial credit details
      expect(find.text('Found: Glycolysis'), findsOneWidget);
      expect(find.text('Missing: Krebs Cycle, Electron Transport Chain'), findsOneWidget);
      expect(find.text('1.0 / 3 pt'), findsOneWidget);
    });

    testWidgets('Typed enumeration item without tapping Add is auto-committed when advancing or submitting', (tester) async {
      final assignmentService = AssignmentService(useFirestore: false);

      await tester.pumpWidget(
        MaterialApp(
          home: AnswerQuizScreen(
            quiz: testQuiz,
            attemptNumber: 1,
            assignmentService: assignmentService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Q1: Answer Cytoplasm
      await tester.tap(find.text('Cytoplasm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next Question'));
      await tester.pumpAndSettle();

      // Q2: Type 'Krebs Cycle' but DO NOT tap Add
      await tester.enterText(
        find.widgetWithText(TextField, 'Type item and tap Add...'),
        'Krebs Cycle',
      );
      await tester.pumpAndSettle();

      // Tap Next Question — _saveCurrentAnswer commits 'Krebs Cycle'
      await tester.tap(find.text('Next Question'));
      await tester.pumpAndSettle();

      // Now on Q3; Q2 should be counted as answered!
      expect(find.text('ATP synthase produces ATP.'), findsOneWidget);
      expect(find.text('2 answered'), findsOneWidget);

      // Go back to Q2 to verify 'Krebs Cycle' chip is there
      await tester.tap(find.text('Previous'));
      await tester.pumpAndSettle();
      expect(find.text('Krebs Cycle'), findsWidgets);
    });
  });
}
