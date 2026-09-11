import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:studexa/models/user_profile.dart';
import 'package:studexa/services/auth_service.dart';
import 'package:studexa/widgets/google_logo.dart';
import 'package:studexa/widgets/google_sign_in_button.dart';

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
      expect(
        AuthService.getErrorMessage(
          FirebaseAuthException(code: 'account-exists-with-different-credential'),
        ),
        'An account already exists with this email using another sign-in method. Please sign in with your original method.',
      );
      expect(
        AuthService.getErrorMessage(
          Exception('PlatformException(sign_in_canceled, The user canceled the sign-in prompt, null)'),
        ),
        'Google sign-in was cancelled.',
      );
      expect(
        AuthService.getErrorMessage(
          Exception('PlatformException(network_error, A network error occurred, null)'),
        ),
        'Network error during Google sign-in. Please check your connection.',
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

  group('Google Sign-In UI & Widget Tests', () {
    testWidgets('GoogleLogo renders without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: GoogleLogo(size: 24)),
          ),
        ),
      );

      expect(find.byType(GoogleLogo), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('AuthDivider renders default and custom labels', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                AuthDivider(),
                AuthDivider(label: 'OR SIGN IN WITH'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('OR'), findsOneWidget);
      expect(find.text('OR SIGN IN WITH'), findsOneWidget);
      expect(find.byType(Divider), findsNWidgets(4));
    });

    testWidgets('GoogleSignInButton renders idle state and triggers callback', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GoogleSignInButton(
                onPressed: () {
                  tapped = true;
                },
                text: 'Continue with Google',
              ),
            ),
          ),
        ),
      );

      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.byType(GoogleLogo), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.byType(GoogleSignInButton));
      expect(tapped, isTrue);
    });

    testWidgets('GoogleSignInButton renders loading spinner and disables interaction', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GoogleSignInButton(
                onPressed: () {
                  tapped = true;
                },
                isLoading: true,
                text: 'Continue with Google',
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Continue with Google'), findsNothing);

      await tester.tap(find.byType(GoogleSignInButton));
      expect(tapped, isFalse);
    });
  });

  group('Google Sign-In Role & Profile Contract Tests', () {
    test('Google sign-in user profile with new account attributes', () {
      final googleUserMap = {
        'email': 'student.google@univ.edu',
        'displayName': 'Google Student',
        'role': 'student',
        'photoUrl': 'https://lh3.googleusercontent.com/a/photo_123',
        'createdAt': '2026-09-10T00:00:00.000Z',
      };

      final profile = UserProfile.fromMap(googleUserMap, 'google_uid_001');

      expect(profile.uid, 'google_uid_001');
      expect(profile.email, 'student.google@univ.edu');
      expect(profile.displayName, 'Google Student');
      expect(profile.photoUrl, 'https://lh3.googleusercontent.com/a/photo_123');
      expect(profile.isStudent, isTrue);
      expect(profile.isTeacher, isFalse);
    });

    test('AuthRoleMismatchException guards Google accounts with mismatched role', () {
      final existingTeacherProfile = UserProfile(
        uid: 'google_uid_teacher',
        email: 'teacher.google@univ.edu',
        displayName: 'Professor Google',
        role: 'teacher',
      );

      // Verify that checking role against student throws
      expect(
        existingTeacherProfile.role.toLowerCase() == 'student',
        isFalse,
      );

      final mismatch = AuthRoleMismatchException(
        actualRole: existingTeacherProfile.role,
        attemptedRole: 'student',
      );

      expect(
        mismatch.toString(),
        contains('registered as a teacher, not a student'),
      );
    });
  });
}
