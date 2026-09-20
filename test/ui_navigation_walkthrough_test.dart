import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:studexa/models/class_model.dart';
import 'package:studexa/models/quiz_model.dart';
import 'package:studexa/screens/auth/role_selection_screen.dart';
import 'package:studexa/screens/auth/login_screen.dart';
import 'package:studexa/screens/auth/register_screen.dart';
import 'package:studexa/screens/teacher/teacher_class_details_screen.dart';
import 'package:studexa/screens/teacher/upload_generate_quiz_screen.dart';
import 'package:studexa/screens/teacher/quiz_detail_screen.dart';
import 'package:studexa/screens/teacher/quiz_monitoring_screen.dart';
import 'package:studexa/screens/student/student_class_details_screen.dart';
import 'package:studexa/screens/student/join_class_screen.dart';
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

  // Reusable test models
  final testClass = ClassModel(
    id: 'test_class_101',
    name: 'General Biology',
    section: 'Section B',
    subject: 'Life Sciences',
    joinCode: 'BIO-8942',
    teacherId: 'teacher_mock_id',
    teacherName: 'Prof. Smith',
    rosterCount: 1,
    createdAt: DateTime.now(),
  );

  final testQuiz = QuizModel(
    id: 'quiz_test_101',
    classId: 'test_class_101',
    teacherId: 'teacher_mock_id',
    materialId: 'mat_101',
    title: 'Cellular Respiration & Bioenergetics',
    type: 'practice',
    status: 'draft',
    generationMethod: 'gemini',
    totalPoints: 10.0,
    questions: [
      QuizQuestion(
        id: 'q1',
        type: QuizQuestionType.multipleChoice,
        question: 'Which organelle is known as the powerhouse of the cell?',
        options: ['Nucleus', 'Mitochondria', 'Ribosome', 'Golgi apparatus'],
        correctAnswer: 'Mitochondria',
        explanation: 'Mitochondria generate ATP via cellular respiration.',
        points: 2.0,
      ),
      QuizQuestion(
        id: 'q2',
        type: QuizQuestionType.trueFalse,
        question: 'Glycolysis requires oxygen to proceed.',
        options: ['True', 'False'],
        correctAnswer: 'False',
        explanation: 'Glycolysis is an anaerobic process.',
        points: 1.0,
      ),
      QuizQuestion(
        id: 'q3',
        type: QuizQuestionType.fillInTheBlank,
        question: 'The primary energy currency of the cell is ____.',
        correctAnswer: 'ATP',
        explanation: 'Adenosine triphosphate stores usable biological energy.',
        points: 2.0,
      ),
      QuizQuestion(
        id: 'q4',
        type: QuizQuestionType.identification,
        question: 'Identify the enzyme that synthesizes ATP from ADP and Pi.',
        correctAnswer: 'ATP Synthase',
        explanation: 'ATP Synthase operates via proton motive force.',
        points: 2.0,
      ),
      QuizQuestion(
        id: 'q5',
        type: QuizQuestionType.enumeration,
        question: 'Enumerate three major stages of cellular respiration.',
        enumerationAnswers: ['Glycolysis', 'Krebs Cycle', 'Electron Transport Chain'],
        correctAnswer: 'Glycolysis, Krebs Cycle, Electron Transport Chain',
        explanation: 'The three aerobic cellular respiration stages.',
        points: 3.0,
      ),
    ],
    createdAt: DateTime.now(),
  );

  group('UI Navigation Walkthrough — Screen Layout & Navigation Tests', () {
    testWidgets('1. RoleSelectionScreen renders logo, branding, and role options', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RoleSelectionScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Studexa'), findsOneWidget);
      expect(find.text('Choose Your Role'), findsOneWidget);
      expect(find.text('Teacher'), findsOneWidget);
      expect(find.text('Student'), findsOneWidget);
      expect(find.byIcon(Icons.school_outlined), findsOneWidget);
      expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    });

    testWidgets('2. LoginScreen renders inputs, validation, and navigates to Register', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(role: 'Teacher'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Studexa'), findsOneWidget);
      expect(find.text('Logging in as Teacher'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Log In'), findsOneWidget);

      // Attempt submit without filling fields -> triggers validation error
      await tester.tap(find.text('Log In'));
      await tester.pumpAndSettle();
      expect(find.text('Please enter your email address.'), findsOneWidget);

      // Verify register link is present
      expect(find.text("Don't have an account? "), findsOneWidget);
      expect(find.text('Register'), findsOneWidget);
    });

    testWidgets('3. RegisterScreen renders segmented role toggle and form fields', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RegisterScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create Your Account'), findsOneWidget);
      expect(find.text('Student'), findsWidgets);
      expect(find.text('Teacher'), findsWidgets);
      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('Email'), findsWidgets);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Confirm Password'), findsOneWidget);

      // Toggle role from Student to Teacher
      await tester.tap(find.text('Teacher').first);
      await tester.pumpAndSettle();

      // Enter mismatched passwords to test validation
      await tester.enterText(find.byType(TextField).at(0), 'John Doe');
      await tester.enterText(find.byType(TextField).at(1), 'john@test.edu');
      await tester.enterText(find.byType(TextField).at(2), 'secret123');
      await tester.enterText(find.byType(TextField).at(3), 'different123');

      final registerBtn = find.widgetWithText(ElevatedButton, 'Register');
      await tester.ensureVisible(registerBtn);
      await tester.pumpAndSettle();
      await tester.tap(registerBtn);
      await tester.pumpAndSettle();
      expect(find.text('Passwords do not match. Please verify and try again.'), findsOneWidget);
    });

    testWidgets('4. TeacherClassDetailsScreen renders class header, tabs, and FAB', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TeacherClassDetailsScreen(classModel: testClass),
        ),
      );
      await tester.pump();

      expect(find.text('General Biology'), findsWidgets);
      expect(find.text('BIO-8942'), findsOneWidget);
      expect(find.text('Materials'), findsOneWidget);
      expect(find.text('Quizzes'), findsOneWidget);
      expect(find.text('Students'), findsOneWidget);

      // Switch to Quizzes tab
      await tester.tap(find.text('Quizzes'));
      await tester.pump();

      // Switch to Students tab
      await tester.tap(find.text('Students'));
      await tester.pump();

      // Switch back to Materials tab
      await tester.tap(find.text('Materials'));
      await tester.pump();

      // Verify locked upload FAB
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('5. UploadGenerateQuizScreen renders locked class banner and question formats', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: UploadGenerateQuizScreen(
            preselectedClass: testClass,
            isClassLocked: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Generate Quiz'), findsOneWidget);
      expect(find.text('Assign to Class'), findsOneWidget);
      expect(find.text('General Biology'), findsWidgets);
      expect(find.text('Question Types'), findsOneWidget);
      expect(find.text('Multiple Choice'), findsOneWidget);
      expect(find.text('True/False'), findsOneWidget);
      expect(find.text('Fill-in-the-Blank'), findsOneWidget);
      expect(find.text('Identification'), findsOneWidget);
      expect(find.text('Enumeration'), findsOneWidget);

      // Toggle a format
      final fillFormat = find.text('Fill-in-the-Blank');
      await tester.ensureVisible(fillFormat);
      await tester.pumpAndSettle();
      await tester.tap(fillFormat);
      await tester.pump();

      // Verify generation action buttons are present
      expect(find.text('Generate Actual Quiz (PDF Exam)'), findsOneWidget);
      expect(find.text('Generate Practice Quiz (App Practice)'), findsOneWidget);
    });

    testWidgets('6. QuizDetailScreen renders all 5 question types, points, and print modal', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: QuizDetailScreen(quiz: testQuiz),
        ),
      );
      await tester.pump();

      expect(find.text('Cellular Respiration & Bioenergetics'), findsWidgets);
      expect(find.text('Draft'), findsOneWidget);
      expect(find.text('AI Generated'), findsOneWidget);
      expect(find.text('5 Questions'), findsOneWidget);
      expect(find.text('10 Pts'), findsOneWidget);

      // Verify question list contains questions
      expect(find.text('Which organelle is known as the powerhouse of the cell?'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Glycolysis requires oxygen to proceed.'),
        80,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Glycolysis requires oxygen to proceed.'), findsOneWidget);

      // Verify actions
      expect(find.text('Publish to Class'), findsOneWidget);
      expect(find.text('Print Exam'), findsOneWidget);

      // Tap "Print Exam" to test the export options modal
      await tester.tap(find.text('Print Exam'));
      await tester.pumpAndSettle();

      expect(find.text('Print Exam (PDF)'), findsOneWidget);
      expect(find.text('Include Teacher Answer Key'), findsOneWidget);
      expect(find.text('Generate & Print'), findsOneWidget);

      // Dismiss modal
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('7. QuizMonitoringScreen renders submission metrics and controls', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: QuizMonitoringScreen(
            quiz: testQuiz,
            className: 'General Biology',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Quiz Monitoring'), findsOneWidget);
      expect(find.text('Completion'), findsOneWidget);
      expect(find.text('Average Score'), findsOneWidget);
      expect(find.text('Assignment Status'), findsOneWidget);
      expect(find.text('Set Deadline'), findsOneWidget);
    });

    testWidgets('8. StudentClassDetailsScreen renders class tabs and views', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StudentClassDetailsScreen(classModel: testClass),
        ),
      );
      await tester.pump();

      expect(find.text('General Biology'), findsWidgets);
      expect(find.text('Instructor: Prof. Smith'), findsOneWidget);
      expect(find.text('Materials'), findsOneWidget);
      expect(find.text('Quizzes'), findsOneWidget);
      expect(find.text('Class Info'), findsOneWidget);

      // Switch to Quizzes tab
      await tester.tap(find.text('Quizzes'));
      await tester.pump();

      // Switch to Class Info tab
      await tester.tap(find.text('Class Info'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('9. JoinClassScreen renders input and join button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: JoinClassScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Join a Class'), findsOneWidget);
      expect(find.text('Enter Class Join Code'), findsOneWidget);
      expect(find.text('Join Class'), findsOneWidget);

      // Type join code
      await tester.enterText(find.byType(TextField), 'BIO-8942');
      await tester.pump();
      expect(find.text('BIO-8942'), findsOneWidget);
    });

    testWidgets('10. AnswerQuizScreen interacts through all 5 question types and submit', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AnswerQuizScreen(quiz: testQuiz),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cellular Respiration & Bioenergetics'), findsOneWidget);
      expect(find.text('Question 1 of 5'), findsOneWidget);
      expect(find.text('Which organelle is known as the powerhouse of the cell?'), findsOneWidget);

      // 1. Multiple Choice: Select 'Mitochondria'
      await tester.tap(find.text('Mitochondria'));
      await tester.pumpAndSettle();

      // Tap Next Question
      await tester.tap(find.text('Next Question'));
      await tester.pumpAndSettle();

      // 2. True/False: Select 'False'
      expect(find.text('Question 2 of 5'), findsOneWidget);
      expect(find.text('Glycolysis requires oxygen to proceed.'), findsOneWidget);
      await tester.tap(find.text('False'));
      await tester.pumpAndSettle();

      // Tap Next Question
      await tester.tap(find.text('Next Question'));
      await tester.pumpAndSettle();

      // 3. Fill-in-the-Blank: Enter 'ATP'
      expect(find.text('Question 3 of 5'), findsOneWidget);
      expect(find.text('The primary energy currency of the cell is ____.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'ATP');
      await tester.pumpAndSettle();

      // Tap Next Question
      await tester.tap(find.text('Next Question'));
      await tester.pumpAndSettle();

      // 4. Identification: Enter 'ATP Synthase'
      expect(find.text('Question 4 of 5'), findsOneWidget);
      expect(find.text('Identify the enzyme that synthesizes ATP from ADP and Pi.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'ATP Synthase');
      await tester.pumpAndSettle();

      // Tap Next Question
      await tester.tap(find.text('Next Question'));
      await tester.pumpAndSettle();

      // 5. Enumeration: Enter items
      expect(find.text('Question 5 of 5'), findsOneWidget);
      expect(find.text('Enumerate three major stages of cellular respiration.'), findsOneWidget);
      expect(find.text('Submit Quiz'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Type item and tap Add...'), 'Glycolysis');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('Glycolysis'), findsWidgets);

      await tester.enterText(find.widgetWithText(TextField, 'Type item and tap Add...'), 'Krebs Cycle');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('Krebs Cycle'), findsWidgets);

      await tester.enterText(find.widgetWithText(TextField, 'Type item and tap Add...'), 'Electron Transport Chain');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('Electron Transport Chain'), findsWidgets);

      // Verify submit button is active on the last question
      expect(find.text('Submit Quiz'), findsOneWidget);
    });
  });
}

