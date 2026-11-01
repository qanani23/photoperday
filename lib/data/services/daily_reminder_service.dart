import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:photo_per_day/data/models/daily_reminder_settings.dart';
import 'package:photo_per_day/data/services/daily_reminder_storage.dart';
import 'package:photo_per_day/data/services/notification_client.dart';

/// Central domain service responsible for managing the user's daily photo reminder.
///
/// Principles:
/// - Exclusively local: Zero cloud schedulers, zero network calls, zero Firebase.
/// - Exactly one notification: Cancels previous schedule on time change or re-enable.
/// - Truthful permission handling: If permission is denied, disables reminder and reflects status.
/// - Respects "One photo per day": Tapping reminder routes to Today without duplicating photos.
/// - Testable: Decoupled from platform notification plugin via [NotificationClient].
class DailyReminderService extends ChangeNotifier {
  DailyReminderService({
    NotificationClient? client,
    DailyReminderStorage? storage,
  }) : _client = client ?? FlutterLocalNotificationClient(),
       _storage = storage ?? DailyReminderStorage();

  static DailyReminderService _instance = DailyReminderService();

  /// Global singleton instance.
  static DailyReminderService get instance => _instance;

  @visibleForTesting
  static void setTestInstance(DailyReminderService testInstance) {
    _instance = testInstance;
  }

  @visibleForTesting
  static void resetTestInstance() {
    _instance = DailyReminderService();
  }

  NotificationClient _client;
  DailyReminderStorage _storage;

  DailyReminderSettings _settings = DailyReminderSettings.defaultSettings;

  bool _isInitialized = false;
  bool _permissionDenied = false;

  /// Optional callback invoked when the user taps a reminder notification.
  VoidCallback? onNotificationTap;

  /// Unique notification ID reserved for the single daily reminder.
  static const int reminderNotificationId = 1001;

  /// Calm notification title.
  static const String reminderTitle = 'Daria';

  /// Calm notification body.
  static const String reminderBody = "Capture today's memory.";

  /// Current user settings.
  DailyReminderSettings get settings => _settings;

  /// Whether the service has completed initialization.
  bool get isInitialized => _isInitialized;

  /// Whether the user previously denied notification permissions.
  bool get permissionDenied => _permissionDenied;

  /// Whether the daily reminder is actively enabled.
  bool get isEnabled => _settings.enabled && !_permissionDenied;

  /// Initializes the service, restores persisted configuration, and synchronizes schedules.
  Future<void> init({
    NotificationClient? client,
    DailyReminderStorage? storage,
  }) async {
    if (client != null) _client = client;
    if (storage != null) _storage = storage;

    await _client.init(onNotificationResponse: _handleNotificationResponse);

    _settings = await _storage.loadSettings();

    if (_settings.enabled) {
      final hasPermission = await _client.hasPermission();
      if (hasPermission) {
        _permissionDenied = false;
        await _scheduleReminder();
      } else {
        _permissionDenied = true;
        _settings = _settings.copyWith(enabled: false);
        await _storage.saveSettings(_settings);
      }
    } else {
      await _client.cancel(reminderNotificationId);
    }

    _isInitialized = true;
    notifyListeners();
  }

  /// Enables or disables the daily reminder.
  ///
  /// When enabling, prompts for notification permission if required.
  /// Returns `true` if the state changed successfully, or `false` if permission was denied.
  Future<bool> setEnabled(bool enabled) async {
    if (enabled) {
      final granted = await _client.requestPermission();
      if (!granted) {
        _permissionDenied = true;
        _settings = _settings.copyWith(enabled: false);
        await _storage.saveSettings(_settings);
        notifyListeners();
        return false;
      }

      _permissionDenied = false;
      _settings = _settings.copyWith(enabled: true);
      await _storage.saveSettings(_settings);
      await _scheduleReminder();
      notifyListeners();
      return true;
    } else {
      _permissionDenied = false;
      _settings = _settings.copyWith(enabled: false);
      await _storage.saveSettings(_settings);
      await _client.cancel(reminderNotificationId);
      notifyListeners();
      return true;
    }
  }

  /// Updates the reminder time (hour and minute in local calendar time).
  Future<bool> setTime({required int hour, required int minute}) async {
    final clampedHour = hour.clamp(0, 23);
    final clampedMinute = minute.clamp(0, 59);

    _settings = _settings.copyWith(hour: clampedHour, minute: clampedMinute);
    await _storage.saveSettings(_settings);

    if (_settings.enabled && !_permissionDenied) {
      await _scheduleReminder();
    }

    notifyListeners();
    return true;
  }

  /// Internal scheduling helper that cancels any prior schedule and sets a single daily reminder.
  Future<void> _scheduleReminder() async {
    await _client.cancel(reminderNotificationId);
    await _client.scheduleDaily(
      id: reminderNotificationId,
      title: reminderTitle,
      body: reminderBody,
      hour: _settings.hour,
      minute: _settings.minute,
    );
  }

  /// Dispatches the notification response tap to [onNotificationTap].
  void _handleNotificationResponse(NotificationResponse response) {
    onNotificationTap?.call();
  }
}
