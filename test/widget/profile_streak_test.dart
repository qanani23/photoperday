import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/screens/profile/profile_screen.dart';

class WidgetProfileTestFakePhotoMetadataStorage extends PhotoMetadataStorage {
  WidgetProfileTestFakePhotoMetadataStorage({super.customBaseDir});

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

class WidgetProfileTestFakePhotoFileManager extends PhotoFileManager {
  WidgetProfileTestFakePhotoFileManager({super.customBaseDir});

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
  late WidgetProfileTestFakePhotoMetadataStorage metadataStorage;
  late WidgetProfileTestFakePhotoFileManager fileManager;
  late PersistentDailyPhotoStore photoStore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('profile_streak_test_');
    metadataStorage = WidgetProfileTestFakePhotoMetadataStorage(
      customBaseDir: tempDir,
    );
    fileManager = WidgetProfileTestFakePhotoFileManager(customBaseDir: tempDir);

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

  Widget createProfileTestWidget() {
    return const MaterialApp(home: Scaffold(body: ProfileScreen()));
  }

  group('Milestone 31 — Profile Photo Streak Widget Tests', () {
    testWidgets('15. Profile displays real calculated values', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Today
      final today = DateKey.today();
      final yesterday = today.previousDay;

      await addSamplePhoto(dateKey: yesterday, title: 'Yesterday Photo');
      await addSamplePhoto(dateKey: today, title: 'Today Photo');

      await tester.pumpWidget(createProfileTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('PHOTO STREAK'), findsOneWidget);
      expect(find.text('Current Streak'), findsOneWidget);
      expect(find.text('Longest Streak'), findsOneWidget);
      expect(find.text('Recorded Days'), findsOneWidget);

      // Current streak: 2 days, Longest: 2 days, Recorded: 2 days
      expect(find.text('2 days'), findsNWidgets(3));
    });

    testWidgets('16. No mock statistics are displayed for empty state', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Completely empty photo store
      await tester.pumpWidget(createProfileTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('PHOTO STREAK'), findsOneWidget);

      // All real streak values are 0 days
      expect(find.text('0 days'), findsNWidgets(3));

      // Ensure mock '74' or '18' numbers are never displayed
      expect(find.text('74'), findsNothing);
      expect(find.text('18'), findsNothing);
    });

    testWidgets('13. Deleting today photo updates current streak dynamically', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final today = DateKey.today();
      final yesterday = today.previousDay;

      await addSamplePhoto(dateKey: yesterday, title: 'Yesterday Photo');
      await addSamplePhoto(dateKey: today, title: 'Today Photo');

      await tester.pumpWidget(createProfileTestWidget());
      await tester.pumpAndSettle();

      // Initially current streak is 2 days
      expect(find.text('Current Streak'), findsOneWidget);

      // Delete today's photo
      photoStore.removePhoto(today.toDateTime());
      await tester.pumpAndSettle();

      // Under M44, yesterday's photo preserves the streak until midnight
      expect(
        find.text('1 day'),
        findsNWidgets(3),
      ); // current streak (preserved), longest streak, and recorded days
    });

    testWidgets(
      '14. Deleting a photo from historical sequence updates longest streak',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // 3 consecutive historical days in the past (not including today)
        const day1 = DateKey(2026, 1, 10);
        const day2 = DateKey(2026, 1, 11);
        const day3 = DateKey(2026, 1, 12);

        await addSamplePhoto(dateKey: day1, title: 'Day 1');
        await addSamplePhoto(dateKey: day2, title: 'Day 2');
        await addSamplePhoto(dateKey: day3, title: 'Day 3');

        await tester.pumpWidget(createProfileTestWidget());
        await tester.pumpAndSettle();

        // Longest streak was 3 days
        expect(find.text('3 days'), findsNWidgets(2)); // longest & recorded
        expect(
          find.text('0 days'),
          findsOneWidget,
        ); // current streak (not today)

        // Delete middle day (day 2)
        photoStore.removePhoto(day2.toDateTime());
        await tester.pumpAndSettle();

        // Sequence is split into two 1-day streaks! Longest drops to 1 day
        expect(find.text('1 day'), findsOneWidget); // longest streak
        expect(find.text('2 days'), findsOneWidget); // recorded days (2 left)
        expect(find.text('0 days'), findsOneWidget); // current streak
      },
    );

    testWidgets(
      '17. Store updates cause the streak UI to refresh dynamically',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createProfileTestWidget());
        await tester.pumpAndSettle();

        // Initially zero
        expect(find.text('0 days'), findsNWidgets(3));

        // Add today's photo
        final today = DateKey.today();
        await addSamplePhoto(dateKey: today, title: 'New Today Photo');
        await tester.pumpAndSettle();

        // Automatically refreshed to 1 day!
        expect(find.text('1 day'), findsNWidgets(3));
      },
    );
  });
}
