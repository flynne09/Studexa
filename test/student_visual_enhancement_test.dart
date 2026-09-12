import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:studexa/models/class_model.dart';
import 'package:studexa/models/material_model.dart';
import 'package:studexa/models/quiz_model.dart';
import 'package:studexa/screens/materials/material_viewer_screen.dart';
import 'package:studexa/screens/student/answer_quiz_screen.dart';
import 'package:studexa/screens/student/join_class_screen.dart';
import 'package:studexa/screens/student/student_class_details_screen.dart';
import 'package:studexa/screens/student/student_home_screen.dart';
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
    const QuizQuestion(
      id: 'q_01',
      question: 'Which cellular organelle produces ATP through oxidative phosphorylation?',
      type: QuizQuestionType.multipleChoice,
      options: ['A. Nucleus', 'B. Mitochondria', 'C. Ribosome', 'D. Golgi'],
      correctAnswer: 'B. Mitochondria',
      points: 1.0,
    ),
    const QuizQuestion(
      id: 'q_02',
      question: 'Glycolysis takes place in the cytoplasm of the cell.',
      type: QuizQuestionType.trueFalse,
      options: ['True', 'False'],
      correctAnswer: 'True',
      points: 1.0,
    ),
    const QuizQuestion(
      id: 'q_03',
      question: 'Enumerate the three primary stages of cellular respiration.',
      type: QuizQuestionType.enumeration,
      enumerationAnswers: ['Glycolysis', 'Krebs Cycle', 'Electron Transport Chain'],
      points: 3.0,
    ),
  ];

  final mockQuiz = QuizModel(
    id: 'quiz_bio_101',
    classId: 'class_bio101',
    teacherId: 'teacher_123',
    materialId: 'mat_01',
    type: 'practice',
    title: 'Cellular Respiration & ATP Synthesis',
    status: 'published',
    questions: mockQuestions,
    createdAt: DateTime(2026, 1, 20),
    updatedAt: DateTime(2026, 1, 20),
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

  final mockClass = ClassModel(
    id: 'class_bio101',
    name: 'General Biology I',
    joinCode: 'BIO101',
    teacherId: 'teacher_123',
    teacherName: 'Dr. Rosalind Franklin',
  );

  final mockMaterial = MaterialModel(
    id: 'mat_01',
    teacherId: 'teacher_123',
    classId: 'class_bio101',
    fileName: 'Lecture_Cellular_Energy.pptx',
    fileType: 'pptx',
    fileRef: 'uploads/teacher_123/mat_01/Lecture_Cellular_Energy.pptx',
    status: 'ready',
    conversionStatus: 'completed',
    extractedText: 'Chapter 7: Cellular Respiration and Fermentation.\n\nKey Concepts:\n1. Catabolic pathways yield energy by oxidizing organic fuels.\n2. Glycolysis harvests chemical energy by oxidizing glucose to pyruvate.\n3. The citric acid cycle completes the energy-yielding oxidation of organic molecules.\n4. Chemiosmosis couples electron transport to ATP synthesis.',
    createdAt: DateTime(2026, 1, 18),
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

  group('Batch 4: Student Core Experience Visual Verification', () {
    testWidgets('StudentHomeScreen renders cleanly on 375px and 1440px',
        (tester) async {
      // 1. Mobile (375x812)
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;

      final key375 = GlobalKey();
      await tester.pumpWidget(buildTestApp(
        StudentHomeScreen(
          initialClassesStream: Stream.value([mockClass]),
        ),
        boundaryKey: key375,
      ));
      await tester.pumpAndSettle();

      expect(find.text('General Biology I'), findsOneWidget);
      expect(find.text('Join Class'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await captureScreenshot(tester, key375, 'batch4_student_home_375px.png');

      // 2. Desktop (1440x900)
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;

      final key1440 = GlobalKey();
      await tester.pumpWidget(buildTestApp(
        StudentHomeScreen(
          initialClassesStream: Stream.value([mockClass]),
        ),
        boundaryKey: key1440,
      ));
      await tester.pumpAndSettle();

      expect(find.text('General Biology I'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await captureScreenshot(tester, key1440, 'batch4_student_home_1440px.png');

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    });

    testWidgets('StudentClassDetailsScreen renders cleanly on 375px and 1440px',
        (tester) async {
      // 1. Mobile (375x812)
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;

      final key375 = GlobalKey();
      await tester.pumpWidget(buildTestApp(
        StudentClassDetailsScreen(
          classModel: mockClass,
          initialClassStream: Stream.value(mockClass),
          initialMaterialsStream: Stream.value([mockMaterial]),
          initialQuizzesStream: Stream.value([mockQuiz]),
          initialPeopleStream: Stream.value(mockStudents),
        ),
        boundaryKey: key375,
      ));
      await tester.pumpAndSettle();

      expect(find.text('General Biology I'), findsWidgets);
      expect(find.text('Quizzes'), findsOneWidget);
      expect(find.text('Materials'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await captureScreenshot(tester, key375, 'batch4_student_class_details_375px.png');

      // 2. Desktop (1440x900)
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;

      final key1440 = GlobalKey();
      await tester.pumpWidget(buildTestApp(
        StudentClassDetailsScreen(
          classModel: mockClass,
          initialClassStream: Stream.value(mockClass),
          initialMaterialsStream: Stream.value([mockMaterial]),
          initialQuizzesStream: Stream.value([mockQuiz]),
          initialPeopleStream: Stream.value(mockStudents),
        ),
        boundaryKey: key1440,
      ));
      await tester.pumpAndSettle();

      expect(find.text('General Biology I'), findsWidgets);
      expect(tester.takeException(), isNull);

      await captureScreenshot(tester, key1440, 'batch4_student_class_details_1440px.png');

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    });

    testWidgets('JoinClassScreen renders cleanly on 375px and 1440px',
        (tester) async {
      // 1. Mobile (375x812)
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;

      final key375 = GlobalKey();
      await tester.pumpWidget(buildTestApp(
        const JoinClassScreen(),
        boundaryKey: key375,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Join a Class'), findsOneWidget);
      expect(find.text('Enter Class Join Code'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await captureScreenshot(tester, key375, 'batch4_join_class_375px.png');

      // 2. Desktop (1440x900)
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;

      final key1440 = GlobalKey();
      await tester.pumpWidget(buildTestApp(
        const JoinClassScreen(),
        boundaryKey: key1440,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Join a Class'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await captureScreenshot(tester, key1440, 'batch4_join_class_1440px.png');

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    });

    testWidgets('AnswerQuizScreen renders cleanly on 375px and 1440px',
        (tester) async {
      // 1. Mobile (375x812)
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;

      final key375 = GlobalKey();
      await tester.pumpWidget(buildTestApp(
        AnswerQuizScreen(
          quiz: mockQuiz,
          quizTitle: mockQuiz.title,
        ),
        boundaryKey: key375,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Cellular Respiration & ATP Synthesis'), findsWidgets);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Next Question'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await captureScreenshot(tester, key375, 'batch4_answer_quiz_375px.png');

      // 2. Desktop (1440x900)
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;

      final key1440 = GlobalKey();
      await tester.pumpWidget(buildTestApp(
        AnswerQuizScreen(
          quiz: mockQuiz,
          quizTitle: mockQuiz.title,
        ),
        boundaryKey: key1440,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Cellular Respiration & ATP Synthesis'), findsWidgets);
      expect(tester.takeException(), isNull);

      await captureScreenshot(tester, key1440, 'batch4_answer_quiz_1440px.png');

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    });

    testWidgets('MaterialViewerScreen renders cleanly on 375px and 1440px',
        (tester) async {
      // 1. Mobile (375x812)
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;

      final key375 = GlobalKey();
      await tester.pumpWidget(buildTestApp(
        MaterialViewerScreen(
          material: mockMaterial,
          initialShowExtractedText: true,
        ),
        boundaryKey: key375,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Lecture_Cellular_Energy.pptx'), findsOneWidget);
      expect(find.text('Extracted Material Text'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await captureScreenshot(tester, key375, 'batch4_material_viewer_375px.png');

      // 2. Desktop (1440x900)
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;

      final key1440 = GlobalKey();
      await tester.pumpWidget(buildTestApp(
        MaterialViewerScreen(
          material: mockMaterial,
          initialShowExtractedText: true,
        ),
        boundaryKey: key1440,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Lecture_Cellular_Energy.pptx'), findsOneWidget);
      expect(find.text('Extracted Material Text'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await captureScreenshot(tester, key1440, 'batch4_material_viewer_1440px.png');

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    });
  });
}
