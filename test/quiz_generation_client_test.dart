import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:studexa/services/quiz_generation_client.dart';

Map<String, dynamic> validResponse() => {
  'success': true,
  'quizId': 'quiz-1',
  'quiz': {
    'classId': 'class-1',
    'materialId': 'material-1',
    'teacherId': 'teacher-1',
    'type': 'actual',
    'title': 'Processes',
    'generationMethod': 'gemini',
    'questions': [
      {
        'id': 'q_1',
        'type': 'identification',
        'question': 'Name a program in execution.',
        'correctAnswer': 'process',
      },
    ],
  },
};
Future<dynamic> generate(QuizGenerationClient client) => client.generate(
  teacherId: 'teacher-1',
  classId: 'class-1',
  materialId: 'material-1',
  isActual: true,
  questionTypes: ['Identification'],
  questionCount: 1,
);

void main() {
  test('uses ID token, canonical types and saved server quiz', () async {
    final client = QuizGenerationClient(
      tokenProvider: () async => 'test-token',
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer test-token');
        final body = jsonDecode(request.body) as Map;
        expect(body['questionTypes'], ['identification']);
        expect(body['questionCount'], 1);
        expect(body.containsKey('teacherId'), isFalse);
        expect(body.containsKey('apiKey'), isFalse);
        return http.Response(jsonEncode(validResponse()), 200);
      }),
    );
    final quiz = await generate(client);
    expect(quiz.id, 'quiz-1');
    expect(quiz.questions.single.correctAnswer, 'process');
  });
  test('signed-out request never reaches network', () async {
    final client = QuizGenerationClient(
      tokenProvider: () async => null,
      client: MockClient((_) async => throw StateError('must not call')),
    );
    await expectLater(
      generate(client),
      throwsA(
        isA<QuizGenerationException>().having(
          (e) => e.message,
          'message',
          contains('Sign in'),
        ),
      ),
    );
  });
  test('rejects unsafe endpoint before attaching a token', () async {
    final client = QuizGenerationClient(
      endpoint: 'http://example.com',
      tokenProvider: () async => throw StateError('must not read token'),
    );
    await expectLater(
      generate(client),
      throwsA(isA<QuizGenerationException>()),
    );
  });
  for (final status in [401, 403, 404, 412, 422, 429, 500, 504]) {
    test('HTTP $status becomes a friendly error without raw details', () async {
      final client = QuizGenerationClient(
        tokenProvider: () async => 'test-token',
        client: MockClient(
          (_) async => http.Response('private upstream diagnostics', status),
        ),
      );
      await expectLater(
        generate(client),
        throwsA(
          isA<QuizGenerationException>().having(
            (e) => e.message,
            'message',
            isNot(contains('private')),
          ),
        ),
      );
    });
  }
  test(
    'rejects malformed JSON and responses that silently used fallback',
    () async {
      for (final payload in [
        'not json',
        '{}',
        jsonEncode(validResponse()..['quiz']['generationMethod'] = 'fallback'),
        jsonEncode(validResponse()..['quiz']['questions'] = []),
      ]) {
        final client = QuizGenerationClient(
          tokenProvider: () async => 'test-token',
          client: MockClient((_) async => http.Response(payload, 200)),
        );
        await expectLater(
          generate(client),
          throwsA(isA<QuizGenerationException>()),
        );
      }
    },
  );
  test('preserves actionable validation and quota messages for the UI', () async {
    const expectedMessages = {
      422:
          'The AI returned incomplete or unsupported questions. Try again with fewer questions.',
      429:
          'The AI service has reached its request limit. Please try again later.',
    };
    for (final entry in expectedMessages.entries) {
      var calls = 0;
      final client = QuizGenerationClient(
        tokenProvider: () async => 'test-token',
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', entry.key);
        }),
      );
      await expectLater(
        generate(client),
        throwsA(
          isA<QuizGenerationException>().having(
            (e) => e.message,
            'message',
            entry.value,
          ),
        ),
      );
      expect(calls, 1);
    }
  });
  test(
    'network and timeout failures do not create a substitute quiz',
    () async {
      for (final failure in [
        http.ClientException('network'),
        TimeoutException('timeout'),
      ]) {
        final client = QuizGenerationClient(
          tokenProvider: () async => 'test-token',
          client: MockClient((_) async => throw failure),
        );
        await expectLater(
          generate(client),
          throwsA(isA<QuizGenerationException>()),
        );
      }
    },
  );
}
