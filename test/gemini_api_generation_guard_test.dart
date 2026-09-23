import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studexa/services/teacher_gemini_key_service.dart';
import 'package:studexa/widgets/gemini_api_generation_guard.dart';

class _StatusService extends TeacherGeminiKeyService {
  _StatusService(this.status)
    : super(tokenProvider: (() async => 'test-token'));
  final TeacherGeminiKeyStatus status;
  @override
  Future<TeacherGeminiKeyStatus> getStatus() async => status;
}

Widget _app(TeacherGeminiKeyService service, ValueNotifier<bool?> result) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: ElevatedButton(
          onPressed: () async {
            result.value = await confirmGeminiGeneration(
              context,
              service: service,
            );
          },
          child: const Text('Generate'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows grace countdown and permits temporary generation', (
    tester,
  ) async {
    final result = ValueNotifier<bool?>(null);
    await tester.pumpWidget(
      _app(
        _StatusService(
          const TeacherGeminiKeyStatus(
            configured: false,
            validationStatus: 'missing',
            graceRemaining: 2,
            fallbackRemainingToday: 2,
          ),
        ),
        result,
      ),
    );
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 of 3 lifetime'), findsOneWidget);
    expect(find.text('Set Up API Key'), findsOneWidget);
    await tester.tap(find.byKey(const Key('use_temporary_generation')));
    await tester.pumpAndSettle();
    expect(result.value, isTrue);
  });

  testWidgets('blocks generation after grace and offers only API settings', (
    tester,
  ) async {
    final result = ValueNotifier<bool?>(null);
    await tester.pumpWidget(
      _app(
        _StatusService(
          const TeacherGeminiKeyStatus(
            configured: false,
            validationStatus: 'missing',
            graceRemaining: 0,
            fallbackRemainingToday: 2,
          ),
        ),
        result,
      ),
    );
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();
    expect(find.textContaining('three temporary generations'), findsOneWidget);
    expect(find.byKey(const Key('use_temporary_generation')), findsNothing);
    expect(find.text('Open API Settings'), findsOneWidget);
    expect(result.value, isNull);
  });
}
