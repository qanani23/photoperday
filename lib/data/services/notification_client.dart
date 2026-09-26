import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Contract for scheduling, querying, and cancelling local device notifications.
abstract class NotificationClient {
  /// Initializes the underlying notification platform client.
  Future<void> init({
    void Function(NotificationResponse)? onNotificationResponse,
  });

  /// Requests notification permissions on platforms where runtime permissions apply.
  Future<bool> requestPermission();

  /// Checks if notification permission is currently granted.
  Future<bool> hasPermission();

  /// Schedules a recurring daily notification matching [hour] and [minute] in local device time.
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  });

  /// Cancels any scheduled notification with the specified [id].
  Future<void> cancel(int id);

  /// Cancels all scheduled notifications.
  Future<void> cancelAll();

  /// Returns the IDs of all currently pending scheduled notifications.
  Future<List<int>> getPendingNotificationIds();

  /// Checks if the app was launched by tapping a notification.
  Future<bool> didAppLaunchFromNotification();
}

/// Production implementation of [NotificationClient] backed by `flutter_local_notifications`
/// and timezone-aware local calendar scheduling.
class FlutterLocalNotificationClient implements NotificationClient {
  FlutterLocalNotificationClient({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  static const String channelId = 'daily_reminder_channel';
  static const String channelName = 'Photo a Day Reminders';
  static const String channelDescription =
      "Daily reminder to capture today's photo";

  @override
  Future<void> init({
    void Function(NotificationResponse)? onNotificationResponse,
  }) async {
    if (_initialized) return;

    try {
      tz_data.initializeTimeZones();
    } catch (_) {}

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    try {
      await _plugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: onNotificationResponse,
      );
    } catch (e) {
      debugPrint('NotificationClient init exception: $e');
    }
    _initialized = true;
  }

  @override
  Future<bool> requestPermission() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidImplementation = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        final granted = await androidImplementation
            ?.requestNotificationsPermission();
        return granted ?? true;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosImplementation = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        final granted = await iosImplementation?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? true;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<bool> hasPermission() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidImplementation = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        final enabled = await androidImplementation?.areNotificationsEnabled();
        return enabled ?? true;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    try {
      await init();

      // Cancel any previous notification with this ID to guarantee no duplicates
      await _plugin.cancel(id: id);

      final scheduledDate = _nextInstanceOfTime(hour, minute);

      const androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      );
      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('NotificationClient scheduleDaily exception: $e');
    }
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  @override
  Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }

  @override
  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  @override
  Future<List<int>> getPendingNotificationIds() async {
    try {
      final requests = await _plugin.pendingNotificationRequests();
      return requests.map((r) => r.id).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<bool> didAppLaunchFromNotification() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      return details?.didNotificationLaunchApp ?? false;
    } catch (_) {
      return false;
    }
  }
}
