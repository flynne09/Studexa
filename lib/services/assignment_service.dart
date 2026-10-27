import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/quiz_assignment_model.dart';
import '../models/quiz_attempt_model.dart';

/// Exception thrown when a quiz attempt cannot be submitted or retrieved
/// (for example, if the assignment is closed, expired, or the backend fails).
class QuizUnavailableException implements Exception {
  const QuizUnavailableException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Checks whether the code is currently running inside a Flutter unit/widget test
/// so that network-dependent Supabase calls can fall back to in-memory mocks.
bool get _isTestEnvironment {
  if (kIsWeb) return false;
  try {
    return Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

/// Service responsible for managing quiz assignments, student quiz attempts,
/// and in-progress draft answers in Supabase (with an in-memory fallback for tests).
class AssignmentService {
  /// Creates an [AssignmentService] instance with an optional injected [SupabaseClient]
  /// and a flag to toggle remote backend calls vs. local test mocks.
  AssignmentService({SupabaseClient? supabase, bool? useRemoteBackend})
      : _injectedSupabase = supabase,
        useRemoteBackend = useRemoteBackend ?? !_isTestEnvironment;

  final SupabaseClient? _injectedSupabase;
  final bool useRemoteBackend;

  /// Stores draft answers in memory when running in test mode ([useRemoteBackend] is false).
  final Map<String, Map<String, dynamic>> _inMemoryDraftAnswers = {};

  /// Returns the active [SupabaseClient] instance (injected or global singleton).
  SupabaseClient get _client =>
      _injectedSupabase ?? Supabase.instance.client;

  /// Creates a new quiz assignment record in the `quiz_assignments` table
  /// linking a quiz to a specific class and optional deadline.
  Future<QuizAssignmentModel> createAssignment({
    required String quizId,
    required String classId,
    required String teacherId,
    required String quizTitle,
    DateTime? deadline,
  }) async {
    // Insert the assignment metadata into Supabase and return the created row.
    final row = await _client
        .from('quiz_assignments')
        .insert({
          'quiz_id': quizId,
          'class_id': classId,
          'teacher_id': teacherId,
          'quiz_title': quizTitle,
          'deadline': deadline?.toUtc().toIso8601String(),
        })
        .select()
        .single();
    return QuizAssignmentModel.fromMap(row, id: row['id'].toString());
  }

  /// Marks an existing quiz assignment as closed so students can no longer submit attempts.
  Future<void> closeAssignment(String assignmentId) async {
    await _client.from('quiz_assignments').update({
      'is_closed': true,
      'closed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', assignmentId);
  }

  /// Reopens a previously closed quiz assignment so students can submit attempts again.
  Future<void> reopenAssignment(String assignmentId) async {
    await _client.from('quiz_assignments').update({
      'is_closed': false,
      'closed_at': null,
    }).eq('id', assignmentId);
  }

  /// Updates or clears the submission deadline for a specific quiz assignment.
  Future<void> updateDeadline(String assignmentId, DateTime? deadline) async {
    await _client.from('quiz_assignments').update({
      'deadline': deadline?.toUtc().toIso8601String(),
    }).eq('id', assignmentId);
  }

  /// Streams all quiz assignments for a given class in real time, ordered newest first.
  Stream<List<QuizAssignmentModel>> streamClassAssignments(String classId) =>
      _client
          .from('quiz_assignments')
          .stream(primaryKey: ['id'])
          .eq('class_id', classId)
          .order('created_at', ascending: false)
          .map((rows) => rows
              .map((row) => QuizAssignmentModel.fromMap(
                    row,
                    id: row['id'].toString(),
                  ))
              .toList());

  /// Fetches the assignment record associated with a specific class and quiz, if one exists.
  Future<QuizAssignmentModel?> getAssignmentForQuiz(
    String classId,
    String quizId,
  ) async {
    final row = await _client
        .from('quiz_assignments')
        .select()
        .eq('class_id', classId)
        .eq('quiz_id', quizId)
        .maybeSingle();
    return row == null
        ? null
        : QuizAssignmentModel.fromMap(row, id: row['id'].toString());
  }

  /// Submits a student's completed quiz attempt.
  /// In test mode, returns a local mock model; in production, invokes the
  /// `submit-quiz-attempt` Supabase Edge Function for authoritative grading and persistence.
  Future<QuizAttemptModel> submitAttempt(QuizAttemptModel attempt) async {
    // Return a mock attempt directly when remote backend is disabled (e.g., widget tests).
    if (!useRemoteBackend) {
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
    try {
      // Call the server-side Edge Function to validate, score, and record the attempt.
      final response = await _client.functions.invoke(
        'submit-quiz-attempt',
        body: {
          'quizId': attempt.quizId,
          'classId': attempt.classId,
          'answers': attempt.answers,
          'clientAttemptId': attempt.id.isEmpty
              ? _uuidV4()
              : _uuidFromText(attempt.id),
        },
      );
      if (response.status != 200 || response.data is! Map) {
        throw const QuizUnavailableException(
          'Studexa could not save this attempt. Your answers are still available.',
        );
      }
      final body = Map<String, dynamic>.from(response.data as Map);
      final row = Map<String, dynamic>.from(body['attempt'] as Map);
      return QuizAttemptModel.fromMap(row, id: row['id'].toString());
    } on FunctionException catch (error) {
      final details = error.details;
      final message = details is Map ? details['error']?.toString() : null;
      throw QuizUnavailableException(
        message ?? 'This quiz attempt is not available right now.',
      );
    }
  }

  /// Streams all student quiz attempts for a specific quiz in a class in real time (used by teachers).
  Stream<List<QuizAttemptModel>> streamClassQuizAttempts(
    String classId,
    String quizId,
  ) =>
      _client
          .from('quiz_attempts')
          .stream(primaryKey: ['id'])
          .eq('class_id', classId)
          .eq('quiz_id', quizId)
          .order('submitted_at', ascending: false)
          .map(_attemptsFromRows);

  /// Streams all quiz attempts submitted by a specific student within a class in real time.
  Stream<List<QuizAttemptModel>> streamStudentClassAttempts(
    String classId,
    String studentId,
  ) =>
      _client
          .from('quiz_attempts')
          .stream(primaryKey: ['id'])
          .eq('class_id', classId)
          .eq('student_id', studentId)
          .order('submitted_at', ascending: false)
          .map(_attemptsFromRows);

  /// Builds a composite lookup key for storing/retrieving draft answers per student, quiz, and attempt number.
  String _draftKey(String studentId, String quizId, int attemptNumber) =>
      '${studentId}_${quizId}_$attemptNumber';

  /// Saves a student's in-progress quiz answers as a draft so they can resume later without losing progress.
  Future<void> saveDraftAnswers({
    required String studentId,
    required String quizId,
    required int attemptNumber,
    required Map<String, dynamic> answers,
  }) async {
    if (!useRemoteBackend) {
      _inMemoryDraftAnswers[_draftKey(studentId, quizId, attemptNumber)] =
          Map<String, dynamic>.from(answers);
      return;
    }
    // Upsert the draft row in the `quiz_drafts` table.
    await _client.from('quiz_drafts').upsert({
      'student_id': studentId,
      'quiz_id': quizId,
      'attempt_number': attemptNumber,
      'answers': answers,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Loads any previously saved draft answers for a given student, quiz, and attempt number.
  Future<Map<String, dynamic>?> getDraftAnswers({
    required String studentId,
    required String quizId,
    required int attemptNumber,
  }) async {
    if (!useRemoteBackend) {
      final value =
          _inMemoryDraftAnswers[_draftKey(studentId, quizId, attemptNumber)];
      return value == null ? null : Map<String, dynamic>.from(value);
    }
    final row = await _client
        .from('quiz_drafts')
        .select('answers')
        .eq('student_id', studentId)
        .eq('quiz_id', quizId)
        .eq('attempt_number', attemptNumber)
        .maybeSingle();
    if (row == null || row['answers'] is! Map) return null;
    return Map<String, dynamic>.from(row['answers'] as Map);
  }

  /// Deletes saved draft answers once a student has finalized and submitted their quiz attempt.
  Future<void> clearDraftAnswers({
    required String studentId,
    required String quizId,
    required int attemptNumber,
  }) async {
    if (!useRemoteBackend) {
      _inMemoryDraftAnswers.remove(_draftKey(studentId, quizId, attemptNumber));
      return;
    }
    await _client
        .from('quiz_drafts')
        .delete()
        .eq('student_id', studentId)
        .eq('quiz_id', quizId)
        .eq('attempt_number', attemptNumber);
  }

  /// Helper that converts raw database maps into a list of [QuizAttemptModel] instances.
  static List<QuizAttemptModel> _attemptsFromRows(
    List<Map<String, dynamic>> rows,
  ) =>
      rows
          .map((row) => QuizAttemptModel.fromMap(
                row,
                id: row['id'].toString(),
              ))
          .toList();

  /// Generates a cryptographically random RFC 4122 version 4 UUID string.
  static String _uuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// Deterministically derives a valid UUID-formatted identifier from an arbitrary string
  /// using FNV-1a style hashing with multiple seeds, ensuring idempotent client attempt IDs.
  static String _uuidFromText(String value) {
    int hash(int seed) {
      var result = seed;
      for (final unit in value.codeUnits) {
        result = ((result ^ unit) * 16777619) & 0xffffffff;
      }
      return result;
    }

    final hex = [0x811c9dc5, 0x9e3779b9, 0x85ebca6b, 0xc2b2ae35]
        .map((seed) => hash(seed).toRadixString(16).padLeft(8, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '4${hex.substring(13, 16)}-a${hex.substring(17, 20)}-${hex.substring(20)}';
  }
}
