/// Represents an assigned Practice Quiz for a class with an optional deadline
/// and open/closed availability toggle.
class QuizAssignmentModel {
  final String id;
  final String quizId;
  final String classId;
  final String teacherId;
  final String quizTitle;
  final DateTime? deadline;
  final bool isClosed;
  final DateTime? createdAt;
  final DateTime? closedAt;

  const QuizAssignmentModel({
    required this.id,
    required this.quizId,
    required this.classId,
    required this.teacherId,
    required this.quizTitle,
    this.deadline,
    this.isClosed = false,
    this.createdAt,
    this.closedAt,
  });

  /// Whether the assignment is currently available for student submissions.
  bool get isOpen => !isClosed;

  /// Whether the assignment deadline has passed.
  bool get isExpired {
    if (deadline == null) return false;
    return DateTime.now().isAfter(deadline!);
  }

  /// Active availability checking both manual closure and deadline expiration.
  bool get isAvailable => !isClosed && !isExpired;

  String get formattedStatus {
    if (isClosed) return 'Closed';
    if (isExpired) return 'Expired';
    return 'Open';
  }

  factory QuizAssignmentModel.fromMap(
    Map<String, dynamic> map, {
    String id = '',
  }) {
    DateTime? parseTimestamp(dynamic val) {
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return QuizAssignmentModel(
      id: id.isNotEmpty ? id : ((map['id'] as String?) ?? ''),
      quizId: (map['quiz_id'] ?? map['quizId'])?.toString() ?? '',
      classId: (map['class_id'] ?? map['classId'])?.toString() ?? '',
      teacherId: (map['teacher_id'] ?? map['teacherId'])?.toString() ?? '',
      quizTitle: (map['quiz_title'] ?? map['quizTitle'])?.toString() ?? 'Untitled Quiz',
      deadline: parseTimestamp(map['deadline']),
      isClosed: (map['is_closed'] ?? map['isClosed']) as bool? ?? false,
      createdAt: parseTimestamp(map['created_at'] ?? map['createdAt']),
      closedAt: parseTimestamp(map['closed_at'] ?? map['closedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'quizId': quizId,
      'classId': classId,
      'teacherId': teacherId,
      'quizTitle': quizTitle,
      'isClosed': isClosed,
      if (deadline != null) 'deadline': deadline!.toUtc().toIso8601String(),
      if (createdAt != null)
        'createdAt': createdAt!.toUtc().toIso8601String(),
      if (closedAt != null) 'closedAt': closedAt!.toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> toDatabaseMap() {
    return {
      'quiz_id': quizId,
      'class_id': classId,
      'teacher_id': teacherId,
      'quiz_title': quizTitle,
      'is_closed': isClosed,
      if (deadline != null) 'deadline': deadline!.toUtc().toIso8601String(),
      if (createdAt != null) 'created_at': createdAt!.toUtc().toIso8601String(),
      if (closedAt != null) 'closed_at': closedAt!.toUtc().toIso8601String(),
    };
  }

  QuizAssignmentModel copyWith({
    String? id,
    String? quizId,
    String? classId,
    String? teacherId,
    String? quizTitle,
    DateTime? deadline,
    bool? isClosed,
    DateTime? createdAt,
    DateTime? closedAt,
  }) {
    return QuizAssignmentModel(
      id: id ?? this.id,
      quizId: quizId ?? this.quizId,
      classId: classId ?? this.classId,
      teacherId: teacherId ?? this.teacherId,
      quizTitle: quizTitle ?? this.quizTitle,
      deadline: deadline ?? this.deadline,
      isClosed: isClosed ?? this.isClosed,
      createdAt: createdAt ?? this.createdAt,
      closedAt: closedAt ?? this.closedAt,
    );
  }
}
