import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

/// Application entry point.
/// Initializes Flutter bindings, connects to the Supabase backend using
/// build-time configuration, and launches the root [MyApp] widget.
void main() async {
  // Ensure Flutter engine and platform channels are initialized before async calls.
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Only initialize Supabase if both URL and publishable key are configured.
    if (SupabaseConfig.isConfigured) {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
      );
    } else {
      // Log a diagnostic warning when running without Supabase dart-defines.
      debugPrint(
        'Supabase is not configured. Start with SUPABASE_URL and '
        'SUPABASE_PUBLISHABLE_KEY dart-defines.',
      );
    }
    // Mount the main application widget tree.
    runApp(const MyApp());
  } catch (_) {
    // Fallback UI displayed if Supabase initialization fails, allowing the user to retry.
    runApp(
      MaterialApp(
        title: 'Studexa',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Studexa could not connect to its services. Check your connection and try again.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: main, child: const Text('Retry')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Root widget of the Studexa application.
/// Configures the global [MaterialApp] theme, title, and initial [SplashScreen] route.
class MyApp extends StatelessWidget {
  /// Creates the root [MyApp] widget.
  const MyApp({super.key});

  /// Builds the top-level [MaterialApp] with the custom academic theme and splash screen.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Studexa',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const SplashScreen(),
    );
  }
}
