import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/user_model.dart';

class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  String get _todayKey => DateFormat('yyyy-MM-dd').format(DateTime.now());

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _users.doc(uid);

  DocumentReference<Map<String, dynamic>> _profileRef(String uid) {
    return _userRef(uid).collection('profile').doc('details');
  }

  DocumentReference<Map<String, dynamic>> _todayLogRef(String uid) {
    return _userRef(uid).collection('health_logs').doc(_todayKey);
  }

  DocumentReference<Map<String, dynamic>> _todaySuggestionRef(String uid) {
    return _userRef(uid).collection('daily_suggestions').doc(_todayKey);
  }

  Stream<UserModel?> watchUserProfile(String uid) {
    return _profileRef(uid).snapshots().asyncMap(
      (snapshot) async => _mapProfileSnapshot(uid, snapshot.data()),
    );
  }

  Future<UserModel?> getUserProfile(String uid) async {
    final snapshot = await _runWithRetry(() => _profileRef(uid).get());
    return _mapProfileSnapshot(uid, snapshot.data());
  }

  Future<void> saveUserProfile(String uid, UserModel user) async {
    final now = DateTime.now().toUtc();
    final profile = user.copyWith(updatedAt: now).toMap();
    await _runWithRetry(() async {
      await _userRef(uid).set(<String, dynamic>{
        'uid': uid,
        'email': user.email,
        'profileUpdatedAt': now,
      }, SetOptions(merge: true));
      await _profileRef(uid).set(profile, SetOptions(merge: true));
    });
  }

  Stream<Map<String, dynamic>> watchTodayHealthLog(String uid) {
    return _todayLogRef(uid).snapshots().map((snapshot) {
      final data = snapshot.data() ?? <String, dynamic>{};
      return _defaultHealthLog(data);
    });
  }

  Future<Map<String, dynamic>> getTodayHealthLog(String uid) async {
    final snapshot = await _runWithRetry(() => _todayLogRef(uid).get());
    return _defaultHealthLog(snapshot.data() ?? <String, dynamic>{});
  }

  Future<List<Map<String, dynamic>>> getRecentHealthLogs(
    String uid, {
    int limit = 3,
  }) async {
    final snapshot = await _runWithRetry(
      () => _userRef(uid)
          .collection('health_logs')
          .orderBy('date', descending: true)
          .limit(limit)
          .get(),
    );
    return snapshot.docs
        .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
        .toList();
  }

  Future<void> saveWaterLog(
    String uid, {
    required int waterIntakeMl,
    required int waterGoalMl,
  }) async {
    await _saveTodayLog(uid, <String, dynamic>{
      'waterIntakeMl': waterIntakeMl,
      'waterGoalMl': waterGoalMl,
    });
  }

  Future<void> saveSteps(String uid, {required int steps}) async {
    await _saveTodayLog(uid, <String, dynamic>{'steps': steps});
  }

  Future<void> saveBloodPressure(
    String uid, {
    required int systolic,
    required int diastolic,
  }) async {
    await _saveTodayLog(uid, <String, dynamic>{
      'systolic': systolic,
      'diastolic': diastolic,
    });
  }

  Future<void> saveCondition(String uid, {required String condition}) async {
    await _saveTodayLog(uid, <String, dynamic>{'condition': condition.trim()});
  }

  Future<void> syncSensorSteps(
    String uid, {
    required int sensorSteps,
    int? baselineSteps,
  }) async {
    final safeBaseline = baselineSteps == null || sensorSteps < baselineSteps
        ? sensorSteps
        : baselineSteps;
    final todaySteps = (sensorSteps - safeBaseline).clamp(0, 999999);
    await _saveTodayLog(uid, <String, dynamic>{
      'steps': todaySteps,
      'stepSensorBaseline': safeBaseline,
      'stepSensorRaw': sensorSteps,
      'stepSensorUpdatedAt': DateTime.now().toUtc(),
    });
  }

  Stream<Map<String, dynamic>?> watchTodaySuggestion(String uid) {
    return _todaySuggestionRef(uid).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null) {
        return null;
      }
      return <String, dynamic>{'id': snapshot.id, ...data};
    });
  }

  Future<Map<String, dynamic>?> getTodaySuggestion(String uid) async {
    final snapshot = await _runWithRetry(() => _todaySuggestionRef(uid).get());
    final data = snapshot.data();
    if (data == null) {
      return null;
    }
    return <String, dynamic>{'id': snapshot.id, ...data};
  }

  Future<void> saveDailySuggestion(
    String uid, {
    required String suggestion,
    String? title,
  }) async {
    await _runWithRetry(
      () => _todaySuggestionRef(uid).set(<String, dynamic>{
        'id': _todayKey,
        'date': _todayKey,
        'title': title ?? 'Daily pregnancy nutrition plan',
        'suggestion': suggestion.trim(),
        'createdAt': DateTime.now().toUtc(),
      }, SetOptions(merge: true)),
    );
  }

  Future<Map<String, dynamic>> getAiDoctorContext(String uid) async {
    final profile = await getUserProfile(uid);
    final todayLog = await getTodayHealthLog(uid);
    final recentLogs = await getRecentHealthLogs(uid, limit: 3);
    final suggestion = await getTodaySuggestion(uid);

    return <String, dynamic>{
      'profile': profile?.toMap(),
      'todayLog': todayLog,
      'recentHealthLogs': recentLogs,
      'dailySuggestion': suggestion,
    };
  }

  Stream<List<Map<String, dynamic>>> watchReminders(String uid) {
    return _userRef(uid)
        .collection('reminders')
        .orderBy('minutesOfDay')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
              .toList(),
        );
  }

  Future<void> addReminder(
    String uid, {
    required String medicineName,
    required int hour,
    required int minute,
    required int notificationId,
    required DateTime nextTriggerAt,
  }) async {
    final doc = _userRef(uid).collection('reminders').doc();
    await _runWithRetry(
      () => doc.set(<String, dynamic>{
        'id': doc.id,
        'notificationId': notificationId,
        'medicineName': medicineName.trim(),
        'hour': hour,
        'minute': minute,
        'minutesOfDay': hour * 60 + minute,
        'timeLabel': _formatTime(hour, minute),
        'nextTriggerAt': nextTriggerAt.toUtc(),
        'createdAt': DateTime.now().toUtc(),
      }),
    );
  }

  Future<void> deleteReminder(String uid, String reminderId) async {
    await _runWithRetry(
      () => _userRef(uid).collection('reminders').doc(reminderId).delete(),
    );
  }

  Stream<List<Map<String, dynamic>>> watchChatMessages(String uid) {
    return _userRef(uid)
        .collection('chats')
        .orderBy('createdAt')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
              .toList(),
        );
  }

  Future<void> addChatMessage(
    String uid, {
    required String role,
    required String text,
  }) async {
    final messageTimestamp = DateTime.now().toUtc();
    final doc = _userRef(uid).collection('chats').doc();
    await _runWithRetry(
      () => doc.set(<String, dynamic>{
        'id': doc.id,
        'message': text.trim(),
        'role': role == 'assistant' ? 'ai' : role,
        'timestamp': messageTimestamp,
        'text': text.trim(),
        'createdAt': messageTimestamp,
      }),
    );
  }

  Future<String> exportUserDataToJson(String uid) async {
    final userSnapshot = await _runWithRetry(() => _userRef(uid).get());
    final profileSnapshot = await _runWithRetry(() => _profileRef(uid).get());
    final healthLogs = await _runWithRetry(
      () => _userRef(uid).collection('health_logs').get(),
    );
    final reminders = await _runWithRetry(
      () => _userRef(uid).collection('reminders').get(),
    );
    final chats = await _runWithRetry(
      () => _userRef(uid).collection('chats').get(),
    );
    final suggestions = await _runWithRetry(
      () => _userRef(uid).collection('daily_suggestions').get(),
    );

    final payload = <String, dynamic>{
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'user': _normaliseValue(userSnapshot.data()),
      'profile': _normaliseValue(profileSnapshot.data()),
      'healthLogs': healthLogs.docs
          .map((doc) => _normaliseValue(doc.data()))
          .toList(),
      'reminders': reminders.docs
          .map((doc) => _normaliseValue(doc.data()))
          .toList(),
      'chats': chats.docs.map((doc) => _normaliseValue(doc.data())).toList(),
      'dailySuggestions': suggestions.docs
          .map((doc) => _normaliseValue(doc.data()))
          .toList(),
    };

    final downloadsDirectory = await getDownloadsDirectory();
    final fallbackDirectory = await getApplicationDocumentsDirectory();
    final targetDirectory = downloadsDirectory ?? fallbackDirectory;

    if (!await targetDirectory.exists()) {
      await targetDirectory.create(recursive: true);
    }

    final fileName =
        'pregnancy_care_export_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';
    final filePath =
        '${targetDirectory.path}${Platform.pathSeparator}$fileName';
    final file = File(filePath);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );

    return file.path;
  }

  Map<String, dynamic> _defaultHealthLog(Map<String, dynamic> data) {
    return <String, dynamic>{
      'date': _todayKey,
      'waterGoalMl': 2000,
      'waterIntakeMl': 0,
      'steps': 0,
      'systolic': 0,
      'diastolic': 0,
      'condition': '',
      ...data,
    };
  }

  Future<void> _saveTodayLog(String uid, Map<String, dynamic> values) async {
    await _runWithRetry(
      () => _todayLogRef(uid).set(<String, dynamic>{
        'date': _todayKey,
        'timestamp': DateTime.now().toUtc(),
        'updatedAt': DateTime.now().toUtc(),
        ...values,
      }, SetOptions(merge: true)),
    );
  }

  Future<UserModel?> _mapProfileSnapshot(
    String uid,
    Map<String, dynamic>? data,
  ) async {
    if (data != null) {
      return UserModel.fromMap(<String, dynamic>{'uid': uid, ...data});
    }

    final legacy = await _runWithRetry(() => _userRef(uid).get());
    final legacyData = legacy.data();
    if (legacyData == null) {
      return null;
    }
    return UserModel.fromMap(<String, dynamic>{'uid': uid, ...legacyData});
  }

  String _formatTime(int hour, int minute) {
    final formattedHour = hour == 0
        ? 12
        : hour > 12
        ? hour - 12
        : hour;
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final formattedMinute = minute.toString().padLeft(2, '0');
    return '$formattedHour:$formattedMinute $suffix';
  }

  dynamic _normaliseValue(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toUtc().toIso8601String();
    }
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    if (value is Map<String, dynamic>) {
      return value.map(
        (key, innerValue) => MapEntry(key, _normaliseValue(innerValue)),
      );
    }
    if (value is Iterable) {
      return value.map(_normaliseValue).toList();
    }
    return value;
  }

  Future<T> _runWithRetry<T>(Future<T> Function() action) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await action();
      } on FirebaseException catch (error) {
        lastError = error;
        if (!_shouldRetry(error) || attempt == 2) {
          throw FirestoreServiceException(_mapFirebaseError(error));
        }
        await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
      } on SocketException {
        lastError = const SocketException('No internet connection');
        if (attempt == 2) {
          throw const FirestoreServiceException(
            'No internet connection. Please reconnect and try again.',
          );
        }
        await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
      }
    }

    throw FirestoreServiceException(lastError.toString());
  }

  bool _shouldRetry(FirebaseException error) {
    return <String>{
      'aborted',
      'cancelled',
      'deadline-exceeded',
      'resource-exhausted',
      'unavailable',
    }.contains(error.code);
  }

  String _mapFirebaseError(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        return 'You do not have permission to update this record.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Firestore is offline right now. Please check your internet connection and try again.';
      default:
        return error.message ?? 'Firestore request failed.';
    }
  }
}

class FirestoreServiceException implements Exception {
  const FirestoreServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
