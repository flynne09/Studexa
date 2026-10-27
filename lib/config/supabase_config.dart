/// Public build-time configuration for the Studexa Supabase backend.
///
/// Provide both values with `--dart-define`; the publishable key is safe for
/// client applications, while a Supabase secret/service-role key must never be
/// included here.
abstract final class SupabaseConfig {
  /// Base URL of the Studexa Supabase project, overridable via `--dart-define=SUPABASE_URL=...`.
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://zuidphgogdwyrtndbgkx.supabase.co',
  );

  /// Public/anon key for client-side Supabase requests, overridable via `--dart-define=SUPABASE_PUBLISHABLE_KEY=...`.
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_KHO1oxB4lXxdxzvOnZJwWA_rdbRtu0a',
  );

  /// Name of the private Supabase Storage bucket where uploaded study materials are stored.
  static const storageBucket = 'study-materials';

  /// Deep-link redirect URI used for native OAuth and email authentication callbacks.
  static const authCallbackUrl = 'com.example.studexa://login-callback/';

  /// Google OAuth 2.0 Web Client ID used to request ID tokens during Google Sign-In.
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '669223676992-tn4l6k5tnh5n7lr6hs8imtphd0i7grhd.apps.googleusercontent.com',
  );

  /// Returns `true` when both the project [url] and [publishableKey] are non-empty.
  static bool get isConfigured =>
      url.trim().isNotEmpty && publishableKey.trim().isNotEmpty;
}
