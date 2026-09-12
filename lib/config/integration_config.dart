/// Public endpoint configuration. AI keys belong in Firebase Secret Manager,
/// never in Flutter source, assets, or --dart-define values.
abstract final class IntegrationConfig {
  static const quizGenerationUrl = String.fromEnvironment(
    'QUIZ_GENERATION_URL',
    defaultValue:
        'https://us-central1-studexa-b5e55.cloudfunctions.net/generateQuizHttp',
  );
}
