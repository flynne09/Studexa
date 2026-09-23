import 'package:flutter/material.dart';

import '../models/quiz_model.dart';
import '../screens/teacher/gemini_api_settings_screen.dart';
import '../services/teacher_gemini_key_service.dart';
import 'app_feedback.dart';

/// Shows the teacher's personal-key or temporary-use choice before starting a
/// new Actual, Practice, or Generate More session.
Future<bool> confirmGeminiGeneration(
  BuildContext context, {
  TeacherGeminiKeyService? service,
}) async {
  final keyService = service ?? TeacherGeminiKeyService();
  TeacherGeminiKeyStatus status;
  try {
    status = await keyService.getStatus();
  } on TeacherGeminiKeyException catch (error) {
    if (context.mounted) {
      AppFeedback.error(
        context,
        error.message,
        title: 'Unable to check API key',
      );
    }
    return false;
  }
  if (!context.mounted) return false;
  if (status.isReady) return true;

  final hasTemporaryUse = !status.configured && status.graceRemaining > 0;
  final choice = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        hasTemporaryUse
            ? 'Choose a Gemini API option'
            : 'Personal Gemini API key required',
      ),
      content: Text(
        hasTemporaryUse
            ? 'You have ${status.graceRemaining} of 3 lifetime temporary generations remaining. Add your own key for regular use, or use one temporary generation now.'
            : status.configured
            ? 'Your saved key needs to be replaced before Studexa can generate another quiz.'
            : 'Your three temporary generations have been used. Add your personal Gemini API key to continue.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        if (hasTemporaryUse)
          TextButton(
            key: const Key('use_temporary_generation'),
            onPressed: () => Navigator.pop(dialogContext, 'temporary'),
            child: const Text('Use Temporary Generation'),
          ),
        ElevatedButton(
          key: const Key('open_gemini_api_settings'),
          onPressed: () => Navigator.pop(dialogContext, 'settings'),
          child: Text(hasTemporaryUse ? 'Set Up API Key' : 'Open API Settings'),
        ),
      ],
    ),
  );
  if (!context.mounted) return false;
  if (choice == 'temporary') return true;
  if (choice != 'settings') return false;

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => GeminiApiSettingsScreen(service: keyService),
    ),
  );
  if (!context.mounted) return false;
  try {
    return (await keyService.getStatus()).isReady;
  } on TeacherGeminiKeyException catch (error) {
    if (context.mounted) {
      AppFeedback.error(
        context,
        error.message,
        title: 'Unable to check API key',
      );
    }
    return false;
  }
}

void showGeminiBackupFeedback(BuildContext context, QuizModel quiz) {
  if (!quiz.backupUsed) return;
  final reason = switch (quiz.backupUsageReason) {
    'grace' => 'You used a temporary Studexa generation.',
    'personal_quota' =>
      'Your personal Gemini quota was reached, so Studexa used its backup.',
    'provider_unavailable' =>
      'Your personal Gemini service was temporarily unavailable, so Studexa used its backup.',
    _ => 'Studexa used its backup Gemini service for this generation.',
  };
  final remaining = quiz.backupUsageReason == 'grace'
      ? quiz.backupGraceRemaining
      : quiz.backupFallbackRemainingToday;
  final suffix = remaining == null
      ? ''
      : quiz.backupUsageReason == 'grace'
      ? ' $remaining temporary generations remain.'
      : ' $remaining fallback sessions remain today.';
  AppFeedback.info(
    context,
    '$reason$suffix',
    title: 'Studexa backup used',
    compact: true,
    duration: const Duration(seconds: 7),
  );
}
