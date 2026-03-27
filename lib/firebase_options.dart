import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Replace this file with the generated version from `flutterfire configure`
/// for a real Firebase project. This fallback keeps the project compilable and
/// lets the app show a clear setup message instead of crashing.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _buildOptions(
          platformName: 'Android',
          apiKey: const String.fromEnvironment('FIREBASE_ANDROID_API_KEY'),
          appId: const String.fromEnvironment('FIREBASE_ANDROID_APP_ID'),
          messagingSenderId: const String.fromEnvironment(
            'FIREBASE_MESSAGING_SENDER_ID',
          ),
          projectId: const String.fromEnvironment('FIREBASE_PROJECT_ID'),
          storageBucket: const String.fromEnvironment(
            'FIREBASE_STORAGE_BUCKET',
          ),
        );
      case TargetPlatform.iOS:
        return _buildOptions(
          platformName: 'iOS',
          apiKey: const String.fromEnvironment('FIREBASE_IOS_API_KEY'),
          appId: const String.fromEnvironment('FIREBASE_IOS_APP_ID'),
          messagingSenderId: const String.fromEnvironment(
            'FIREBASE_MESSAGING_SENDER_ID',
          ),
          projectId: const String.fromEnvironment('FIREBASE_PROJECT_ID'),
          storageBucket: const String.fromEnvironment(
            'FIREBASE_STORAGE_BUCKET',
          ),
          iosBundleId: const String.fromEnvironment(
            'FIREBASE_IOS_BUNDLE_ID',
            defaultValue: 'newlife.app',
          ),
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for ${defaultTargetPlatform.name}. '
          'Run `flutterfire configure` for this platform.',
        );
    }
  }

  static FirebaseOptions _buildOptions({
    required String platformName,
    required String apiKey,
    required String appId,
    required String messagingSenderId,
    required String projectId,
    required String storageBucket,
    String? iosBundleId,
  }) {
    final requiredValues = <String>[
      apiKey,
      appId,
      messagingSenderId,
      projectId,
      storageBucket,
    ];

    if (requiredValues.any((value) => value.isEmpty)) {
      throw UnsupportedError(
        'Firebase is not configured for $platformName. Run `flutterfire configure` '
        'to generate `lib/firebase_options.dart` for your Firebase project.',
      );
    }

    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      storageBucket: storageBucket,
      iosBundleId: iosBundleId,
    );
  }
}
