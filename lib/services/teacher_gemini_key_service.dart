import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/integration_config.dart';
import '../config/supabase_config.dart';

/// Represents the current configuration and quota status of a teacher's personal Gemini API key.
class TeacherGeminiKeyStatus {
  const TeacherGeminiKeyStatus({
    required this.configured,
    required this.validationStatus,
    required this.graceRemaining,
    required this.fallbackRemainingToday,
    this.maskedKey,
  });

  /// Whether a personal Gemini API key is saved for this teacher.
  final bool configured;

  /// Validation status of the saved key (e.g., `'valid'`, `'invalid'`, `'missing'`).
  final String validationStatus;

  /// Masked representation of the API key for safe display in the UI.
  final String? maskedKey;

  /// Remaining grace-period generations before a personal key is strictly required.
  final int graceRemaining;

  /// Remaining daily fallback generations allowed using the shared system key.
  final int fallbackRemainingToday;

  /// Returns `true` when a personal API key is both configured and verified as valid.
  bool get isReady => configured && validationStatus == 'valid';

  /// Constructs a [TeacherGeminiKeyStatus] from a JSON map returned by the Edge Function.
  factory TeacherGeminiKeyStatus.fromMap(Map<String, dynamic> map) {
    return TeacherGeminiKeyStatus(
      configured: map['configured'] == true,
      validationStatus: map['status']?.toString() ?? 'missing',
      maskedKey: map['maskedKey'] as String?,
      graceRemaining: (map['graceRemaining'] as num?)?.toInt() ?? 0,
      fallbackRemainingToday:
          (map['fallbackRemainingToday'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Exception thrown when reading, verifying, or deleting a teacher's Gemini API key fails.
class TeacherGeminiKeyException implements Exception {
  const TeacherGeminiKeyException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => message;
}

/// Service that communicates with the `teacher-gemini-key` Supabase Edge Function
/// to inspect, save/verify, or remove a teacher's personal Gemini API key.
class TeacherGeminiKeyService {
  /// Creates a [TeacherGeminiKeyService] with optional HTTP client and token provider overrides for testing.
  TeacherGeminiKeyService({
    this.client,
    Future<String?> Function()? tokenProvider,
    this.endpoint = IntegrationConfig.teacherGeminiKeyUrl,
  }) : _tokenProvider =
           tokenProvider ??
           (() async => Supabase.instance.client.auth.currentSession?.accessToken);

  final http.Client? client;
  final Future<String?> Function() _tokenProvider;
  final String endpoint;

  /// Fetches the teacher's current Gemini API key status and remaining fallback quota.
  Future<TeacherGeminiKeyStatus> getStatus() => _request('GET');

  /// Saves and verifies a new personal Gemini API key on the backend.
  Future<TeacherGeminiKeyStatus> saveAndVerify(String apiKey) =>
      _request('PUT', apiKey: apiKey.trim());

  /// Deletes the teacher's stored personal Gemini API key from the backend.
  Future<TeacherGeminiKeyStatus> remove() => _request('DELETE');

  /// Internal helper that sends an authenticated HTTP request (`GET`, `PUT`, or `DELETE`)
  /// to the teacher Gemini key Edge Function and parses the resulting [TeacherGeminiKeyStatus].
  Future<TeacherGeminiKeyStatus> _request(
    String method, {
    String? apiKey,
  }) async {
    // Validate that the configured endpoint is a clean HTTPS URL.
    final uri = Uri.tryParse(endpoint);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery) {
      throw const TeacherGeminiKeyException(
        'Gemini API Settings are not configured correctly.',
      );
    }
    // Retrieve the current user's Supabase JWT access token.
    String? token;
    try {
      token = await _tokenProvider().timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const TeacherGeminiKeyException(
        'Session verification took too long. Check your connection and try again.',
      );
    } on AuthException {
      throw const TeacherGeminiKeyException(
        'Could not verify your session. Sign in again.',
      );
    }
    if (token == null || token.isEmpty) {
      throw const TeacherGeminiKeyException(
        'Your session has ended. Sign in again.',
      );
    }
    final ownedClient = client ?? http.Client();
    try {
      final request = http.Request(method, uri)
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'apikey': SupabaseConfig.publishableKey,
          'Content-Type': 'application/json',
        });
      if (apiKey != null) request.body = jsonEncode({'apiKey': apiKey});
      final streamed = await ownedClient
          .send(request)
          .timeout(const Duration(seconds: 25));
      final response = await http.Response.fromStream(streamed);
      Map<String, dynamic> body;
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } on Object {
        throw const TeacherGeminiKeyException(
          'Gemini API Settings returned an invalid response.',
        );
      }
      if (response.statusCode != 200 || body['success'] != true) {
        throw TeacherGeminiKeyException(
          body['error']?.toString() ??
              'Gemini API Settings are temporarily unavailable.',
          code: body['code']?.toString(),
        );
      }
      final rawStatus = body['status'];
      if (rawStatus is! Map) {
        throw const TeacherGeminiKeyException(
          'Gemini API Settings returned an invalid response.',
        );
      }
      return TeacherGeminiKeyStatus.fromMap(
        Map<String, dynamic>.from(rawStatus),
      );
    } on TimeoutException {
      throw const TeacherGeminiKeyException(
        'The request took too long. Check your connection and try again.',
      );
    } on AuthException {
      throw const TeacherGeminiKeyException(
        'Could not verify your session. Sign in again.',
      );
    } on http.ClientException {
      throw const TeacherGeminiKeyException(
        'Could not connect to Gemini API Settings. Check your connection.',
      );
    } finally {
      // Close the temporary HTTP client if it was created internally for this request.
      if (client == null) ownedClient.close();
    }
  }
}
