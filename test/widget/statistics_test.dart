import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/core/routing/app_router.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/screens/profile/profile_screen.dart';
import 'package:photo_per_day/screens/statistics/statistics_screen.dart';
import 'package:photo_per_day/widgets/settings_tile.dart';

class WidgetStatisticsFakePhotoMetadataStorage extends PhotoMetadataStorage {
  WidgetStatisticsFakePhotoMetadataStorage({super.customBaseDir});

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

class WidgetStatisticsFakePhotoFileManager extends PhotoFileManager {
  WidgetStatisticsFakePhotoFileManager({super.customBaseDir});

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late WidgetStatisticsFakePhotoMetadataStorage metadataStorage;
  late WidgetStatisticsFakePhotoFileManager fileManager;
  late PersistentDailyPhotoStore photoStore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('statistics_widget_test_');
    metadataStorage = WidgetStatisticsFakePhotoMetadataStorage(
      customBaseDir: tempDir,
    );
    fileManager = WidgetStatisticsFakePhotoFileManager(customBaseDir: tempDir);

    photoStore = PersistentDailyPhotoStore(
      metadataStorage: metadataStorage,
      fileManager: fileManager,
    );
    await photoStore.init();
    PersistentDailyPhotoStore.setTestInstance(photoStore);
  });

  tearDown(() async {
    PersistentDailyPhotoStore.resetTestInstance();
    photoStore.dispose();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  Future<PhotoEntry> addSamplePhoto({
    required DateKey dateKey,
    required String title,
  }) async {
    final entry = PhotoEntry(
      date: dateKey.toDateTime(),
      title: title,
      syncStatus: SyncStatus.localOnly,
      gradientColors: const [Colors.teal, Colors.indigo],
    );
    await photoStore.savePhoto(entry: entry);
    return entry;
  }

  group('Milestone 32 — Statistics Widget & Navigation Tests', () {
    testWidgets('17. Profile Statistics tile opens StatisticsScreen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          onGenerateRoute: AppRouter.onGenerateRoute,
          home: Scaffold(body: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Find Statistics SettingsTile under Memories & Journal
      final statisticsTile = find.widgetWithText(SettingsTile, 'Statistics');
      expect(statisticsTile, findsOneWidget);
      expect(find.text('See your Daria history'), findsOneWidget);

      await tester.ensureVisible(statisticsTile);
      await tester.pumpAndSettle();

      // Tap Statistics tile
      await tester.tap(statisticsTile);
      await tester.pumpAndSettle();

      // Verify StatisticsScreen is opened
      expect(find.byType(StatisticsScreen), findsOneWidget);
      expect(find.text('YOUR PHOTO JOURNEY'), findsOneWidget);
    });

    testWidgets(
      'Tapping PHOTO STREAK card in Profile also opens StatisticsScreen',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          const MaterialApp(
            onGenerateRoute: AppRouter.onGenerateRoute,
            home: Scaffold(body: ProfileScreen()),
          ),
        );
        await tester.pumpAndSettle();

        final streakHeader = find.text('PHOTO STREAK');
        expect(streakHeader, findsOneWidget);

        await tester.tap(streakHeader);
        await tester.pumpAndSettle();

        expect(find.byType(StatisticsScreen), findsOneWidget);
      },
    );

    testWidgets('18. Statistics screen displays real calculated values', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const refToday = DateKey(2026, 3, 20);

      // Add photos:
      // Jan 15, 2026
      // Feb 10, 2026
      // Mar 18, 2026
      // Mar 19, 2026
      // Mar 20, 2026 (today)
      await addSamplePhoto(
        dateKey: const DateKey(2026, 1, 15),
        title: 'Jan Photo',
      );
      await addSamplePhoto(
        dateKey: const DateKey(2026, 2, 10),
        title: 'Feb Photo',
      );
      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 18),
        title: 'Mar 18 Photo',
      );
      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 19),
        title: 'Mar 19 Photo',
      );
      await addSamplePhoto(dateKey: refToday, title: 'Today Photo');

      await tester.pumpWidget(
        MaterialApp(
          home: StatisticsScreen(store: photoStore, todayKey: refToday),
        ),
      );
      await tester.pumpAndSettle();

      // Total photos: 5, Recorded days: 5
      expect(find.text('5'), findsNWidgets(2)); // Total Photos & Recorded Days
      expect(find.text('Total Photos'), findsOneWidget);
      expect(find.text('Recorded Days'), findsOneWidget);

      // Current streak: 3 days (18, 19, 20)
      expect(find.text('3 days'), findsNWidgets(2)); // Current & Longest
      expect(find.text('Current Streak'), findsOneWidget);
      expect(find.text('Longest Streak'), findsOneWidget);

      // Milestone dates
      expect(find.text('January 15, 2026'), findsOneWidget); // First photo
      expect(find.text('March 20, 2026'), findsOneWidget); // Latest photo

      // Time breakdown:
      // This Month (March): 3 photos
      expect(find.text('3 photos'), findsOneWidget);
      // This Year (2026): 5 photos
      expect(find.text('5 photos'), findsOneWidget);

      // Monthly activity card
      expect(find.text('MONTHLY ACTIVITY (2026)'), findsOneWidget);
      expect(find.text('5 total'), findsOneWidget);
    });

    testWidgets('19. Empty state contains no mock statistics', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const refToday = DateKey(2026, 3, 20);

      // Empty store
      await tester.pumpWidget(
        MaterialApp(
          home: StatisticsScreen(store: photoStore, todayKey: refToday),
        ),
      );
      await tester.pumpAndSettle();

      // Empty state guidance banner & CTA button
      expect(find.text('Begin your Daria journey'), findsOneWidget);
      expect(find.text("Capture Today's Photo"), findsOneWidget);

      // Real 0 values in overview
      expect(
        find.descendant(
          of: find.byKey(const Key('stat_total_photos')),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('stat_recorded_days')),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
      expect(
        find.text('0 days'),
        findsNWidgets(3),
      ); // Current streak, longest streak, longest gap

      // Dates are "Not available"
      expect(find.text('Not available'), findsNWidgets(2));

      // Time breakdown: 0 photos
      expect(find.text('0 photos'), findsNWidgets(2)); // This month, this year

      // No mock numbers like '74' or '18'
      expect(find.text('74'), findsNothing);
      expect(find.text('18'), findsNothing);
    });

    testWidgets('20. Store changes refresh the Statistics screen dynamically', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const refToday = DateKey(2026, 3, 20);

      await tester.pumpWidget(
        MaterialApp(
          home: StatisticsScreen(store: photoStore, todayKey: refToday),
        ),
      );
      await tester.pumpAndSettle();

      // Initially empty
      expect(find.text('Begin your Daria journey'), findsOneWidget);
      expect(find.text('0 days'), findsNWidgets(3));

      // 1. Add photo for today
      await addSamplePhoto(dateKey: refToday, title: 'Today Photo');
      await tester.pumpAndSettle();

      // Screen updates live: CTA is gone, values updated!
      expect(find.text('Begin your Daria journey'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('stat_total_photos')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('stat_recorded_days')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(
        find.text('1 day'),
        findsNWidgets(2),
      ); // current streak, longest streak
      expect(find.text('March 20, 2026'), findsNWidgets(2)); // first and latest

      // 2. Delete photo for today
      photoStore.removePhoto(refToday.toDateTime());
      await tester.pumpAndSettle();

      // Screen drops back to empty state!
      expect(find.text('Begin your Daria journey'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('stat_total_photos')),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('stat_recorded_days')),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
      expect(find.text('0 days'), findsNWidgets(3));
      expect(find.text('Not available'), findsNWidgets(2));
    });

    testWidgets('Empty state CTA button invokes onCaptureTap callback', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool captureTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: StatisticsScreen(
            store: photoStore,
            todayKey: const DateKey(2026, 3, 20),
            onCaptureTap: () => captureTapped = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final captureButton = find.widgetWithText(
        ElevatedButton,
        "Capture Today's Photo",
      );
      expect(captureButton, findsOneWidget);

      await tester.tap(captureButton);
      await tester.pumpAndSettle();

      expect(captureTapped, isTrue);
    });
  });
}
