import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_profile.dart';
import 'firestore_provider.dart';

/// Exception thrown when a user attempts to log in under a role that differs
/// from their registered account role (e.g., teacher logging in as student).
class AuthRoleMismatchException implements Exception {
  const AuthRoleMismatchException({
    required this.actualRole,
    required this.attemptedRole,
  });

  final String actualRole;
  final String attemptedRole;

  @override
  String toString() {
    return 'This account is registered as a $actualRole, not a $attemptedRole. Please select the correct role on the start screen.';
  }
}

/// Service managing user authentication with Firebase Auth and profile synchronization
/// with Cloud Firestore `users/{uid}`.
class AuthService {
  /// OAuth 2.0 Web Client ID registered in Firebase Console / Google Cloud.
  static const String webGoogleClientId =
      '669223676992-tn4l6k5tnh5n7lr6hs8imtphd0i7grhd.apps.googleusercontent.com';

  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = getAppFirestore(firestore),
        _googleSignIn = googleSignIn ??
            GoogleSignIn(
              clientId: kIsWeb ? webGoogleClientId : null,
            );

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  /// Registers a new user with email and password and creates their profile
  /// document in Cloud Firestore.
  Future<UserProfile> registerWithEmail({
    required String email,
    required String password,
    required String displayName,
    required String role,
  }) async {
    final normalizedRole = role.trim().toLowerCase();
    if (normalizedRole != 'teacher' && normalizedRole != 'student') {
      throw ArgumentError("Role must be 'teacher' or 'student'.");
    }

    final cleanEmail = email.trim().toLowerCase();
    final cleanDisplayName = displayName.trim();

    User? user;
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
      user = credential.user;
    } on FirebaseAuthException catch (e) {
      // Recovery for orphaned account: if previous registration created auth account
      // but failed during Firestore document write, retry signing in to recover and write profile.
      if (e.code == 'email-already-in-use') {
        try {
          final signInCredential = await _auth.signInWithEmailAndPassword(
            email: cleanEmail,
            password: password,
          );
          user = signInCredential.user;
          if (user != null) {
            final existing = await _usersCollection.doc(user.uid).get(
              const GetOptions(source: Source.server),
            ).timeout(const Duration(seconds: 15));
            if (existing.exists) {
              await _auth.signOut();
              rethrow; // A real duplicate account is not orphan recovery.
            }
          }
        } catch (_) {
          // Re-throw original exception if sign-in also fails (e.g. wrong password or real duplicate account)
          rethrow;
        }
      } else {
        rethrow;
      }
    }

    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-null',
        message: 'User creation failed. Please try again.',
      );
    }

    final profile = UserProfile(
      uid: user.uid,
      email: cleanEmail,
      displayName: cleanDisplayName.isNotEmpty
          ? cleanDisplayName
          : cleanEmail.split('@').first,
      role: normalizedRole,
      createdAt: DateTime.now(),
      photoUrl: user.photoURL,
    );

    // Concurrently update Firebase Auth display name and persist user profile to Firestore
    try {
      await Future.wait([
        if (cleanDisplayName.isNotEmpty)
          user.updateDisplayName(cleanDisplayName).catchError((_) {}),
        _saveUserProfile(user.uid, profile),
      ]);
    } on TimeoutException {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'database-timeout',
        message:
            'Database connection timed out. Please ensure Cloud Firestore is created in your Firebase Console.',
      );
    }

    return profile;
  }

  /// Writes user profile to Firestore with timeout guarding against uncreated databases.
  Future<void> _saveUserProfile(String uid, UserProfile profile) async {
    try {
      await _usersCollection
          .doc(uid)
          .set(profile.toMap(), SetOptions(merge: true))
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'database-timeout',
        message:
            'Database connection timed out. Please ensure Cloud Firestore is created in your Firebase Console.',
      );
    }
  }

  /// Signs in an existing user with email and password, verifies their Firestore
  /// profile, and enforces role compatibility.
  Future<UserProfile> signInWithEmail({
    required String email,
    required String password,
    required String expectedRole,
  }) async {
    final targetRole = expectedRole.trim().toLowerCase();
    if (targetRole != 'teacher' && targetRole != 'student') {
      throw ArgumentError("Choose Teacher or Student before signing in.");
    }
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-null',
        message: 'Sign-in failed. Please try again.',
      );
    }

    // Fetch user profile from Cloud Firestore
    final docSnapshot = await _usersCollection.doc(user.uid).get().timeout(const Duration(seconds: 15));
    UserProfile profile;

    if (!docSnapshot.exists || docSnapshot.data() == null) {
      // Fallback: If Firestore profile document does not exist yet, create it with the requested role
      profile = UserProfile(
        uid: user.uid,
        email: user.email ?? email.trim(),
        displayName: user.displayName ?? email.split('@').first,
        role: targetRole,
        createdAt: DateTime.now(),
        photoUrl: user.photoURL,
      );
      await _saveUserProfile(user.uid, profile);
    } else {
      profile = UserProfile.fromFirestore(docSnapshot);
    }

    // Enforce role guarding
    if (profile.role.toLowerCase() != targetRole) {
      // Sign out immediately to preserve role boundary
      await _auth.signOut();
      throw AuthRoleMismatchException(
        actualRole: profile.role,
        attemptedRole: targetRole,
      );
    }

    return profile;
  }

  /// Signs in or registers a user using Google Sign-In, syncs/verifies their
  /// Firestore profile document in `users/{uid}`, and enforces role compatibility.
  ///
  /// Returns [UserProfile] on success, or `null` if the user cancelled the sign-in prompt.
  /// Throws [AuthRoleMismatchException] if the existing account belongs to a different role.
  Future<UserProfile?> signInWithGoogle({required String role}) async {
    final normalizedRole = role.trim().toLowerCase();
    if (normalizedRole != 'teacher' && normalizedRole != 'student') {
      throw ArgumentError("Role must be 'teacher' or 'student'.");
    }

    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      // User cancelled the sign-in flow
      return null;
    }

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;
    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);
    final user = userCredential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-null',
        message: 'Google sign-in failed. Please try again.',
      );
    }

    // Check if user profile already exists in Cloud Firestore
    final docSnapshot = await _usersCollection.doc(user.uid).get().timeout(const Duration(seconds: 15));
    UserProfile profile;

    if (!docSnapshot.exists || docSnapshot.data() == null) {
      // New user: persist initial profile with selected role and Google account info
      final cleanDisplayName = (user.displayName != null &&
              user.displayName!.trim().isNotEmpty)
          ? user.displayName!.trim()
          : (googleUser.displayName != null &&
                  googleUser.displayName!.trim().isNotEmpty
              ? googleUser.displayName!.trim()
              : (user.email?.split('@').first ?? 'User'));

      profile = UserProfile(
        uid: user.uid,
        email: (user.email ?? googleUser.email).trim().toLowerCase(),
        displayName: cleanDisplayName,
        role: normalizedRole,
        createdAt: DateTime.now(),
        photoUrl: user.photoURL ?? googleUser.photoUrl,
      );

      await _saveUserProfile(user.uid, profile);
    } else {
      profile = UserProfile.fromFirestore(docSnapshot);

      // Enforce role guarding
      if (profile.role.toLowerCase() != normalizedRole) {
        // Sign out immediately to preserve role boundary
        await _auth.signOut();
        try {
          await _googleSignIn.signOut();
        } catch (_) {}
        throw AuthRoleMismatchException(
          actualRole: profile.role,
          attemptedRole: normalizedRole,
        );
      }

      // Sync avatar if existing profile didn't have one
      if (profile.photoUrl == null &&
          (user.photoURL != null || googleUser.photoUrl != null)) {
        final newPhoto = user.photoURL ?? googleUser.photoUrl;
        profile = profile.copyWith(photoUrl: newPhoto);
        _usersCollection
            .doc(user.uid)
            .update({'photoUrl': newPhoto}).catchError((_) {});
      }
    }

    return profile;
  }

  /// Retrieves the current authenticated user's Firestore profile, or null if unauthenticated.
  Future<UserProfile?> getCurrentUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final doc = await _usersCollection.doc(user.uid).get().timeout(const Duration(seconds: 15));
    if (!doc.exists || doc.data() == null) return null;
    return UserProfile.fromFirestore(doc);
  }

  /// Signs out the current user from Firebase Auth and Google Sign-In.
  Future<void> signOut() async {
    await _auth.signOut();
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }

  /// Converts common Firebase Auth & Firestore errors into friendly user-facing messages.
  static String getErrorMessage(Object error) {
    if (error is AuthRoleMismatchException) {
      return error.toString();
    }
    if (error is TimeoutException) {
      return 'The connection took too long. Check your Internet connection and try again.';
    }
    if (error is ArgumentError) {
      return error.message?.toString() ?? error.toString();
    }

    final rawStr = error.toString();
    if (rawStr.toUpperCase().contains('CONFIGURATION_NOT_FOUND')) {
      return 'Firebase Authentication is not enabled for this project. Please go to Firebase Console > Authentication > Sign-in method and enable Email/Password.';
    }
    if (rawStr.contains('sign_in_canceled') || rawStr.contains('canceled')) {
      return 'Google sign-in was cancelled.';
    }
    if (rawStr.contains('network_error')) {
      return 'Network error during Google sign-in. Please check your connection.';
    }

    if (error is FirebaseAuthException) {
      final code = error.code.toLowerCase();
      if (code.contains('configuration-not-found') ||
          (error.message != null &&
              error.message!.toUpperCase().contains('CONFIGURATION_NOT_FOUND'))) {
        return 'Firebase Authentication is not enabled for this project. Please go to Firebase Console > Authentication > Sign-in method and enable Email/Password.';
      }

      switch (code) {
        case 'user-not-found':
          return 'No user found with this email address.';
        case 'wrong-password':
          return 'Incorrect password. Please try again.';
        case 'invalid-credential':
          return 'Invalid email or password. Please check your credentials.';
        case 'email-already-in-use':
          return 'An account already exists with this email address.';
        case 'account-exists-with-different-credential':
          return 'An account already exists with this email using another sign-in method. Please sign in with your original method.';
        case 'invalid-email':
          return 'The email address is invalid.';
        case 'weak-password':
          return 'Password must be at least 6 characters.';
        case 'user-disabled':
          return 'This account has been disabled.';
        case 'too-many-requests':
          return 'Too many attempts. Please try again in a few minutes.';
        case 'network-request-failed':
          return 'Network error. Please check your internet connection.';
        case 'operation-not-allowed':
          return 'Email/password sign-in is not enabled. Please enable it in Firebase Console under Authentication > Sign-in method.';
        default:
          return error.message ?? 'Authentication error occurred.';
      }
    }
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'Permission denied when accessing user profile. Please try again.';
        case 'unavailable':
          return 'Database service is temporarily unavailable. Please check your connection.';
        case 'database-timeout':
          return 'Database connection timed out. Please ensure Cloud Firestore is created in your Firebase Console.';
        case 'not-found':
          return 'Cloud Firestore database was not found. Please click "Create database" in Firebase Console > Firestore Database.';
        default:
          return error.message ?? 'A database error occurred (${error.code}).';
      }
    }
    return error.toString();
  }
}
