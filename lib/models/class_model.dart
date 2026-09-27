class ClassModel {
  const ClassModel({
    required this.id,
    required this.name,
    required this.joinCode,
    required this.teacherId,
    this.teacherName = '',
    this.section = '',
    this.subject = '',
    this.status = 'active',
    this.rosterCount = 0,
    this.recentQuiz = 'No quizzes yet',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String joinCode;
  final String teacherId;
  final String teacherName;
  final String section;
  final String subject;
  final String status;
  final int rosterCount;
  final String recentQuiz;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toMap() => {
        'name': name,
        'joinCode': joinCode.toUpperCase(),
        'teacherId': teacherId,
        'teacherName': teacherName,
        'section': section,
        'subject': subject,
        'status': status,
        'rosterCount': rosterCount,
        'recentQuiz': recentQuiz,
        if (createdAt != null)
          'createdAt': createdAt!.toUtc().toIso8601String(),
      };

  Map<String, dynamic> toDatabaseMap() => {
        'name': name,
        'join_code': joinCode.toUpperCase(),
        'teacher_id': teacherId,
        'teacher_name': teacherName,
        'section': section,
        'subject': subject,
        'status': status,
        'roster_count': rosterCount,
        'recent_quiz': recentQuiz,
        if (createdAt != null)
          'created_at': createdAt!.toUtc().toIso8601String(),
      };

  factory ClassModel.fromMap(Map<String, dynamic> map, [String? id]) {
    DateTime? date(dynamic value) =>
        value is String ? DateTime.tryParse(value)?.toLocal() : null;
    T? first<T>(String snake, String camel) {
      final value = map[snake] ?? map[camel];
      return value is T ? value : null;
    }

    return ClassModel(
      id: id ?? map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      joinCode: (first<String>('join_code', 'joinCode') ?? '').toUpperCase(),
      teacherId: first<String>('teacher_id', 'teacherId') ?? '',
      teacherName: first<String>('teacher_name', 'teacherName') ?? '',
      section: map['section']?.toString() ?? '',
      subject: map['subject']?.toString() ?? '',
      status: map['status']?.toString() ?? 'active',
      rosterCount: (map['roster_count'] ?? map['rosterCount']) is num
          ? ((map['roster_count'] ?? map['rosterCount']) as num).toInt()
          : 0,
      recentQuiz:
          first<String>('recent_quiz', 'recentQuiz') ?? 'No quizzes yet',
      createdAt: date(map['created_at'] ?? map['createdAt']),
      updatedAt: date(map['updated_at'] ?? map['updatedAt']),
    );
  }

  ClassModel copyWith({
    String? name,
    String? joinCode,
    String? teacherId,
    String? teacherName,
    String? section,
    String? subject,
    String? status,
    int? rosterCount,
    String? recentQuiz,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      ClassModel(
        id: id,
        name: name ?? this.name,
        joinCode: joinCode ?? this.joinCode,
        teacherId: teacherId ?? this.teacherId,
        teacherName: teacherName ?? this.teacherName,
        section: section ?? this.section,
        subject: subject ?? this.subject,
        status: status ?? this.status,
        rosterCount: rosterCount ?? this.rosterCount,
        recentQuiz: recentQuiz ?? this.recentQuiz,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class ClassMember {
  const ClassMember({
    required this.userId,
    required this.role,
    required this.displayName,
    this.email = '',
    this.joinedAt,
  });

  final String userId;
  final String role;
  final String displayName;
  final String email;
  final DateTime? joinedAt;

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'role': role.toLowerCase(),
        'displayNameSnapshot': displayName,
        'emailSnapshot': email,
        if (joinedAt != null)
          'joinedAt': joinedAt!.toUtc().toIso8601String(),
      };

  Map<String, dynamic> toDatabaseMap() => {
        'user_id': userId,
        'role': role.toLowerCase(),
        'display_name_snapshot': displayName,
        'email_snapshot': email,
        if (joinedAt != null)
          'joined_at': joinedAt!.toUtc().toIso8601String(),
      };

  factory ClassMember.fromMap(Map<String, dynamic> map, [String? id]) {
    final joined = map['joined_at'] ?? map['joinedAt'];
    return ClassMember(
      userId: (map['user_id'] ?? map['userId'] ?? id ?? '').toString(),
      role: (map['role'] ?? 'student').toString().toLowerCase(),
      displayName:
          (map['display_name_snapshot'] ?? map['displayNameSnapshot'] ?? '')
              .toString(),
      email: (map['email_snapshot'] ?? map['emailSnapshot'] ?? '').toString(),
      joinedAt:
          joined is String ? DateTime.tryParse(joined)?.toLocal() : null,
    );
  }
}
