import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    tz_data.initializeTimeZones();
    await _configureLocalTimezone();

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await _plugin.initialize(settings: initializationSettings);
    _isInitialized = true;
    debugPrint('NotificationService initialized');
  }

  Future<void> requestPermissions() async {
    await initialize();

    final androidImplementation = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final iosImplementation = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();

    await androidImplementation?.requestNotificationsPermission();
    await androidImplementation?.requestExactAlarmsPermission();
    await iosImplementation?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<DateTime> scheduleDailyReminder({
    required int notificationId,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    await initialize();
    final scheduledDate = _nextInstanceOfTime(hour: hour, minute: minute);
    debugPrint(
      'Scheduling reminder id=$notificationId at ${scheduledDate.toLocal()}',
    );

    await _plugin.zonedSchedule(
      id: notificationId,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'pregnancy_care_reminders',
          'Medicine reminders',
          channelDescription: 'Daily medicine reminders for pregnancy care',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    return scheduledDate.toLocal();
  }

  Future<void> cancelReminder(int notificationId) async {
    await initialize();
    debugPrint('Cancelling reminder id=$notificationId');
    await _plugin.cancel(id: notificationId);
  }

  int createNotificationId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return now.remainder(2147483647);
  }

  Future<void> _configureLocalTimezone() async {
    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      final timezoneName = timezoneInfo.identifier;
      tz.setLocalLocation(tz.getLocation(timezoneName));
      debugPrint('Timezone configured: $timezoneName');
    } catch (error) {
      debugPrint('Timezone configuration failed, using UTC fallback: $error');
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
  }

  tz.TZDateTime _nextInstanceOfTime({required int hour, required int minute}) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (!scheduledDate.isAfter(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    return scheduledDate;
  }
}
