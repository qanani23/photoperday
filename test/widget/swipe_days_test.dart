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
import 'package:photo_per_day/screens/diary/swipe_days_screen.dart';
import 'package:photo_per_day/screens/photo_detail/photo_detail_screen.dart';

class WidgetSwipeTestFakePhotoMetadataStorage extends PhotoMetadataStorage {
  WidgetSwipeTestFakePhotoMetadataStorage({super.customBaseDir});

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

class WidgetSwipeTestFakePhotoFileManager extends PhotoFileManager {
  WidgetSwipeTestFakePhotoFileManager({super.customBaseDir});

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late WidgetSwipeTestFakePhotoFileManager fileManager;
  late WidgetSwipeTestFakePhotoMetadataStorage metadataStorage;
  late PersistentDailyPhotoStore photoStore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('swipe_widget_test_');
    fileManager = WidgetSwipeTestFakePhotoFileManager(customBaseDir: tempDir);
    metadataStorage = WidgetSwipeTestFakePhotoMetadataStorage(
      customBaseDir: tempDir,
    );

    photoStore = PersistentDailyPhotoStore(
      fileManager: fileManager,
      metadataStorage: metadataStorage,
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
    String title = 'Sample Memory',
    String? location,
    SyncStatus syncStatus = SyncStatus.localOnly,
    String? driveFileId,
  }) async {
    final imageFile = createDummyImage('img_${dateKey.format()}');
    final entry = PhotoEntry(
      date: dateKey.toDateTime(hour: 14, minute: 30),
      title: title,
      location: location,
      timeFormatted: '2:30 PM',
      imagePath: imageFile.path,
      syncStatus: syncStatus,
      driveFileId: driveFileId,
      gradientColors: const [Colors.amber, Colors.deepOrange],
    );
    return photoStore.savePhoto(entry: entry, sourceTempPath: imageFile.path);
  }

  Widget createTestWidget({DateKey? initialDateKey, Widget? child}) {
    return MaterialApp(
      onGenerateRoute: AppRouter.onGenerateRoute,
      home:
          child ??
          SwipeDaysScreen(store: photoStore, initialDateKey: initialDateKey),
    );
  }

  group('Milestone 29 — Swipe Through Days Widget Tests', () {
    testWidgets('1. Viewer loads persisted photos only (no mocks)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 10),
        title: 'Only Real Persisted Photo',
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Only Real Persisted Photo'), findsOneWidget);
      expect(find.text('1 of 1 recorded days'), findsOneWidget);
      // Ensure mock photos like "Morning Roast" do not appear
      expect(find.text('Morning Roast'), findsNothing);
    });

    testWidgets(
      '2. Photos are ordered deterministically by DateKey (oldest to newest)',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Insert out of chronological order
        await addSamplePhoto(
          dateKey: const DateKey(2026, 3, 20),
          title: 'Newest March 20',
        );
        await addSamplePhoto(
          dateKey: const DateKey(2026, 3, 10),
          title: 'Oldest March 10',
        );
        await addSamplePhoto(
          dateKey: const DateKey(2026, 3, 15),
          title: 'Middle March 15',
        );

        // Start explicitly at oldest (March 10)
        await tester.pumpWidget(
          createTestWidget(initialDateKey: const DateKey(2026, 3, 10)),
        );
        await tester.pumpAndSettle();

        // Page 0 should be the oldest photo
        expect(find.text('Oldest March 10'), findsOneWidget);
        expect(find.text('1 of 3'), findsOneWidget);

        // Move to page 1 (middle)
        await tester.tap(find.text('Newer'));
        await tester.pumpAndSettle();
        expect(find.text('Middle March 15'), findsOneWidget);
        expect(find.text('2 of 3'), findsOneWidget);

        // Move to page 2 (newest)
        await tester.tap(find.text('Newer'));
        await tester.pumpAndSettle();
        expect(find.text('Newest March 20'), findsOneWidget);
        expect(find.text('3 of 3'), findsOneWidget);
      },
    );

    testWidgets('3. Future dates are excluded from the swipe viewer', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

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

      expect(find.text('Valid Past Photo'), findsOneWidget);
      expect(find.text('Future Phantom Photo'), findsNothing);
      expect(find.text('1 of 1 recorded days'), findsOneWidget);
      expect(find.text('1 of 1'), findsOneWidget);
    });

    testWidgets(
      '4. Starting from a selected DateKey opens the correct page directly',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await addSamplePhoto(
          dateKey: const DateKey(2026, 3, 1),
          title: 'Photo 1st',
        );
        await addSamplePhoto(
          dateKey: const DateKey(2026, 3, 5),
          title: 'Target Photo 5th',
        );
        await addSamplePhoto(
          dateKey: const DateKey(2026, 3, 10),
          title: 'Photo 10th',
        );

        // Open specifically requesting March 5th
        await tester.pumpWidget(
          createTestWidget(initialDateKey: const DateKey(2026, 3, 5)),
        );
        await tester.pumpAndSettle();

        expect(find.text('Target Photo 5th'), findsOneWidget);
        expect(find.text('2 of 3'), findsOneWidget);
        expect(find.text('Photo 1st'), findsNothing);
        expect(find.text('Photo 10th'), findsNothing);
      },
    );

    testWidgets('5. Swipe/page navigation moves between recorded days', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 1),
        title: 'Day One',
      );
      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 2),
        title: 'Day Two',
      );

      await tester.pumpWidget(
        createTestWidget(initialDateKey: const DateKey(2026, 3, 1)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Day One'), findsOneWidget);

      // Swipe left gesture (drag right-to-left) to advance to newer day
      await tester.drag(find.byType(PageView), const Offset(-800.0, 0.0));
      await tester.pumpAndSettle();

      expect(find.text('Day Two'), findsOneWidget);

      // Swipe right gesture (drag left-to-right) to go back to older day
      await tester.drag(find.byType(PageView), const Offset(800.0, 0.0));
      await tester.pumpAndSettle();

      expect(find.text('Day One'), findsOneWidget);
    });

    testWidgets('6. Missing calendar dates do not create empty pages', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // User has only March 21, March 25, March 28
      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 21),
        title: 'March 21 Entry',
      );
      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 25),
        title: 'March 25 Entry',
      );
      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 28),
        title: 'March 28 Entry',
      );

      await tester.pumpWidget(
        createTestWidget(initialDateKey: const DateKey(2026, 3, 21)),
      );
      await tester.pumpAndSettle();

      // Total count is strictly 3 recorded days
      expect(find.text('1 of 3 recorded days'), findsOneWidget);

      // Advance to 2nd recorded day
      await tester.tap(find.text('Newer'));
      await tester.pumpAndSettle();
      expect(find.text('March 25 Entry'), findsOneWidget);

      // Advance to 3rd recorded day
      await tester.tap(find.text('Newer'));
      await tester.pumpAndSettle();
      expect(find.text('March 28 Entry'), findsOneWidget);

      // No intervening blank dates
      expect(find.text('March 22 Entry'), findsNothing);
      expect(find.text('March 26 Entry'), findsNothing);
    });

    testWidgets('7. Oldest-day boundary disables Older navigation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 1),
        title: 'Oldest Day',
      );
      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 2),
        title: 'Newer Day',
      );

      await tester.pumpWidget(
        createTestWidget(initialDateKey: const DateKey(2026, 3, 1)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Oldest Day'), findsOneWidget);

      // The "Older" button should be disabled
      final olderButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Older'),
      );
      expect(olderButton.onPressed, isNull);
    });

    testWidgets('8. Newest-day boundary disables Newer navigation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 1),
        title: 'Oldest Day',
      );
      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 2),
        title: 'Newest Day',
      );

      await tester.pumpWidget(
        createTestWidget(initialDateKey: const DateKey(2026, 3, 2)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Newest Day'), findsOneWidget);

      // The "Newer" button should be disabled
      final newerButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Newer'),
      );
      expect(newerButton.onPressed, isNull);
    });

    testWidgets('9. No circular wrapping occurs across boundaries', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 1),
        title: 'First Date',
      );
      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 2),
        title: 'Last Date',
      );

      await tester.pumpWidget(
        createTestWidget(initialDateKey: const DateKey(2026, 3, 2)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Last Date'), findsOneWidget);

      // Attempt to drag left past newest date
      await tester.drag(find.byType(PageView), const Offset(-500.0, 0.0));
      await tester.pumpAndSettle();

      // Remains strictly on Last Date without wrapping to First Date
      expect(find.text('Last Date'), findsOneWidget);
      expect(find.text('First Date'), findsNothing);
    });

    testWidgets('10. Metadata (title, location, time) is displayed correctly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 18),
        title: 'Spring Blossom Walk',
        location: 'Central Park Conservatory, NYC',
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Spring Blossom Walk'), findsOneWidget);
      expect(find.text('Central Park Conservatory, NYC'), findsOneWidget);
      expect(find.text('Wednesday, March 18, 2026'), findsOneWidget);
      expect(find.text('2:30 PM'), findsOneWidget);
    });

    testWidgets(
      '11. Metadata changes in store are dynamically reflected in viewer',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await addSamplePhoto(
          dateKey: const DateKey(2026, 3, 10),
          title: 'Initial Title',
        );

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Initial Title'), findsOneWidget);

        // Mutate metadata directly in store
        await photoStore.updatePhotoMetadata(
          dateKey: const DateKey(2026, 3, 10),
          title: 'Updated Title From Edit',
          location: 'New Location',
        );
        await tester.pumpAndSettle();

        // Viewer reflects changes live
        expect(find.text('Updated Title From Edit'), findsOneWidget);
        expect(find.text('New Location'), findsOneWidget);
        expect(find.text('Initial Title'), findsNothing);
      },
    );

    testWidgets('12. Photo replacement updates the displayed entry', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 12),
        title: 'Original Shot',
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Original Shot'), findsOneWidget);

      // Add second photo on same date
      final secondImage = createDummyImage('second_shot');
      final second = PhotoEntry(
        date: DateTime(2026, 3, 12, 17, 0),
        title: 'Second Awesome Sunset',
        timeFormatted: '5:00 PM',
        imagePath: secondImage.path,
        gradientColors: const [Colors.purple, Colors.pink],
      );
      await photoStore.savePhoto(
        entry: second,
        sourceTempPath: secondImage.path,
      );
      await tester.pumpAndSettle();

      expect(find.text('Original Shot'), findsOneWidget);
      final day = photoStore.getDay(const DateKey(2026, 3, 12))!;
      expect(day.photos.length, 2);
      expect(day.photos[1].title, 'Second Awesome Sunset');
    });

    testWidgets(
      '13. Deleted current photo is handled safely without dangling crash',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await addSamplePhoto(
          dateKey: const DateKey(2026, 3, 1),
          title: 'First Photo',
        );
        await addSamplePhoto(
          dateKey: const DateKey(2026, 3, 2),
          title: 'Photo To Delete',
        );
        await addSamplePhoto(
          dateKey: const DateKey(2026, 3, 3),
          title: 'Third Photo',
        );

        // Open on the photo to be deleted
        await tester.pumpWidget(
          createTestWidget(initialDateKey: const DateKey(2026, 3, 2)),
        );
        await tester.pumpAndSettle();

        expect(find.text('Photo To Delete'), findsOneWidget);
        expect(find.text('2 of 3'), findsOneWidget);

        // Delete the photo from the store
        photoStore.removePhoto(const DateKey(2026, 3, 2).toDateTime());
        await tester.pumpAndSettle();

        // Should safely transition to one of the remaining photos
        expect(find.text('Photo To Delete'), findsNothing);
        expect(find.text('2 of 2'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Text &&
                (w.data == 'Third Photo' || w.data == 'First Photo'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '14. Missing or corrupted photo file renders fallback artwork',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final entry = PhotoEntry(
          date: DateTime(2026, 3, 14),
          title: 'Corrupt File Memory',
          imagePath: '/invalid/path/missing_file.jpg',
          gradientColors: const [Colors.teal, Colors.cyan],
        );
        await metadataStorage.saveAll({entry.dateKey: entry});
        await photoStore.init();

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Corrupt File Memory'), findsOneWidget);
        // Fallback icon renders inside hero area
        expect(find.byIcon(Icons.photo_camera_rounded), findsOneWidget);
      },
    );

    testWidgets('15. Tapping View Details opens existing PhotoDetailScreen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 10),
        title: 'Memory To Inspect',
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final detailsButton = find.text('View Details');
      expect(detailsButton, findsOneWidget);

      await tester.tap(detailsButton);
      await tester.pumpAndSettle();

      // PhotoDetailScreen is displayed
      expect(find.byType(PhotoDetailScreen), findsOneWidget);
      expect(find.text('Photo Memory'), findsOneWidget);

      // Back returns to SwipeDaysScreen
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.byType(SwipeDaysScreen), findsOneWidget);
      expect(find.text('Memory To Inspect'), findsOneWidget);
    });

    testWidgets('16. Empty viewer state renders guidance and capture action', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('No Photos to Browse'), findsOneWidget);
      expect(find.text("Capture Today's Photo"), findsOneWidget);
      expect(find.byType(PageView), findsNothing);
    });

    testWidgets('17. Position indicator reflects actual recorded entries', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 1),
        title: 'Entry 1',
      );
      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 10),
        title: 'Entry 2',
      );
      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 20),
        title: 'Entry 3',
      );
      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 30),
        title: 'Entry 4',
      );

      await tester.pumpWidget(
        createTestWidget(initialDateKey: const DateKey(2026, 3, 20)),
      );
      await tester.pumpAndSettle();

      // Page 3 of 4 (0-indexed: 2)
      expect(find.text('3 of 4'), findsOneWidget);
      expect(find.text('3 of 4 recorded days'), findsOneWidget);
    });

    testWidgets('18. Recorded days navigate smoothly across entries', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Day 1
      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 1),
        title: 'First Memory',
      );
      // Day 2
      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 2),
        title: 'Second Memory',
      );
      // Day 3
      await addSamplePhoto(
        dateKey: const DateKey(2026, 3, 3),
        title: 'Third Memory',
      );

      // Start on page 1
      await tester.pumpWidget(
        createTestWidget(initialDateKey: const DateKey(2026, 3, 1)),
      );
      await tester.pumpAndSettle();
      expect(find.text('First Memory'), findsOneWidget);
      expect(find.text('Backed up'), findsNothing);

      // Move to page 2
      await tester.tap(find.text('Newer'));
      await tester.pumpAndSettle();
      expect(find.text('Second Memory'), findsOneWidget);

      // Move to page 3
      await tester.tap(find.text('Newer'));
      await tester.pumpAndSettle();
      expect(find.text('Third Memory'), findsOneWidget);
    });
  });
}
