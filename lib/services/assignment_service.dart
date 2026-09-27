import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/quiz_assignment_model.dart';
import '../models/quiz_attempt_model.dart';

class QuizUnavailableException implements Exception {
  const QuizUnavailableException(this.message);
  final String message;

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

class AssignmentService {
  AssignmentService({SupabaseClient? supabase, bool? useRemoteBackend})
      : _injectedSupabase = supabase,
        useRemoteBackend = useRemoteBackend ?? !_isTestEnvironment;

  final SupabaseClient? _injectedSupabase;
  final bool useRemoteBackend;
  final Map<String, Map<String, dynamic>> _inMemoryDraftAnswers = {};

  SupabaseClient get _client =>
      _injectedSupabase ?? Supabase.instance.client;

  Future<QuizAssignmentModel> createAssignment({
    required String quizId,
    required String classId,
    required String teacherId,
    required String quizTitle,
    DateTime? deadline,
  }) async {
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

  Future<void> closeAssignment(String assignmentId) async {
    await _client.from('quiz_assignments').update({
      'is_closed': true,
      'closed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', assignmentId);
  }

  Future<void> reopenAssignment(String assignmentId) async {
    await _client.from('quiz_assignments').update({
      'is_closed': false,
      'closed_at': null,
    }).eq('id', assignmentId);
  }

  Future<void> updateDeadline(String assignmentId, DateTime? deadline) async {
    await _client.from('quiz_assignments').update({
      'deadline': deadline?.toUtc().toIso8601String(),
    }).eq('id', assignmentId);
  }

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

  Future<QuizAttemptModel> submitAttempt(QuizAttemptModel attempt) async {
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

  String _draftKey(String studentId, String quizId, int attemptNumber) =>
      '${studentId}_${quizId}_$attemptNumber';

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
    await _client.from('quiz_drafts').upsert({
      'student_id': studentId,
      'quiz_id': quizId,
      'attempt_number': attemptNumber,
      'answers': answers,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

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

  static List<QuizAttemptModel> _attemptsFromRows(
    List<Map<String, dynamic>> rows,
  ) =>
      rows
          .map((row) => QuizAttemptModel.fromMap(
                row,
                id: row['id'].toString(),
              ))
          .toList();

  static String _uuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

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
