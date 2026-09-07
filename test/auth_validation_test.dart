import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:studexa/models/user_profile.dart';
import 'package:studexa/services/auth_service.dart';

void main() {
  group('UserProfile Model Tests', () {
    test('serializes to map correctly', () {
      final profile = UserProfile(
        uid: 'user_123',
        email: 'teacher@school.edu',
        displayName: 'Professor Charles',
        role: 'teacher',
        createdAt: DateTime(2026, 1, 15),
      );

      final map = profile.toMap();

      expect(map['uid'], 'user_123');
      expect(map['email'], 'teacher@school.edu');
      expect(map['displayName'], 'Professor Charles');
      expect(map['role'], 'teacher');
      expect(profile.isTeacher, isTrue);
      expect(profile.isStudent, isFalse);
    });

    test('deserializes from map with String date fallback', () {
      final map = {
        'email': 'student@school.edu',
        'displayName': 'Alex Morgan',
        'role': 'student',
        'createdAt': '2026-02-20T10:00:00.000Z',
      };

      final profile = UserProfile.fromMap(map, 'stu_999');

      expect(profile.uid, 'stu_999');
      expect(profile.email, 'student@school.edu');
      expect(profile.displayName, 'Alex Morgan');
      expect(profile.role, 'student');
      expect(profile.isStudent, isTrue);
      expect(profile.isTeacher, isFalse);
      expect(profile.createdAt?.year, 2026);
    });

    test('case-insensitivity of roles', () {
      final profileTeacher = UserProfile(
        uid: 't1',
        email: 't@s.edu',
        displayName: 'Teacher',
        role: 'Teacher',
      );
      expect(profileTeacher.isTeacher, isTrue);

      final profileStudent = UserProfile(
        uid: 's1',
        email: 's@s.edu',
        displayName: 'Student',
        role: 'STUDENT',
      );
      expect(profileStudent.isStudent, isTrue);
    });
  });

  group('Auth Validation & Error Mapping Tests', () {
    test('AuthRoleMismatchException string format', () {
      const exception = AuthRoleMismatchException(
        actualRole: 'teacher',
        attemptedRole: 'student',
      );

      expect(
        exception.toString(),
        contains('registered as a teacher, not a student'),
      );
    });

    test('AuthService.getErrorMessage mappings for AuthRoleMismatchException', () {
      expect(
        AuthService.getErrorMessage(
          const AuthRoleMismatchException(
            actualRole: 'student',
            attemptedRole: 'teacher',
          ),
        ),
        contains('registered as a student, not a teacher'),
      );
    });

    test('AuthService.getErrorMessage mappings for FirebaseAuthException', () {
      expect(
        AuthService.getErrorMessage(
          FirebaseAuthException(code: 'email-already-in-use'),
        ),
        'An account already exists with this email address.',
      );
      expect(
        AuthService.getErrorMessage(
          FirebaseAuthException(code: 'weak-password'),
        ),
        'Password must be at least 6 characters.',
      );
      expect(
        AuthService.getErrorMessage(
          FirebaseAuthException(code: 'invalid-email'),
        ),
        'The email address is invalid.',
      );
      expect(
        AuthService.getErrorMessage(
          FirebaseAuthException(code: 'operation-not-allowed'),
        ),
        'Email/password sign-in is not enabled. Please enable it in Firebase Console under Authentication > Sign-in method.',
      );
      expect(
        AuthService.getErrorMessage(
          FirebaseAuthException(code: 'configuration-not-found'),
        ),
        'Firebase Authentication is not enabled for this project. Please go to Firebase Console > Authentication > Sign-in method and enable Email/Password.',
      );
      expect(
        AuthService.getErrorMessage(
          Exception('Failed to load resource: the server responded with a status of 400 (CONFIGURATION_NOT_FOUND)'),
        ),
        'Firebase Authentication is not enabled for this project. Please go to Firebase Console > Authentication > Sign-in method and enable Email/Password.',
      );
      expect(
        AuthService.getErrorMessage(
          FirebaseAuthException(code: 'network-request-failed'),
        ),
        'Network error. Please check your internet connection.',
      );
    });

    test('AuthService.getErrorMessage mappings for FirebaseException', () {
      expect(
        AuthService.getErrorMessage(
          FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
        ),
        'Permission denied when accessing user profile. Please try again.',
      );
      expect(
        AuthService.getErrorMessage(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        ),
        'Database service is temporarily unavailable. Please check your connection.',
      );
      expect(
        AuthService.getErrorMessage(
          FirebaseException(plugin: 'cloud_firestore', code: 'database-timeout'),
        ),
        'Database connection timed out. Please ensure Cloud Firestore is created in your Firebase Console.',
      );
      expect(
        AuthService.getErrorMessage(
          FirebaseException(plugin: 'cloud_firestore', code: 'not-found'),
        ),
        'Cloud Firestore database was not found. Please click "Create database" in Firebase Console > Firestore Database.',
      );
    });

    test('AuthService.getErrorMessage mappings for ArgumentError', () {
      expect(
        AuthService.getErrorMessage(
          ArgumentError("Role must be 'teacher' or 'student'."),
        ),
        contains("Role must be 'teacher' or 'student'."),
      );
    });

    test('Registration email format validation check', () {
      final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
      expect(emailRegex.hasMatch('valid@school.edu'), isTrue);
      expect(emailRegex.hasMatch('student123@university.ac.uk'), isTrue);
      expect(emailRegex.hasMatch('teacher.name+tag@sub.domain.org'), isTrue);
      expect(emailRegex.hasMatch('invalid-email'), isFalse);
      expect(emailRegex.hasMatch('no-at.com'), isFalse);
      expect(emailRegex.hasMatch('@nodomain.com'), isFalse);
      expect(emailRegex.hasMatch('test@domain'), isFalse);
      expect(emailRegex.hasMatch('test@.com'), isFalse);
    });

    test('Password validation rules', () {
      bool isValidPassword(String password) => password.length >= 6;
      expect(isValidPassword('12345'), isFalse);
      expect(isValidPassword('123456'), isTrue);
      expect(isValidPassword('strongSecretPass!'), isTrue);
    });

    test('Password confirmation matching', () {
      bool passwordsMatch(String p1, String p2) => p1 == p2;
      expect(passwordsMatch('password123', 'password123'), isTrue);
      expect(passwordsMatch('password123', 'password456'), isFalse);
    });
  });
}
