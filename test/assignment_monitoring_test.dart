import 'package:flutter_test/flutter_test.dart';
import 'package:studexa/models/quiz_assignment_model.dart';
import 'package:studexa/models/quiz_attempt_model.dart';
import 'package:studexa/services/assignment_service.dart';

void main() {
  group('QuizAssignmentModel Tests', () {
    test('QuizAssignmentModel serializes and deserializes properly', () {
      final deadline = DateTime.now().add(const Duration(days: 3));
      final assignment = QuizAssignmentModel(
        id: 'assign_1',
        quizId: 'quiz_123',
        classId: 'class_abc',
        teacherId: 'teacher_xyz',
        quizTitle: 'Cellular Respiration Practice',
        deadline: deadline,
        isClosed: false,
      );

      final map = assignment.toMap();
      expect(map['quizId'], 'quiz_123');
      expect(map['classId'], 'class_abc');
      expect(map['teacherId'], 'teacher_xyz');
      expect(map['quizTitle'], 'Cellular Respiration Practice');
      expect(map['isClosed'], false);

      final reconstructed = QuizAssignmentModel.fromMap(map, id: 'assign_1');
      expect(reconstructed.id, 'assign_1');
      expect(reconstructed.quizTitle, assignment.quizTitle);
      expect(reconstructed.isClosed, false);
      expect(reconstructed.isOpen, true);
    });

    test('Availability logic correctly evaluates open, closed, and expired states', () {
      final now = DateTime.now();

      // Open with future deadline
      final openAssignment = QuizAssignmentModel(
        id: 'a1',
        quizId: 'q1',
        classId: 'c1',
        teacherId: 't1',
        quizTitle: 'Active Quiz',
        deadline: now.add(const Duration(hours: 5)),
        isClosed: false,
      );
      expect(openAssignment.isOpen, true);
      expect(openAssignment.isExpired, false);
      expect(openAssignment.isAvailable, true);
      expect(openAssignment.formattedStatus, 'Open');

      // Open with no deadline
      final noDeadlineAssignment = QuizAssignmentModel(
        id: 'a2',
        quizId: 'q2',
        classId: 'c1',
        teacherId: 't1',
        quizTitle: 'Always Open Quiz',
        isClosed: false,
      );
      expect(noDeadlineAssignment.isOpen, true);
      expect(noDeadlineAssignment.isExpired, false);
      expect(noDeadlineAssignment.isAvailable, true);

      // Manually closed
      final closedAssignment = openAssignment.copyWith(isClosed: true);
      expect(closedAssignment.isOpen, false);
      expect(closedAssignment.isAvailable, false);
      expect(closedAssignment.formattedStatus, 'Closed');

      // Expired deadline
      final expiredAssignment = QuizAssignmentModel(
        id: 'a3',
        quizId: 'q3',
        classId: 'c1',
        teacherId: 't1',
        quizTitle: 'Past Deadline Quiz',
        deadline: now.subtract(const Duration(hours: 1)),
        isClosed: false,
      );
      expect(expiredAssignment.isExpired, true);
      expect(expiredAssignment.isAvailable, false);
      expect(expiredAssignment.formattedStatus, 'Expired');
    });
  });

  group('QuizAttemptModel Tests', () {
    test('QuizAttemptModel serializes and computes stats correctly', () {
      final attempt = QuizAttemptModel(
        id: 'att_101',
        quizId: 'quiz_123',
        classId: 'class_abc',
        studentId: 'student_55',
        studentName: 'Alex Morgan',
        score: 18.0,
        totalPoints: 20.0,
        percentage: 90.0,
        breakdown: const [
          {
            'questionId': 'q_1',
            'earned': 1.0,
            'points': 1.0,
            'isCorrect': true,
          },
          {
            'questionId': 'q_2',
            'earned': 2.0,
            'points': 2.0,
            'isCorrect': true,
          },
        ],
      );

      expect(attempt.formattedPercentage, '90%');
      expect(attempt.formattedScore, '18.0 / 20');
      expect(attempt.isPassed, true);

      final map = attempt.toMap();
      expect(map['studentId'], 'student_55');
      expect(map['score'], 18.0);
      expect(map['percentage'], 90.0);

      final reconstructed = QuizAttemptModel.fromMap(map, id: 'att_101');
      expect(reconstructed.id, 'att_101');
      expect(reconstructed.studentName, 'Alex Morgan');
      expect(reconstructed.breakdown.length, 2);
      expect(reconstructed.isPassed, true);
    });

    test('Passing threshold accurately distinguishes pass and fail', () {
      final passAttempt = QuizAttemptModel(
        id: 'p1',
        quizId: 'q1',
        classId: 'c1',
        studentId: 's1',
        studentName: 'Pass Student',
        score: 7.0,
        totalPoints: 10.0,
        percentage: 70.0,
      );
      expect(passAttempt.isPassed, true);

      final failAttempt = QuizAttemptModel(
        id: 'f1',
        quizId: 'q1',
        classId: 'c1',
        studentId: 's2',
        studentName: 'Fail Student',
        score: 6.5,
        totalPoints: 10.0,
        percentage: 65.0,
      );
      expect(failAttempt.isPassed, false);
    });
  });

  group('QuizUnavailableException Tests', () {
    test('QuizUnavailableException formats clean message', () {
      const ex = QuizUnavailableException('This quiz deadline has passed.');
      expect(ex.toString(), 'This quiz deadline has passed.');
    });
  });
}
