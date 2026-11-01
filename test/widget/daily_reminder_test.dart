import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/app.dart';
import 'package:photo_per_day/core/routing/app_router.dart';
import 'package:photo_per_day/data/models/daily_reminder_settings.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/daily_reminder_service.dart';
import 'package:photo_per_day/data/services/daily_reminder_storage.dart';
import 'package:photo_per_day/data/services/notification_client.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/screens/profile/profile_screen.dart';
import 'package:photo_per_day/screens/today/today_screen.dart';
import 'package:photo_per_day/widgets/scrolling_time_picker.dart';
import 'package:photo_per_day/widgets/settings_tile.dart';

class WidgetTestFakeNotificationClient implements NotificationClient {
  bool permissionGranted = true;
  final Map<int, String> scheduled = {};
  void Function(NotificationResponse)? onResponse;

  @override
  Future<void> init({
    void Function(NotificationResponse)? onNotificationResponse,
  }) async {
    onResponse = onNotificationResponse;
  }

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    scheduled[id] = '$hour:$minute';
  }

  @override
  Future<void> cancel(int id) async {
    scheduled.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    scheduled.clear();
  }

  @override
  Future<List<int>> getPendingNotificationIds() async =>
      scheduled.keys.toList();

  @override
  Future<bool> didAppLaunchFromNotification() async => false;
}

class WidgetReminderFakePhotoMetadataStorage extends PhotoMetadataStorage {
  WidgetReminderFakePhotoMetadataStorage({super.customBaseDir});

  final Map<DateKey, PhotoEntry> _memory = {};

  @override
  Future<void> init() async {}

  @override
  Future<Map<DateKey, PhotoEntry>> loadAll() async => Map.from(_memory);

  @override
  Future<void> saveAll(Map<DateKey, PhotoEntry> entries) async {
    _memory.clear();
    _memory.addAll(entries);
  }

  @override
  Future<void> clear() async {
    _memory.clear();
  }
}

class WidgetReminderFakePhotoFileManager extends PhotoFileManager {
  WidgetReminderFakePhotoFileManager({super.customBaseDir});

  @override
  Future<void> init() async {}

  @override
  Future<String> persistPhotoFile({
    required String sourcePath,
    required DateKey dateKey,
  }) async => sourcePath;

  @override
  bool isManagedPath(String path) => true;

  @override
  Future<bool> deletePhotoFile(String? path) async => true;
}

class WidgetReminderFakeStorage extends DailyReminderStorage {
  WidgetReminderFakeStorage({super.customBaseDir});

  DailyReminderSettings _memory = DailyReminderSettings.defaultSettings;

  @override
  Future<DailyReminderSettings> loadSettings() async => _memory;

  @override
  Future<void> saveSettings(DailyReminderSettings settings) async {
    _memory = settings;
  }

  @override
  Future<void> clearSettings() async {
    _memory = DailyReminderSettings.defaultSettings;
  }
}

void main() {
  group('Milestone 33 — Daily Reminder Widget Tests', () {
    late WidgetReminderFakeStorage reminderStorage;
    late WidgetTestFakeNotificationClient fakeClient;
    late DailyReminderService reminderService;
    late PersistentDailyPhotoStore photoStore;

    setUp(() async {
      // In-memory PhotoStore
      final metaStorage = WidgetReminderFakePhotoMetadataStorage();
      final fileManager = WidgetReminderFakePhotoFileManager();

      photoStore = PersistentDailyPhotoStore(
        metadataStorage: metaStorage,
        fileManager: fileManager,
      );
      await photoStore.init();
      PersistentDailyPhotoStore.setTestInstance(photoStore);

      // In-memory ReminderService
      reminderStorage = WidgetReminderFakeStorage();
      fakeClient = WidgetTestFakeNotificationClient();
      reminderService = DailyReminderService(
        client: fakeClient,
        storage: reminderStorage,
      );
      await reminderService.init();
      DailyReminderService.setTestInstance(reminderService);
    });

    tearDown(() async {
      DailyReminderService.resetTestInstance();
      PersistentDailyPhotoStore.resetTestInstance();
      photoStore.dispose();
    });

    Widget createProfileTestWidget() {
      return const MaterialApp(home: Scaffold(body: ProfileScreen()));
    }

    testWidgets('1. Profile displays real default reminder state (Disabled)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createProfileTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Daily Reminder'), findsOneWidget);
      expect(
        find.text('Get a daily reminder to capture your photo.'),
        findsOneWidget,
      );

      final switchFinder = find.descendant(
        of: find.widgetWithText(SettingsTile, 'Daily Reminder'),
        matching: find.byType(Switch),
      );
      expect(switchFinder, findsOneWidget);
      final switchWidget = tester.widget<Switch>(switchFinder);
      expect(switchWidget.value, isFalse);

      // Reminder is confirmed disabled
      expect(reminderService.isEnabled, isFalse);
    });

    testWidgets('2. Enabling Daily Reminder updates UI and shows time badge', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createProfileTestWidget());
      await tester.pumpAndSettle();

      final switchFinder = find.descendant(
        of: find.widgetWithText(SettingsTile, 'Daily Reminder'),
        matching: find.byType(Switch),
      );
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(reminderService.isEnabled, isTrue);
      expect(find.text('Every day · 8:00 PM'), findsOneWidget);
      expect(find.text('8:00 PM'), findsOneWidget);

      final switchWidget = tester.widget<Switch>(switchFinder);
      expect(switchWidget.value, isTrue);

      expect(find.text('Daily reminder enabled for 8:00 PM'), findsOneWidget);
    });

    testWidgets('3. Profile displays saved reminder state with custom time', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await reminderService.setEnabled(true);
      await reminderService.setTime(hour: 9, minute: 30);

      await tester.pumpWidget(createProfileTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Every day · 9:30 AM'), findsOneWidget);
      expect(find.text('9:30 AM'), findsOneWidget);

      final switchWidget = tester.widget<Switch>(
        find.descendant(
          of: find.widgetWithText(SettingsTile, 'Daily Reminder'),
          matching: find.byType(Switch),
        ),
      );
      expect(switchWidget.value, isTrue);
    });

    testWidgets(
      '4. Permission denied keeps switch OFF and shows truthful status',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        fakeClient.permissionGranted = false;

        await tester.pumpWidget(createProfileTestWidget());
        await tester.pumpAndSettle();

        final switchFinder = find.descendant(
          of: find.widgetWithText(SettingsTile, 'Daily Reminder'),
          matching: find.byType(Switch),
        );
        await tester.tap(switchFinder);
        await tester.pumpAndSettle();

        expect(reminderService.isEnabled, isFalse);
        expect(reminderService.permissionDenied, isTrue);

        final switchWidget = tester.widget<Switch>(switchFinder);
        expect(switchWidget.value, isFalse);

        expect(
          find.text('Permission denied • Enable in system settings'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Notification permission is required to enable daily reminders.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('5. Tapping time badge opens time picker dialog', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await reminderService.setEnabled(true);

      await tester.pumpWidget(createProfileTestWidget());
      await tester.pumpAndSettle();

      final timeChipFinder = find.text('8:00 PM');
      expect(timeChipFinder, findsOneWidget);

      await tester.tap(timeChipFinder);
      await tester.pumpAndSettle();

      // Time picker dialog should now be visible
      expect(find.byType(ScrollingTimePickerDialog), findsOneWidget);

      // Tap OK/Cancel to close dialog
      final cancelButton = find.text('Cancel');
      if (cancelButton.evaluate().isNotEmpty) {
        await tester.tap(cancelButton);
        await tester.pumpAndSettle();
      }
    });

    testWidgets('6. Notification tap navigation routes directly to Today tab', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const PhotoPerDayApp());
      await tester.pumpAndSettle();

      // Dispatch notification tap navigation
      AppRouter.navigateToToday();
      await tester.pumpAndSettle();

      // Verify TodayScreen is displayed
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets(
      '7. Existing today photo is preserved and not duplicated on notification tap',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const todayKey = DateKey(2026, 3, 15);
        final todayEntry = PhotoEntry(
          date: todayKey.toDateTime(),
          title: 'Today Memory Invariant',
          syncStatus: SyncStatus.localOnly,
          gradientColors: const [Colors.amber, Colors.deepOrange],
        );
        await photoStore.savePhoto(entry: todayEntry);

        expect(photoStore.count, 1);

        await tester.pumpWidget(const PhotoPerDayApp());
        await tester.pumpAndSettle();

        // Dispatch notification tap
        AppRouter.navigateToToday();
        await tester.pumpAndSettle();

        // Verify today's existing photo entry is displayed on TodayScreen
        expect(find.byType(TodayScreen), findsOneWidget);

        // Verify store count has NOT increased and no duplicate was created
        expect(photoStore.count, 1);
      },
    );
  });
}
