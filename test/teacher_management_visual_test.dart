import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:studexa/models/class_model.dart';
import 'package:studexa/models/quiz_assignment_model.dart';
import 'package:studexa/models/quiz_attempt_model.dart';
import 'package:studexa/models/quiz_model.dart';
import 'package:studexa/screens/teacher/quiz_detail_screen.dart';
import 'package:studexa/screens/teacher/quiz_monitoring_screen.dart';
import 'package:studexa/screens/teacher/teacher_results_screen.dart';
import 'package:studexa/theme/app_theme.dart';

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

  final mockQuestions = [
    QuizQuestion(
      id: 'q_01',
      question: 'What is the time complexity of merge sort in the worst case?',
      type: QuizQuestionType.multipleChoice,
      options: ['O(n)', 'O(n log n)', 'O(n^2)', 'O(1)'],
      correctAnswer: 'O(n log n)',
      explanation: 'Merge sort always divides the array into halves and merges in linear time.',
      points: 2.0,
    ),
    QuizQuestion(
      id: 'q_02',
      question: 'Binary search requires an array to be sorted.',
      type: QuizQuestionType.trueFalse,
      options: ['True', 'False'],
      correctAnswer: 'True',
      explanation: 'Binary search works by comparing the target with the middle element of a sorted list.',
      points: 1.0,
    ),
    QuizQuestion(
      id: 'q_03',
      question: 'List three fundamental asymptotic notations.',
      type: QuizQuestionType.enumeration,
      options: const [],
      enumerationAnswers: ['Big O', 'Big Omega', 'Big Theta'],
      correctAnswer: 'Big O, Big Omega, Big Theta',
      explanation: 'These represent upper, lower, and tight bounds respectively.',
      points: 3.0,
    ),
    QuizQuestion(
      id: 'q_04',
      question: 'Name the data structure that follows LIFO order.',
      type: QuizQuestionType.identification,
      options: const [],
      correctAnswer: 'Stack',
      explanation: 'Last In, First Out is implemented using a Stack.',
      points: 1.0,
    ),
  ];

  final mockQuiz = QuizModel(
    id: 'quiz_algo_01',
    classId: 'class_cs101',
    teacherId: 'teacher_123',
    materialId: 'mat_01',
    type: 'practice',
    title: 'Algorithms & Complexity Exam',
    status: 'published',
    questions: mockQuestions,
    createdAt: DateTime(2026, 1, 22),
    updatedAt: DateTime(2026, 1, 22),
  );

  final mockStudents = [
    ClassMember(
      userId: 'student_01',
      displayName: 'Alice Walker',
      email: 'alice@studexa.edu',
      role: 'student',
      joinedAt: DateTime(2026, 1, 16),
    ),
    ClassMember(
      userId: 'student_02',
      displayName: 'Bob Martinez',
      email: 'bob@studexa.edu',
      role: 'student',
      joinedAt: DateTime(2026, 1, 16),
    ),
  ];

  final List<QuizAttemptModel> mockAttempts = [
    QuizAttemptModel(
      id: 'attempt_01',
      quizId: 'quiz_algo_01',
      classId: 'class_cs101',
      studentId: 'student_01',
      studentName: 'Alice Walker',
      score: 7.0,
      totalPoints: 7.0,
      percentage: 100.0,
      submittedAt: DateTime(2026, 1, 23, 14, 30),
      breakdown: [
        {
          'questionId': 'q_01',
          'userAnswer': 'O(n log n)',
          'correctAnswer': 'O(n log n)',
          'isCorrect': true,
          'earned': 2.0,
          'points': 2.0,
        },
        {
          'questionId': 'q_02',
          'userAnswer': 'True',
          'correctAnswer': 'True',
          'isCorrect': true,
          'earned': 1.0,
          'points': 1.0,
        },
      ],
    ),
  ];

  final mockClass = ClassModel(
    id: 'class_cs101',
    name: 'CS 101 - Intro to Programming',
    joinCode: 'CS101',
    teacherId: 'teacher_123',
    teacherName: 'Prof. Turing',
  );

  final mockAssignment = QuizAssignmentModel(
    id: 'assign_01',
    quizId: 'quiz_algo_01',
    classId: 'class_cs101',
    teacherId: 'teacher_123',
    quizTitle: 'Algorithms & Complexity Exam',
    isClosed: false,
    deadline: DateTime(2026, 2, 1),
    createdAt: DateTime(2026, 1, 22),
  );

  Widget buildTestApp(Widget child, {Key? boundaryKey}) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: RepaintBoundary(
        key: boundaryKey,
        child: child,
      ),
    );
  }

  Future<void> captureScreenshot(
    WidgetTester tester,
    GlobalKey boundaryKey,
    String filename,
  ) async {
    await tester.runAsync(() async {
      final boundary = boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 1.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final dir = Directory(
            r'C:\Users\FLYNNE EJ\.gemini\antigravity\brain\b67e6326-7873-4bee-8301-e3bdf7e5f251',
          );
          final file = File('${dir.path}/$filename');
          await file.writeAsBytes(byteData.buffer.asUint8List());
        }
      }
    });
  }

  group('Batch 3: Teacher Quiz Management & Analytics Visual Verification', () {
    testWidgets('QuizDetailScreen renders cleanly on 375px and 1440px',
        (tester) async {
      // 1. Mobile (375x812)
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;

      final key375 = GlobalKey();
      await tester.pumpWidget(buildTestApp(
        QuizDetailScreen(
          quiz: mockQuiz,
          initialClass: mockClass,
        ),
        boundaryKey: key375,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Algorithms & Complexity Exam'), findsOneWidget);
      expect(find.text('Q1'), findsOneWidget);
      expect(find.text('Print Exam'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await captureScreenshot(tester, key375, 'batch3_quiz_detail_375px.png');

      // 2. Desktop (1440x900)
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;

      final key1440 = GlobalKey();
      await tester.pumpWidget(buildTestApp(
        QuizDetailScreen(
          quiz: mockQuiz,
          initialClass: mockClass,
        ),
        boundaryKey: key1440,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Algorithms & Complexity Exam'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await captureScreenshot(tester, key1440, 'batch3_quiz_detail_1440px.png');

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    });

    testWidgets('QuizMonitoringScreen renders cleanly on 375px and 1440px',
        (tester) async {
      // 1. Mobile (375x812)
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;

      final key375 = GlobalKey();
      await tester.pumpWidget(buildTestApp(
        QuizMonitoringScreen(
          quiz: mockQuiz,
          className: 'CS 101 - Intro to Programming',
          initialMembersStream: Stream.value(mockStudents),
          initialAttemptsStream: Stream.value(mockAttempts),
          initialAssignment: mockAssignment,
        ),
        boundaryKey: key375,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Quiz Monitoring'), findsOneWidget);
      expect(find.text('Assignment Status'), findsOneWidget);
      expect(find.text('Student Submissions'), findsOneWidget);
      expect(find.text('Alice Walker'), findsOneWidget);
      expect(find.text('Bob Martinez'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await captureScreenshot(
        tester,
        key375,
        'batch3_quiz_monitoring_375px.png',
      );

      // 2. Desktop (1440x900)
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;

      final key1440 = GlobalKey();
      await tester.pumpWidget(buildTestApp(
        QuizMonitoringScreen(
          quiz: mockQuiz,
          className: 'CS 101 - Intro to Programming',
          initialMembersStream: Stream.value(mockStudents),
          initialAttemptsStream: Stream.value(mockAttempts),
          initialAssignment: mockAssignment,
        ),
        boundaryKey: key1440,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Quiz Monitoring'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await captureScreenshot(
        tester,
        key1440,
        'batch3_quiz_monitoring_1440px.png',
      );

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    });

    testWidgets('TeacherResultsScreen renders cleanly on 375px and 1440px',
        (tester) async {
      // 1. Mobile (375x812)
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;

      final key375 = GlobalKey();
      await tester.pumpWidget(buildTestApp(
        TeacherResultsScreen(
          classId: 'class_cs101',
          className: 'CS 101 - Intro to Programming',
          quizTitle: 'Algorithms & Complexity Exam',
          initialMembersStream: Stream.value(mockStudents),
        ),
        boundaryKey: key375,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Quiz Results'), findsOneWidget);
      expect(find.text('Enrolled Students'), findsOneWidget);
      expect(find.text('Alice Walker'), findsOneWidget);
      expect(find.text('Bob Martinez'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await captureScreenshot(
        tester,
        key375,
        'batch3_teacher_results_375px.png',
      );

      // 2. Desktop (1440x900)
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;

      final key1440 = GlobalKey();
      await tester.pumpWidget(buildTestApp(
        TeacherResultsScreen(
          classId: 'class_cs101',
          className: 'CS 101 - Intro to Programming',
          quizTitle: 'Algorithms & Complexity Exam',
          initialMembersStream: Stream.value(mockStudents),
        ),
        boundaryKey: key1440,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Quiz Results'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await captureScreenshot(
        tester,
        key1440,
        'batch3_teacher_results_1440px.png',
      );

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    });
  });
}
