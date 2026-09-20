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
import 'package:studexa/models/user_profile.dart';
import 'package:studexa/screens/teacher/teacher_home_screen.dart';
import 'package:studexa/screens/teacher/teacher_class_details_screen.dart';
import 'package:studexa/screens/teacher/upload_generate_quiz_screen.dart';
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

  final mockTeacher = UserProfile(
    uid: 'teacher_123',
    email: 'teacher@studexa.edu',
    displayName: 'Professor Charles Xavier',
    role: 'teacher',
    createdAt: DateTime(2026, 1, 1),
  );

  final mockClass = ClassModel(
    id: 'class_cs101',
    name: 'CS 101 - Intro to Programming',
    section: 'Section A',
    joinCode: 'CS101A',
    teacherId: 'teacher_123',
    teacherName: 'Professor Charles Xavier',
    rosterCount: 24,
    createdAt: DateTime(2026, 1, 15),
    updatedAt: DateTime(2026, 1, 15),
  );

  final mockMaterial = MaterialModel(
    id: 'mat_01',
    classId: 'class_cs101',
    teacherId: 'teacher_123',
    fileName: 'Lecture_1_Algorithms.pdf',
    fileType: 'pdf',
    fileRef: 'uploads/teacher_123/mat_01/Lecture_1_Algorithms.pdf',
    status: 'ready',
    extractedText: 'Introduction to Algorithms and Data Structures. Sorting, Searching, and Asymptotic Complexity analysis.',
    fileSizeBytes: 2048576,
    createdAt: DateTime(2026, 1, 20),
    extractedAt: DateTime(2026, 1, 20),
  );

  final mockQuiz = QuizModel(
    id: 'quiz_01',
    classId: 'class_cs101',
    teacherId: 'teacher_123',
    materialId: 'mat_01',
    type: 'practice',
    title: 'Algorithms Concept Check',
    status: 'published',
    questions: [],
    createdAt: DateTime(2026, 1, 22),
    updatedAt: DateTime(2026, 1, 22),
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

  Future<void> captureScreenshot(WidgetTester tester, GlobalKey boundaryKey, String filename) async {
    await tester.runAsync(() async {
      final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 1.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final dir = Directory(r'C:\Users\FLYNNE EJ\.gemini\antigravity\brain\b67e6326-7873-4bee-8301-e3bdf7e5f251');
          final file = File('${dir.path}/$filename');
          await file.writeAsBytes(byteData.buffer.asUint8List());
        }
      }
    });
  }

  group('Batch 2: Teacher Core Visual & Responsive Verification (375px & 1440px)', () {
    testWidgets('TeacherHomeScreen renders without overflow on 375px and 1440px', (tester) async {
      // 1. Mobile Viewport (375x812)
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;

      final key375 = GlobalKey();
      await tester.pumpWidget(buildTestApp(
        TeacherHomeScreen(
          initialProfile: mockTeacher,
          initialClassesStream: Stream.value([mockClass]),
        ),
        boundaryKey: key375,
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Teacher Account'), findsOneWidget);
      expect(find.text('My Classes & Materials'), findsOneWidget);
      expect(find.text('Professor Charles Xavier'), findsOneWidget);
      expect(find.text('CS 101 - Intro to Programming'), findsOneWidget);
      expect(find.text('Upload Material'), findsOneWidget);
      expect(find.text('Create Class'), findsOneWidget);
      await captureScreenshot(tester, key375, 'batch2_teacher_home_375px.png');

      // 2. Desktop Viewport (1440x900)
      tester.view.physicalSize = const Size(1440, 900);
      final key1440 = GlobalKey();
      await tester.pumpWidget(buildTestApp(
        TeacherHomeScreen(
          initialProfile: mockTeacher,
          initialClassesStream: Stream.value([mockClass]),
        ),
        boundaryKey: key1440,
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      final constrainedBoxFinder = find.byType(ConstrainedBox);
      expect(constrainedBoxFinder, findsWidgets);
      await captureScreenshot(tester, key1440, 'batch2_teacher_home_1440px.png');

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('TeacherClassDetailsScreen renders without overflow on 375px and 1440px', (tester) async {
      // 1. Mobile Viewport (375x812)
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;

      final key375 = GlobalKey();
      await tester.pumpWidget(buildTestApp(
        TeacherClassDetailsScreen(
          classModel: mockClass,
          initialClassStream: Stream.value(mockClass),
          initialMaterialsStream: Stream.value([mockMaterial]),
          initialQuizzesStream: Stream.value([mockQuiz]),
          initialStudentsStream: Stream.value([]),
        ),
        boundaryKey: key375,
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('CS 101 - Intro to Programming'), findsWidgets);
      expect(find.text('CS101A'), findsOneWidget);
      expect(find.text('Materials'), findsOneWidget);
      expect(find.text('Quizzes'), findsOneWidget);
      expect(find.text('Students'), findsOneWidget);
      expect(find.text('Lecture_1_Algorithms.pdf'), findsOneWidget);
      await captureScreenshot(tester, key375, 'batch2_teacher_class_details_375px.png');

      // 2. Desktop Viewport (1440x900)
      tester.view.physicalSize = const Size(1440, 900);
      final key1440 = GlobalKey();
      await tester.pumpWidget(buildTestApp(
        TeacherClassDetailsScreen(
          classModel: mockClass,
          initialClassStream: Stream.value(mockClass),
          initialMaterialsStream: Stream.value([mockMaterial]),
          initialQuizzesStream: Stream.value([mockQuiz]),
          initialStudentsStream: Stream.value([]),
        ),
        boundaryKey: key1440,
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      final constrainedBoxFinder = find.byType(ConstrainedBox);
      expect(constrainedBoxFinder, findsWidgets);
      await captureScreenshot(tester, key1440, 'batch2_teacher_class_details_1440px.png');

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('UploadGenerateQuizScreen renders without overflow on 375px and 1440px', (tester) async {
      // 1. Mobile Viewport (375x812)
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;

      final key375 = GlobalKey();
      await tester.pumpWidget(buildTestApp(
        UploadGenerateQuizScreen(
          initialClassId: mockClass.id,
          preselectedClass: mockClass,
          preselectedMaterial: mockMaterial,
          isClassLocked: true,
        ),
        boundaryKey: key375,
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Generate Quiz'), findsOneWidget);
      expect(find.text('Assign to Class'), findsOneWidget);
      expect(find.text('Number of Questions'), findsOneWidget);
      expect(find.text('Generate Actual Quiz (PDF Exam)'), findsOneWidget);
      expect(find.text('Generate Practice Quiz (App Practice)'), findsOneWidget);
      await captureScreenshot(tester, key375, 'batch2_upload_quiz_375px.png');

      // 2. Desktop Viewport (1440x900)
      tester.view.physicalSize = const Size(1440, 900);
      final key1440 = GlobalKey();
      await tester.pumpWidget(buildTestApp(
        UploadGenerateQuizScreen(
          initialClassId: mockClass.id,
          preselectedClass: mockClass,
          preselectedMaterial: mockMaterial,
          isClassLocked: true,
        ),
        boundaryKey: key1440,
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      final constrainedBoxFinder = find.byType(ConstrainedBox);
      expect(constrainedBoxFinder, findsWidgets);
      await captureScreenshot(tester, key1440, 'batch2_upload_quiz_1440px.png');

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}
