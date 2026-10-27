import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/class_model.dart';

/// Exception thrown when joining or loading a class fails (e.g., invalid join code,
/// already enrolled, or inactive class).
class ClassJoinException implements Exception {
  const ClassJoinException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Service responsible for creating classes, enrolling students via join codes,
/// and streaming class and roster data from Supabase.
class ClassService {
  /// Creates a [ClassService] with an optional injected [SupabaseClient] for testing.
  ClassService({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  /// Resolves the active [SupabaseClient] instance.
  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  /// Client-side candidate generation remains useful for previews and tests;
  /// the database RPC is authoritative for uniqueness.
  Future<String> generateUniqueJoinCode({String prefix = 'CLS'}) async {
    // Exclude visually ambiguous characters like I, O, 0, 1.
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    final letters = prefix.replaceAll(RegExp('[^a-zA-Z]'), '').toUpperCase();
    final safePrefix = letters.length >= 3
        ? letters.substring(0, 3)
        : ('${letters}CLS').substring(0, 3);
    final suffix = List.generate(
      4,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
    return '$safePrefix-$suffix';
  }

  /// Creates a new class for a teacher by calling the `create_studexa_class` database RPC,
  /// which generates an authoritative unique join code and inserts the class record.
  Future<ClassModel> createClass({
    required String name,
    required String section,
    required String teacherId,
    required String teacherName,
  }) async {
    final cleanName = name.trim();
    final cleanSection = section.trim();
    if (cleanName.isEmpty) throw ArgumentError('Class name cannot be empty.');
    if (cleanSection.isEmpty) {
      throw ArgumentError('Class section cannot be empty.');
    }
    final data = await _client.rpc(
      'create_studexa_class',
      params: {'p_name': cleanName, 'p_section': cleanSection},
    );
    return ClassModel.fromMap(_singleMap(data));
  }

  /// Streams all classes owned by a specific teacher in real time, ordered newest first.
  Stream<List<ClassModel>> getTeacherClassesStream(String teacherId) => _client
      .from('classes')
      .stream(primaryKey: ['id'])
      .eq('teacher_id', teacherId)
      .order('created_at', ascending: false)
      .map((rows) => rows.map(ClassModel.fromMap).toList());

  /// Streams all members (teacher and enrolled students) of a specific class in real time.
  Stream<List<ClassMember>> getClassMembersStream(String classId) => _client
      .from('class_members')
      .stream(primaryKey: ['class_id', 'user_id'])
      .eq('class_id', classId)
      .order('joined_at')
      .map((rows) => rows.map(ClassMember.fromMap).toList());

  /// Enrolls a student into a class using a teacher-shared join code via the
  /// `join_studexa_class` RPC and returns the joined [ClassModel].
  Future<ClassModel> joinClassByCode({
    required String joinCode,
    required String studentId,
    required String studentName,
    String studentEmail = '',
  }) async {
    final code = joinCode.trim().toUpperCase();
    if (code.isEmpty) {
      throw const ClassJoinException('Please enter a valid join code.');
    }
    try {
      final data = await _client.rpc(
        'join_studexa_class',
        params: {'p_join_code': code},
      );
      return ClassModel.fromMap(_singleMap(data));
    } on PostgrestException catch (error) {
      throw ClassJoinException(_joinMessage(error.message, code));
    }
  }

  /// RLS exposes only classes the signed-in Student has joined.
  Stream<List<ClassModel>> getStudentJoinedClassesStream(String studentId) =>
      _client
          .from('classes')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .map((rows) => rows.map(ClassModel.fromMap).toList());

  /// Streams live updates for a single class by its [classId].
  Stream<ClassModel?> streamClass(String classId) => _client
      .from('classes')
      .stream(primaryKey: ['id'])
      .eq('id', classId)
      .limit(1)
      .map((rows) => rows.isEmpty ? null : ClassModel.fromMap(rows.first));

  /// Fetches a single class record by its [classId] once.
  Future<ClassModel?> getClassById(String classId) async {
    final data = await _client
        .from('classes')
        .select()
        .eq('id', classId)
        .maybeSingle();
    return data == null
        ? null
        : ClassModel.fromMap(Map<String, dynamic>.from(data));
  }

  /// Extracts a single map from an RPC response (handling both direct Map and single-element List responses).
  static Map<String, dynamic> _singleMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
    throw const ClassJoinException('The class service returned no class.');
  }

  /// Maps raw database RPC error strings to user-friendly messages when joining a class fails.
  static String _joinMessage(String raw, String code) {
    final text = raw.toLowerCase();
    if (text.contains('not found')) {
      return 'No class found with join code "$code". Please verify the code with your teacher.';
    }
    if (text.contains('already enrolled')) {
      return 'You are already enrolled in this class.';
    }
    if (text.contains('inactive')) {
      return 'This class is inactive and is not accepting new students.';
    }
    if (text.contains('student account')) {
      return 'Sign in with a Student account before joining a class.';
    }
    return 'Studexa could not join this class. Check the code and try again.';
  }
}
