/// Public build-time configuration for the Studexa Supabase backend.
///
/// Provide both values with `--dart-define`; the publishable key is safe for
/// client applications, while a Supabase secret/service-role key must never be
/// included here.
abstract final class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://zuidphgogdwyrtndbgkx.supabase.co',
  );
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_KHO1oxB4lXxdxzvOnZJwWA_rdbRtu0a',
  );
  static const storageBucket = 'study-materials';
  static const authCallbackUrl = 'com.example.studexa://login-callback/';
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '669223676992-tn4l6k5tnh5n7lr6hs8imtphd0i7grhd.apps.googleusercontent.com',
  );

  static bool get isConfigured =>
      url.trim().isNotEmpty && publishableKey.trim().isNotEmpty;
}
