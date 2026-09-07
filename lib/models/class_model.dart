import 'package:cloud_firestore/cloud_firestore.dart';

/// Data model representing a class in Studexa stored in Firestore `classes/{classId}`.
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

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'joinCode': joinCode.toUpperCase(),
      'teacherId': teacherId,
      'teacherName': teacherName,
      'section': section,
      'subject': subject,
      'status': status,
      'rosterCount': rosterCount,
      'recentQuiz': recentQuiz,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory ClassModel.fromMap(Map<String, dynamic> map, String id) {
    DateTime? created;
    final rawCreated = map['createdAt'];
    if (rawCreated is Timestamp) {
      created = rawCreated.toDate();
    } else if (rawCreated is String) {
      created = DateTime.tryParse(rawCreated);
    }

    DateTime? updated;
    final rawUpdated = map['updatedAt'];
    if (rawUpdated is Timestamp) {
      updated = rawUpdated.toDate();
    } else if (rawUpdated is String) {
      updated = DateTime.tryParse(rawUpdated);
    }

    return ClassModel(
      id: id,
      name: map['name'] as String? ?? '',
      joinCode: (map['joinCode'] as String? ?? '').toUpperCase(),
      teacherId: map['teacherId'] as String? ?? '',
      teacherName: map['teacherName'] as String? ?? '',
      section: map['section'] as String? ?? '',
      subject: map['subject'] as String? ?? '',
      status: map['status'] as String? ?? 'active',
      rosterCount: (map['rosterCount'] as num?)?.toInt() ?? 0,
      recentQuiz: map['recentQuiz'] as String? ?? 'No quizzes yet',
      createdAt: created,
      updatedAt: updated,
    );
  }

  factory ClassModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return ClassModel.fromMap(data, doc.id);
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
  }) {
    return ClassModel(
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
}

/// Data model representing a member (student or teacher) in `classes/{classId}/members/{uid}`.
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

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'role': role.toLowerCase(),
      'displayNameSnapshot': displayName,
      'emailSnapshot': email,
      'joinedAt': joinedAt != null
          ? Timestamp.fromDate(joinedAt!)
          : FieldValue.serverTimestamp(),
    };
  }

  factory ClassMember.fromMap(Map<String, dynamic> map, String id) {
    DateTime? joined;
    final rawJoined = map['joinedAt'];
    if (rawJoined is Timestamp) {
      joined = rawJoined.toDate();
    } else if (rawJoined is String) {
      joined = DateTime.tryParse(rawJoined);
    }

    return ClassMember(
      userId: map['userId'] as String? ?? id,
      role: (map['role'] as String? ?? 'student').toLowerCase(),
      displayName: map['displayNameSnapshot'] as String? ?? '',
      email: map['emailSnapshot'] as String? ?? '',
      joinedAt: joined,
    );
  }

  factory ClassMember.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return ClassMember.fromMap(data, doc.id);
  }
}
