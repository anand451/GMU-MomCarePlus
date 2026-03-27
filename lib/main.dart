import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'models/user_model.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';
import 'services/ai_service.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notificationService = NotificationService();
  await notificationService.initialize();

  String? firebaseInitializationError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error) {
    try {
      await Firebase.initializeApp();
    } catch (_) {
      firebaseInitializationError = error.toString();
    }
  }

  runApp(
    PregnancyCareApp(
      firebaseInitializationError: firebaseInitializationError,
      notificationService: notificationService,
    ),
  );
}

class PregnancyCareApp extends StatelessWidget {
  const PregnancyCareApp({
    super.key,
    this.firebaseInitializationError,
    required this.notificationService,
  });

  final String? firebaseInitializationError;
  final NotificationService notificationService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
        Provider<FirestoreService>(create: (_) => FirestoreService()),
        Provider<AiService>(create: (_) => AiService()),
        Provider<NotificationService>.value(value: notificationService),
      ],
      child: MaterialApp(
        title: 'Pregnancy Care',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        home: firebaseInitializationError == null
            ? const _AppRoot()
            : _FirebaseSetupScreen(error: firebaseInitializationError!),
      ),
    );
  }

  ThemeData _buildTheme() {
    const surface = Color(0xFF0B0B0B);
    const elevatedSurface = Color(0xFF141414);
    const accentBlue = Color(0xFF8ED8FF);
    const accentGold = Color(0xFFFFC857);

    final colorScheme = const ColorScheme.dark(
      primary: accentBlue,
      secondary: accentGold,
      surface: surface,
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      onSurface: Colors.white,
      onSurfaceVariant: Color(0xFFADADAD),
      error: Color(0xFFFF8A80),
      onError: Colors.black,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF040404),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: elevatedSurface,
        indicatorColor: accentGold.withValues(alpha: 0.2),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: elevatedSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: accentBlue),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accentGold,
          foregroundColor: Colors.black,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: elevatedSurface,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _AppRoot extends StatelessWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context) {
    final authService = context.read<AuthService>();

    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen(
            message: 'Checking your secure session...',
          );
        }

        final user = authSnapshot.data;
        if (user == null) {
          return const LoginScreen();
        }

        final firestoreService = context.read<FirestoreService>();
        return StreamBuilder<UserModel?>(
          stream: firestoreService.watchUserProfile(user.uid),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingScreen(
                message: 'Loading your care dashboard...',
              );
            }

            final profile =
                profileSnapshot.data ??
                UserModel.empty(uid: user.uid, email: user.email ?? '');

            if (!profile.isComplete) {
              return ProfileScreen(
                userId: user.uid,
                initialProfile: profile,
                isInitialSetup: true,
              );
            }

            return HomeScreen(userId: user.uid, profile: profile);
          },
        );
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message),
          ],
        ),
      ),
    );
  }
}

class _FirebaseSetupScreen extends StatelessWidget {
  const _FirebaseSetupScreen({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Firebase setup required',
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This project is ready for Firebase, but it still needs your own project configuration before auth and Firestore can run.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '1. dart pub global activate flutterfire_cli\n'
                    '2. flutterfire configure\n'
                    '3. Add the generated platform Firebase files if prompted\n'
                    '4. Restart the app',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  SelectableText(
                    'Initialization error:\n$error',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
