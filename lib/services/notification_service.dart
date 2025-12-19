import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz.initializeTimeZones();
    // Set your local timezone
    tz.setLocalLocation(tz.getLocation('Africa/Casablanca'));

    final androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    final initSettings = InitializationSettings(android: androidInit);
    await flutterLocalNotificationsPlugin.initialize(initSettings);

    // Create Android notification channel for habit reminders
    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final channel = AndroidNotificationChannel(
      'habit_channel',
      'Habits',
      description: 'Habit reminders',
      importance: Importance.max,
    );
    await androidPlugin?.createNotificationChannel(channel);
  }

  Future<void> scheduleHabitReminder({
    required String id,
    required String title,
    required DateTime reminderTime,
  }) async {
    final now = DateTime.now();

    if (reminderTime.isBefore(now)) {
      print(
        '⚠️ Not scheduling notification for $title - reminder time is in the past',
      );
      return;
    }

    // Convert to TZDateTime
    final scheduledTZ = tz.TZDateTime.from(reminderTime, tz.local);
    final secondsUntil = reminderTime.difference(now).inSeconds;

    print('📅 Scheduling notification:');
    print('   ID: ${id.hashCode}');
    print('   Title: $title');
    print('   Reminder DateTime: $reminderTime');
    print('   TZ DateTime: $scheduledTZ');
    print('   Seconds until notification: ${secondsUntil}s');

    try {
      // Cancel any existing notification with this ID first
      await flutterLocalNotificationsPlugin.cancel(id.hashCode);

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id.hashCode,
        'Time for $title!',
        'Don\'t forget to complete your habit.',
        scheduledTZ,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'habit_channel',
            'Habits',
            channelDescription: 'Habit reminders',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );

      // Verify it was scheduled
      final pendingNotifications = await flutterLocalNotificationsPlugin
          .pendingNotificationRequests();
      final thisNotification = pendingNotifications
          .where((n) => n.id == id.hashCode)
          .toList();

      if (thisNotification.isNotEmpty) {
        print(
          '✅ Notification scheduled successfully and verified in pending list',
        );
      } else {
        print('⚠️ Notification scheduled but NOT found in pending list!');
      }

      print('📋 Total pending notifications: ${pendingNotifications.length}');
    } catch (e) {
      print('❌ Error scheduling notification: $e');
      rethrow;
    }
  }

  // Keep the old method for backward compatibility, but mark as deprecated
  @deprecated
  Future<void> scheduleOneHourLeftNotification({
    required String id,
    required String title,
    required DateTime scheduledAt,
  }) async {
    await scheduleHabitReminder(
      id: id,
      title: title,
      reminderTime: scheduledAt,
    );
  }

  /// Compute when to schedule the notification.
  ///
  /// - If [scheduledAt] is already in the past, returns null.
  /// - Otherwise returns [scheduledAt] (when habit becomes available).
  static DateTime? computeNotificationTime(
    DateTime scheduledAt, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    if (scheduledAt.isBefore(current)) return null;
    return scheduledAt; // Notify when habit becomes available
  }

  Future<void> cancelNotification(String id) async {
    await flutterLocalNotificationsPlugin.cancel(id.hashCode);
  }

  /// Request runtime notification permissions on the current platform.
  /// Returns true if permission was granted (or the platform does not require one).
  Future<bool> requestPermissions() async {
    try {
      // Request notification permission
      final androidImpl = flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      final androidGranted = await androidImpl
          ?.requestNotificationsPermission();

      // Request exact alarm permission (Android 12+)
      // This is CRITICAL for scheduled notifications
      final exactAlarmStatus = await Permission.scheduleExactAlarm.request();

      return (androidGranted ?? true) && exactAlarmStatus.isGranted;
    } catch (_) {
      return true;
    }
  }

  /// Check if exact alarm permission is granted
  Future<bool> hasExactAlarmPermission() async {
    return await Permission.scheduleExactAlarm.isGranted;
  }

  /// Show an immediate test notification so the user can verify notifications are working.
  Future<void> showTestNotification({
    required String id,
    String title = 'Test Notification',
    String body = 'This is a test notification from your app.',
  }) async {
    await flutterLocalNotificationsPlugin.show(
      id.hashCode,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'habit_channel',
          'Habits',
          channelDescription: 'Habit reminders',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );
  }

  /// Get list of all pending scheduled notifications
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await flutterLocalNotificationsPlugin.pendingNotificationRequests();
  }
}
