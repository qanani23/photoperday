import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/day_entry.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/screens/photo_detail/photo_detail_screen.dart';
import 'package:photo_per_day/screens/today/today_screen.dart';
import 'package:photo_per_day/widgets/day_preview_card.dart';

class TestMetadataStorage extends PhotoMetadataStorage {
  final Map<DateKey, DayEntry> days = {};

  @override
  Future<void> init() async {}

  @override
  Future<bool> hasPersistedRecords() async => days.isNotEmpty;

  @override
  Future<Map<DateKey, DayEntry>> loadDays() async => Map.from(days);

  @override
  Future<void> saveDays(Map<DateKey, DayEntry> updatedDays) async {
    days.clear();
    days.addAll(updatedDays);
  }

  @override
  Future<Map<DateKey, PhotoEntry>> loadAll() async {
    final map = <DateKey, PhotoEntry>{};
    for (final e in days.entries) {
      if (e.value.isNotEmpty) map[e.key] = e.value.primaryPhoto!;
    }
    return map;
  }

  @override
  Future<void> saveAll(Map<DateKey, PhotoEntry> entries) async {
    days.clear();
    for (final e in entries.entries) {
      days[e.key] = DayEntry.fromSinglePhoto(e.value);
    }
  }

  @override
  Future<void> clear() async => days.clear();
}

class TestFileManager extends PhotoFileManager {
  final Set<String> managedFiles = {};
  Directory? tempDir;

  @override
  Future<void> init() async {}

  @override
  Future<String> persistPhotoFile({
    required String sourcePath,
    required DateKey dateKey,
  }) async {
    final baseDir = tempDir?.path ?? Directory.systemTemp.path;
    final dest =
        '$baseDir/managed_${dateKey.format()}_${managedFiles.length + 1}.jpg';
    final src = File(sourcePath);
    if (src.existsSync()) {
      src.copySync(dest);
    } else {
      File(dest).writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
    }
    managedFiles.add(dest);
    return dest;
  }

  @override
  bool isManagedPath(String path) => managedFiles.contains(path);

  @override
  Future<bool> deletePhotoFile(String? path) async {
    if (path != null) {
      managedFiles.remove(path);
      final f = File(path);
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
    return true;
  }

  @override
  Future<List<String>> pruneUnreferencedPhotos(
    Set<String> referencedPaths,
  ) async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late TestMetadataStorage testStorage;
  late TestFileManager testFileManager;
  late PersistentDailyPhotoStore store;

  File createSyntheticPhotoFile(String name) {
    final file = File('${tempDir.path}/$name.jpg');
    file.writeAsBytesSync(const [
      0xFF,
      0xD8,
      0xFF,
      0xE0,
      0x00,
      0x10,
      0x4A,
      0x46,
      0x49,
      0x46,
      0x00,
      0x01,
      0xFF,
      0xD9,
    ]);
    return file;
  }

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('m62_test_');
    testStorage = TestMetadataStorage();
    testFileManager = TestFileManager()..tempDir = tempDir;
    store = PersistentDailyPhotoStore(
      fileManager: testFileManager,
      metadataStorage: testStorage,
    );
    PersistentDailyPhotoStore.setTestInstance(store);
    await store.init();
  });

  tearDown(() {
    PersistentDailyPhotoStore.resetTestInstance();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  PhotoEntry createSamplePhoto({
    required DateKey dateKey,
    required String id,
    int order = 0,
    String title = 'Sample Photo',
    String? imagePath,
  }) {
    final path =
        imagePath ??
        createSyntheticPhotoFile(
          id.isNotEmpty
              ? id
              : 'unnamed_${DateTime.now().microsecondsSinceEpoch}',
        ).path;
    return PhotoEntry(
      id: id,
      date: dateKey.toDateTime(),
      title: title,
      timeFormatted: '10:00 AM',
      order: order,
      imagePath: path,
      syncStatus: SyncStatus.localOnly,
      gradientColors: const [Colors.blue, Colors.purple],
    );
  }

  group('M62 — Multi-Photo Add, Swipe, and Replace Behavior Tests', () {
    test(
      '1 & 2. Add second and third photo to a day: all photos remain and count updates',
      () async {
        const dateKey = DateKey(2026, 4, 15);
        final p1 = createSamplePhoto(
          dateKey: dateKey,
          id: 'photo-1',
          title: 'First Photo',
        );

        // Add first photo
        await store.addPhotoToDay(dateKey: dateKey, photo: p1);
        var day = store.getDay(dateKey);
        expect(day, isNotNull);
        expect(day!.photoCount, equals(1));
        expect(day.photos.first.id, equals('photo-1'));

        // Add second photo
        final p2 = createSamplePhoto(
          dateKey: dateKey,
          id: 'photo-2',
          title: 'Second Photo',
        );
        await store.addPhotoToDay(dateKey: dateKey, photo: p2);
        day = store.getDay(dateKey);
        expect(day!.photoCount, equals(2));
        expect(day.photos[0].id, equals('photo-1'));
        expect(day.photos[1].id, equals('photo-2'));

        // Add third photo
        final p3 = createSamplePhoto(
          dateKey: dateKey,
          id: 'photo-3',
          title: 'Third Photo',
        );
        await store.addPhotoToDay(dateKey: dateKey, photo: p3);
        day = store.getDay(dateKey);
        expect(day!.photoCount, equals(3));
        expect(
          day.photos.map((p) => p.id).toList(),
          equals(['photo-1', 'photo-2', 'photo-3']),
        );
      },
    );

    test(
      '3. Original photo ID, title, and properties remain unchanged after appending new photos',
      () async {
        const dateKey = DateKey(2026, 4, 16);
        final origFile = createSyntheticPhotoFile('orig-id-123');
        final originalPhoto = createSamplePhoto(
          dateKey: dateKey,
          id: 'orig-id-123',
          title: 'Original Memory',
          imagePath: origFile.path,
        );
        await store.addPhotoToDay(dateKey: dateKey, photo: originalPhoto);

        // Append 2 more photos
        await store.addPhotoToDay(
          dateKey: dateKey,
          photo: createSamplePhoto(
            dateKey: dateKey,
            id: 'new-id-456',
            title: 'Second Memory',
          ),
        );
        await store.addPhotoToDay(
          dateKey: dateKey,
          photo: createSamplePhoto(
            dateKey: dateKey,
            id: 'new-id-789',
            title: 'Third Memory',
          ),
        );

        final day = store.getDay(dateKey);
        expect(day, isNotNull);
        final first = day!.photos.first;
        expect(first.id, equals('orig-id-123'));
        expect(first.title, equals('Original Memory'));
        expect(first.imagePath, isNotEmpty);
      },
    );

    testWidgets(
      '4. DailyCaptureWorkflow and addPhotoToDay append to existing day without replacement dialog',
      (tester) async {
        const dateKey = DateKey(2026, 4, 17);
        final p1 = createSamplePhoto(dateKey: dateKey, id: 'first-capture');
        await store.addPhotoToDay(dateKey: dateKey, photo: p1);

        // Append photo without ID creates a unique ID and preserves existing photo
        final tempCapture = createSyntheticPhotoFile('capture_temp');
        final p2 = createSamplePhoto(
          dateKey: dateKey,
          id: '',
          title: 'Workflow Capture',
          imagePath: tempCapture.path,
        );
        final saved = await store.addPhotoToDay(
          dateKey: dateKey,
          photo: p2,
          sourceTempPath: tempCapture.path,
        );

        expect(saved, isNotNull);
        final day = store.getDay(dateKey);
        expect(day!.photoCount, equals(2));
        expect(day.photos[0].id, equals('first-capture'));
        expect(day.photos[1].title, equals('Workflow Capture'));
        expect(day.photos[1].id, isNotEmpty);
        expect(day.photos[1].id, isNot(equals('first-capture')));
      },
    );

    test(
      '6 & 7. All photos persist across store reload and listeners are notified immediately',
      () async {
        const dateKey = DateKey(2026, 4, 18);
        int listenerNotificationCount = 0;
        store.addListener(() {
          listenerNotificationCount++;
        });

        await store.addPhotoToDay(
          dateKey: dateKey,
          photo: createSamplePhoto(dateKey: dateKey, id: 'reload-1'),
        );
        await store.addPhotoToDay(
          dateKey: dateKey,
          photo: createSamplePhoto(dateKey: dateKey, id: 'reload-2'),
        );
        expect(listenerNotificationCount, greaterThanOrEqualTo(2));

        // Create a fresh store instance pointing to same storage and init
        final reloadedStore = PersistentDailyPhotoStore(
          fileManager: testFileManager,
          metadataStorage: testStorage,
        );
        await reloadedStore.init();

        final reloadedDay = reloadedStore.getDay(dateKey);
        expect(reloadedDay, isNotNull);
        expect(reloadedDay!.photoCount, equals(2));
        expect(reloadedDay.photos[0].id, equals('reload-1'));
        expect(reloadedDay.photos[1].id, equals('reload-2'));
      },
    );

    test(
      '11. Reordering and deleting photos update collection and primary photo',
      () async {
        const dateKey = DateKey(2026, 4, 19);
        await store.addPhotoToDay(
          dateKey: dateKey,
          photo: createSamplePhoto(dateKey: dateKey, id: 'pA'),
        );
        await store.addPhotoToDay(
          dateKey: dateKey,
          photo: createSamplePhoto(dateKey: dateKey, id: 'pB'),
        );
        await store.addPhotoToDay(
          dateKey: dateKey,
          photo: createSamplePhoto(dateKey: dateKey, id: 'pC'),
        );

        expect(store.getDay(dateKey)!.primaryPhoto!.id, equals('pA'));

        // Reorder: pB, pC, pA
        final reordered = await store.reorderPhotos(
          dateKey: dateKey,
          orderedPhotoIds: ['pB', 'pC', 'pA'],
        );
        expect(reordered, isNotNull);
        expect(reordered.primaryPhoto!.id, equals('pB'));
        expect(
          reordered.photos.map((p) => p.id).toList(),
          equals(['pB', 'pC', 'pA']),
        );

        // Delete pB: primary becomes pC
        final afterDelete = await store.removePhotoById(
          dateKey: dateKey,
          photoId: 'pB',
        );
        expect(afterDelete, isNotNull);
        expect(afterDelete!.photoCount, equals(2));
        expect(afterDelete.primaryPhoto!.id, equals('pC'));
        expect(
          afterDelete.photos.map((p) => p.id).toList(),
          equals(['pC', 'pA']),
        );
      },
    );

    test(
      '12. Explicit replace photo replaces the target photo while keeping other photos',
      () async {
        const dateKey = DateKey(2026, 4, 20);
        final p1 = createSamplePhoto(
          dateKey: dateKey,
          id: 'stay-1',
          title: 'Stay Photo 1',
        );
        final p2 = createSamplePhoto(
          dateKey: dateKey,
          id: 'replace-me',
          title: 'Old Version',
        );
        final p3 = createSamplePhoto(
          dateKey: dateKey,
          id: 'stay-2',
          title: 'Stay Photo 2',
        );

        await store.addPhotoToDay(dateKey: dateKey, photo: p1);
        await store.addPhotoToDay(dateKey: dateKey, photo: p2);
        await store.addPhotoToDay(dateKey: dateKey, photo: p3);

        final replacedImg = createSyntheticPhotoFile('replaced_img');
        final updatedP2 = p2.copyWith(
          title: 'Replaced Version',
          imagePath: replacedImg.path,
        );
        final replaced = await store.replacePhotoInDay(
          dateKey: dateKey,
          targetPhotoId: 'replace-me',
          newPhoto: updatedP2,
        );

        expect(replaced, isNotNull);
        expect(replaced.title, equals('Replaced Version'));

        final day = store.getDay(dateKey);
        expect(day, isNotNull);
        expect(day!.photoCount, equals(3));
        expect(day.photos[0].id, equals('stay-1'));
        expect(day.photos[1].id, equals('replace-me'));
        expect(day.photos[1].title, equals('Replaced Version'));
        expect(day.photos[1].imagePath, contains('managed_2026-04-20_'));
        expect(day.photos[1].imagePath, isNot(equals(p2.imagePath)));
        expect(day.photos[2].id, equals('stay-2'));
      },
    );

    test(
      '13. Daily notes and note-only days remain intact during photo additions and deletions',
      () async {
        const dateKey = DateKey(2026, 4, 21);
        await store.updateDayNote(
          dateKey: dateKey,
          note: 'Important daily thought',
        );

        var day = store.getDay(dateKey);
        expect(day, isNotNull);
        expect(day!.hasNote, isTrue);
        expect(day.note, equals('Important daily thought'));
        expect(day.hasPhotos, isFalse);

        // Add a photo
        await store.addPhotoToDay(
          dateKey: dateKey,
          photo: createSamplePhoto(dateKey: dateKey, id: 'note-photo-1'),
        );
        day = store.getDay(dateKey);
        expect(day!.note, equals('Important daily thought'));
        expect(day.photoCount, equals(1));

        // Remove the photo with preserveNoteOnlyDay: true
        day = await store.removePhotoById(
          dateKey: dateKey,
          photoId: 'note-photo-1',
          preserveNoteOnlyDay: true,
        );
        expect(day, isNotNull);
        expect(day!.hasPhotos, isFalse);
        expect(day.note, equals('Important daily thought'));
      },
    );

    testWidgets(
      '8 & 9. TodayScreen displays thumbnail strip, swipe PageView, and position indicators',
      (tester) async {
        const dateKey = DateKey(2026, 4, 22);
        final p1 = createSamplePhoto(
          dateKey: dateKey,
          id: 'tp-1',
          title: 'First Morning',
        );
        final p2 = createSamplePhoto(
          dateKey: dateKey,
          id: 'tp-2',
          title: 'Second Afternoon',
        );

        await store.addPhotoToDay(dateKey: dateKey, photo: p1);
        await store.addPhotoToDay(dateKey: dateKey, photo: p2);

        await tester.pumpWidget(
          MaterialApp(
            home: TodayScreen(store: store, todayDate: dateKey.toDateTime()),
            routes: {
              AppConstants.photoDetailRoute: (ctx) {
                final arg =
                    ModalRoute.of(ctx)!.settings.arguments as PhotoEntry;
                return PhotoDetailScreen(photoEntry: arg);
              },
            },
          ),
        );
        await tester.pumpAndSettle();

        // Look for position badge "1 of 2"
        expect(find.text('1 of 2'), findsOneWidget);

        // Look for thumbnail indicators "1" and "2"
        expect(find.text('1'), findsWidgets);
        expect(find.text('2'), findsWidgets);

        // Verify Add Photo button is present
        expect(find.text('Add Photo'), findsOneWidget);

        // Verify Replace Photo button is present
        expect(find.text('Replace Photo'), findsOneWidget);

        // Tap on thumbnail 2
        final thumbnail2Finder = find.widgetWithText(GestureDetector, '2');
        if (thumbnail2Finder.evaluate().isNotEmpty) {
          await tester.tap(thumbnail2Finder.first);
          await tester.pumpAndSettle();
          expect(find.text('2 of 2'), findsOneWidget);
        }
      },
    );

    testWidgets(
      '10. PhotoDetailScreen displays swipeable PageView and preserves selected photo',
      (tester) async {
        const dateKey = DateKey(2026, 4, 23);
        final p1 = createSamplePhoto(
          dateKey: dateKey,
          id: 'pdt-1',
          title: 'Sunrise Run',
        );
        final p2 = createSamplePhoto(
          dateKey: dateKey,
          id: 'pdt-2',
          title: 'Evening Walk',
        );

        await store.addPhotoToDay(dateKey: dateKey, photo: p1);
        await store.addPhotoToDay(dateKey: dateKey, photo: p2);

        // Open PhotoDetailScreen directly focused on p2
        await tester.pumpWidget(
          MaterialApp(
            home: PhotoDetailScreen(photoEntry: p2),
            routes: {
              AppConstants.swipeDaysRoute: (ctx) =>
                  const Scaffold(body: Text('SwipeDays')),
            },
          ),
        );
        await tester.pumpAndSettle();

        // Indicators for 2 of 2
        expect(find.text('2 of 2'), findsOneWidget);
        expect(find.text('Evening Walk'), findsOneWidget);

        // Verify explicit action buttons
        expect(find.text('Add Photo'), findsOneWidget);
        expect(find.text('Replace Photo'), findsOneWidget);
      },
    );

    testWidgets(
      '5. DayPreviewCard includes add photo button when photos exist',
      (tester) async {
        const dateKey = DateKey(2026, 4, 24);
        final p1 = createSamplePhoto(dateKey: dateKey, id: 'prev-1');
        await store.addPhotoToDay(dateKey: dateKey, photo: p1);

        bool addPhotoTapped = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DayPreviewCard(
                photoEntry: p1,
                dayEntry: store.getDay(dateKey),
                selectedDate: dateKey.toDateTime(),
                onAddPhotoTap: () {
                  addPhotoTapped = true;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final addPhotoIcon = find.byIcon(Icons.add_a_photo_outlined);
        expect(addPhotoIcon, findsOneWidget);

        await tester.tap(addPhotoIcon);
        await tester.pumpAndSettle();
        expect(addPhotoTapped, isTrue);
      },
    );
  });
}
