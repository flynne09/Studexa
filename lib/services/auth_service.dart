import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/user_profile.dart';

/// Exception thrown when a user attempts to sign in with a role (Teacher or Student)
/// that does not match the immutable role assigned to their account at registration.
class AuthRoleMismatchException implements Exception {
  const AuthRoleMismatchException({
    required this.actualRole,
    required this.attemptedRole,
  });

  final String actualRole;
  final String attemptedRole;

  @override
  String toString() =>
      'This account is registered as a $actualRole, not a $attemptedRole. Please select the correct role on the start screen.';
}

/// Exception thrown after email sign-up when Supabase requires the user
/// to click a confirmation link sent to their email before establishing a session.
class EmailConfirmationRequiredException implements Exception {
  const EmailConfirmationRequiredException(this.email);
  final String email;

  @override
  String toString() =>
      'Check $email for a verification link, then return to Studexa and sign in.';
}

/// Authentication and immutable Studexa role management backed by Supabase.
class AuthService {
  /// Initializes [AuthService] with optional dependency injection for [SupabaseClient]
  /// and [GoogleSignIn] (configured for either web or native platforms).
  AuthService({SupabaseClient? client, GoogleSignIn? googleSignIn})
      : _injectedClient = client,
        _googleSignIn = googleSignIn ??
            GoogleSignIn(
              clientId: kIsWeb && SupabaseConfig.googleWebClientId.isNotEmpty
                  ? SupabaseConfig.googleWebClientId
                  : null,
              serverClientId:
                  !kIsWeb && SupabaseConfig.googleWebClientId.isNotEmpty
                      ? SupabaseConfig.googleWebClientId
                      : null,
            );

  final SupabaseClient? _injectedClient;
  final GoogleSignIn _googleSignIn;

  /// Resolves the active [SupabaseClient] instance.
  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  /// Returns a lightweight [AuthenticatedUser] snapshot for the currently signed-in user,
  /// or `null` if no session is active.
  AuthenticatedUser? get currentUser {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    return AuthenticatedUser(
      uid: user.id,
      email: user.email,
      displayName: _displayName(user),
      photoUrl: _photoUrl(user),
    );
  }

  /// Emits updates whenever the user's authentication session changes (sign-in, sign-out, token refresh).
  Stream<AuthenticatedUser?> get authStateChanges =>
      _client.auth.onAuthStateChange.map((event) {
        final user = event.session?.user;
        if (user == null) return null;
        return AuthenticatedUser(
          uid: user.id,
          email: user.email,
          displayName: _displayName(user),
          photoUrl: _photoUrl(user),
        );
      });

  /// Registers a new user account with email, password, display name, and chosen role.
  /// Throws [EmailConfirmationRequiredException] if email verification is enabled and pending,
  /// otherwise claims the role and loads the full [UserProfile].
  Future<UserProfile> registerWithEmail({
    required String email,
    required String password,
    required String displayName,
    required String role,
  }) async {
    final normalizedRole = _validatedRole(role);
    final cleanEmail = email.trim().toLowerCase();
    final cleanName = displayName.trim();
    // Create the user in Supabase Auth with initial metadata for role and display name.
    final response = await _client.auth.signUp(
      email: cleanEmail,
      password: password,
      emailRedirectTo:
          kIsWeb ? Uri.base.origin : SupabaseConfig.authCallbackUrl,
      data: {
        'studexa_role': normalizedRole,
        'display_name': cleanName.isEmpty
            ? cleanEmail.split('@').first
            : cleanName,
      },
    );
    if (response.user == null) {
      throw const AuthException('Account creation failed. Please try again.');
    }
    if (response.session == null) {
      throw EmailConfirmationRequiredException(cleanEmail);
    }
    return _claimAndLoadProfile(normalizedRole);
  }

  /// Signs in an existing user with email and password, verifying that their
  /// registered profile role matches [expectedRole]. Signs out immediately on mismatch.
  Future<UserProfile> signInWithEmail({
    required String email,
    required String password,
    required String expectedRole,
  }) async {
    final role = _validatedRole(expectedRole);
    await _client.auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    try {
      return await _claimAndLoadProfile(role);
    } catch (_) {
      // Ensure the session is cleared if role validation or profile loading fails.
      await _client.auth.signOut();
      rethrow;
    }
  }

  /// Authenticates the user via Google OAuth and exchanges the Google ID/access tokens
  /// for a Supabase session, then claims or verifies the user's [role].
  /// Returns `null` if the user cancels the Google sign-in prompt.
  Future<UserProfile?> signInWithGoogle({required String role}) async {
    final normalizedRole = _validatedRole(role);
    if (SupabaseConfig.googleWebClientId.trim().isEmpty) {
      throw const AuthException(
        'Google sign-in is not configured for this build.',
      );
    }
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;
    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;
    if (idToken == null || idToken.isEmpty || accessToken == null) {
      throw const AuthException(
        'Google did not return the credentials required to sign in.',
      );
    }
    // Sign in to Supabase using the OAuth tokens issued by Google.
    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
    try {
      return await _claimAndLoadProfile(normalizedRole);
    } catch (e) {
      debugPrint('Google sign in profile claim error: $e');
      await _client.auth.signOut();
      await _googleSignIn.signOut().catchError((_) => null);
      rethrow;
    }
  }

  /// Invokes the `claim_studexa_role` Postgres RPC to atomically bind or verify
  /// the user's role in the `profiles` table, throwing [AuthRoleMismatchException]
  /// if the account already belongs to the opposite role.
  Future<UserProfile> _claimAndLoadProfile(String expectedRole) async {
    dynamic response;
    try {
      response = await _client.rpc(
        'claim_studexa_role',
        params: {'p_role': expectedRole},
      );
    } on PostgrestException catch (error) {
      final match = RegExp(
        r'registered as a (teacher|student), not a (teacher|student)',
        caseSensitive: false,
      ).firstMatch(error.message);
      if (match != null) {
        throw AuthRoleMismatchException(
          actualRole: match.group(1)!.toLowerCase(),
          attemptedRole: match.group(2)!.toLowerCase(),
        );
      }
      rethrow;
    }
    // Normalize the RPC response (which may be a single Map or a single-element List).
    final map = response is Map
        ? Map<String, dynamic>.from(response)
        : response is List && response.isNotEmpty && response.first is Map
            ? Map<String, dynamic>.from(response.first as Map)
            : null;
    final profile = map == null
        ? await getCurrentUserProfile()
        : UserProfile.fromMap(map);
    if (profile == null || profile.role.isEmpty) {
      throw const AuthException('Your Studexa profile could not be loaded.');
    }
    if (profile.role != expectedRole) {
      throw AuthRoleMismatchException(
        actualRole: profile.role,
        attemptedRole: expectedRole,
      );
    }
    return profile;
  }

  /// Queries the `profiles` table for the currently authenticated user's profile record.
  Future<UserProfile?> getCurrentUserProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final data = await _client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    if (data == null) return null;
    return UserProfile.fromMap(Map<String, dynamic>.from(data));
  }

  /// Signs the user out of both Supabase Auth and Google Sign-In.
  Future<void> signOut() async {
    await _client.auth.signOut();
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }

  /// Validates and normalizes a role string to lowercase `'teacher'` or `'student'`.
  static String _validatedRole(String role) {
    final value = role.trim().toLowerCase();
    if (value != 'teacher' && value != 'student') {
      throw ArgumentError("Role must be 'teacher' or 'student'.");
    }
    return value;
  }

  /// Extracts a human-readable display name from Supabase user metadata.
  static String? _displayName(User user) =>
      (user.userMetadata?['display_name'] ??
              user.userMetadata?['full_name'] ??
              user.userMetadata?['name'])
          ?.toString();

  /// Extracts a profile avatar URL from Supabase user metadata.
  static String? _photoUrl(User user) =>
      (user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'])
          ?.toString();

  /// Translates raw auth, database, platform, or network exceptions into
  /// user-friendly error messages suitable for UI display.
  static String getErrorMessage(Object error) {
    if (error is EmailConfirmationRequiredException ||
        error is AuthRoleMismatchException) {
      return error.toString();
    }
    if (error is TimeoutException) {
      return 'The connection took too long. Check your Internet connection and try again.';
    }
    if (error is ArgumentError) {
      return error.message?.toString() ?? error.toString();
    }
    if (error is AuthException) {
      final message = error.message.toLowerCase();
      if (message.contains('invalid login credentials')) {
        return 'Invalid email or password. Please check your credentials.';
      }
      if (message.contains('email not confirmed')) {
        return 'Confirm your email first, then return to Studexa and sign in.';
      }
      if (message.contains('already registered') ||
          message.contains('already exists')) {
        return 'An account already exists with this email address.';
      }
      if (message.contains('password')) {
        return 'Password must be at least 6 characters.';
      }
      if (message.contains('rate limit')) {
        return 'Too many attempts. Please try again in a few minutes.';
      }
      return error.message;
    }
    if (error is PostgrestException) {
      return error.message;
    }
    if (error is PlatformException) {
      final code = error.code;
      final message = error.message ?? '';
      if (message.contains('10') || code.contains('10')) {
        return 'Google Sign-In configuration error (ApiException: 10). Ensure the SHA-1 matches and your account is added under Test Users in Google Cloud Console.';
      }
      if (message.contains('12500') || code.contains('12500')) {
        return 'Google Sign-In failed (ApiException: 12500). Check Google Cloud OAuth consent configuration.';
      }
      if (code == 'sign_in_failed') {
        return 'Google sign-in could not be completed. ($message)';
      }
      return error.message ?? error.code;
    }
    final raw = error.toString();
    if (raw.contains('sign_in_canceled') || raw.contains('canceled')) {
      return 'Google sign-in was cancelled.';
    }
    if (raw.contains('SocketException') || raw.contains('network_error')) {
      return 'Network error. Please check your internet connection.';
    }
    return 'Studexa could not complete this request. Please try again.';
  }
}
