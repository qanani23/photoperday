import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/daily_reminder_service.dart';
import 'package:photo_per_day/data/services/daily_reminder_storage.dart';
import 'package:photo_per_day/data/services/notification_client.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';

class ScheduledRecord {
  const ScheduledRecord({
    required this.id,
    required this.title,
    required this.body,
    required this.hour,
    required this.minute,
  });

  final int id;
  final String title;
  final String body;
  final int hour;
  final int minute;
}

class FakeNotificationClient implements NotificationClient {
  bool permissionGranted = true;
  int initCallCount = 0;
  int requestPermissionCallCount = 0;
  int hasPermissionCallCount = 0;
  final Map<int, ScheduledRecord> scheduled = {};
  final List<int> cancelledIds = [];
  int cancelAllCallCount = 0;
  void Function(NotificationResponse)? onResponseCallback;

  @override
  Future<void> init({
    void Function(NotificationResponse)? onNotificationResponse,
  }) async {
    initCallCount++;
    onResponseCallback = onNotificationResponse;
  }

  @override
  Future<bool> requestPermission() async {
    requestPermissionCallCount++;
    return permissionGranted;
  }

  @override
  Future<bool> hasPermission() async {
    hasPermissionCallCount++;
    return permissionGranted;
  }

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    scheduled[id] = ScheduledRecord(
      id: id,
      title: title,
      body: body,
      hour: hour,
      minute: minute,
    );
  }

  @override
  Future<void> cancel(int id) async {
    cancelledIds.add(id);
    scheduled.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCallCount++;
    scheduled.clear();
  }

  @override
  Future<List<int>> getPendingNotificationIds() async =>
      scheduled.keys.toList();

  @override
  Future<bool> didAppLaunchFromNotification() async => false;

  void triggerTap(int id) {
    onResponseCallback?.call(
      NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        id: id,
      ),
    );
  }
}

void main() {
  group('Milestone 33 — DailyReminderService Unit Tests', () {
    late Directory tempDir;
    late DailyReminderStorage storage;
    late FakeNotificationClient client;
    late DailyReminderService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('reminder_unit_test_');
      storage = DailyReminderStorage(customBaseDir: tempDir.path);
      client = FakeNotificationClient();
      service = DailyReminderService(client: client, storage: storage);
      await service.init();
    });

    tearDown(() async {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('1. Default reminder state is disabled at 8:00 PM', () {
      expect(service.isEnabled, isFalse);
      expect(service.settings.enabled, isFalse);
      expect(service.settings.hour, 20);
      expect(service.settings.minute, 0);
      expect(service.settings.formattedTime, '8:00 PM');
      expect(service.permissionDenied, isFalse);
      expect(client.scheduled.isEmpty, isTrue);
    });

    test('2. Enabling reminder persists enabled state to disk', () async {
      final success = await service.setEnabled(true);
      expect(success, isTrue);
      expect(service.isEnabled, isTrue);

      final loaded = await storage.loadSettings();
      expect(loaded.enabled, isTrue);
      expect(loaded.hour, 20);
      expect(loaded.minute, 0);
    });

    test('3. Selected hour/minute persist to disk', () async {
      await service.setTime(hour: 9, minute: 30);
      expect(service.settings.hour, 9);
      expect(service.settings.minute, 30);
      expect(service.settings.formattedTime, '9:30 AM');

      final loaded = await storage.loadSettings();
      expect(loaded.hour, 9);
      expect(loaded.minute, 30);
    });

    test('4. Disabling reminder cancels scheduled notification', () async {
      await service.setEnabled(true);
      expect(client.scheduled.containsKey(1001), isTrue);

      final success = await service.setEnabled(false);
      expect(success, isTrue);
      expect(service.isEnabled, isFalse);
      expect(client.scheduled.containsKey(1001), isFalse);
      expect(client.cancelledIds.contains(1001), isTrue);

      final loaded = await storage.loadSettings();
      expect(loaded.enabled, isFalse);
    });

    test('5. Enabling schedules exactly one calm notification', () async {
      await service.setEnabled(true);
      expect(client.scheduled.length, 1);
      final record = client.scheduled[1001];
      expect(record, isNotNull);
      expect(record!.id, DailyReminderService.reminderNotificationId);
      expect(record.title, 'Daria');
      expect(record.body, "Capture today's memory.");
      expect(record.hour, 20);
      expect(record.minute, 0);
    });

    test(
      '6. Changing time cancels and replaces the previous schedule',
      () async {
        await service.setEnabled(true);
        expect(client.scheduled[1001]?.hour, 20);

        await service.setTime(hour: 7, minute: 45);
        expect(client.scheduled.length, 1);
        expect(client.scheduled[1001]?.hour, 7);
        expect(client.scheduled[1001]?.minute, 45);
        expect(service.settings.formattedTime, '7:45 AM');
      },
    );

    test('7. Re-enabling does not create duplicate schedules', () async {
      await service.setEnabled(true);
      await service.setEnabled(true);
      await service.setEnabled(true);

      expect(client.scheduled.length, 1);
      expect(client.scheduled.containsKey(1001), isTrue);
    });

    test(
      '8. App restart restores configuration and synchronizes schedule',
      () async {
        await service.setTime(hour: 18, minute: 15);
        await service.setEnabled(true);

        // Simulate app restart by initializing a new service instance with same storage
        final newClient = FakeNotificationClient();
        final restartedService = DailyReminderService(
          client: newClient,
          storage: storage,
        );
        await restartedService.init();

        expect(restartedService.isEnabled, isTrue);
        expect(restartedService.settings.hour, 18);
        expect(restartedService.settings.minute, 15);
        expect(restartedService.settings.formattedTime, '6:15 PM');
        expect(newClient.scheduled.length, 1);
        expect(newClient.scheduled[1001]?.hour, 18);
        expect(newClient.scheduled[1001]?.minute, 15);
      },
    );

    test('9. Permission denied does not report reminder as enabled', () async {
      client.permissionGranted = false;

      final success = await service.setEnabled(true);
      expect(success, isFalse);
      expect(service.isEnabled, isFalse);
      expect(service.permissionDenied, isTrue);
      expect(client.scheduled.isEmpty, isTrue);

      final loaded = await storage.loadSettings();
      expect(loaded.enabled, isFalse);
    });

    test(
      '10. Permission revoked during restart updates state truthfully',
      () async {
        await service.setEnabled(true);
        expect(service.isEnabled, isTrue);

        // Now client permission is revoked externally
        final newClient = FakeNotificationClient()..permissionGranted = false;
        final restartedService = DailyReminderService(
          client: newClient,
          storage: storage,
        );
        await restartedService.init();

        expect(restartedService.isEnabled, isFalse);
        expect(restartedService.permissionDenied, isTrue);
        expect(newClient.scheduled.isEmpty, isTrue);

        final loaded = await storage.loadSettings();
        expect(loaded.enabled, isFalse);
      },
    );

    test('11. Notification tap triggers onNotificationTap callback', () async {
      bool tapDispatched = false;
      service.onNotificationTap = () {
        tapDispatched = true;
      };

      await service.setEnabled(true);
      client.triggerTap(1001);

      expect(tapDispatched, isTrue);
    });

    test(
      '12. Changing time while disabled does not schedule notification',
      () async {
        expect(service.isEnabled, isFalse);
        await service.setTime(hour: 10, minute: 0);

        expect(service.settings.hour, 10);
        expect(client.scheduled.isEmpty, isTrue);

        final loaded = await storage.loadSettings();
        expect(loaded.hour, 10);
        expect(loaded.enabled, isFalse);
      },
    );

    test('13. Time clamping works correctly for invalid inputs', () async {
      await service.setTime(hour: 99, minute: -5);
      expect(service.settings.hour, 23);
      expect(service.settings.minute, 0);

      await service.setTime(hour: -10, minute: 150);
      expect(service.settings.hour, 0);
      expect(service.settings.minute, 59);
    });

    test(
      '14. Scheduling does not modify PersistentDailyPhotoStore or photos',
      () async {
        final metaStorage = PhotoMetadataStorage(customBaseDir: tempDir);
        final fileManager = PhotoFileManager(customBaseDir: tempDir);

        final photoStore = PersistentDailyPhotoStore(
          metadataStorage: metaStorage,
          fileManager: fileManager,
        );
        await photoStore.init();

        // Add one sample photo
        const dateKey = DateKey(2026, 3, 26);
        final entry = PhotoEntry(
          date: dateKey.toDateTime(),
          title: 'Sample Photo',
          syncStatus: SyncStatus.localOnly,
          gradientColors: const [Colors.teal, Colors.indigo],
        );
        await photoStore.savePhoto(entry: entry);

        expect(photoStore.count, 1);

        // Enable and modify reminders
        await service.setEnabled(true);
        await service.setTime(hour: 21, minute: 0);
        await service.setEnabled(false);

        // Verify store data is completely untouched
        expect(photoStore.count, 1);
        final retrieved = photoStore.getPhotoByKey(dateKey);
        expect(retrieved?.title, 'Sample Photo');
        expect(retrieved?.date, entry.date);

        photoStore.dispose();
      },
    );
  });
}
