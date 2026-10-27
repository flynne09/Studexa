/// Provider-neutral authenticated user exposed to the Studexa UI.
class AuthenticatedUser {
  /// Creates an [AuthenticatedUser] representing the currently signed-in session identity.
  const AuthenticatedUser({
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
  });

  /// Unique Supabase Auth UUID of the user.
  final String uid;

  /// Email address associated with the authenticated account.
  final String? email;

  /// User's full display name, if available from auth metadata.
  final String? displayName;

  /// Optional avatar or profile picture URL.
  final String? photoUrl;
}

/// Studexa profile stored in Supabase `public.profiles`.
class UserProfile {
  /// Creates a [UserProfile] instance with user identity and role assignment.
  const UserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    this.createdAt,
    this.photoUrl,
  });

  /// Unique user ID matching `auth.users.id`.
  final String uid;

  /// Normalized email address of the user.
  final String email;

  /// Full display name shown in class rosters, quizzes, and account menus.
  final String displayName;

  /// Immutable account role: `'teacher'` or `'student'`.
  final String role;

  /// Timestamp when the user profile was created.
  final DateTime? createdAt;

  /// Optional profile picture URL.
  final String? photoUrl;

  /// Returns `true` if this profile belongs to a Teacher account.
  bool get isTeacher => role.toLowerCase() == 'teacher';

  /// Returns `true` if this profile belongs to a Student account.
  bool get isStudent => role.toLowerCase() == 'student';

  /// Serializes this [UserProfile] to a camelCase map for domain use.
  Map<String, dynamic> toMap() => {
        'uid': uid,
        'email': email.toLowerCase(),
        'displayName': displayName,
        'role': role.toLowerCase(),
        if (photoUrl != null) 'photoUrl': photoUrl,
        if (createdAt != null)
          'createdAt': createdAt!.toUtc().toIso8601String(),
      };

  /// Serializes this [UserProfile] to a snake_case map for the `public.profiles` table.
  Map<String, dynamic> toDatabaseMap() => {
        'id': uid,
        'email': email.toLowerCase(),
        'display_name': displayName,
        'role': role.toLowerCase(),
        if (photoUrl != null) 'photo_url': photoUrl,
        if (createdAt != null)
          'created_at': createdAt!.toUtc().toIso8601String(),
      };

  /// Constructs a [UserProfile] from a database or domain map.
  factory UserProfile.fromMap(Map<String, dynamic> map, [String? uid]) {
    // Helper to parse ISO-8601 date strings into local DateTime objects.
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

  /// Creates a copy of this [UserProfile] with specified fields replaced.
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
