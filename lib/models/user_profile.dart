/// Provider-neutral authenticated user exposed to the Studexa UI.
class AuthenticatedUser {
  const AuthenticatedUser({
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
  });

  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
}

/// Studexa profile stored in Supabase `public.profiles`.
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
  final String role;
  final DateTime? createdAt;
  final String? photoUrl;

  bool get isTeacher => role.toLowerCase() == 'teacher';
  bool get isStudent => role.toLowerCase() == 'student';

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'email': email.toLowerCase(),
        'displayName': displayName,
        'role': role.toLowerCase(),
        if (photoUrl != null) 'photoUrl': photoUrl,
        if (createdAt != null)
          'createdAt': createdAt!.toUtc().toIso8601String(),
      };

  Map<String, dynamic> toDatabaseMap() => {
        'id': uid,
        'email': email.toLowerCase(),
        'display_name': displayName,
        'role': role.toLowerCase(),
        if (photoUrl != null) 'photo_url': photoUrl,
        if (createdAt != null)
          'created_at': createdAt!.toUtc().toIso8601String(),
      };

  factory UserProfile.fromMap(Map<String, dynamic> map, [String? uid]) {
    DateTime? parseDate(dynamic value) =>
        value is String ? DateTime.tryParse(value)?.toLocal() : null;
    return UserProfile(
      uid: uid ?? map['id']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      displayName: map['display_name']?.toString() ??
          map['displayName']?.toString() ??
          '',
      role: (map['role']?.toString() ?? '').toLowerCase(),
      createdAt: parseDate(map['created_at'] ?? map['createdAt']),
      photoUrl: (map['photo_url'] ?? map['photoUrl'])?.toString(),
    );
  }

  UserProfile copyWith({
    String? email,
    String? displayName,
    String? role,
    DateTime? createdAt,
    String? photoUrl,
  }) =>
      UserProfile(
        uid: uid,
        email: email ?? this.email,
        displayName: displayName ?? this.displayName,
        role: role ?? this.role,
        createdAt: createdAt ?? this.createdAt,
        photoUrl: photoUrl ?? this.photoUrl,
      );
}
