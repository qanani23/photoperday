import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/core/routing/app_router.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/memory_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/screens/diary/memories_screen.dart';
import 'package:photo_per_day/screens/diary/swipe_days_screen.dart';
import 'package:photo_per_day/screens/photo_detail/photo_detail_screen.dart';

class WidgetMemoriesTestFakePhotoMetadataStorage extends PhotoMetadataStorage {
  WidgetMemoriesTestFakePhotoMetadataStorage({super.customBaseDir});

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

class WidgetMemoriesTestFakePhotoFileManager extends PhotoFileManager {
  WidgetMemoriesTestFakePhotoFileManager({super.customBaseDir});

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
  late WidgetMemoriesTestFakePhotoMetadataStorage metadataStorage;
  late WidgetMemoriesTestFakePhotoFileManager fileManager;
  late PersistentDailyPhotoStore photoStore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('memories_widget_test_');
    metadataStorage = WidgetMemoriesTestFakePhotoMetadataStorage(
      customBaseDir: tempDir,
    );
    fileManager = WidgetMemoriesTestFakePhotoFileManager(
      customBaseDir: tempDir,
    );

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
    String? location,
    String timeFormatted = '2:45 PM',
    SyncStatus syncStatus = SyncStatus.localOnly,
    String? imagePath,
  }) async {
    final entry = PhotoEntry(
      date: dateKey.toDateTime(),
      title: title,
      location: location,
      timeFormatted: timeFormatted,
      syncStatus: syncStatus,
      imagePath: imagePath,
      gradientColors: const [Colors.indigo, Colors.blueGrey],
    );
    await photoStore.savePhoto(entry: entry);
    return entry;
  }

  Widget createTestWidget({DateTime? targetDate, VoidCallback? onCaptureTap}) {
    return MaterialApp(
      initialRoute: AppConstants.memoriesRoute,
      onGenerateRoute: (settings) {
        if (settings.name == AppConstants.memoriesRoute) {
          return MaterialPageRoute<void>(
            builder: (_) => MemoriesScreen(
              targetDate: targetDate,
              store: photoStore,
              onCaptureTap: onCaptureTap,
            ),
            settings: settings,
          );
        }
        return AppRouter.onGenerateRoute(settings);
      },
    );
  }

  group('Milestone 30 — On This Day / Memories Tests', () {
    testWidgets('1. Finds previous-year photo with same month/day', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final targetDate = DateTime(2026, 3, 28);

      // Add a previous-year photo on March 28, 2025
      await addSamplePhoto(
        dateKey: const DateKey(2025, 3, 28),
        title: 'Central Park Walk 2025',
      );

      await tester.pumpWidget(createTestWidget(targetDate: targetDate));
      await tester.pumpAndSettle();

      expect(find.text('Central Park Walk 2025'), findsOneWidget);
      expect(find.text('1 year ago'), findsOneWidget);
      expect(find.text('No memories from this day yet'), findsNothing);
    });

    testWidgets('2. Does not include current-year photo', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final targetDate = DateTime(2026, 3, 28);

      // Add only today's current-year photo (2026-03-28)
      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 28),
        title: 'Today Capture 2026',
      );

      await tester.pumpWidget(createTestWidget(targetDate: targetDate));
      await tester.pumpAndSettle();

      // Today's current-year photo must NOT appear
      expect(find.text('Today Capture 2026'), findsNothing);
      expect(find.text('No memories from this day yet'), findsOneWidget);
    });

    testWidgets('3. Does not include different month/day', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final targetDate = DateTime(2026, 3, 28);

      // Add photos from previous year but different month/day
      await addSamplePhoto(
        dateKey: const DateKey(2025, 3, 15),
        title: 'Mid March Photo',
      );
      await addSamplePhoto(
        dateKey: const DateKey(2025, 3, 29),
        title: 'March 29 Photo',
      );

      await tester.pumpWidget(createTestWidget(targetDate: targetDate));
      await tester.pumpAndSettle();

      expect(find.text('Mid March Photo'), findsNothing);
      expect(find.text('March 29 Photo'), findsNothing);
      expect(find.text('No memories from this day yet'), findsOneWidget);
    });

    testWidgets('4. Returns multiple historical years', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final targetDate = DateTime(2026, 3, 28);

      await addSamplePhoto(
        dateKey: const DateKey(2025, 3, 28),
        title: 'Memory 2025',
      );
      await addSamplePhoto(
        dateKey: const DateKey(2024, 3, 28),
        title: 'Memory 2024',
      );
      await addSamplePhoto(
        dateKey: const DateKey(2023, 3, 28),
        title: 'Memory 2023',
      );

      await tester.pumpWidget(createTestWidget(targetDate: targetDate));
      await tester.pumpAndSettle();

      expect(find.text('Memory 2025'), findsOneWidget);
      expect(find.text('Memory 2024'), findsOneWidget);
      expect(find.text('Memory 2023'), findsOneWidget);
      expect(find.text('3 memories'), findsOneWidget);
    });

    testWidgets('5. Correct newest-to-oldest memory ordering', (tester) async {
      final targetDate = DateTime(2026, 3, 28);

      final memories = MemoryService.instance.getMemoriesForDate(
        targetDate,
        sourceEntries: [
          PhotoEntry(
            date: DateTime(2023, 3, 28),
            title: 'Memory 2023',
            gradientColors: const [],
          ),
          PhotoEntry(
            date: DateTime(2025, 3, 28),
            title: 'Memory 2025',
            gradientColors: const [],
          ),
          PhotoEntry(
            date: DateTime(2024, 3, 28),
            title: 'Memory 2024',
            gradientColors: const [],
          ),
        ],
      );

      expect(memories.length, 3);
      expect(memories[0].dateKey, const DateKey(2025, 3, 28));
      expect(memories[1].dateKey, const DateKey(2024, 3, 28));
      expect(memories[2].dateKey, const DateKey(2023, 3, 28));
    });

    testWidgets('6. No memories returns empty state', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final targetDate = DateTime(2026, 3, 28);

      await tester.pumpWidget(createTestWidget(targetDate: targetDate));
      await tester.pumpAndSettle();

      expect(find.text('No memories from this day yet'), findsOneWidget);
      expect(find.text("Capture Today's Photo"), findsOneWidget);
    });

    testWidgets('7. Future entries are excluded', (tester) async {
      final targetDate = DateTime(2026, 3, 28);

      final memories = MemoryService.instance.getMemoriesForDate(
        targetDate,
        sourceEntries: [
          // Future year relative to targetDate
          PhotoEntry(
            date: DateTime(2027, 3, 28),
            title: 'Future Year',
            gradientColors: const [],
          ),
          // Past year
          PhotoEntry(
            date: DateTime(2025, 3, 28),
            title: 'Valid Memory',
            gradientColors: const [],
          ),
        ],
      );

      expect(memories.length, 1);
      expect(memories.first.title, 'Valid Memory');
    });

    testWidgets('8. February 29 behavior is correct', (tester) async {
      // 1. If targetDate is Feb 28, 2025: Feb 29 from leap year 2024 must NOT match
      final targetFeb28 = DateTime(2025, 2, 28);
      final memoriesFeb28 = MemoryService.instance.getMemoriesForDate(
        targetFeb28,
        sourceEntries: [
          PhotoEntry(
            date: DateTime(2024, 2, 29),
            title: 'Leap Day 2024',
            gradientColors: const [],
          ),
          PhotoEntry(
            date: DateTime(2024, 2, 28),
            title: 'Feb 28 2024',
            gradientColors: const [],
          ),
        ],
      );
      expect(memoriesFeb28.length, 1);
      expect(memoriesFeb28.first.title, 'Feb 28 2024');

      // 2. If targetDate is Feb 29, 2028: Feb 29, 2024 MATCHES, Feb 28, 2024 DOES NOT
      final targetFeb29 = DateTime(2028, 2, 29);
      final memoriesFeb29 = MemoryService.instance.getMemoriesForDate(
        targetFeb29,
        sourceEntries: [
          PhotoEntry(
            date: DateTime(2024, 2, 29),
            title: 'Leap Day 2024',
            gradientColors: const [],
          ),
          PhotoEntry(
            date: DateTime(2024, 2, 28),
            title: 'Feb 28 2024',
            gradientColors: const [],
          ),
        ],
      );
      expect(memoriesFeb29.length, 1);
      expect(memoriesFeb29.first.title, 'Leap Day 2024');
    });

    testWidgets('9. Tapping a memory opens existing PhotoDetailScreen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final targetDate = DateTime(2026, 3, 28);
      await addSamplePhoto(
        dateKey: const DateKey(2025, 3, 28),
        title: 'Detail Navigation Memory',
      );

      await tester.pumpWidget(createTestWidget(targetDate: targetDate));
      await tester.pumpAndSettle();

      final detailsButton = find.text('View Details');
      expect(detailsButton, findsOneWidget);

      await tester.tap(detailsButton);
      await tester.pumpAndSettle();

      // Verify PhotoDetailScreen was opened
      expect(find.byType(PhotoDetailScreen), findsOneWidget);
      expect(find.text('Detail Navigation Memory'), findsWidgets);
    });

    testWidgets('10. Memory uses the original PhotoEntry/DateKey', (
      tester,
    ) async {
      final targetDate = DateTime(2026, 3, 28);
      final entry = await addSamplePhoto(
        dateKey: const DateKey(2024, 3, 28),
        title: 'Original DateKey Memory',
      );

      final memories = MemoryService.instance.getMemoriesForDate(
        targetDate,
        store: photoStore,
      );

      expect(memories.length, 1);
      expect(memories.first.dateKey, const DateKey(2024, 3, 28));
      expect(memories.first.date, entry.date);
      expect(memories.first.dateKey.year, 2024);
    });

    testWidgets('11. Metadata is displayed correctly', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final targetDate = DateTime(2026, 3, 28);
      await addSamplePhoto(
        dateKey: const DateKey(2025, 3, 28),
        title: 'Golden Sunset Hike',
        location: 'Bear Mountain Peak, NY',
      );

      await tester.pumpWidget(createTestWidget(targetDate: targetDate));
      await tester.pumpAndSettle();

      expect(find.text('Golden Sunset Hike'), findsOneWidget);
      expect(find.text('Bear Mountain Peak, NY'), findsOneWidget);
      expect(find.text('1 year ago'), findsOneWidget);
    });

    testWidgets('12. Missing/corrupt photo uses fallback artwork', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final targetDate = DateTime(2026, 3, 28);
      final entry = PhotoEntry(
        date: DateTime(2025, 3, 28),
        title: 'Corrupt File Memory',
        imagePath: '/invalid/path/missing.jpg',
        gradientColors: const [Colors.teal, Colors.cyan],
      );
      await metadataStorage.saveAll({entry.dateKey: entry});
      await photoStore.init();

      await tester.pumpWidget(createTestWidget(targetDate: targetDate));
      await tester.pumpAndSettle();

      expect(find.text('Corrupt File Memory'), findsOneWidget);
      // Fallback icon renders
      expect(find.byIcon(Icons.photo_camera_rounded), findsOneWidget);
    });

    testWidgets(
      '13. Deleting a memory source removes it from the memory list',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final targetDate = DateTime(2026, 3, 28);
        await addSamplePhoto(
          dateKey: const DateKey(2025, 3, 28),
          title: 'Memory To Delete',
        );

        await tester.pumpWidget(createTestWidget(targetDate: targetDate));
        await tester.pumpAndSettle();

        expect(find.text('Memory To Delete'), findsOneWidget);

        // Delete from store
        photoStore.removePhoto(const DateKey(2025, 3, 28).toDateTime());
        await tester.pumpAndSettle();

        // Disappears dynamically, rendering empty state
        expect(find.text('Memory To Delete'), findsNothing);
        expect(find.text('No memories from this day yet'), findsOneWidget);
      },
    );

    testWidgets('14. Replacing a memory source updates its displayed photo', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final targetDate = DateTime(2026, 3, 28);
      await addSamplePhoto(
        dateKey: const DateKey(2025, 3, 28),
        title: 'Initial Memory Title',
      );

      await tester.pumpWidget(createTestWidget(targetDate: targetDate));
      await tester.pumpAndSettle();

      expect(find.text('Initial Memory Title'), findsOneWidget);

      // Update metadata in store
      await photoStore.updatePhotoMetadata(
        dateKey: const DateKey(2025, 3, 28),
        title: 'Replaced Memory Title',
      );
      await tester.pumpAndSettle();

      expect(find.text('Replaced Memory Title'), findsOneWidget);
      expect(find.text('Initial Memory Title'), findsNothing);
    });

    testWidgets(
      '15. Memory presentation renders without obsolete cloud sync chips',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final targetDate = DateTime(2026, 3, 28);
        await addSamplePhoto(
          dateKey: const DateKey(2025, 3, 28),
          title: 'Memory Photo',
          syncStatus: SyncStatus.synced,
        );

        await tester.pumpWidget(createTestWidget(targetDate: targetDate));
        await tester.pumpAndSettle();

        expect(find.text('Memory Photo'), findsOneWidget);
        expect(find.text('Backed up'), findsNothing);
      },
    );

    testWidgets('16. No mock photos appear', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final targetDate = DateTime(2026, 3, 28);

      // Store is completely empty
      await tester.pumpWidget(createTestWidget(targetDate: targetDate));
      await tester.pumpAndSettle();

      // No mock titles, only graceful empty state
      expect(find.text('Morning Coffee Routine'), findsNothing);
      expect(find.text('Sunset Walk'), findsNothing);
      expect(find.text('No memories from this day yet'), findsOneWidget);
    });

    testWidgets(
      '17. Swipe viewer integration uses existing SwipeDaysScreen rather than another paging implementation',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final targetDate = DateTime(2026, 3, 28);
        await addSamplePhoto(
          dateKey: const DateKey(2025, 3, 28),
          title: 'Memory 2025',
        );
        await addSamplePhoto(
          dateKey: const DateKey(2024, 3, 28),
          title: 'Memory 2024',
        );

        await tester.pumpWidget(createTestWidget(targetDate: targetDate));
        await tester.pumpAndSettle();

        // Tap "Browse in Carousel" on memory card
        final browseCarouselBtn = find.text('Browse in Carousel').first;
        await tester.tap(browseCarouselBtn);
        await tester.pumpAndSettle();

        // Verifies the existing SwipeDaysScreen is pushed
        expect(find.byType(SwipeDaysScreen), findsOneWidget);
        expect(find.text('On This Day'), findsOneWidget);
        expect(find.byType(PageView), findsOneWidget);
      },
    );

    testWidgets('18. Current-day photo cannot appear as its own memory', (
      tester,
    ) async {
      final targetDate = DateTime(2026, 3, 28);

      // Only today's photo is in the store
      final memories = MemoryService.instance.getMemoriesForDate(
        targetDate,
        sourceEntries: [
          PhotoEntry(
            date: DateTime(2026, 3, 28),
            title: "Today's Photo",
            gradientColors: const [],
          ),
        ],
      );

      // Current-day photo must NEVER appear as its own memory
      expect(memories.isEmpty, isTrue);
    });
  });
}
