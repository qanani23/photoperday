import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/day_entry.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/screens/calendar/full_calendar_screen.dart';
import 'package:photo_per_day/screens/home/home_screen.dart';
import 'package:photo_per_day/screens/photo_detail/photo_detail_screen.dart';
import 'package:photo_per_day/widgets/calendar_cell.dart';
import 'package:photo_per_day/widgets/calendar_grid.dart';

class _TestMetadataStorage extends PhotoMetadataStorage {
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

class _TestFileManager extends PhotoFileManager {
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
  late _TestMetadataStorage mockStorage;
  late _TestFileManager mockFileManager;
  late PersistentDailyPhotoStore testStore;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('m62_home_test_');
    mockStorage = _TestMetadataStorage();
    mockFileManager = _TestFileManager()..tempDir = tempDir;

    testStore = PersistentDailyPhotoStore(
      fileManager: mockFileManager,
      metadataStorage: mockStorage,
    );
    PersistentDailyPhotoStore.setTestInstance(testStore);
    await testStore.init();
  });

  tearDown(() async {
    PersistentDailyPhotoStore.resetTestInstance();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  PhotoEntry createSamplePhoto(
    DateTime date, {
    String id = '',
    String title = 'Sample Title',
    int order = 0,
  }) {
    final dateKey = DateKey.fromDateTime(date);
    final filePath = '${tempDir.path}/photo_${dateKey.format()}_$order.jpg';
    File(filePath).writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);

    return PhotoEntry(
      id: id.isNotEmpty ? id : 'photo_${dateKey.format()}_$order',
      date: date,
      title: title,
      timeFormatted: '10:30 AM',
      imagePath: filePath,
      order: order,
      gradientColors: const [Color(0xFFB86B35), Color(0xFF2B2823)],
    );
  }

  Widget buildHomeScreen({
    DateTime? initialDate,
    PersistentDailyPhotoStore? store,
    bool showFullCalendar = false,
  }) {
    return MaterialApp(
      home: HomeScreen(
        wrapWithScaffold: false,
        initialDate: initialDate ?? DateTime(2026, 10, 15),
        store: store ?? testStore,
        showFullCalendar: showFullCalendar,
      ),
      onGenerateRoute: (settings) {
        if (settings.name == AppConstants.photoDetailRoute) {
          final entry = settings.arguments as PhotoEntry;
          return MaterialPageRoute<void>(
            builder: (_) => PhotoDetailScreen(photoEntry: entry),
            settings: settings,
          );
        }
        if (settings.name == AppConstants.fullCalendarRoute) {
          return MaterialPageRoute<void>(
            builder: (_) => FullCalendarScreen(
              wrapWithScaffold: false,
              initialDate: initialDate ?? DateTime(2026, 10, 15),
              store: store ?? testStore,
            ),
            settings: settings,
          );
        }
        return null;
      },
    );
  }

  group('M62 — Redesign Home as Current-Month Photo Calendar + Memories Timeline', () {
    testWidgets(
      '1. Shows current local month and year automatically without month chevrons',
      (tester) async {
        final localDate = DateTime(2026, 10, 15);
        await tester.pumpWidget(buildHomeScreen(initialDate: localDate));
        await tester.pumpAndSettle();

        // 1. Current month header displays "October 2026" and "This Month"
        expect(find.text('October 2026'), findsOneWidget);
        expect(find.text('This Month'), findsOneWidget);

        // 2. Exactly ONE compact CalendarGrid exists for October 2026 (not 12 months)
        expect(find.byType(CalendarGrid), findsOneWidget);
        expect(
          find.byKey(const ValueKey('compact-grid-2026-10')),
          findsOneWidget,
        );

        // 3. No previous/next month navigation arrows on the compact Home calendar
        expect(find.byTooltip('Previous month'), findsNothing);
        expect(find.byTooltip('Next month'), findsNothing);
        expect(find.byTooltip('Previous year'), findsNothing);
        expect(find.byTooltip('Next year'), findsNothing);

        // 4. Compact 7-column calendar grid displays correct day count (31 days in October)
        // Check days 1 and 31 exist in the compact grid
        final grid = find.byKey(const ValueKey('compact-grid-2026-10'));
        expect(
          find.descendant(of: grid, matching: find.text('1')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: grid, matching: find.text('31')),
          findsOneWidget,
        );

        // 5. Sunday-first date alignment: Oct 1, 2026 is Thursday (weekday 4).
        // Leading offset = 4 blank cells.
        final calendarCells = tester
            .widgetList<CalendarCell>(
              find.descendant(of: grid, matching: find.byType(CalendarCell)),
            )
            .toList();
        expect(
          calendarCells
              .take(4)
              .every((c) => c.style == CalendarCellStyle.blank),
          isTrue,
        );
        expect(calendarCells[4].day, 1);
      },
    );

    testWidgets(
      '2. Calendar displays photo indicator & multi-photo badge on dates with photos',
      (tester) async {
        final oct5 = DateTime(2026, 10, 5);
        final oct10 = DateTime(2026, 10, 10);

        // Add 1 photo on Oct 5
        final photo1 = createSamplePhoto(oct5, id: 'p1', title: 'Single Photo');
        await testStore.addPhotoToDay(
          dateKey: DateKey.fromDateTime(oct5),
          photo: photo1,
        );

        // Add 3 photos on Oct 10
        for (int i = 0; i < 3; i++) {
          final p = createSamplePhoto(oct10, id: 'p10_$i', order: i);
          await testStore.addPhotoToDay(
            dateKey: DateKey.fromDateTime(oct10),
            photo: p,
          );
        }

        await tester.pumpWidget(
          buildHomeScreen(initialDate: DateTime(2026, 10, 15)),
        );
        await tester.pumpAndSettle();

        // Check CalendarCell for Oct 5: photo cell, photoCount = 1
        final oct5CellFinder = find.byKey(const ValueKey(DateKey(2026, 10, 5)));
        expect(oct5CellFinder, findsOneWidget);
        final oct5Cell = tester.widget<CalendarCell>(oct5CellFinder);
        expect(oct5Cell.style, CalendarCellStyle.photo);
        expect(oct5Cell.photoCount, 1);

        // Check CalendarCell for Oct 10: photo cell, photoCount = 3
        final oct10CellFinder = find.byKey(
          const ValueKey(DateKey(2026, 10, 10)),
        );
        expect(oct10CellFinder, findsOneWidget);
        final oct10Cell = tester.widget<CalendarCell>(oct10CellFinder);
        expect(oct10Cell.style, CalendarCellStyle.photo);
        expect(oct10Cell.photoCount, 3);
      },
    );

    testWidgets('3. Displays helpful empty state when no memories exist yet', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildHomeScreen(initialDate: DateTime(2026, 10, 15)),
      );
      await tester.pumpAndSettle();

      // Empty state is rendered
      expect(
        find.byKey(const ValueKey('home_memories_empty_state')),
        findsOneWidget,
      );
      expect(find.text('No Memories Yet'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home_empty_add_photo_button')),
        findsOneWidget,
      );
      expect(find.text('Add Your First Photo'), findsOneWidget);
    });

    testWidgets(
      '4. Populated timeline displays reverse-chronological order and groups photos by day',
      (tester) async {
        final oct2 = DateTime(2026, 10, 2);
        final oct8 = DateTime(2026, 10, 8);
        final oct12 = DateTime(2026, 10, 12);

        // Add photos on Oct 2, Oct 8 (2 photos), Oct 12
        await testStore.addPhotoToDay(
          dateKey: DateKey.fromDateTime(oct2),
          photo: createSamplePhoto(
            oct2,
            id: 'p_oct2',
            title: 'October 2 Photo',
          ),
        );
        await testStore.addPhotoToDay(
          dateKey: DateKey.fromDateTime(oct8),
          photo: createSamplePhoto(
            oct8,
            id: 'p_oct8_1',
            title: 'October 8 First',
          ),
        );
        await testStore.addPhotoToDay(
          dateKey: DateKey.fromDateTime(oct8),
          photo: createSamplePhoto(oct8, id: 'p_oct8_2', order: 1),
        );
        await testStore.addPhotoToDay(
          dateKey: DateKey.fromDateTime(oct12),
          photo: createSamplePhoto(
            oct12,
            id: 'p_oct12',
            title: 'October 12 Photo',
          ),
        );

        await tester.pumpWidget(
          buildHomeScreen(initialDate: DateTime(2026, 10, 15)),
        );
        await tester.pumpAndSettle();

        // Empty state must not be visible
        expect(
          find.byKey(const ValueKey('home_memories_empty_state')),
          findsNothing,
        );

        // Timeline cards must be present for Oct 12, Oct 8, Oct 2 (reverse chronological)
        final card12 = find.byKey(const ValueKey('timeline_day_2026-10-12'));
        final card8 = find.byKey(const ValueKey('timeline_day_2026-10-08'));
        final card2 = find.byKey(const ValueKey('timeline_day_2026-10-02'));

        expect(card12, findsOneWidget);
        expect(card8, findsOneWidget);
        expect(card2, findsOneWidget);

        // Verify order on screen: card12 y < card8 y < card2 y
        final y12 = tester.getTopLeft(card12).dy;
        final y8 = tester.getTopLeft(card8).dy;
        final y2 = tester.getTopLeft(card2).dy;
        expect(
          y12,
          lessThan(y8),
          reason: 'Newest day (Oct 12) must appear above Oct 8',
        );
        expect(
          y8,
          lessThan(y2),
          reason: 'Oct 8 must appear above oldest day (Oct 2)',
        );

        // Verify grouping: Oct 8 has 2 photos grouped in 1 card with "2 photos" badge
        expect(
          find.descendant(of: card8, matching: find.text('2 photos')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '5. Shared note preview on photo days and note-only day handling',
      (tester) async {
        final oct6 = DateTime(2026, 10, 6);
        final oct7 = DateTime(2026, 10, 7);

        // Oct 6: Photo + Shared Note
        await testStore.addPhotoToDay(
          dateKey: DateKey.fromDateTime(oct6),
          photo: createSamplePhoto(oct6, id: 'p_oct6', title: 'Scenic Lake'),
        );
        await testStore.updateDayNote(
          dateKey: DateKey.fromDateTime(oct6),
          note: 'Hiked up the trail at sunrise. Crisp cool autumn air!',
        );

        // Oct 7: Note-only day (no photos)
        await testStore.updateDayNote(
          dateKey: DateKey.fromDateTime(oct7),
          note: 'A quiet rainy afternoon reading by the fireplace.',
        );

        await tester.pumpWidget(
          buildHomeScreen(initialDate: DateTime(2026, 10, 15)),
        );
        await tester.pumpAndSettle();

        // 1. Photo day preview shows shared note
        final card6 = find.byKey(const ValueKey('timeline_day_2026-10-06'));
        expect(card6, findsOneWidget);
        expect(
          find.descendant(
            of: card6,
            matching: find.text(
              'Hiked up the trail at sunrise. Crisp cool autumn air!',
            ),
          ),
          findsOneWidget,
        );

        // 2. Note-only day renders clean reflection card
        final card7 = find.byKey(const ValueKey('timeline_day_2026-10-07'));
        expect(card7, findsOneWidget);
        expect(
          find.descendant(of: card7, matching: find.text('Daily Reflection')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: card7,
            matching: find.text(
              'A quiet rainy afternoon reading by the fireplace.',
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('6. Tapping a calendar cell with memories opens photo detail', (
      tester,
    ) async {
      final oct9 = DateTime(2026, 10, 9);
      await testStore.addPhotoToDay(
        dateKey: DateKey.fromDateTime(oct9),
        photo: createSamplePhoto(
          oct9,
          id: 'p_oct9',
          title: 'Golden Hour Sunset',
        ),
      );

      final oct14 = DateTime(2026, 10, 14);
      await testStore.updateDayNote(
        dateKey: DateKey.fromDateTime(oct14),
        note: 'Stargazing on a clear night.',
      );

      await tester.pumpWidget(
        buildHomeScreen(initialDate: DateTime(2026, 10, 15)),
      );
      await tester.pumpAndSettle();

      // 6a. Tap cell with photo
      final oct9Cell = find.byKey(const ValueKey(DateKey(2026, 10, 9)));
      expect(oct9Cell, findsOneWidget);

      await tester.tap(oct9Cell);
      await tester.pumpAndSettle();

      // Navigates to PhotoDetailScreen
      expect(find.byType(PhotoDetailScreen), findsOneWidget);
      expect(find.text('Golden Hour Sunset'), findsOneWidget);

      // Pop back to Home
      Navigator.pop(tester.element(find.byType(PhotoDetailScreen)));
      await tester.pumpAndSettle();

      // 6b. Tap cell with note-only memory
      final oct14Cell = find.byKey(const ValueKey(DateKey(2026, 10, 14)));
      expect(oct14Cell, findsOneWidget);

      await tester.tap(oct14Cell);
      await tester.pumpAndSettle();

      expect(find.byType(PhotoDetailScreen), findsOneWidget);
      expect(find.text('Daily Reflection'), findsOneWidget);
    });

    testWidgets('7. Tapping a timeline entry opens photo detail', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final oct11 = DateTime(2026, 10, 11);
      await testStore.addPhotoToDay(
        dateKey: DateKey.fromDateTime(oct11),
        photo: createSamplePhoto(
          oct11,
          id: 'p_oct11',
          title: 'Mountain Peak View',
        ),
      );

      final oct13 = DateTime(2026, 10, 13);
      await testStore.updateDayNote(
        dateKey: DateKey.fromDateTime(oct13),
        note: 'Walked through the forest trails.',
      );

      await tester.pumpWidget(
        buildHomeScreen(initialDate: DateTime(2026, 10, 15)),
      );
      await tester.pumpAndSettle();

      // 7a. Tap photo memory entry card
      final card11 = find.byKey(const ValueKey('timeline_day_2026-10-11'));
      expect(card11, findsOneWidget);

      await tester.tap(card11);
      await tester.pumpAndSettle();

      expect(find.byType(PhotoDetailScreen), findsOneWidget);
      expect(find.text('Mountain Peak View'), findsOneWidget);

      // Pop back to Home
      Navigator.pop(tester.element(find.byType(PhotoDetailScreen)));
      await tester.pumpAndSettle();

      // 7b. Tap note-only memory entry card
      final card13 = find.byKey(const ValueKey('timeline_day_2026-10-13'));
      expect(card13, findsOneWidget);

      await tester.tap(card13);
      await tester.pumpAndSettle();

      expect(find.byType(PhotoDetailScreen), findsOneWidget);
      expect(find.text('Daily Reflection'), findsOneWidget);
    });

    testWidgets(
      '8. "Full calendar" action opens the full calendar screen with year navigation',
      (tester) async {
        await tester.pumpWidget(
          buildHomeScreen(initialDate: DateTime(2026, 10, 15)),
        );
        await tester.pumpAndSettle();

        // Find "Full calendar" button on Home
        final fullCalendarBtn = find.byKey(
          const ValueKey('home_full_calendar_button'),
        );
        expect(fullCalendarBtn, findsOneWidget);

        await tester.tap(fullCalendarBtn);
        await tester.pumpAndSettle();

        // Navigates to FullCalendarScreen
        expect(find.byType(FullCalendarScreen), findsOneWidget);
        // FullCalendarScreen contains year navigation chevrons
        expect(find.byTooltip('Previous year'), findsOneWidget);
        expect(find.byTooltip('Next year'), findsOneWidget);
      },
    );

    testWidgets('9. Month boundaries and leap year handling', (tester) async {
      // Leap year: February 2028 has 29 days
      final leapFeb = DateTime(2028, 2, 10);
      await tester.pumpWidget(buildHomeScreen(initialDate: leapFeb));
      await tester.pumpAndSettle();

      expect(find.text('February 2028'), findsOneWidget);
      final leapGrid = find.byKey(const ValueKey('compact-grid-2028-2'));
      expect(leapGrid, findsOneWidget);
      expect(
        find.descendant(of: leapGrid, matching: find.text('29')),
        findsOneWidget,
      );

      // Non-leap year: February 2027 has 28 days (day 29 does not exist)
      final nonLeapFeb = DateTime(2027, 2, 10);
      await tester.pumpWidget(buildHomeScreen(initialDate: nonLeapFeb));
      await tester.pumpAndSettle();

      expect(find.text('February 2027'), findsOneWidget);
      final nonLeapGrid = find.byKey(const ValueKey('compact-grid-2027-2'));
      expect(nonLeapGrid, findsOneWidget);
      expect(
        find.descendant(of: nonLeapGrid, matching: find.text('28')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: nonLeapGrid, matching: find.text('29')),
        findsNothing,
      );
    });

    testWidgets(
      '10. Regression coverage: adding, deleting, and reordering photos updates Home cleanly',
      (tester) async {
        final date = DateTime(2026, 10, 4);
        final dateKey = DateKey.fromDateTime(date);

        // 1. Initial add
        final p1 = createSamplePhoto(
          date,
          id: 'p_reg_1',
          title: 'First Photo',
          order: 0,
        );
        await testStore.addPhotoToDay(dateKey: dateKey, photo: p1);

        await tester.pumpWidget(
          buildHomeScreen(initialDate: DateTime(2026, 10, 15)),
        );
        await tester.pumpAndSettle();

        final card = find.byKey(const ValueKey('timeline_day_2026-10-04'));
        expect(card, findsOneWidget);
        expect(
          find.descendant(of: card, matching: find.text('First Photo')),
          findsOneWidget,
        );

        // 2. Add second photo to same day
        final p2 = createSamplePhoto(
          date,
          id: 'p_reg_2',
          title: 'Second Photo',
          order: 1,
        );
        await testStore.addPhotoToDay(dateKey: dateKey, photo: p2);
        await tester.pumpAndSettle();

        expect(
          find.descendant(of: card, matching: find.text('2 photos')),
          findsOneWidget,
        );

        // 3. Reorder photos
        await testStore.reorderPhotos(
          dateKey: dateKey,
          orderedPhotoIds: ['p_reg_2', 'p_reg_1'],
        );
        await tester.pumpAndSettle();

        // Primary photo is now p2 ('Second Photo')
        expect(
          find.descendant(of: card, matching: find.text('Second Photo')),
          findsOneWidget,
        );

        // 4. Delete photo
        await testStore.removePhotoById(dateKey: dateKey, photoId: 'p_reg_2');
        await tester.pumpAndSettle();

        // Now only 1 photo remains
        expect(
          find.descendant(of: card, matching: find.text('2 photos')),
          findsNothing,
        );
        expect(
          find.descendant(of: card, matching: find.text('First Photo')),
          findsOneWidget,
        );

        // 5. Delete last photo
        await testStore.removePhotoById(dateKey: dateKey, photoId: 'p_reg_1');
        await tester.pumpAndSettle();

        // Card is removed from timeline; empty state reappears
        expect(
          find.byKey(const ValueKey('timeline_day_2026-10-04')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('home_memories_empty_state')),
          findsOneWidget,
        );
      },
    );
  });
}
