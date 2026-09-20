/// Public endpoint configuration. AI keys belong in Supabase Edge Function Secrets,
/// never in Flutter source, assets, or --dart-define values.
abstract final class IntegrationConfig {
  static const quizGenerationUrl = String.fromEnvironment(
    'QUIZ_GENERATION_URL',
    defaultValue:
        'https://zuidphgogdwyrtndbgkx.supabase.co/functions/v1/generate-quiz',
  );
}
