import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents an authenticated Studexa user profile stored in Firestore `users/{uid}`.
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    this.createdAt,
    this.photoUrl,
  });

  final String uid;
  final String email;
  final String displayName;
  /// Role must be 'teacher' or 'student'.
  final String role;
  final DateTime? createdAt;
  final String? photoUrl;

  bool get isTeacher => role.toLowerCase() == 'teacher';
  bool get isStudent => role.toLowerCase() == 'student';

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email.toLowerCase(),
      'displayName': displayName,
      'role': role.toLowerCase(),
      if (photoUrl != null) 'photoUrl': photoUrl,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map, String uid) {
    DateTime? created;
    final rawCreated = map['createdAt'];
    if (rawCreated is Timestamp) {
      created = rawCreated.toDate();
    } else if (rawCreated is String) {
      created = DateTime.tryParse(rawCreated);
    }

    return UserProfile(
      uid: uid,
      email: map['email'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
      role: (map['role'] as String? ?? 'student').toLowerCase(),
      createdAt: created,
      photoUrl: map['photoUrl'] as String?,
    );
  }

  factory UserProfile.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return UserProfile.fromMap(data, doc.id);
  }

  UserProfile copyWith({
    String? email,
    String? displayName,
    String? role,
    DateTime? createdAt,
    String? photoUrl,
  }) {
    return UserProfile(
      uid: uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }
}
