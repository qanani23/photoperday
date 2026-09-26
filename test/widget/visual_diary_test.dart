import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/core/routing/app_router.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/data/services/sync_queue.dart';
import 'package:photo_per_day/data/services/sync_queue_storage.dart';
import 'package:photo_per_day/screens/diary/visual_diary_screen.dart';
import 'package:photo_per_day/screens/home/home_screen.dart';
import 'package:photo_per_day/screens/photo_detail/photo_detail_screen.dart';
import 'package:photo_per_day/screens/profile/profile_screen.dart';
import 'package:photo_per_day/widgets/visual_diary_entry.dart';

import 'package:photo_per_day/data/models/sync_operation.dart';
import 'package:photo_per_day/data/models/sync_tombstone.dart';

class WidgetDiaryTestFakePhotoMetadataStorage extends PhotoMetadataStorage {
  WidgetDiaryTestFakePhotoMetadataStorage({super.customBaseDir});

  final Map<DateKey, PhotoEntry> _memory = {};
  final List<SyncTombstone> _deletions = [];

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
  Future<List<SyncTombstone>> loadPendingDeletions() async =>
      List.from(_deletions);

  @override
  Future<void> savePendingDeletions(List<SyncTombstone> deletions) async {
    _deletions.clear();
    _deletions.addAll(deletions);
  }

  @override
  Future<void> clear() async {
    _memory.clear();
    _deletions.clear();
  }
}

class WidgetDiaryTestFakePhotoFileManager extends PhotoFileManager {
  WidgetDiaryTestFakePhotoFileManager({super.customBaseDir});

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

  @override
  Future<List<String>> pruneUnreferencedPhotos(
    Set<String> referencedPaths,
  ) async => [];
}

class WidgetDiaryTestFakeSyncQueueStorage extends SyncQueueStorage {
  WidgetDiaryTestFakeSyncQueueStorage({super.customBaseDir});

  final List<SyncOperation> _ops = [];

  @override
  Future<void> init() async {}

  @override
  Future<List<SyncOperation>> loadQueue() async => List.from(_ops);

  @override
  Future<void> saveQueue(List<SyncOperation> operations) async {
    _ops.clear();
    _ops.addAll(operations);
  }

  @override
  Future<void> clear() async {
    _ops.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late WidgetDiaryTestFakePhotoFileManager fileManager;
  late WidgetDiaryTestFakePhotoMetadataStorage metadataStorage;
  late WidgetDiaryTestFakeSyncQueueStorage syncQueueStorage;
  late SyncQueue syncQueue;
  late PersistentDailyPhotoStore photoStore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('diary_widget_test_');
    fileManager = WidgetDiaryTestFakePhotoFileManager(customBaseDir: tempDir);
    metadataStorage = WidgetDiaryTestFakePhotoMetadataStorage(
      customBaseDir: tempDir,
    );
    syncQueueStorage = WidgetDiaryTestFakeSyncQueueStorage(
      customBaseDir: tempDir,
    );
    syncQueue = SyncQueue(storage: syncQueueStorage);
    await syncQueue.init();

    photoStore = PersistentDailyPhotoStore(
      fileManager: fileManager,
      metadataStorage: metadataStorage,
      syncQueue: syncQueue,
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

  const List<int> k1x1PngBytes = <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0A,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0x00,
    0x01,
    0x00,
    0x00,
    0x05,
    0x00,
    0x01,
    0x0D,
    0x0A,
    0x2D,
    0xB4,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ];

  File createDummyImage(String name) {
    final file = File('${tempDir.path}/$name.png');
    file.writeAsBytesSync(k1x1PngBytes);
    return file;
  }

  Future<PhotoEntry> addSamplePhoto({
    required DateKey dateKey,
    String title = 'Sample Title',
    String? caption,
    String? location,
    SyncStatus syncStatus = SyncStatus.localOnly,
    String? driveFileId,
  }) async {
    final imageFile = createDummyImage('img_${dateKey.format()}');
    final entry = PhotoEntry(
      date: dateKey.toDateTime(hour: 14, minute: 30),
      title: title,
      caption: caption,
      location: location,
      timeFormatted: '2:30 PM',
      imagePath: imageFile.path,
      syncStatus: syncStatus,
      driveFileId: driveFileId,
      gradientColors: const [Colors.amber, Colors.deepOrange],
    );
    return photoStore.savePhoto(entry: entry, sourceTempPath: imageFile.path);
  }

  Widget createTestWidget({Widget? child}) {
    return MaterialApp(
      onGenerateRoute: AppRouter.onGenerateRoute,
      home: child ?? VisualDiaryScreen(store: photoStore),
    );
  }

  group('Milestone 28 — Visual Diary Widget Tests', () {
    testWidgets('1. Empty diary state renders guidance and capture action', (
      tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Diary'), findsOneWidget);
      expect(find.text('Your Photo Journal'), findsOneWidget);
      expect(find.text("Capture Today's Photo"), findsOneWidget);
      expect(find.byType(VisualDiaryEntryCard), findsNothing);
    });

    testWidgets(
      '2. Displays persisted photos in chronological order (newest first)',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Add three photos out of order
        await addSamplePhoto(
          dateKey: const DateKey(2026, 3, 10),
          title: 'Older Photo 10th',
        );
        await addSamplePhoto(
          dateKey: const DateKey(2026, 3, 15),
          title: 'Newest Photo 15th',
        );
        await addSamplePhoto(
          dateKey: const DateKey(2026, 3, 12),
          title: 'Middle Photo 12th',
        );

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // All three cards must appear
        final cards = tester
            .widgetList<VisualDiaryEntryCard>(find.byType(VisualDiaryEntryCard))
            .toList();
        expect(cards.length, equals(3));

        // Invariant: Newest first
        expect(cards[0].entry.title, equals('Newest Photo 15th'));
        expect(cards[1].entry.title, equals('Middle Photo 12th'));
        expect(cards[2].entry.title, equals('Older Photo 10th'));

        // Check header count pill
        expect(find.text('3 entries'), findsOneWidget);
      },
    );

    testWidgets('3. Excludes future dates from the chronological journal', (
      tester,
    ) async {
      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 10),
        title: 'Valid Past Photo',
      );
      await addSamplePhoto(
        dateKey: const DateKey(2099, 12, 31),
        title: 'Future Phantom Photo',
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Only the valid past photo should be shown
      expect(find.text('Valid Past Photo'), findsOneWidget);
      expect(find.text('Future Phantom Photo'), findsNothing);
      expect(find.byType(VisualDiaryEntryCard), findsOneWidget);
      expect(find.text('1 entry'), findsOneWidget);
    });

    testWidgets(
      '4. Diary entry with no metadata still renders cleanly without empty sections',
      (tester) async {
        final imageFile = createDummyImage('clean_empty_meta');
        final entry = PhotoEntry(
          date: DateTime(2026, 3, 8, 11, 15),
          title: '',
          caption: null,
          location: null,
          timeFormatted: '11:15 AM',
          imagePath: imageFile.path,
          gradientColors: const [Colors.blue, Colors.purple],
        );
        await photoStore.savePhoto(
          entry: entry,
          sourceTempPath: imageFile.path,
        );

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(VisualDiaryEntryCard), findsOneWidget);
        expect(find.text('Sunday, March 8, 2026'), findsOneWidget);
        expect(find.text('11:15 AM'), findsOneWidget);
        // No placeholder text should be fabricated
        expect(find.text('No caption'), findsNothing);
        expect(find.text('No title'), findsNothing);
        expect(find.text('No location'), findsNothing);
      },
    );

    testWidgets(
      '5. Diary entry with title, multiline caption, and location displays gracefully',
      (tester) async {
        await addSamplePhoto(
          dateKey: const DateKey(2026, 3, 14),
          title: 'Sunset over Observatory',
          caption:
              'Golden light reflecting off the canyon hills as evening fell.',
          location: 'Griffith Observatory, Los Angeles',
        );

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Sunset over Observatory'), findsOneWidget);
        expect(
          find.text(
            'Golden light reflecting off the canyon hills as evening fell.',
          ),
          findsOneWidget,
        );
        expect(find.text('Griffith Observatory, Los Angeles'), findsOneWidget);
      },
    );

    testWidgets(
      '6. Sync status uses existing presentation mapping (localOnly, synced, pending, failed)',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // 1. Local only
        await addSamplePhoto(
          dateKey: const DateKey(2026, 3, 1),
          title: 'Local Photo',
          syncStatus: SyncStatus.localOnly,
        );
        // 2. Synced
        await addSamplePhoto(
          dateKey: const DateKey(2026, 3, 2),
          title: 'Synced Photo',
          syncStatus: SyncStatus.synced,
          driveFileId: 'drive_123',
        );
        // 3. Failed
        await addSamplePhoto(
          dateKey: const DateKey(2026, 3, 3),
          title: 'Failed Photo',
          syncStatus: SyncStatus.failed,
        );

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('On this device'), findsOneWidget);
        expect(find.text('Backed up'), findsOneWidget);
        expect(find.text('Backup failed'), findsOneWidget);
      },
    );

    testWidgets(
      '7. Missing or unavailable local image file renders fallback art without crash',
      (tester) async {
        final entry = PhotoEntry(
          date: DateTime(2026, 3, 7),
          title: 'Missing File Memory',
          imagePath: '/non/existent/path/lost_image.jpg',
          gradientColors: const [Colors.teal, Colors.indigo],
        );
        // Directly put into store metadata without writing file to disk
        await metadataStorage.saveAll({entry.dateKey: entry});
        await photoStore.init();

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Missing File Memory'), findsOneWidget);
        // Fallback icon renders inside entry card
        expect(find.byIcon(Icons.photo_camera_rounded), findsWidgets);
      },
    );

    testWidgets('8. Tapping diary entry opens existing PhotoDetailScreen', (
      tester,
    ) async {
      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 14),
        title: 'Inspectable Memory',
        caption: 'A moment to open and inspect.',
      );

      await tester.pumpWidget(
        const MaterialApp(
          initialRoute: AppConstants.diaryRoute,
          onGenerateRoute: AppRouter.onGenerateRoute,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(VisualDiaryScreen), findsOneWidget);
      expect(find.text('Inspectable Memory'), findsOneWidget);

      // Tap on the diary entry card
      await tester.tap(find.byType(VisualDiaryEntryCard));
      await tester.pumpAndSettle();

      // Invariant: Resolves through PhotoDetailScreen
      expect(find.byType(PhotoDetailScreen), findsOneWidget);
      expect(find.text('Photo Memory'), findsOneWidget);
    });

    testWidgets(
      '9. Dynamic updates: Metadata edits in store immediately reflect in Diary',
      (tester) async {
        const dateKey = DateKey(2026, 3, 12);
        await addSamplePhoto(
          dateKey: dateKey,
          title: 'Original Title',
          caption: 'Original Caption',
        );

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Original Title'), findsOneWidget);
        expect(find.text('Original Caption'), findsOneWidget);

        // Perform metadata edit on store
        await photoStore.updatePhotoMetadata(
          dateKey: dateKey,
          title: 'Refined Journal Title',
          caption: 'Refined prose narrative.',
        );
        await tester.pumpAndSettle();

        // Invariant: Live update reflected in UI
        expect(find.text('Refined Journal Title'), findsOneWidget);
        expect(find.text('Refined prose narrative.'), findsOneWidget);
        expect(find.text('Original Title'), findsNothing);
      },
    );

    testWidgets(
      '10. Dynamic updates: Deleted photo immediately disappears from Diary',
      (tester) async {
        final entry = await addSamplePhoto(
          dateKey: const DateKey(2026, 3, 11),
          title: 'Short Lived Memory',
        );

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Short Lived Memory'), findsOneWidget);
        expect(find.byType(VisualDiaryEntryCard), findsOneWidget);

        // Delete photo
        photoStore.removePhoto(entry.date);
        await tester.pumpAndSettle();

        // Invariant: Disappears and empty state is rendered
        expect(find.text('Short Lived Memory'), findsNothing);
        expect(find.byType(VisualDiaryEntryCard), findsNothing);
        expect(find.text('Your Photo Journal'), findsOneWidget);
      },
    );

    testWidgets(
      '11. Dynamic updates: Replaced photo reflects new content in Diary',
      (tester) async {
        const dateKey = DateKey(2026, 3, 9);
        await addSamplePhoto(dateKey: dateKey, title: 'Initial Shot');

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Initial Shot'), findsOneWidget);

        // Replace photo on same date
        final replacementImage = createDummyImage('replacement_shot');
        final replacement = PhotoEntry(
          date: dateKey.toDateTime(hour: 16, minute: 0),
          title: 'Upgraded Replacement Shot',
          imagePath: replacementImage.path,
          gradientColors: const [Colors.cyan, Colors.blue],
        );
        await photoStore.savePhoto(
          entry: replacement,
          sourceTempPath: replacementImage.path,
        );
        await tester.pumpAndSettle();

        expect(find.text('Upgraded Replacement Shot'), findsOneWidget);
        expect(find.text('Initial Shot'), findsNothing);
      },
    );

    testWidgets(
      '12. Navigation integration: HomeScreen header Diary > button opens VisualDiaryScreen',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            initialRoute: AppConstants.initialRoute,
            routes: {
              AppConstants.initialRoute: (_) => const HomeScreen(),
              AppConstants.diaryRoute: (_) =>
                  VisualDiaryScreen(store: photoStore),
            },
          ),
        );
        await tester.pumpAndSettle();

        // Find Diary > button in AppHeader
        final diaryButton = find.text('Diary >');
        expect(diaryButton, findsOneWidget);

        await tester.tap(diaryButton);
        await tester.pumpAndSettle();

        expect(find.byType(VisualDiaryScreen), findsOneWidget);
        expect(find.text('CHRONOLOGICAL PHOTO JOURNAL'), findsOneWidget);
      },
    );

    testWidgets(
      '13. Navigation integration: ProfileScreen Visual Diary tile opens VisualDiaryScreen',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            initialRoute: AppConstants.initialRoute,
            routes: {
              AppConstants.initialRoute: (_) =>
                  const Scaffold(body: ProfileScreen()),
              AppConstants.diaryRoute: (_) =>
                  VisualDiaryScreen(store: photoStore),
            },
          ),
        );
        await tester.pumpAndSettle();

        // Find Visual Diary tile in ProfileScreen
        final diaryTile = find.text('Visual Diary');
        expect(diaryTile, findsOneWidget);

        await tester.ensureVisible(diaryTile);
        await tester.pumpAndSettle();

        await tester.tap(diaryTile);
        await tester.pumpAndSettle();

        expect(find.byType(VisualDiaryScreen), findsOneWidget);
        expect(find.text('CHRONOLOGICAL PHOTO JOURNAL'), findsOneWidget);
      },
    );
  });
}
