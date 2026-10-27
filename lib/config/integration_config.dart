/// Public endpoint configuration. AI keys belong in Supabase Edge Function Secrets,
/// never in Flutter source, assets, or --dart-define values.
abstract final class IntegrationConfig {
  /// Endpoint URL for the `generate-quiz` Supabase Edge Function used to generate AI quizzes.
  static const quizGenerationUrl = String.fromEnvironment(
    'QUIZ_GENERATION_URL',
    defaultValue:
        'https://zuidphgogdwyrtndbgkx.supabase.co/functions/v1/generate-quiz',
  );

  /// Endpoint URL for the `teacher-gemini-key` Supabase Edge Function used to manage a teacher's personal Gemini API key.
  static const teacherGeminiKeyUrl = String.fromEnvironment(
    'TEACHER_GEMINI_KEY_URL',
    defaultValue:
        'https://zuidphgogdwyrtndbgkx.supabase.co/functions/v1/teacher-gemini-key',
  );

  /// Endpoint URL for the `submit-quiz-attempt` Supabase Edge Function used for authoritative server-side quiz grading.
  static const submitQuizAttemptUrl = String.fromEnvironment(
    'SUBMIT_QUIZ_ATTEMPT_URL',
    defaultValue:
        'https://zuidphgogdwyrtndbgkx.supabase.co/functions/v1/submit-quiz-attempt',
  );
}
