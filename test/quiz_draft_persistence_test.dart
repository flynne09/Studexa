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

  group('Task 2 — Quiz Draft Answers Persistence Tests', () {
    final testQuiz = QuizModel(
      id: 'quiz_draft_persist_test',
      classId: 'class_cs_101',
      teacherId: 'teacher_001',
      materialId: 'mat_001',
      title: 'Operating Systems Quiz',
      type: 'practice',
      status: 'published',
      questions: const [
        QuizQuestion(
          id: 'q1',
          type: QuizQuestionType.multipleChoice,
          question: 'What handles CPU scheduling?',
          options: ['OS Kernel', 'Web Browser', 'Compiler'],
          correctAnswer: 'OS Kernel',
          points: 1.0,
        ),
        QuizQuestion(
          id: 'q2',
          type: QuizQuestionType.fillInTheBlank,
          question: 'A running program in memory is called a _______.',
          correctAnswer: 'process',
          points: 1.0,
        ),
        QuizQuestion(
          id: 'q3',
          type: QuizQuestionType.enumeration,
          question: 'Enumerate two process states:',
          enumerationAnswers: ['Running', 'Ready'],
          points: 2.0,
        ),
      ],
    );

    testWidgets('Draft answers are persisted on dispose and restored on reopen with correct scoring', (tester) async {
      final assignmentService = AssignmentService(useFirestore: false);

      // Ensure fresh draft state
      await assignmentService.clearDraftAnswers(
        studentId: 'guest_student',
        quizId: 'quiz_draft_persist_test',
        attemptNumber: 1,
      );

      // ── Step 1: Open Quiz for Attempt 1 ──────────────────────────────
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

      // Q1 (Multiple Choice): Answer 'OS Kernel'
      expect(find.text('What handles CPU scheduling?'), findsOneWidget);
      await tester.tap(find.text('OS Kernel'));
      await tester.pumpAndSettle();

      // Advance to Q2
      await tester.tap(find.text('Next Question'));
      await tester.pumpAndSettle();

      // Q2 (Fill in the Blank): Enter 'process'
      expect(find.text('A running program in memory is called a _______.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'process');
      await tester.pumpAndSettle();

      // Advance to Q3
      await tester.tap(find.text('Next Question'));
      await tester.pumpAndSettle();

      // Q3 (Enumeration): Add one item 'Running'
      expect(find.text('Enumerate two process states:'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Running');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('Running'), findsOneWidget);

      // Verify draft in assignmentService has all 3 answers
      final draftsBeforeExit = await assignmentService.getDraftAnswers(
        studentId: 'guest_student',
        quizId: 'quiz_draft_persist_test',
        attemptNumber: 1,
      );
      expect(draftsBeforeExit, isNotNull);
      expect(draftsBeforeExit!['q1'], equals('OS Kernel'));
      expect(draftsBeforeExit['q2'], equals('process'));
      expect(draftsBeforeExit['q3'], equals(['Running']));

      // ── Step 2: Simulate Closing the Quiz (Dispose) ───────────────────
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Closed Screen')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Closed Screen'), findsOneWidget);

      // ── Step 3: Reopen the Quiz Screen for Same Attempt ───────────────
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

      // Badges: Q1, Q2, and Q3 should all be restored as answered!
      expect(find.text('3 answered'), findsOneWidget);
      expect(find.text('0 unanswered'), findsOneWidget);

      // Check Q1 is selected as 'OS Kernel'
      expect(find.text('What handles CPU scheduling?'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsWidgets);

      // Check Q2 restores text
      await tester.tap(find.text('Next Question'));
      await tester.pumpAndSettle();
      expect(find.text('process'), findsOneWidget);

      // Check Q3 restores enumeration chips
      await tester.tap(find.text('Next Question'));
      await tester.pumpAndSettle();
      expect(find.text('Running'), findsOneWidget);

      // Add second item 'Ready' to Q3
      await tester.enterText(find.byType(TextField), 'Ready');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('Ready'), findsOneWidget);

      // ── Step 4: Submit the Quiz ───────────────────────────────────────
      // Last question reached; Submit Quiz button should be visible and clickable
      final submitButton = find.widgetWithText(ElevatedButton, 'Submit Quiz');
      expect(submitButton, findsOneWidget);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // In confirmation dialog, tap Submit
      final confirmSubmit = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Submit'),
      );
      expect(confirmSubmit, findsOneWidget);
      await tester.tap(confirmSubmit);
      await tester.pumpAndSettle();

      // Results dialog should be displayed with 100% score (4.0 / 4)
      expect(find.text('Quiz Results'), findsOneWidget);
      expect(find.text('4.0 / 4'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);

      // ── Step 5: Verify Draft is Cleared on Submit ─────────────────────
      final draftsAfterSubmit = await assignmentService.getDraftAnswers(
        studentId: 'guest_student',
        quizId: 'quiz_draft_persist_test',
        attemptNumber: 1,
      );
      expect(draftsAfterSubmit, isNull);
    });
  });
}
