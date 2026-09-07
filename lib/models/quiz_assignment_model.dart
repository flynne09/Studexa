import 'package:cloud_firestore/cloud_firestore.dart';

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

  factory QuizAssignmentModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return QuizAssignmentModel.fromMap(data, id: doc.id);
  }

  factory QuizAssignmentModel.fromMap(
    Map<String, dynamic> map, {
    String id = '',
  }) {
    DateTime? parseTimestamp(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return QuizAssignmentModel(
      id: id.isNotEmpty ? id : ((map['id'] as String?) ?? ''),
      quizId: (map['quizId'] as String?) ?? '',
      classId: (map['classId'] as String?) ?? '',
      teacherId: (map['teacherId'] as String?) ?? '',
      quizTitle: (map['quizTitle'] as String?) ?? 'Untitled Quiz',
      deadline: parseTimestamp(map['deadline']),
      isClosed: (map['isClosed'] as bool?) ?? false,
      createdAt: parseTimestamp(map['createdAt']),
      closedAt: parseTimestamp(map['closedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'quizId': quizId,
      'classId': classId,
      'teacherId': teacherId,
      'quizTitle': quizTitle,
      'isClosed': isClosed,
      if (deadline != null) 'deadline': Timestamp.fromDate(deadline!),
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      if (closedAt != null) 'closedAt': Timestamp.fromDate(closedAt!),
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
