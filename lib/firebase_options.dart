// Generated from FlutterFire configuration, then customized to keep API keys
// out of tracked Dart source. Re-running `flutterfire configure` can overwrite
// this file; preserve the FIREBASE_*_API_KEY dart-define integration below.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static const _webApiKey = String.fromEnvironment('FIREBASE_WEB_API_KEY');
  static const _androidApiKey = String.fromEnvironment(
    'FIREBASE_ANDROID_API_KEY',
  );
  static const _iosApiKey = String.fromEnvironment('FIREBASE_IOS_API_KEY');
  static const _windowsApiKey = String.fromEnvironment(
    'FIREBASE_WINDOWS_API_KEY',
  );

  static String _requiredApiKey(String defineName, String value) {
    if (value.trim().isEmpty) {
      throw StateError(
        'Missing $defineName. Run Flutter with '
        '--dart-define-from-file=firebase.config.json.',
      );
    }
    return value;
  }

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static FirebaseOptions get web => FirebaseOptions(
    apiKey: _requiredApiKey('FIREBASE_WEB_API_KEY', _webApiKey),
    appId: '1:669223676992:web:353797444e61b528ec03a5',
    messagingSenderId: '669223676992',
    projectId: 'studexa-b5e55',
    authDomain: 'studexa-b5e55.firebaseapp.com',
    storageBucket: 'studexa-b5e55.firebasestorage.app',
    measurementId: 'G-R8PE956NDJ',
  );

  static FirebaseOptions get android => FirebaseOptions(
    apiKey: _requiredApiKey('FIREBASE_ANDROID_API_KEY', _androidApiKey),
    appId: '1:669223676992:android:20358f050015e2a8ec03a5',
    messagingSenderId: '669223676992',
    projectId: 'studexa-b5e55',
    storageBucket: 'studexa-b5e55.firebasestorage.app',
  );

  static FirebaseOptions get ios => FirebaseOptions(
    apiKey: _requiredApiKey('FIREBASE_IOS_API_KEY', _iosApiKey),
    appId: '1:669223676992:ios:a1631f300c42ab4fec03a5',
    messagingSenderId: '669223676992',
    projectId: 'studexa-b5e55',
    storageBucket: 'studexa-b5e55.firebasestorage.app',
    iosBundleId: 'com.example.studexa',
  );

  static FirebaseOptions get windows => FirebaseOptions(
    apiKey: _requiredApiKey('FIREBASE_WINDOWS_API_KEY', _windowsApiKey),
    appId: '1:669223676992:web:9901f9c863b470c1ec03a5',
    messagingSenderId: '669223676992',
    projectId: 'studexa-b5e55',
    authDomain: 'studexa-b5e55.firebaseapp.com',
    storageBucket: 'studexa-b5e55.firebasestorage.app',
    measurementId: 'G-0J5P2GT50S',
  );
}
