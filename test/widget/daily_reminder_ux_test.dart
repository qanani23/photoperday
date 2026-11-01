import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/daily_reminder_settings.dart';
import 'package:photo_per_day/data/services/daily_reminder_service.dart';
import 'package:photo_per_day/data/services/daily_reminder_storage.dart';
import 'package:photo_per_day/data/services/notification_client.dart';
import 'package:photo_per_day/screens/settings/settings_screen.dart';
import 'package:photo_per_day/widgets/scrolling_time_picker.dart';
import 'package:photo_per_day/widgets/settings_tile.dart';

class UxFakeNotificationClient implements NotificationClient {
  bool permissionGranted = true;
  final Map<int, String> scheduled = {};

  @override
  Future<void> init({
    void Function(NotificationResponse)? onNotificationResponse,
  }) async {}

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

class UxFakeReminderStorage extends DailyReminderStorage {
  UxFakeReminderStorage({super.customBaseDir});

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
  group('Milestone 43 — Daily Reminder UX & Scrolling Picker Widget Tests', () {
    late UxFakeReminderStorage reminderStorage;
    late UxFakeNotificationClient fakeClient;
    late DailyReminderService reminderService;

    setUp(() async {
      reminderStorage = UxFakeReminderStorage();
      fakeClient = UxFakeNotificationClient();
      reminderService = DailyReminderService(
        client: fakeClient,
        storage: reminderStorage,
      );
      await reminderService.init();
      DailyReminderService.setTestInstance(reminderService);
    });

    tearDown(() {
      DailyReminderService.resetTestInstance();
    });

    Widget createSettingsWidget() {
      return const MaterialApp(home: SettingsScreen());
    }

    testWidgets('1. Settings shows Daily Reminder and explicit Edit button', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createSettingsWidget());
      await tester.pumpAndSettle();

      expect(find.text('Daily Reminder'), findsOneWidget);
      expect(
        find.text('Receive a reminder to capture today\'s photo'),
        findsOneWidget,
      );
      expect(find.text('Edit'), findsOneWidget);
      expect(
        find.descendant(
          of: find.widgetWithText(SettingsTile, 'Daily Reminder'),
          matching: find.byType(Switch),
        ),
        findsOneWidget,
      );
    });

    testWidgets('2. Tapping Edit button opens ScrollingTimePickerDialog', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createSettingsWidget());
      await tester.pumpAndSettle();

      final editButtonFinder = find.text('Edit');
      expect(editButtonFinder, findsOneWidget);

      await tester.tap(editButtonFinder);
      await tester.pumpAndSettle();

      // Scrolling time picker dialog is displayed
      expect(find.byType(ScrollingTimePickerDialog), findsOneWidget);
      expect(find.text('Set Reminder Time'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('3. ScrollingTimePickerDialog Cancel discards changes', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await reminderService.setTime(hour: 8, minute: 0);

      await tester.pumpWidget(createSettingsWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(ScrollingTimePickerDialog), findsNothing);
      expect(reminderService.settings.hour, equals(8));
      expect(reminderService.settings.minute, equals(0));
    });

    testWidgets('4. ScrollingTimePickerDialog Save commits new time', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await reminderService.setEnabled(true);
      await reminderService.setTime(hour: 8, minute: 0);

      await tester.pumpWidget(createSettingsWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // Tap Save (without scrolling, saves the initial/selected time)
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.byType(ScrollingTimePickerDialog), findsNothing);
      expect(
        fakeClient.scheduled.containsKey(
          DailyReminderService.reminderNotificationId,
        ),
        isTrue,
      );
    });

    testWidgets(
      '5. Turning reminder OFF then ON preserves previously configured time',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Configure a custom time (e.g. 19:30 / 7:30 PM)
        await reminderService.setEnabled(true);
        await reminderService.setTime(hour: 19, minute: 30);

        expect(reminderService.settings.hour, equals(19));
        expect(reminderService.settings.minute, equals(30));
        expect(
          fakeClient.scheduled[DailyReminderService.reminderNotificationId],
          equals('19:30'),
        );

        await tester.pumpWidget(createSettingsWidget());
        await tester.pumpAndSettle();

        // Toggle switch OFF
        final switchFinder = find.descendant(
          of: find.widgetWithText(SettingsTile, 'Daily Reminder'),
          matching: find.byType(Switch),
        );
        await tester.tap(switchFinder);
        await tester.pumpAndSettle();

        expect(reminderService.isEnabled, isFalse);
        expect(
          fakeClient.scheduled.containsKey(
            DailyReminderService.reminderNotificationId,
          ),
          isFalse,
        );
        // Hour and minute should still be 19:30
        expect(reminderService.settings.hour, equals(19));
        expect(reminderService.settings.minute, equals(30));

        // Toggle switch back ON
        await tester.tap(switchFinder);
        await tester.pumpAndSettle();

        expect(reminderService.isEnabled, isTrue);
        // Restores 19:30, NOT resetting to 08:00
        expect(reminderService.settings.hour, equals(19));
        expect(reminderService.settings.minute, equals(30));
        expect(
          fakeClient.scheduled[DailyReminderService.reminderNotificationId],
          equals('19:30'),
        );
      },
    );
  });
}
