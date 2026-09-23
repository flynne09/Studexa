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
        expect(body['mode'], 'initial');
        expect(body['clientSessionId'], isA<String>());
        expect(body['batchRequestId'], isA<String>());
        expect(body.containsKey('teacherId'), isFalse);
        expect(body.containsKey('apiKey'), isFalse);
        return http.Response(jsonEncode(validResponse()), 200);
      }),
    );
    final quiz = await generate(client);
    expect(quiz.id, 'quiz-1');
    expect(quiz.questions.single.correctAnswer, 'process');
  });
  test(
    'saves a shortfall draft and uses one separate Generate more action',
    () async {
      var calls = 0;
      final client = QuizGenerationClient(
        tokenProvider: () async => 'test-token',
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          calls++;
          expect(body['clientSessionId'], isA<String>());
          expect(body['batchRequestId'], isA<String>());
          if (calls == 1) expect(body['mode'], 'initial');
          if (calls == 2) {
            expect(body['mode'], 'automatic');
            expect(body['continueQuizId'], 'quiz-1');
          }
          if (calls == 3) {
            expect(body['mode'], 'extra');
            expect(body['continueQuizId'], 'quiz-1');
          }
          final payload = validResponse();
          payload['quiz']['requestedQuestionCount'] = 3;
          payload['quiz']['selectedQuestionTypes'] = ['identification'];
          payload['quiz']['extraGenerationAttempted'] = calls == 3;
          if (calls == 3) {
            payload['quiz']['questions'].add({
              'id': 'q_2',
              'type': 'identification',
              'question': 'Name the component that schedules the CPU.',
              'correctAnswer': 'kernel',
            });
            payload['quiz']['questions'].add({
              'id': 'q_3',
              'type': 'true_false',
              'question': 'RAM stores active programs.',
              'correctAnswer': 'True',
              'origin': 'manual',
            });
          }
          return http.Response(jsonEncode(payload), 200);
        }),
      );
      final first = await client.generate(
        teacherId: 'teacher-1',
        classId: 'class-1',
        materialId: 'material-1',
        isActual: true,
        questionTypes: ['Identification'],
        questionCount: 3,
      );
      expect(first.hasGenerationShortfall, isTrue);
      final second = await client.generate(
        teacherId: 'teacher-1',
        classId: 'class-1',
        materialId: 'material-1',
        isActual: true,
        questionTypes: ['Identification'],
        questionCount: 3,
        continueQuizId: first.id,
      );
      expect(second.questionCount, 3);
      expect(second.extraGenerationAttempted, isTrue);
      expect(second.questions.last.origin, 'manual');
      expect(calls, 3);
    },
  );
  test('coordinates 50 questions in five 10-question batches', () async {
    var calls = 0;
    String? sessionId;
    final client = QuizGenerationClient(
      tokenProvider: () async => 'test-token',
      client: MockClient((request) async {
        calls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(request.headers['apikey'], isNotEmpty);
        sessionId ??= body['clientSessionId'] as String;
        expect(body['clientSessionId'], sessionId);
        expect(body['mode'], calls == 1 ? 'initial' : 'automatic');
        if (calls > 1) expect(body['continueQuizId'], 'quiz-1');
        final payload = validResponse();
        payload['quiz']['requestedQuestionCount'] = 50;
        payload['quiz']['selectedQuestionTypes'] = ['identification'];
        payload['quiz']['questions'] = List.generate(
          calls * 10,
          (index) => {
            'id': 'q_${index + 1}',
            'type': 'identification',
            'question': 'Distinct question ${index + 1}?',
            'correctAnswer': 'answer ${index + 1}',
          },
        );
        return http.Response(jsonEncode(payload), 200);
      }),
    );
    final quiz = await client.generate(
      teacherId: 'teacher-1',
      classId: 'class-1',
      materialId: 'material-1',
      isActual: true,
      questionTypes: ['Identification'],
      questionCount: 50,
    );
    expect(calls, 5);
    expect(quiz.questionCount, 50);
  });
  test('retries a timed-out batch with the same idempotency IDs', () async {
    var calls = 0;
    String? firstSession;
    String? firstBatch;
    final client = QuizGenerationClient(
      tokenProvider: () async => 'test-token',
      client: MockClient((request) async {
        calls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        firstSession ??= body['clientSessionId'] as String;
        firstBatch ??= body['batchRequestId'] as String;
        expect(body['clientSessionId'], firstSession);
        expect(body['batchRequestId'], firstBatch);
        if (calls == 1) throw TimeoutException('lost response');
        return http.Response(jsonEncode(validResponse()), 200);
      }),
    );
    final quiz = await generate(client);
    expect(quiz.id, 'quiz-1');
    expect(calls, 2);
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
  test('preserves structured personal-key setup errors', () async {
    final client = QuizGenerationClient(
      tokenProvider: () async => 'test-token',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': 'Add your personal Gemini API key to continue.',
            'code': 'personal-key-required',
          }),
          412,
        ),
      ),
    );
    await expectLater(
      generate(client),
      throwsA(
        isA<QuizGenerationException>()
            .having((e) => e.requiresApiKeySetup, 'setup', isTrue)
            .having((e) => e.code, 'code', 'personal-key-required'),
      ),
    );
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
