/// Build-time configuration for the Supabase Storage-only integration.
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

  static bool get isConfigured =>
      url.trim().isNotEmpty && publishableKey.trim().isNotEmpty;
}
