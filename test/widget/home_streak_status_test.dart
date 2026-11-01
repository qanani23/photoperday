import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/data/services/streak_service.dart';
import 'package:photo_per_day/screens/home/home_screen.dart';

class StreakFakePhotoMetadataStorage extends PhotoMetadataStorage {
  StreakFakePhotoMetadataStorage({super.customBaseDir});

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

class StreakFakePhotoFileManager extends PhotoFileManager {
  StreakFakePhotoFileManager({super.customBaseDir});

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
  group('Milestone 53 — Home Screen Local Streak Status Tests', () {
    late Directory tempDir;
    late PersistentDailyPhotoStore photoStore;

    setUp(() async {
      StreakService.instance.clearCache();
      tempDir = await Directory.systemTemp.createTemp('home_streak_test_');
      final metaStorage = StreakFakePhotoMetadataStorage();
      final fileManager = StreakFakePhotoFileManager();

      photoStore = PersistentDailyPhotoStore(
        metadataStorage: metaStorage,
        fileManager: fileManager,
      );
      await photoStore.init();
      PersistentDailyPhotoStore.setTestInstance(photoStore);
    });

    tearDown(() async {
      PersistentDailyPhotoStore.resetTestInstance();
      photoStore.dispose();
      StreakService.instance.clearCache();
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    Widget createHomeWidget() {
      return const MaterialApp(home: HomeScreen(showFullCalendar: true));
    }

    testWidgets(
      '1. Home screen displays local streak overview card when empty',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createHomeWidget());
        await tester.pumpAndSettle();

        // Verify streak banner presence on Home screen
        expect(
          find.byKey(const ValueKey('home_streak_status_banner')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('streak_display_number')))
              .data,
          '0',
        );
      },
    );

    testWidgets(
      '2. Home streak reflects single source of truth from local diary photos',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Add 3 consecutive days leading up to today
        final now = DateTime.now();
        for (int i = 0; i < 3; i++) {
          final d = now.subtract(Duration(days: i));
          await photoStore.savePhoto(
            entry: PhotoEntry(
              date: DateTime(d.year, d.month, d.day),
              title: 'Day $i',
              syncStatus: SyncStatus.localOnly,
              gradientColors: const [Colors.amber, Colors.deepOrange],
            ),
          );
        }

        final currentStreak = StreakService.instance
            .calculateStreak(store: photoStore, todayDate: now)
            .currentStreak;
        expect(currentStreak, equals(3));

        await tester.pumpWidget(createHomeWidget());
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('streak_display_number')))
              .data,
          '3',
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('streak_display_label')))
              .data,
          'CURRENT STREAK',
        );
      },
    );

    testWidgets(
      '3. Home streak banner reactively updates when photo is saved',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createHomeWidget());
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('streak_display_number')))
              .data,
          '0',
        );

        // Save today's photo
        final now = DateTime.now();
        await photoStore.savePhoto(
          entry: PhotoEntry(
            date: DateTime(now.year, now.month, now.day),
            title: 'Today Photo',
            syncStatus: SyncStatus.localOnly,
            gradientColors: const [Colors.amber, Colors.deepOrange],
          ),
        );

        await tester.pumpAndSettle();

        // Streak reactively updates to 1 day streak
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('streak_display_number')))
              .data,
          '1',
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('streak_display_label')))
              .data,
          'CURRENT STREAK',
        );
      },
    );

    testWidgets('4. Local photo starts and increments streak directly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createHomeWidget());
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('streak_display_number')))
            .data,
        '0',
      );

      // Save today's photo
      final now = DateTime.now();
      await photoStore.savePhoto(
        entry: PhotoEntry(
          date: DateTime(now.year, now.month, now.day),
          title: 'Local Only Photo',
          syncStatus: SyncStatus.localOnly,
          gradientColors: const [Colors.amber, Colors.deepOrange],
        ),
      );

      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('streak_display_number')))
            .data,
        '1',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('streak_display_label')))
            .data,
        'CURRENT STREAK',
      );
    });
  });
}
