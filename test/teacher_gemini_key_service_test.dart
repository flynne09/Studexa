import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:studexa/services/teacher_gemini_key_service.dart';

void main() {
  test('GET uses Firebase token and exposes masked status only', () async {
    final client = TeacherGeminiKeyService(
      tokenProvider: () async => 'firebase-token',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.headers['Authorization'], 'Bearer firebase-token');
        return http.Response(
          jsonEncode({
            'success': true,
            'status': {
              'configured': true,
              'status': 'valid',
              'maskedKey': '••••1234',
              'graceRemaining': 3,
              'fallbackRemainingToday': 2,
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final status = await client.getStatus();
    expect(status.isReady, isTrue);
    expect(status.maskedKey, '••••1234');
  });

  test(
    'PUT sends key only to the settings endpoint and keeps error code',
    () async {
      final client = TeacherGeminiKeyService(
        tokenProvider: () async => 'firebase-token',
        client: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(jsonDecode(request.body)['apiKey'], 'teacher-key-1234');
          return http.Response(
            jsonEncode({
              'error': 'Google rejected this API key.',
              'code': 'invalid-api-key',
            }),
            400,
          );
        }),
      );
      await expectLater(
        client.saveAndVerify(' teacher-key-1234 '),
        throwsA(
          isA<TeacherGeminiKeyException>()
              .having((e) => e.code, 'code', 'invalid-api-key')
              .having((e) => e.message, 'message', contains('rejected')),
        ),
      );
    },
  );
}
