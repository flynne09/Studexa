import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/user_profile.dart';

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

class EmailConfirmationRequiredException implements Exception {
  const EmailConfirmationRequiredException(this.email);
  final String email;

  @override
  String toString() =>
      'Check $email for a verification link, then return to Studexa and sign in.';
}

/// Authentication and immutable Studexa role management backed by Supabase.
class AuthService {
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

  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

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

  Future<UserProfile> registerWithEmail({
    required String email,
    required String password,
    required String displayName,
    required String role,
  }) async {
    final normalizedRole = _validatedRole(role);
    final cleanEmail = email.trim().toLowerCase();
    final cleanName = displayName.trim();
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
      await _client.auth.signOut();
      rethrow;
    }
  }

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

  Future<void> signOut() async {
    await _client.auth.signOut();
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }

  static String _validatedRole(String role) {
    final value = role.trim().toLowerCase();
    if (value != 'teacher' && value != 'student') {
      throw ArgumentError("Role must be 'teacher' or 'student'.");
    }
    return value;
  }

  static String? _displayName(User user) =>
      (user.userMetadata?['display_name'] ??
              user.userMetadata?['full_name'] ??
              user.userMetadata?['name'])
          ?.toString();

  static String? _photoUrl(User user) =>
      (user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'])
          ?.toString();

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
