import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/integration_config.dart';
import '../config/supabase_config.dart';

class TeacherGeminiKeyStatus {
  const TeacherGeminiKeyStatus({
    required this.configured,
    required this.validationStatus,
    required this.graceRemaining,
    required this.fallbackRemainingToday,
    this.maskedKey,
  });

  final bool configured;
  final String validationStatus;
  final String? maskedKey;
  final int graceRemaining;
  final int fallbackRemainingToday;

  bool get isReady => configured && validationStatus == 'valid';

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

class TeacherGeminiKeyException implements Exception {
  const TeacherGeminiKeyException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => message;
}

class TeacherGeminiKeyService {
  TeacherGeminiKeyService({
    this.client,
    Future<String?> Function()? tokenProvider,
    this.endpoint = IntegrationConfig.teacherGeminiKeyUrl,
  }) : _tokenProvider =
           tokenProvider ??
           (() async => FirebaseAuth.instance.currentUser?.getIdToken());

  final http.Client? client;
  final Future<String?> Function() _tokenProvider;
  final String endpoint;

  Future<TeacherGeminiKeyStatus> getStatus() => _request('GET');

  Future<TeacherGeminiKeyStatus> saveAndVerify(String apiKey) =>
      _request('PUT', apiKey: apiKey.trim());

  Future<TeacherGeminiKeyStatus> remove() => _request('DELETE');

  Future<TeacherGeminiKeyStatus> _request(
    String method, {
    String? apiKey,
  }) async {
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
    String? token;
    try {
      token = await _tokenProvider().timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const TeacherGeminiKeyException(
        'Session verification took too long. Check your connection and try again.',
      );
    } on FirebaseAuthException {
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
    } on FirebaseAuthException {
      throw const TeacherGeminiKeyException(
        'Could not verify your session. Sign in again.',
      );
    } on http.ClientException {
      throw const TeacherGeminiKeyException(
        'Could not connect to Gemini API Settings. Check your connection.',
      );
    } finally {
      if (client == null) ownedClient.close();
    }
  }
}
