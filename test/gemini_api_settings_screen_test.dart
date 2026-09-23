import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studexa/screens/teacher/gemini_api_settings_screen.dart';
import 'package:studexa/services/teacher_gemini_key_service.dart';
import 'package:studexa/theme/app_theme.dart';

class _FakeKeyService extends TeacherGeminiKeyService {
  _FakeKeyService(this.current)
    : super(tokenProvider: (() async => 'test-token'));

  TeacherGeminiKeyStatus current;
  String? submitted;

  @override
  Future<TeacherGeminiKeyStatus> getStatus() async => current;

  @override
  Future<TeacherGeminiKeyStatus> saveAndVerify(String apiKey) async {
    submitted = apiKey;
    current = const TeacherGeminiKeyStatus(
      configured: true,
      validationStatus: 'valid',
      maskedKey: '••••1234',
      graceRemaining: 3,
      fallbackRemainingToday: 2,
    );
    return current;
  }

  @override
  Future<TeacherGeminiKeyStatus> remove() async {
    current = const TeacherGeminiKeyStatus(
      configured: false,
      validationStatus: 'missing',
      graceRemaining: 3,
      fallbackRemainingToday: 2,
    );
    return current;
  }
}

void main() {
  testWidgets('shows obscured input and complete Google AI Studio guide', (
    tester,
  ) async {
    final service = _FakeKeyService(
      const TeacherGeminiKeyStatus(
        configured: false,
        validationStatus: 'missing',
        graceRemaining: 3,
        fallbackRemainingToday: 2,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: GeminiApiSettingsScreen(service: service),
      ),
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const Key('gemini_api_key_input')),
    );
    expect(field.obscureText, isTrue);
    expect(find.text('How to get your API key'), findsOneWidget);
    expect(find.text('Copy Link'), findsOneWidget);
    expect(find.textContaining('Dashboard → Projects'), findsOneWidget);
    expect(find.textContaining('Save and Verify'), findsWidgets);
    expect(find.textContaining('Never share your key'), findsOneWidget);
  });

  testWidgets('validates, clears, and displays only the masked saved key', (
    tester,
  ) async {
    final service = _FakeKeyService(
      const TeacherGeminiKeyStatus(
        configured: false,
        validationStatus: 'missing',
        graceRemaining: 3,
        fallbackRemainingToday: 2,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: GeminiApiSettingsScreen(service: service),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('gemini_api_key_input')),
      'personal-secret-key-1234',
    );
    await tester.tap(find.byKey(const Key('save_verify_gemini_key')));
    await tester.pumpAndSettle();
    expect(service.submitted, 'personal-secret-key-1234');
    expect(find.textContaining('••••1234'), findsOneWidget);
    expect(find.textContaining('personal-secret-key'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('gemini_api_key_input')))
          .controller
          ?.text,
      isEmpty,
    );
  });
}
