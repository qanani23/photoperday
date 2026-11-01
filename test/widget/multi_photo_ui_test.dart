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
import 'package:photo_per_day/screens/diary/swipe_days_screen.dart';
import 'package:photo_per_day/screens/photo_detail/photo_detail_screen.dart';
import 'package:photo_per_day/screens/today/today_screen.dart';
import 'package:photo_per_day/widgets/calendar_cell.dart';
import 'package:photo_per_day/widgets/day_preview_card.dart';

class M59FakeMetadataStorage extends PhotoMetadataStorage {
  M59FakeMetadataStorage();

  final Map<DateKey, DayEntry> _days = {};

  @override
  Future<void> init() async {}

  @override
  Future<bool> hasPersistedRecords() async => _days.isNotEmpty;

  @override
  Future<Map<DateKey, DayEntry>> loadDays() async => Map.from(_days);

  @override
  Future<void> saveDays(Map<DateKey, DayEntry> days) async {
    _days.clear();
    _days.addAll(days);
  }

  @override
  Future<Map<DateKey, PhotoEntry>> loadAll() async {
    final res = <DateKey, PhotoEntry>{};
    for (final e in _days.entries) {
      if (e.value.isNotEmpty) res[e.key] = e.value.primaryPhoto!;
    }
    return res;
  }

  @override
  Future<void> saveAll(Map<DateKey, PhotoEntry> entries) async {
    _days.clear();
    for (final e in entries.entries) {
      _days[e.key] = DayEntry.fromSinglePhoto(e.value);
    }
  }

  @override
  Future<void> clear() async {
    _days.clear();
  }
}

class M59FakeFileManager extends PhotoFileManager {
  M59FakeFileManager();

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

  late M59FakeMetadataStorage fakeStorage;
  late M59FakeFileManager fakeFileManager;
  late PersistentDailyPhotoStore store;

  setUp(() async {
    fakeStorage = M59FakeMetadataStorage();
    fakeFileManager = M59FakeFileManager();
    store = PersistentDailyPhotoStore(
      fileManager: fakeFileManager,
      metadataStorage: fakeStorage,
    );
    PersistentDailyPhotoStore.setTestInstance(store);
    await store.init();
  });

  tearDown(() {
    PersistentDailyPhotoStore.resetTestInstance();
  });

  PhotoEntry createSamplePhoto({
    required DateKey dateKey,
    required String id,
    int order = 0,
    String title = 'Sample Photo',
  }) {
    return PhotoEntry(
      id: id,
      date: dateKey.toDateTime(),
      title: title,
      timeFormatted: '10:00 AM',
      order: order,
      syncStatus: SyncStatus.localOnly,
      gradientColors: const [Colors.blue, Colors.purple],
    );
  }

  Widget createTestWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(body: child),
      routes: {
        AppConstants.photoDetailRoute: (ctx) {
          final arg = ModalRoute.of(ctx)!.settings.arguments as PhotoEntry;
          return PhotoDetailScreen(photoEntry: arg);
        },
      },
    );
  }

  group('M59: Multi-Photo UI Tests', () {
    testWidgets(
      '1. Day with multiple photos displays thumbnail strip and photo count in DayPreviewCard',
      (tester) async {
        const dateKey = DateKey(2026, 4, 10);
        final p1 = createSamplePhoto(
          dateKey: dateKey,
          id: 'p1',
          title: 'First Photo',
        );
        final p2 = createSamplePhoto(
          dateKey: dateKey,
          id: 'p2',
          title: 'Second Photo',
        );
        final p3 = createSamplePhoto(
          dateKey: dateKey,
          id: 'p3',
          title: 'Third Photo',
        );

        final dayEntry = DayEntry(
          dateKey: dateKey,
          photos: [p1, p2, p3],
          note: 'A delightful multi-photo day reflection.',
        );
        await fakeStorage.saveDays({dateKey: dayEntry});
        await store.init();

        await tester.pumpWidget(
          createTestWidget(
            DayPreviewCard(
              photoEntry: p1,
              dayEntry: store.getDay(dateKey),
              selectedDate: dateKey.toDateTime(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify photo count badge
        expect(find.text('3 photos'), findsOneWidget);

        // Verify note snippet is displayed
        expect(
          find.text('A delightful multi-photo day reflection.'),
          findsOneWidget,
        );

        // Verify thumbnail order indicators
        expect(find.text('1'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
      },
    );

    testWidgets(
      '2. Photo position indicators in SwipeDaysScreen and PhotoDetailScreen show correct index and total (2 of 3)',
      (tester) async {
        const dateKey = DateKey(2026, 4, 12);
        final p1 = createSamplePhoto(
          dateKey: dateKey,
          id: 'p1',
          title: 'Sunrise Walk',
        );
        final p2 = createSamplePhoto(
          dateKey: dateKey,
          id: 'p2',
          title: 'Afternoon Cafe',
        );
        final p3 = createSamplePhoto(
          dateKey: dateKey,
          id: 'p3',
          title: 'Stargazing Night',
        );

        final dayEntry = DayEntry(
          dateKey: dateKey,
          photos: [p1, p2, p3],
          note: 'Busy day outdoors',
        );
        await fakeStorage.saveDays({dateKey: dayEntry});
        await store.init();

        // Test PhotoDetailScreen for second photo (2 of 3)
        await tester.pumpWidget(
          createTestWidget(PhotoDetailScreen(photoEntry: p2)),
        );
        await tester.pumpAndSettle();

        expect(find.text('Photos on this day (2 of 3)'), findsOneWidget);
        expect(find.text('Busy day outdoors'), findsOneWidget);

        // Test SwipeDaysScreen
        await tester.pumpWidget(createTestWidget(const SwipeDaysScreen()));
        await tester.pumpAndSettle();

        // SwipeDaysScreen displays intra-day badge for multi-photo day
        expect(find.textContaining('of 3'), findsWidgets);
      },
    );

    testWidgets(
      '3. Adding a photo appends to day collection without replacing existing photos',
      (tester) async {
        const dateKey = DateKey(2026, 4, 15);
        final p1 = createSamplePhoto(
          dateKey: dateKey,
          id: 'photo_existing',
          title: 'Original Photo',
        );

        await store.addPhotoToDay(dateKey: dateKey, photo: p1);
        expect(store.getDay(dateKey)!.photoCount, 1);

        final p2 = createSamplePhoto(
          dateKey: dateKey,
          id: 'photo_second',
          title: 'Second Photo',
        );
        await store.addPhotoToDay(dateKey: dateKey, photo: p2);

        final day = store.getDay(dateKey)!;
        expect(day.photoCount, 2);
        expect(day.photos[0].id, 'photo_existing');
        expect(day.photos[1].id, 'photo_second');
      },
    );

    testWidgets('4. Deleting one photo preserves other photos and daily note', (
      tester,
    ) async {
      const dateKey = DateKey(2026, 4, 18);
      final p1 = createSamplePhoto(
        dateKey: dateKey,
        id: 'p1',
        title: 'Keep Me',
      );
      final p2 = createSamplePhoto(
        dateKey: dateKey,
        id: 'p2',
        title: 'Delete Me',
      );

      final day = DayEntry(
        dateKey: dateKey,
        photos: [p1, p2],
        note: 'Shared daily memories note',
      );
      await fakeStorage.saveDays({dateKey: day});
      await store.init();

      // Delete p2
      final updated = await store.removePhotoById(
        dateKey: dateKey,
        photoId: 'p2',
      );
      expect(updated, isNotNull);
      expect(updated!.photoCount, 1);
      expect(updated.photos.first.id, 'p1');
      expect(updated.photos.first.title, 'Keep Me');
      expect(updated.note, 'Shared daily memories note');
    });

    testWidgets(
      '5. Deleting last photo preserves note with preserveNoteOnlyDay: true',
      (tester) async {
        const dateKey = DateKey(2026, 4, 20);
        final p1 = createSamplePhoto(
          dateKey: dateKey,
          id: 'p_only',
          title: 'Sole Photo',
        );

        final day = DayEntry(
          dateKey: dateKey,
          photos: [p1],
          note: 'Important note to preserve',
        );
        await fakeStorage.saveDays({dateKey: day});
        await store.init();

        // Delete sole photo with preserveNoteOnlyDay = true
        final updated = await store.removePhotoById(
          dateKey: dateKey,
          photoId: 'p_only',
          preserveNoteOnlyDay: true,
        );

        expect(updated, isNotNull);
        expect(updated!.isNoteOnly, isTrue);
        expect(updated.photos.isEmpty, isTrue);
        expect(updated.note, 'Important note to preserve');

        // Verify store persists note-only day
        final retrieved = store.getDay(dateKey);
        expect(retrieved, isNotNull);
        expect(retrieved!.isNoteOnly, isTrue);
        expect(retrieved.note, 'Important note to preserve');
      },
    );

    testWidgets('6. Editing a note persists after reloading the day', (
      tester,
    ) async {
      const dateKey = DateKey(2026, 4, 22);
      final p1 = createSamplePhoto(dateKey: dateKey, id: 'p1');
      await store.addPhotoToDay(dateKey: dateKey, photo: p1);

      // Update note
      await store.updateDayNote(
        dateKey: dateKey,
        note: 'Updated day note via M59 UI',
      );

      // Verify in store
      expect(store.getDay(dateKey)!.note, 'Updated day note via M59 UI');

      // Re-initialize store from metadata storage to verify persistence
      final freshStore = PersistentDailyPhotoStore(
        fileManager: fakeFileManager,
        metadataStorage: fakeStorage,
      );
      await freshStore.init();

      expect(freshStore.getDay(dateKey)!.note, 'Updated day note via M59 UI');
    });

    testWidgets(
      '7. Reordering photos persists and displays in updated order after reload',
      (tester) async {
        const dateKey = DateKey(2026, 4, 25);
        final p1 = createSamplePhoto(dateKey: dateKey, id: 'p1', title: 'One');
        final p2 = createSamplePhoto(dateKey: dateKey, id: 'p2', title: 'Two');
        final p3 = createSamplePhoto(
          dateKey: dateKey,
          id: 'p3',
          title: 'Three',
        );

        await store.addPhotoToDay(dateKey: dateKey, photo: p1);
        await store.addPhotoToDay(dateKey: dateKey, photo: p2);
        await store.addPhotoToDay(dateKey: dateKey, photo: p3);

        // Reorder: Move 'Three' to front
        final reordered = await store.reorderPhotos(
          dateKey: dateKey,
          orderedPhotoIds: ['p3', 'p1', 'p2'],
        );

        expect(reordered.photos.map((p) => p.id).toList(), ['p3', 'p1', 'p2']);

        // Reload store to verify persistence
        final reloadedStore = PersistentDailyPhotoStore(
          fileManager: fakeFileManager,
          metadataStorage: fakeStorage,
        );
        await reloadedStore.init();

        final reloadedDay = reloadedStore.getDay(dateKey)!;
        expect(reloadedDay.photos.map((p) => p.id).toList(), [
          'p3',
          'p1',
          'p2',
        ]);
      },
    );

    testWidgets(
      '8. Calendar cell indicators and photo counts reflect the correct day',
      (tester) async {
        // Render cell with multiple photos (4 photos) and a note
        await tester.pumpWidget(
          createTestWidget(
            const CalendarCell(
              day: 28,
              style: CalendarCellStyle.photo,
              photoCount: 4,
              hasNote: true,
              isSelected: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify count text in badge
        expect(find.text('4'), findsOneWidget);

        // Verify note indicator tooltip/semantics
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                (w.properties.label?.contains('4 photos') ?? false) &&
                (w.properties.label?.contains('Daily note') ?? false),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '9. Empty days, note-only days, and legacy single-photo days behave safely',
      (tester) async {
        const emptyDateKey = DateKey(2026, 5, 1);
        const noteOnlyDateKey = DateKey(2026, 5, 2);
        const singlePhotoDateKey = DateKey(2026, 5, 3);

        // Note-only day
        await store.updateDayNote(
          dateKey: noteOnlyDateKey,
          note: 'Only notes today',
        );

        // Single photo day
        await store.addPhotoToDay(
          dateKey: singlePhotoDateKey,
          photo: createSamplePhoto(
            dateKey: singlePhotoDateKey,
            id: 'single_p',
            title: 'Single Legacy',
          ),
        );

        // Verify Empty day
        expect(store.getDay(emptyDateKey), isNull);

        // Verify Note-only day
        final noteOnlyDay = store.getDay(noteOnlyDateKey);
        expect(noteOnlyDay, isNotNull);
        expect(noteOnlyDay!.isNoteOnly, isTrue);
        expect(noteOnlyDay.hasPhotos, isFalse);
        expect(noteOnlyDay.note, 'Only notes today');

        // Verify Single photo day
        final singleDay = store.getDay(singlePhotoDateKey);
        expect(singleDay, isNotNull);
        expect(singleDay!.photoCount, 1);
        expect(singleDay.isNoteOnly, isFalse);

        // Test DayPreviewCard for note-only day
        await tester.pumpWidget(
          createTestWidget(
            DayPreviewCard(
              dayEntry: noteOnlyDay,
              selectedDate: noteOnlyDateKey.toDateTime(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Daily Note'), findsOneWidget);
        expect(find.text('Only notes today'), findsOneWidget);
      },
    );

    testWidgets(
      '10. TodayScreen reflects multi-photo collection, switcher, and daily note',
      (tester) async {
        final todayDate = DateTime(2026, 5, 10);
        final dateKey = DateKey.fromDateTime(todayDate);

        final p1 = createSamplePhoto(
          dateKey: dateKey,
          id: 't1',
          title: 'Morning Coffee',
        );
        final p2 = createSamplePhoto(
          dateKey: dateKey,
          id: 't2',
          title: 'Evening Walk',
        );

        final day = DayEntry(
          dateKey: dateKey,
          photos: [p1, p2],
          note: 'Today reflection note',
        );
        await fakeStorage.saveDays({dateKey: day});
        await store.init();

        await tester.pumpWidget(
          createTestWidget(TodayScreen(todayDate: todayDate, store: store)),
        );
        await tester.pumpAndSettle();

        // Check header/badge shows "1 of 2"
        expect(find.text('1 of 2'), findsOneWidget);

        // Check thumbnail strip has items 1 and 2
        expect(find.text('1'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);

        // Check daily reflection note is rendered
        expect(find.text('Today reflection note'), findsOneWidget);
        expect(find.text('Add Photo'), findsOneWidget);
        expect(find.text('Replace Photo'), findsOneWidget);
      },
    );
  });
}
