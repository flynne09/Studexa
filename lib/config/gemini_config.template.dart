/// Template configuration for Google Gemini AI.
///
/// To configure your own credentials:
/// 1. Copy this file to `lib/config/gemini_config.dart` in the same directory.
/// 2. Replace the placeholder below with your personal Gemini API key from Google AI Studio.
/// 3. `gemini_config.dart` is git-ignored and will not be pushed to version control.
class GeminiConfig {
  /// The active Google Gemini API Key used for AI quiz generation.
  static const String apiKey = 'YOUR_GEMINI_API_KEY_HERE';

  /// Active Gemini model name
  static const String modelName = 'gemini-3.6-flash';
}
