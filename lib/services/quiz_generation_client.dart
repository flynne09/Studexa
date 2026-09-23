import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/integration_config.dart';
import '../config/supabase_config.dart';
import '../models/quiz_model.dart';

class QuizGenerationException implements Exception {
  const QuizGenerationException(this.message, {this.code});
  final String message;
  final String? code;
  bool get requiresApiKeySetup =>
      code == 'personal-key-required' || code == 'personal-key-invalid';
  @override
  String toString() => message;
}

/// Calls Supabase Edge Functions using a Firebase ID token. The server validates
/// ownership and saves each bounded Gemini batch to a private Firestore draft.
class QuizGenerationClient {
  QuizGenerationClient({
    this.client,
    Future<String?> Function()? tokenProvider,
    this.endpoint = IntegrationConfig.quizGenerationUrl,
    this.timeout = const Duration(seconds: 150),
  }) : _tokenProvider =
           tokenProvider ??
           (() async => FirebaseAuth.instance.currentUser?.getIdToken());

  final http.Client? client;
  final Future<String?> Function() _tokenProvider;
  final String endpoint;
  final Duration timeout;

  static String _requestId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<QuizModel> generate({
    required String teacherId,
    required String classId,
    required String materialId,
    required bool isActual,
    required List<String> questionTypes,
    required int questionCount,
    String? sourceQuizId,
    String? continueQuizId,
  }) async {
    final types = questionTypes
        .map((type) => QuizQuestionType.fromString(type).value)
        .toSet()
        .toList();
    if (teacherId.trim().isEmpty ||
        classId.trim().isEmpty ||
        materialId.trim().isEmpty) {
      throw const QuizGenerationException(
        'Sign in and choose a class and study material first.',
      );
    }
    if (questionCount < 1 ||
        questionCount > 50 ||
        types.isEmpty ||
        types.length > questionCount) {
      throw const QuizGenerationException(
        'Choose 1–50 questions and at least one question per selected type.',
      );
    }
    final uri = Uri.tryParse(endpoint);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery) {
      throw const QuizGenerationException(
        'Quiz generation is not configured correctly. Contact your administrator.',
      );
    }
    final httpClient = client ?? http.Client();
    try {
      final token = await _tokenProvider().timeout(const Duration(seconds: 15));
      if (token == null || token.isEmpty) {
        throw const QuizGenerationException(
          'Your session has ended. Sign in again to generate a quiz.',
        );
      }
      final sessionId = _requestId();
      var quizId = continueQuizId;
      QuizModel? current;
      final maxBatches = (questionCount / 10).ceil() + 3;
      for (var batch = 0; batch < maxBatches; batch++) {
        final mode = continueQuizId == null
            ? (batch == 0 ? 'initial' : 'automatic')
            : (batch == 0 ? 'extra' : 'extra_continue');
        try {
          final next = await _sendBatch(
            httpClient: httpClient,
            uri: uri,
            token: token,
            teacherId: teacherId,
            classId: classId,
            materialId: materialId,
            isActual: isActual,
            types: types,
            questionCount: questionCount,
            sourceQuizId: sourceQuizId,
            continueQuizId: quizId,
            clientSessionId: sessionId,
            batchRequestId: _requestId(),
            mode: mode,
          );
          final previousCount = current?.questionCount ?? 0;
          current = next;
          quizId = next.id;
          if (next.questionCount >= questionCount ||
              next.questionCount <= previousCount) {
            break;
          }
        } on QuizGenerationException {
          if (current != null) return current;
          rethrow;
        } on TimeoutException {
          if (current != null) return current;
          rethrow;
        } on http.ClientException {
          if (current != null) return current;
          rethrow;
        } on FormatException {
          if (current != null) return current;
          rethrow;
        } on TypeError {
          if (current != null) return current;
          rethrow;
        }
      }
      if (current == null) {
        throw const FormatException('No quiz draft returned');
      }
      return current;
    } on QuizGenerationException {
      rethrow;
    } on TimeoutException {
      throw const QuizGenerationException(
        'Quiz generation took too long. Check your connection and try again with fewer questions.',
      );
    } on FirebaseAuthException {
      throw const QuizGenerationException(
        'Could not verify your session. Check your connection and sign in again.',
      );
    } on http.ClientException {
      throw const QuizGenerationException(
        'Could not connect to the quiz service. Check your Internet connection and try again.',
      );
    } on FormatException {
      throw const QuizGenerationException(
        'The quiz service returned an invalid response. Please try again.',
      );
    } on TypeError {
      throw const QuizGenerationException(
        'The quiz service returned an invalid response. Please try again.',
      );
    } finally {
      if (client == null) httpClient.close();
    }
  }

  Future<QuizModel> _sendBatch({
    required http.Client httpClient,
    required Uri uri,
    required String token,
    required String teacherId,
    required String classId,
    required String materialId,
    required bool isActual,
    required List<String> types,
    required int questionCount,
    required String? sourceQuizId,
    required String? continueQuizId,
    required String clientSessionId,
    required String batchRequestId,
    required String mode,
  }) async {
    final supabaseHost = Uri.parse(SupabaseConfig.url).host;
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      if (uri.host == supabaseHost) 'apikey': SupabaseConfig.publishableKey,
    };
    final requestBody = jsonEncode({
      'classId': classId,
      'materialId': materialId,
      'quizType': isActual ? 'actual' : 'practice',
      'questionTypes': types,
      'questionCount': questionCount,
      'sourceQuizId': ?sourceQuizId,
      'continueQuizId': ?continueQuizId,
      'clientSessionId': clientSessionId,
      'batchRequestId': batchRequestId,
      'mode': mode,
    });
    Future<http.Response> send() => httpClient
        .post(uri, headers: headers, body: requestBody)
        .timeout(timeout);
    late http.Response response;
    try {
      response = await send();
    } on TimeoutException {
      response = await send();
    } on http.ClientException {
      response = await send();
    }
    if (response.statusCode != 200) {
      Map<String, dynamic>? errorBody;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          errorBody = Map<String, dynamic>.from(decoded);
        }
      } on FormatException {
        // Use the safe status-based message below.
      }
      const messages = {
        400: 'Check the selected document, question types and question count.',
        401: 'Your session has ended. Sign in again to generate a quiz.',
        403:
            'Only the teacher who owns this class and material can generate its quizzes.',
        404:
            'The material or quiz service could not be found. Refresh and try again.',
        412:
            'Quiz generation is not ready. Check that the material has readable text and ask your administrator to verify the AI configuration.',
        422:
            'The AI returned incomplete or unsupported questions. Try again with fewer questions.',
        429:
            'The AI service has reached its request limit. Please try again later.',
        504: 'Quiz generation took too long. Try again with fewer questions.',
      };
      throw QuizGenerationException(
        errorBody?['error']?.toString() ??
            messages[response.statusCode] ??
            'The quiz service is temporarily unavailable. Please try again.',
        code: errorBody?['code']?.toString(),
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final id = body['quizId'];
    final data = body['quiz'] as Map<String, dynamic>;
    final raw = data['questions'] as List<dynamic>;
    if (body['success'] != true ||
        id is! String ||
        id.isEmpty ||
        data['generationMethod'] != 'gemini' ||
        data['teacherId'] != teacherId ||
        data['classId'] != classId ||
        data['materialId'] != materialId ||
        data['type'] != (isActual ? 'actual' : 'practice') ||
        raw.isEmpty ||
        raw.length > questionCount ||
        raw.any(
          (q) =>
              q is! Map ||
              !(continueQuizId == null
                  ? types.contains(q['type'])
                  : QuizQuestionType.values.any(
                      (type) => type.value == q['type'],
                    )),
        )) {
      throw const FormatException('Invalid quiz response contract');
    }
    final quiz = QuizModel.fromMap(data, id: id);
    if (quiz.questions.map((q) => q.id).toSet().length != raw.length ||
        quiz.questions.any(
          (q) =>
              q.id.isEmpty ||
              q.question.trim().isEmpty ||
              q.correctAnswer.trim().isEmpty,
        ) ||
        types.any((type) => !quiz.questions.any((q) => q.type.value == type))) {
      throw const FormatException('Invalid questions');
    }
    return quiz;
  }
}
