/// Represents an academic class created by a teacher in Studexa.
/// Stores class metadata, join code for student enrollment, roster count, and status.
class ClassModel {
  /// Creates a [ClassModel] instance with required identifiers and optional metadata.
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

  /// Unique UUID identifier of the class in Supabase.
  final String id;

  /// Display name of the class (e.g., "BSCS 3A - Software Engineering").
  final String name;

  /// Unique alphanumeric code used by students to join this class.
  final String joinCode;

  /// User ID of the teacher who owns and manages this class.
  final String teacherId;

  /// Display name of the teacher who created the class.
  final String teacherName;

  /// Class section identifier (optional).
  final String section;

  /// Academic subject or course name (optional).
  final String subject;

  /// Current lifecycle status of the class (e.g., 'active' or 'archived').
  final String status;

  /// Total number of students currently enrolled in the class.
  final int rosterCount;

  /// Title or summary of the most recently published quiz in this class.
  final String recentQuiz;

  /// Timestamp when the class was created.
  final DateTime? createdAt;

  /// Timestamp when the class record was last updated.
  final DateTime? updatedAt;

  /// Serializes this [ClassModel] into a camelCase map for in-app domain usage.
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

  /// Serializes this [ClassModel] into a snake_case map matching the Supabase `public.classes` table schema.
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

  /// Constructs a [ClassModel] from a raw database (snake_case) or domain (camelCase) map.
  factory ClassModel.fromMap(Map<String, dynamic> map, [String? id]) {
    // Helper to safely parse ISO-8601 timestamp strings into local DateTime objects.
    DateTime? date(dynamic value) =>
        value is String ? DateTime.tryParse(value)?.toLocal() : null;
    // Helper to read a typed field from either its snake_case or camelCase key.
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

  /// Creates a new [ClassModel] copy with specified fields updated.
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

/// Represents a member (typically an enrolled student) belonging to a class roster.
class ClassMember {
  /// Creates a [ClassMember] record with user identity and enrollment timestamp.
  const ClassMember({
    required this.userId,
    required this.role,
    required this.displayName,
    this.email = '',
    this.joinedAt,
  });

  /// Unique user ID of the class member.
  final String userId;

  /// Role of the member within the class (e.g., 'student' or 'teacher').
  final String role;

  /// Snapshot of the user's display name captured when joining the class.
  final String displayName;

  /// Snapshot of the user's email address captured when joining the class.
  final String email;

  /// Timestamp indicating when the user joined the class.
  final DateTime? joinedAt;

  /// Serializes this [ClassMember] into a camelCase map.
  Map<String, dynamic> toMap() => {
        'userId': userId,
        'role': role.toLowerCase(),
        'displayNameSnapshot': displayName,
        'emailSnapshot': email,
        if (joinedAt != null)
          'joinedAt': joinedAt!.toUtc().toIso8601String(),
      };

  /// Serializes this [ClassMember] into a snake_case map for the `public.class_members` table.
  Map<String, dynamic> toDatabaseMap() => {
        'user_id': userId,
        'role': role.toLowerCase(),
        'display_name_snapshot': displayName,
        'email_snapshot': email,
        if (joinedAt != null)
          'joined_at': joinedAt!.toUtc().toIso8601String(),
      };

  /// Constructs a [ClassMember] from a database or domain map.
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
