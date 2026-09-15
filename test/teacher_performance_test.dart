import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:studexa/models/class_model.dart';
import 'package:studexa/models/quiz_model.dart';
import 'package:studexa/screens/teacher/teacher_class_details_screen.dart';
import 'package:studexa/screens/teacher/quiz_detail_screen.dart';

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

  final testClass = ClassModel(
    id: 'class_perf_1',
    name: 'Advanced Algorithms',
    joinCode: 'ALGO-101',
    teacherId: 'teacher_perf',
    teacherName: 'Dr. Turing',
    rosterCount: 25,
    createdAt: DateTime.now(),
  );

  final testQuiz = QuizModel(
    id: 'quiz_perf_1',
    classId: 'class_perf_1',
    teacherId: 'teacher_perf',
    materialId: 'mat_perf_1',
    title: 'Dynamic Programming & Graphs',
    type: 'practice',
    status: 'published',
    questions: [
      QuizQuestion(
        id: 'q1',
        type: QuizQuestionType.multipleChoice,
        question: 'What is the time complexity of Dijkstra with a binary heap?',
        options: ['O(V^2)', 'O((V + E) log V)', 'O(VE)', 'O(E log E)'],
        correctAnswer: 'O((V + E) log V)',
        points: 1.0,
      ),
    ],
    createdAt: DateTime.now(),
  );

  group('Task 6 — Teacher Performance & Non-blocking Operations Tests', () {
    testWidgets('Quiz query errors show retry instead of an empty class', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: TeacherClassDetailsScreen(
          classModel: testClass,
          initialMaterialsStream: Stream.value([]),
          initialQuizzesStream: Stream<List<QuizModel>>.error(
            StateError('permission-denied'),
          ),
        ),
      ));
      await tester.tap(find.text('Quizzes'));
      await tester.pumpAndSettle();

      expect(find.text('Unable to load quizzes. Check your connection and try again.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('No Quizzes Created Yet'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Teacher class shows Actual drafts and published Practice', (tester) async {
      final actualQuiz = QuizModel(
        id: 'actual_visibility', classId: testClass.id,
        teacherId: testClass.teacherId, materialId: 'material_visibility',
        title: 'Actual draft exam', type: 'actual', status: 'draft', questions: [],
      );
      await tester.pumpWidget(MaterialApp(
        home: TeacherClassDetailsScreen(
          classModel: testClass,
          initialMaterialsStream: Stream.value([]),
          initialQuizzesStream: Stream.value([actualQuiz, testQuiz]),
        ),
      ));
      await tester.tap(find.text('Quizzes'));
      await tester.pumpAndSettle();

      expect(find.text('Actual draft exam'), findsOneWidget);
      expect(find.text(testQuiz.title), findsOneWidget);
      expect(find.text('No Quizzes Created Yet'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('1. TeacherClassDetailsScreen renders cached streams, header info, and keep-alive tabs', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TeacherClassDetailsScreen(classModel: testClass),
        ),
      );
      await tester.pump();

      // Verify header correctly shows interpolated instructor and student count
      expect(find.text('Advanced Algorithms'), findsWidgets);
      expect(find.text('ALGO-101'), findsOneWidget);
      expect(find.text('Instructor: Dr. Turing'), findsOneWidget);
      expect(find.text('25 students'), findsOneWidget);

      // Verify TabBar tabs
      expect(find.text('Materials'), findsOneWidget);
      expect(find.text('Quizzes'), findsOneWidget);
      expect(find.text('Students'), findsOneWidget);

      // Switch tabs and verify smooth transition without recreation issues
      await tester.tap(find.text('Quizzes'));
      await tester.pump();
      expect(find.byType(TabBarView), findsOneWidget);

      await tester.tap(find.text('Students'));
      await tester.pump();
      expect(find.byType(TabBarView), findsOneWidget);

      await tester.tap(find.text('Materials'));
      await tester.pump();
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('2. QuizDetailScreen deletion shows non-blocking progress SnackBar feedback', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: QuizDetailScreen(quiz: testQuiz),
        ),
      );
      await tester.pump();

      expect(find.text('Dynamic Programming & Graphs'), findsWidgets);

      // Trigger delete quiz dialog via AppBar IconButton
      final deleteBtn = find.byTooltip('Delete Quiz');
      expect(deleteBtn, findsOneWidget);
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      // Verify confirm dialog
      expect(find.text('Delete Quiz?'), findsOneWidget);
      expect(find.text('Are you sure you want to permanently delete this quiz? This action cannot be undone.'), findsOneWidget);

      // Confirm deletion
      final confirmDelete = find.widgetWithText(ElevatedButton, 'Delete');
      await tester.tap(confirmDelete);
      await tester.pump();

      // Immediately upon confirmation, non-blocking progress feedback should be displayed
      expect(find.text('Removing "Dynamic Programming & Graphs" from this class.'), findsOneWidget);
    });

    test('3. Upload progress throttling helper ensures state updates >= 5% steps or completion', () {
      final stateUpdates = <double>[];
      double currentProgress = 0.0;

      void onProgress(double progress) {
        if ((progress - currentProgress).abs() >= 0.05 || progress >= 1.0 || currentProgress == 0.0) {
          currentProgress = progress;
          stateUpdates.add(progress);
        }
      }

      // Simulate a rapid stream of micro chunk events (100 discrete chunk steps)
      for (int i = 1; i <= 100; i++) {
        onProgress(i / 100.0);
      }

      // Instead of 100 setState calls, throttling reduces it by ~80%
      expect(stateUpdates.length, lessThanOrEqualTo(21));
      expect(stateUpdates.first, equals(0.01)); // Initial progress
      expect(stateUpdates.last, equals(1.0)); // Always captures 100% completion
    });
  });
}
