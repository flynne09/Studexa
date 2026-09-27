import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

bool _initialized = false;

class _MemoryAsyncStorage extends GotrueAsyncStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> getItem({required String key}) async => _values[key];

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }

  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }
}

Future<void> setupMockSupabase() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!_initialized) {
    await Supabase.initialize(
      url: 'https://zuidphgogdwyrtndbgkx.supabase.co',
      publishableKey: 'sb_publishable_test_key',
      httpClient: MockClient((request) async {
        final isRestRequest = request.url.path.startsWith('/rest/v1/');
        return http.Response(
          isRestRequest ? '[]' : '{}',
          200,
          request: request,
          headers: {
            'content-type': 'application/json',
            if (isRestRequest) 'content-range': '0-0/0',
          },
        );
      }),
      realtimeClientOptions: RealtimeClientOptions(
        transport: (_, _) => throw UnsupportedError(
          'Realtime transport is disabled in widget tests.',
        ),
        disconnectOnEmptyChannelsAfter: Duration.zero,
        connectionCloseTimeout: Duration.zero,
      ),
      authOptions: FlutterAuthClientOptions(
        persistSession: false,
        authFlowType: AuthFlowType.implicit,
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryAsyncStorage(),
      ),
    );
    _initialized = true;
  }
}
