# pregnancy_care_app

Production-ready Flutter mobile app for pregnancy healthcare with Firebase auth, Firestore storage, AI chat, medicine reminders, and JSON export.

## Stack

- Flutter 3.41.2
- Dart 3.11.0
- Firebase Core, Auth, Firestore
- Provider state injection
- Google Gemini REST API via `http`

## Firebase setup

1. Install the FlutterFire CLI:

```bash
dart pub global activate flutterfire_cli
```

2. Configure Firebase from the project root:

```bash
flutterfire configure
```

3. This generates a real `lib/firebase_options.dart` for your Firebase project.

4. If you are building Android, place the generated `google-services.json` file in `android/app/` when Firebase prompts for it.

## Gemini setup

Run the app with an API key:

```bash
flutter run --dart-define=GEMINI_API_KEY=your_gemini_key
```

Optional model override:

```bash
flutter run --dart-define=GEMINI_API_KEY=your_gemini_key --dart-define=GEMINI_MODEL=gemini-2.5-flash
```

## Android Firebase Gradle setup

This project already uses Kotlin DSL and includes the Google Services plugin:

- `android/settings.gradle.kts`
- `android/app/build.gradle.kts`

If you are working in an older Flutter project that still uses Groovy `build.gradle`, the equivalent plugin setup is:

```gradle
plugins {
    id "com.android.application"
    id "org.jetbrains.kotlin.android"
    id "com.google.gms.google-services"
}
```

and in the top-level `build.gradle`:

```gradle
plugins {
    id "com.google.gms.google-services" version "4.4.3" apply false
}
```

## Features

- Email/password login and registration
- Auth state listener with profile gate
- Firestore user profile at `users/{uid}`
- Daily dashboard with water, steps, blood pressure, and condition logging
- Medicine reminders in Firestore
- WhatsApp-style AI pregnancy chat saved at `users/{uid}/chats`
- JSON export to the platform downloads directory when available
- Black glassmorphism UI with smooth transitions
