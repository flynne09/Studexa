import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/quiz_assignment_model.dart';
import '../models/quiz_attempt_model.dart';
import 'firestore_provider.dart';

/// Exception thrown when attempting to submit a quiz that has closed or passed its deadline.
class QuizUnavailableException implements Exception {
  final String message;
  const QuizUnavailableException(this.message);

  @override
  String toString() => message;
}

bool get _isTestEnvironment {
  if (kIsWeb) return false;
  try {
    return Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

/// Service managing quiz assignments, deadlines, availability status, and student attempts.
class AssignmentService {
  AssignmentService({FirebaseFirestore? firestore, bool? useFirestore})
      : _firestore = firestore ?? getAppFirestore(),
        useFirestore = useFirestore ?? !_isTestEnvironment;

  final FirebaseFirestore _firestore;
  final bool useFirestore;
  final Map<String, Map<String, dynamic>> _inMemoryDraftAnswers = {};

  CollectionReference<Map<String, dynamic>> get _assignmentsCollection =>
      _firestore.collection('quizAssignments');

  CollectionReference<Map<String, dynamic>> get _attemptsCollection =>
      _firestore.collection('attempts');

  /// Creates a class assignment for a practice quiz.
  Future<QuizAssignmentModel> createAssignment({
    required String quizId,
    required String classId,
    required String teacherId,
    required String quizTitle,
    DateTime? deadline,
  }) async {
    final docRef = _assignmentsCollection.doc();
    final assignment = QuizAssignmentModel(
      id: docRef.id,
      quizId: quizId,
      classId: classId,
      teacherId: teacherId,
      quizTitle: quizTitle,
      deadline: deadline,
      isClosed: false,
      createdAt: DateTime.now(),
    );

    await docRef.set({
      ...assignment.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    return assignment;
  }

  /// Closes an assignment, preventing any new submissions.
  Future<void> closeAssignment(String assignmentId) async {
    await _assignmentsCollection.doc(assignmentId).update({
      'isClosed': true,
      'closedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Reopens a previously closed assignment.
  Future<void> reopenAssignment(String assignmentId) async {
    await _assignmentsCollection.doc(assignmentId).update({
      'isClosed': false,
      'closedAt': FieldValue.delete(),
    });
  }

  /// Updates or extends the deadline of an assignment.
  Future<void> updateDeadline(String assignmentId, DateTime? newDeadline) async {
    await _assignmentsCollection.doc(assignmentId).update({
      'deadline': newDeadline != null ? Timestamp.fromDate(newDeadline) : FieldValue.delete(),
    });
  }

  /// Streams assignments for a given class in real time.
  Stream<List<QuizAssignmentModel>> streamClassAssignments(String classId) {
    return _assignmentsCollection
        .where('classId', isEqualTo: classId)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => QuizAssignmentModel.fromFirestore(doc))
          .toList();
      list.sort((a, b) {
        if (a.createdAt == null && b.createdAt == null) return 0;
        if (a.createdAt == null) return 1;
        if (b.createdAt == null) return -1;
        return b.createdAt!.compareTo(a.createdAt!);
      });
      return list;
    });
  }

  /// Retrieves the active assignment for a quiz within a class, if any.
  Future<QuizAssignmentModel?> getAssignmentForQuiz(String classId, String quizId) async {
    final snapshot = await _assignmentsCollection
        .where('classId', isEqualTo: classId)
        .where('quizId', isEqualTo: quizId)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    return QuizAssignmentModel.fromFirestore(snapshot.docs.first);
  }

  /// Submits a student's graded quiz attempt after verifying availability.
  Future<QuizAttemptModel> submitAttempt(QuizAttemptModel attempt) async {
    if (!useFirestore) {
      return QuizAttemptModel(
        id: 'mock_attempt_${DateTime.now().millisecondsSinceEpoch}',
        quizId: attempt.quizId,
        assignmentId: attempt.assignmentId,
        classId: attempt.classId,
        studentId: attempt.studentId,
        studentName: attempt.studentName,
        answers: attempt.answers,
        score: attempt.score,
        totalPoints: attempt.totalPoints,
        percentage: attempt.percentage,
        submittedAt: DateTime.now(),
        breakdown: attempt.breakdown,
      );
    }

    // 1. Availability validation: check if an assignment exists
    final assignmentSnapshot = await _assignmentsCollection
        .where('classId', isEqualTo: attempt.classId)
        .where('quizId', isEqualTo: attempt.quizId)
        .limit(1)
        .get();

    if (assignmentSnapshot.docs.isNotEmpty) {
      final assignment =
          QuizAssignmentModel.fromFirestore(assignmentSnapshot.docs.first);
      if (assignment.isClosed) {
        throw const QuizUnavailableException(
          'This quiz has been closed by the instructor. New submissions are no longer accepted.',
        );
      }
      if (assignment.isExpired) {
        throw const QuizUnavailableException(
          'The submission deadline for this quiz has passed.',
        );
      }
    }

    // 2. Validate maximum attempt limit (max 2 attempts per practice quiz)
    if (attempt.quizId.isNotEmpty && attempt.studentId.isNotEmpty) {
      Query<Map<String, dynamic>> query = _attemptsCollection
          .where('quizId', isEqualTo: attempt.quizId)
          .where('studentId', isEqualTo: attempt.studentId);
      if (attempt.classId.isNotEmpty) {
        query = query.where('classId', isEqualTo: attempt.classId);
      }
      final existingAttemptsSnapshot = await query.get();
      if (existingAttemptsSnapshot.docs.length >= 2) {
        throw const QuizUnavailableException(
          'You have reached the maximum 2 attempts for this practice quiz.',
        );
      }
    }

    // 3. Persist attempt
    final docRef = _attemptsCollection.doc();
    final savedAttempt = QuizAttemptModel(
      id: docRef.id,
      quizId: attempt.quizId,
      assignmentId: attempt.assignmentId,
      classId: attempt.classId,
      studentId: attempt.studentId,
      studentName: attempt.studentName,
      answers: attempt.answers,
      score: attempt.score,
      totalPoints: attempt.totalPoints,
      percentage: attempt.percentage,
      submittedAt: DateTime.now(),
      breakdown: attempt.breakdown,
    );

    await docRef.set({
      ...savedAttempt.toMap(),
      'submittedAt': FieldValue.serverTimestamp(),
    });

    return savedAttempt;
  }

  /// Streams all attempts for a quiz within a specific class.
  Stream<List<QuizAttemptModel>> streamClassQuizAttempts(
    String classId,
    String quizId,
  ) {
    return _attemptsCollection
        .where('classId', isEqualTo: classId)
        .where('quizId', isEqualTo: quizId)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => QuizAttemptModel.fromFirestore(doc))
          .toList();
      list.sort((a, b) {
        if (a.submittedAt == null && b.submittedAt == null) return 0;
        if (a.submittedAt == null) return 1;
        if (b.submittedAt == null) return -1;
        return b.submittedAt!.compareTo(a.submittedAt!);
      });
      return list;
    });
  }

  /// Streams a student's past attempts for a given class.
  Stream<List<QuizAttemptModel>> streamStudentClassAttempts(
    String classId,
    String studentId,
  ) {
    return _attemptsCollection
        .where('classId', isEqualTo: classId)
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => QuizAttemptModel.fromFirestore(doc))
          .toList();
    });
  }

  String _draftKey(String studentId, String quizId, int attemptNumber) =>
      '${studentId}_${quizId}_$attemptNumber';

  /// Saves in-progress (unsubmitted) quiz answers for an active attempt.
  Future<void> saveDraftAnswers({
    required String studentId,
    required String quizId,
    required int attemptNumber,
    required Map<String, dynamic> answers,
  }) async {
    final key = _draftKey(studentId, quizId, attemptNumber);
    _inMemoryDraftAnswers[key] = Map<String, dynamic>.from(answers);

    if (!useFirestore || studentId.isEmpty || quizId.isEmpty) return;

    try {
      final docRef = _firestore
          .collection('users')
          .doc(studentId)
          .collection('attempts')
          .doc('draft_${quizId}_attempt_$attemptNumber');

      await docRef.set({
        'quizId': quizId,
        'studentId': studentId,
        'attemptNumber': attemptNumber,
        'answers': answers,
        'isDraft': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  /// Retrieves previously saved in-progress answers for an active attempt, or null if none.
  Future<Map<String, dynamic>?> getDraftAnswers({
    required String studentId,
    required String quizId,
    required int attemptNumber,
  }) async {
    final key = _draftKey(studentId, quizId, attemptNumber);
    final memorySaved = _inMemoryDraftAnswers[key];

    if (!useFirestore || studentId.isEmpty || quizId.isEmpty) {
      return memorySaved != null ? Map<String, dynamic>.from(memorySaved) : null;
    }

    try {
      final docSnapshot = await _firestore
          .collection('users')
          .doc(studentId)
          .collection('attempts')
          .doc('draft_${quizId}_attempt_$attemptNumber')
          .get()
          .timeout(const Duration(seconds: 2));

      if (docSnapshot.exists && docSnapshot.data() != null) {
        final data = docSnapshot.data()!;
        final answers = data['answers'];
        if (answers is Map) {
          final mapped = Map<String, dynamic>.from(answers);
          _inMemoryDraftAnswers[key] = mapped;
          return mapped;
        }
      }
    } catch (_) {}

    return memorySaved != null ? Map<String, dynamic>.from(memorySaved) : null;
  }

  /// Clears in-progress draft answers once an attempt has been officially submitted.
  Future<void> clearDraftAnswers({
    required String studentId,
    required String quizId,
    required int attemptNumber,
  }) async {
    final key = _draftKey(studentId, quizId, attemptNumber);
    _inMemoryDraftAnswers.remove(key);

    if (!useFirestore || studentId.isEmpty || quizId.isEmpty) return;

    try {
      await _firestore
          .collection('users')
          .doc(studentId)
          .collection('attempts')
          .doc('draft_${quizId}_attempt_$attemptNumber')
          .delete()
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
  }
}
