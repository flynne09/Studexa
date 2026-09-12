import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studexa/models/quiz_attempt_model.dart';
import 'package:studexa/models/quiz_model.dart';
import 'package:studexa/screens/student/answer_quiz_screen.dart';
import 'package:studexa/services/assignment_service.dart';
import 'quiz_draft_persistence_test.dart' as firebase_setup;

class ControlledAssignmentService extends AssignmentService {
  ControlledAssignmentService() : super(useFirestore: false);
  final pending = Completer<QuizAttemptModel>();
  QuizAttemptModel? submitted;
  int submitCalls = 0;
  bool cleared = false;
  @override
  Future<QuizAttemptModel> submitAttempt(QuizAttemptModel attempt) {
    submitCalls++;
    submitted = attempt;
    return pending.future;
  }
  @override
  Future<void> clearDraftAnswers({required String studentId, required String quizId, required int attemptNumber}) async {
    cleared = true;
    await super.clearDraftAnswers(studentId: studentId, quizId: quizId, attemptNumber: attemptNumber);
  }
}

const quiz = QuizModel(id: 'save-test', classId: 'class-1', teacherId: 'teacher-1', materialId: 'material-1', type: 'practice', title: 'Saved scores', questions: [
  QuizQuestion(id: 'q1', type: QuizQuestionType.multipleChoice, question: 'Which component schedules work?', options: ['Kernel', 'Browser'], correctAnswer: 'Kernel'),
]);

Future<void> startSubmission(WidgetTester tester, ControlledAssignmentService service) async {
  await tester.pumpWidget(MaterialApp(home: AnswerQuizScreen(quiz: quiz, assignmentService: service, initialAnswers: const {'q1': 'Kernel'})));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ElevatedButton, 'Submit Quiz'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(firebase_setup.setupMockFirebase);
  testWidgets('results wait for persistence; submitting blocks another save; dispose does not recreate a cleared draft', (tester) async {
    final service = ControlledAssignmentService();
    await startSubmission(tester, service);
    expect(find.text('Saving your result...'), findsOneWidget);
    expect(find.text('Quiz Results'), findsNothing);
    expect(service.cleared, isFalse);
    expect(service.submitCalls, 1);
    expect(service.submitted!.id, 'guest_student_save-test_attempt_1');
    service.pending.complete(service.submitted!);
    await tester.pumpAndSettle();
    expect(find.text('Quiz Results'), findsOneWidget);
    expect(service.cleared, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(await service.getDraftAnswers(studentId: 'guest_student', quizId: 'save-test', attemptNumber: 1), isNull);
  });
  testWidgets('failed persistence keeps answers and does not show saved results', (tester) async {
    final service = ControlledAssignmentService();
    await startSubmission(tester, service);
    service.pending.completeError(const QuizUnavailableException('The quiz has closed.'));
    await tester.pumpAndSettle();
    expect(find.text('Quiz Results'), findsNothing);
    expect(find.textContaining('Your answers have been kept.'), findsOneWidget);
    expect(service.cleared, isFalse);
    expect((await service.getDraftAnswers(studentId: 'guest_student', quizId: 'save-test', attemptNumber: 1))!['q1'], 'Kernel');
  });
}
