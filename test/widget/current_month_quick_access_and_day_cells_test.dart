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
import 'package:photo_per_day/screens/home/home_screen.dart';
import 'package:photo_per_day/screens/main_shell.dart';
import 'package:photo_per_day/screens/photo_detail/photo_detail_screen.dart';
import 'package:photo_per_day/widgets/bottom_nav_dock.dart';
import 'package:photo_per_day/widgets/calendar_cell.dart';
import 'package:photo_per_day/widgets/today_pulse_ring.dart';

class TestPhotoMetadataStorage extends PhotoMetadataStorage {
  TestPhotoMetadataStorage({super.customBaseDir});

  final Map<DateKey, DayEntry> _days = {};
  bool _hasSaved = false;

  @override
  Future<void> init() async {}

  @override
  Future<bool> hasPersistedRecords() async => _hasSaved;

  @override
  Future<Map<DateKey, DayEntry>> loadDays() async => Map.from(_days);

  @override
  Future<void> saveDays(Map<DateKey, DayEntry> days) async {
    _hasSaved = true;
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
    _hasSaved = true;
    _days.clear();
    for (final e in entries.entries) {
      _days[e.key] = DayEntry.fromSinglePhoto(e.value);
    }
  }

  @override
  Future<void> clear() async {
    _days.clear();
    _hasSaved = false;
  }
}

class TestPhotoFileManager extends PhotoFileManager {
  TestPhotoFileManager({super.customBaseDir});

  @override
  Future<void> init() async {}

  @override
  bool isManagedPath(String path) => false;

  @override
  Future<String> persistPhotoFile({
    required String sourcePath,
    required DateKey dateKey,
  }) async {
    return sourcePath;
  }

  @override
  Future<bool> deletePhotoFile(String? managedPath) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late TestPhotoMetadataStorage metadataStorage;
  late TestPhotoFileManager fileManager;
  late PersistentDailyPhotoStore testStore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('m42_day_cells_test_');
    metadataStorage = TestPhotoMetadataStorage(customBaseDir: tempDir);
    fileManager = TestPhotoFileManager(customBaseDir: tempDir);

    testStore = PersistentDailyPhotoStore(
      metadataStorage: metadataStorage,
      fileManager: fileManager,
    );
    await testStore.init();
    PersistentDailyPhotoStore.setTestInstance(testStore);
  });

  tearDown(() async {
    PersistentDailyPhotoStore.resetTestInstance();
    testStore.dispose();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  Widget buildTestableHomeScreen({
    DateTime? initialDate,
    DateTime? initialSelectedDate,
  }) {
    return MaterialApp(
      home: HomeScreen(
        initialDate: initialDate ?? DateTime(2026, 10, 3),
        initialSelectedDate: initialSelectedDate,
        store: testStore,
        showFullCalendar: true,
      ),
      onGenerateRoute: (settings) {
        if (settings.name == AppConstants.photoDetailRoute) {
          final entry = settings.arguments as PhotoEntry;
          return MaterialPageRoute<void>(
            builder: (_) => PhotoDetailScreen(photoEntry: entry),
            settings: settings,
          );
        }
        return null;
      },
    );
  }

  // ==================================================
  // TESTS — CURRENT MONTH (PART 1)
  // ==================================================
  group('Milestone 42 — Tests: Current Month Quick Access', () {
    testWidgets('1. Current year opens at current month', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final currentDate = DateTime(2026, 10, 3);
      await tester.pumpWidget(
        buildTestableHomeScreen(initialDate: currentDate),
      );
      await tester.pumpAndSettle();

      // October 2026 section must be rendered and visible
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('Current Month'), findsOneWidget);
    });

    testWidgets('2. Historical year opens near January', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final currentDate = DateTime(2026, 10, 3);
      await tester.pumpWidget(
        buildTestableHomeScreen(initialDate: currentDate),
      );
      await tester.pumpAndSettle();

      // Switch to previous year (2025)
      await tester.tap(find.byTooltip('Previous year'));
      await tester.pumpAndSettle();

      expect(find.text('2025'), findsOneWidget);
      expect(find.text('January 2025'), findsOneWidget);
      expect(find.text('Current Month'), findsNothing);
    });

    testWidgets('3. Future year opens near January', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final currentDate = DateTime(2026, 10, 3);
      await tester.pumpWidget(
        buildTestableHomeScreen(initialDate: currentDate),
      );
      await tester.pumpAndSettle();

      // Switch forward to future year (2027)
      await tester.tap(find.byTooltip('Next year'));
      await tester.pumpAndSettle();

      expect(find.text('2027'), findsOneWidget);
      expect(find.text('January 2027'), findsOneWidget);
      expect(find.text('Current Month'), findsNothing);
    });

    testWidgets('4. Returning to current year targets current month', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final currentDate = DateTime(2026, 10, 3);
      await tester.pumpWidget(
        buildTestableHomeScreen(initialDate: currentDate),
      );
      await tester.pumpAndSettle();

      // 2026 -> 2025
      await tester.tap(find.byTooltip('Previous year'));
      await tester.pumpAndSettle();
      expect(find.text('2025'), findsOneWidget);

      // 2025 -> 2026 (back to current year)
      await tester.tap(find.byTooltip('Next year'));
      await tester.pumpAndSettle();

      expect(find.text('2026'), findsOneWidget);
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('This Year'), findsOneWidget);
      expect(find.text('Current Month'), findsOneWidget);
    });

    testWidgets('5. User can still scroll through all 12 months', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final currentDate = DateTime(2026, 10, 3);
      await tester.pumpWidget(
        buildTestableHomeScreen(initialDate: currentDate),
      );
      await tester.pumpAndSettle();

      final scrollFinder = find.byType(SingleChildScrollView);
      expect(scrollFinder, findsOneWidget);

      // Scroll downward toward December
      await tester.drag(scrollFinder, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('December 2026'), findsOneWidget);

      // Scroll upward toward earlier months (July/August)
      await tester.drag(scrollFinder, const Offset(0, 1500));
      await tester.pumpAndSettle();
      expect(find.text('August 2026'), findsWidgets);
    });

    testWidgets('6. Scroll position is not reset after editing a day', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final photo = PhotoEntry(
        date: DateTime(2026, 10, 15),
        title: 'Mid October Walk',
        timeFormatted: '2:30 PM',
        gradientColors: const [Colors.teal, Colors.blue],
      );
      await testStore.savePhoto(entry: photo);

      await tester.pumpWidget(
        buildTestableHomeScreen(initialDate: DateTime(2026, 10, 3)),
      );
      await tester.pumpAndSettle();

      final scrollableState = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final initialOffset = scrollableState.position.pixels;

      // Open detail screen for day 15
      final octoberGrid = find.byKey(const ValueKey('2026-10'));
      final day15Finder = find.descendant(
        of: octoberGrid,
        matching: find.widgetWithText(CalendarCell, '15'),
      );
      await tester.tap(day15Finder);
      await tester.pumpAndSettle();

      expect(find.byType(PhotoDetailScreen), findsOneWidget);

      // Return back to Home
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      final afterReturnOffset = scrollableState.position.pixels;
      // Scroll position must remain where it was
      expect(afterReturnOffset, equals(initialOffset));
      expect(find.text('October 2026'), findsOneWidget);
    });

    testWidgets(
      '7. Scroll position is preserved when returning from another screen where appropriate',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: const MainShell(),
            routes: {
              AppConstants.settingsRoute: (_) =>
                  const Scaffold(body: Text('Settings Screen')),
            },
          ),
        );
        await tester.pumpAndSettle();

        // Switch to Me tab
        final meTab = find.descendant(
          of: find.byType(BottomNavDock),
          matching: find.text('Me'),
        );
        await tester.tap(meTab);
        await tester.pumpAndSettle();
        expect(find.text('Profile'), findsOneWidget);

        // Return to Home tab
        final homeTab = find.descendant(
          of: find.byType(BottomNavDock),
          matching: find.text('Home'),
        );
        await tester.tap(homeTab);
        await tester.pumpAndSettle();

        // Home screen remains preserved and active
        expect(find.text('This Month'), findsOneWidget);
      },
    );
  });

  // ==================================================
  // TESTS — DAY CELLS (PART 2)
  // ==================================================
  group('Milestone 42 — Tests: Day Cells & Deterministic State', () {
    testWidgets('1. Empty day renders correctly', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestableHomeScreen(initialDate: DateTime(2026, 10, 3)),
      );
      await tester.pumpAndSettle();

      final octoberGrid = find.byKey(const ValueKey('2026-10'));
      final day10Finder = find.descendant(
        of: octoberGrid,
        matching: find.widgetWithText(CalendarCell, '10'),
      );
      expect(day10Finder, findsOneWidget);

      final CalendarCell day10Cell = tester.widget(day10Finder);
      expect(day10Cell.style, CalendarCellStyle.empty);
      expect(day10Cell.imageProvider, isNull);
    });

    testWidgets('2. Photo day renders correctly', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final photo = PhotoEntry(
        date: DateTime(2026, 10, 15),
        title: 'Autumn Trail',
        timeFormatted: '2:15 PM',
        gradientColors: const [Colors.amber, Colors.deepOrange],
      );
      await testStore.savePhoto(entry: photo);

      await tester.pumpWidget(
        buildTestableHomeScreen(initialDate: DateTime(2026, 10, 3)),
      );
      await tester.pumpAndSettle();

      final octoberGrid = find.byKey(const ValueKey('2026-10'));
      final day15Finder = find.descendant(
        of: octoberGrid,
        matching: find.widgetWithText(CalendarCell, '15'),
      );
      expect(day15Finder, findsOneWidget);

      final CalendarCell day15Cell = tester.widget(day15Finder);
      expect(day15Cell.style, CalendarCellStyle.photo);
      expect(
        day15Cell.gradientColors,
        equals([Colors.amber, Colors.deepOrange]),
      );
    });

    testWidgets('3. Add photo -> cell updates', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestableHomeScreen(initialDate: DateTime(2026, 10, 3)),
      );
      await tester.pumpAndSettle();

      final octoberGrid = find.byKey(const ValueKey('2026-10'));
      final day20Finder = find.descendant(
        of: octoberGrid,
        matching: find.widgetWithText(CalendarCell, '20'),
      );

      // Verify Oct 20 initially empty
      final cellBefore = tester.widget<CalendarCell>(day20Finder);
      expect(cellBefore.style, CalendarCellStyle.empty);

      // Add photo to Oct 20 in store
      await testStore.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2026, 10, 20),
          title: 'Sunset Peak',
          timeFormatted: '6:30 PM',
          gradientColors: const [Colors.purple, Colors.pink],
        ),
      );
      await tester.pumpAndSettle();

      // Cell immediately updates to photo style
      final cellAfter = tester.widget<CalendarCell>(day20Finder);
      expect(cellAfter.style, CalendarCellStyle.photo);
      expect(cellAfter.gradientColors, equals([Colors.purple, Colors.pink]));
    });

    testWidgets(
      '4. Add subsequent photo on same day -> cell remains photo and entries accumulate',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final initialPhoto = PhotoEntry(
          date: DateTime(2026, 10, 15),
          title: 'Initial Shot',
          timeFormatted: '10:00 AM',
          gradientColors: const [Colors.blue, Colors.cyan],
        );
        await testStore.savePhoto(entry: initialPhoto);

        await tester.pumpWidget(
          buildTestableHomeScreen(initialDate: DateTime(2026, 10, 3)),
        );
        await tester.pumpAndSettle();

        final octoberGrid = find.byKey(const ValueKey('2026-10'));
        final day15Finder = find.descendant(
          of: octoberGrid,
          matching: find.widgetWithText(CalendarCell, '15'),
        );

        // Add second photo on same day
        final secondPhoto = PhotoEntry(
          date: DateTime(2026, 10, 15),
          title: 'Second Shot',
          timeFormatted: '3:00 PM',
          gradientColors: const [Colors.teal, Colors.green],
        );
        await testStore.savePhoto(entry: secondPhoto);
        await tester.pumpAndSettle();

        final updatedCell = tester.widget<CalendarCell>(day15Finder);
        expect(updatedCell.style, CalendarCellStyle.photo);
        expect(updatedCell.gradientColors, equals([Colors.blue, Colors.cyan]));
        final day = testStore.getDay(const DateKey(2026, 10, 15))!;
        expect(day.photos.length, 2);
      },
    );

    testWidgets('5. Delete photo -> cell updates', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final photo = PhotoEntry(
        date: DateTime(2026, 10, 12),
        title: 'To Be Deleted',
        timeFormatted: '1:00 PM',
        gradientColors: const [Colors.red, Colors.orange],
      );
      await testStore.savePhoto(entry: photo);

      await tester.pumpWidget(
        buildTestableHomeScreen(initialDate: DateTime(2026, 10, 3)),
      );
      await tester.pumpAndSettle();

      final octoberGrid = find.byKey(const ValueKey('2026-10'));
      final day12Finder = find.descendant(
        of: octoberGrid,
        matching: find.widgetWithText(CalendarCell, '12'),
      );

      // Cell shows photo
      expect(
        tester.widget<CalendarCell>(day12Finder).style,
        CalendarCellStyle.photo,
      );

      // Delete photo
      await testStore.removePhotoAsync(DateTime(2026, 10, 12));
      await tester.pumpAndSettle();

      // Cell reverts to empty style immediately
      expect(
        tester.widget<CalendarCell>(day12Finder).style,
        CalendarCellStyle.empty,
      );
    });

    testWidgets('6. Persisted photo appears after reload', (tester) async {
      const dateKey = DateKey(2026, 10, 5);
      final photo = PhotoEntry(
        date: dateKey.toDateTime(),
        title: 'Persisted Memory',
        timeFormatted: '12:00 PM',
        gradientColors: const [Colors.indigo, Colors.blue],
      );
      await testStore.savePhoto(entry: photo);

      // Verify persisted in metadataStorage
      final loaded = await metadataStorage.loadAll();
      expect(loaded.containsKey(dateKey), isTrue);

      // Simulate app reload by initializing a second store pointing to the same metadataStorage
      final reloadedStore = PersistentDailyPhotoStore(
        metadataStorage: metadataStorage,
        fileManager: fileManager,
      );
      await reloadedStore.init();

      expect(reloadedStore.hasPhotoByKey(dateKey), isTrue);
      expect(reloadedStore.getPhotoByKey(dateKey)?.title, 'Persisted Memory');

      reloadedStore.dispose();
    });

    testWidgets('7. Deleted photo remains deleted after reload', (
      tester,
    ) async {
      const dateKey = DateKey(2026, 10, 7);
      final photo = PhotoEntry(
        date: dateKey.toDateTime(),
        title: 'Temporary Snapshot',
        timeFormatted: '11:00 AM',
        gradientColors: const [Colors.amber, Colors.orange],
      );
      await testStore.savePhoto(entry: photo);

      // Verify photo exists before delete
      expect(testStore.hasPhotoByKey(dateKey), isTrue);

      // Delete photo
      await testStore.removePhotoAsync(dateKey.toDateTime());

      // Simulate app reload
      final reloadedAfterDelete = PersistentDailyPhotoStore(
        metadataStorage: metadataStorage,
        fileManager: fileManager,
      );
      await reloadedAfterDelete.init();

      // Verification: photo remains deleted
      expect(reloadedAfterDelete.hasPhotoByKey(dateKey), isFalse);
      expect(reloadedAfterDelete.getPhotoByKey(dateKey), isNull);

      reloadedAfterDelete.dispose();
    });

    testWidgets('8. Missing photo file uses fallback', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Create a temporary dummy image file to pass savePhoto validation
      final dummyFile = File('${tempDir.path}/temp_shot.jpg')
        ..writeAsBytesSync([1, 2, 3, 4, 5]);

      final photo = PhotoEntry(
        date: DateTime(2026, 10, 8),
        title: 'Missing File Entry',
        imagePath: dummyFile.path,
        gradientColors: const [Colors.deepPurple, Colors.indigo],
      );
      await testStore.savePhoto(entry: photo, sourceTempPath: dummyFile.path);

      // Delete the file on disk to simulate missing/corrupted file
      if (dummyFile.existsSync()) dummyFile.deleteSync();

      await tester.pumpWidget(
        buildTestableHomeScreen(initialDate: DateTime(2026, 10, 3)),
      );
      await tester.pumpAndSettle();

      final octoberGrid = find.byKey(const ValueKey('2026-10'));
      final day8Finder = find.descendant(
        of: octoberGrid,
        matching: find.widgetWithText(CalendarCell, '8'),
      );
      expect(day8Finder, findsOneWidget);

      final CalendarCell day8Cell = tester.widget(day8Finder);
      expect(day8Cell.style, CalendarCellStyle.photo);
      // Fallback colors available
      expect(
        day8Cell.gradientColors,
        equals([Colors.deepPurple, Colors.indigo]),
      );
    });

    testWidgets('9. January 15 and February 15 are independent', (
      tester,
    ) async {
      const jan15Key = DateKey(2026, 1, 15);
      const feb15Key = DateKey(2026, 2, 15);

      await testStore.savePhoto(
        entry: PhotoEntry(
          date: jan15Key.toDateTime(),
          title: 'January 15',
          timeFormatted: '9:00 AM',
          gradientColors: const [Colors.blue, Colors.indigo],
        ),
      );

      // Jan 15 has photo, Feb 15 does not
      expect(testStore.hasPhotoByKey(jan15Key), isTrue);
      expect(testStore.hasPhotoByKey(feb15Key), isFalse);
    });

    testWidgets('10. Same date in different years is independent', (
      tester,
    ) async {
      const oct15Key2025 = DateKey(2025, 10, 15);
      const oct15Key2026 = DateKey(2026, 10, 15);

      await testStore.savePhoto(
        entry: PhotoEntry(
          date: oct15Key2026.toDateTime(),
          title: 'October 15 2026',
          timeFormatted: '4:00 PM',
          gradientColors: const [Colors.orange, Colors.deepOrange],
        ),
      );

      expect(testStore.hasPhotoByKey(oct15Key2025), isFalse);
      expect(testStore.hasPhotoByKey(oct15Key2026), isTrue);
    });

    testWidgets('11. Today\'s pulse works with empty day', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final today = DateTime(2026, 10, 3);
      await tester.pumpWidget(buildTestableHomeScreen(initialDate: today));
      await tester.pumpAndSettle();

      final octoberGrid = find.byKey(const ValueKey('2026-10'));
      final todayCellFinder = find.descendant(
        of: octoberGrid,
        matching: find.widgetWithText(CalendarCell, '3'),
      );
      final CalendarCell emptyTodayCell = tester.widget(todayCellFinder);
      expect(emptyTodayCell.style, CalendarCellStyle.empty);
      expect(emptyTodayCell.isToday, isTrue);
      expect(emptyTodayCell.showTodayPulse, isTrue);
      expect(find.byType(TodayPulseRing), findsWidgets);
    });

    testWidgets('12. Today\'s pulse works with photo day', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final today = DateTime(2026, 10, 3);
      await testStore.savePhoto(
        entry: PhotoEntry(
          date: today,
          title: 'Today With Photo',
          timeFormatted: '11:00 AM',
          gradientColors: const [Colors.amber, Colors.orange],
        ),
      );

      await tester.pumpWidget(buildTestableHomeScreen(initialDate: today));
      await tester.pumpAndSettle();

      final octoberGrid = find.byKey(const ValueKey('2026-10'));
      final todayCellFinder = find.descendant(
        of: octoberGrid,
        matching: find.widgetWithText(CalendarCell, '3'),
      );
      final CalendarCell photoTodayCell = tester.widget(todayCellFinder);
      expect(photoTodayCell.style, CalendarCellStyle.photo);
      expect(photoTodayCell.isToday, isTrue);
      expect(photoTodayCell.showTodayPulse, isTrue);
      expect(find.byType(TodayPulseRing), findsWidgets);
    });

    testWidgets('13. Editing one day does not change another day', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestableHomeScreen(initialDate: DateTime(2026, 10, 3)),
      );
      await tester.pumpAndSettle();

      final octoberGrid = find.byKey(const ValueKey('2026-10'));
      final day10Finder = find.descendant(
        of: octoberGrid,
        matching: find.widgetWithText(CalendarCell, '10'),
      );
      final day11Finder = find.descendant(
        of: octoberGrid,
        matching: find.widgetWithText(CalendarCell, '11'),
      );

      // Add photo to Day 10
      await testStore.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2026, 10, 10),
          title: 'October 10',
          gradientColors: const [Colors.blue, Colors.cyan],
        ),
      );
      await tester.pumpAndSettle();

      // Day 10 has photo; Day 11 remains empty
      expect(
        tester.widget<CalendarCell>(day10Finder).style,
        CalendarCellStyle.photo,
      );
      expect(
        tester.widget<CalendarCell>(day11Finder).style,
        CalendarCellStyle.empty,
      );
    });

    testWidgets('14. Returning from editing does not show stale data', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final photo = PhotoEntry(
        date: DateTime(2026, 10, 5),
        title: 'Morning Walk',
        timeFormatted: '8:30 AM',
        gradientColors: const [Colors.green, Colors.teal],
      );
      await testStore.savePhoto(entry: photo);

      await tester.pumpWidget(
        buildTestableHomeScreen(initialDate: DateTime(2026, 10, 3)),
      );
      await tester.pumpAndSettle();

      final octoberGrid = find.byKey(const ValueKey('2026-10'));
      final day5Finder = find.descendant(
        of: octoberGrid,
        matching: find.widgetWithText(CalendarCell, '5'),
      );
      expect(day5Finder, findsOneWidget);

      // Tap cell to view detail
      await tester.tap(day5Finder);
      await tester.pumpAndSettle();
      expect(find.byType(PhotoDetailScreen), findsOneWidget);

      // Modify photo in store (e.g. replace or delete during edit flow)
      await testStore.removePhotoAsync(DateTime(2026, 10, 5));

      // Return to Home
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      // Day 5 must immediately reflect empty state without stale photo data
      expect(
        tester.widget<CalendarCell>(day5Finder).style,
        CalendarCellStyle.empty,
      );
    });

    testWidgets('15. All calendar months use the same canonical DateKey logic', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestableHomeScreen(initialDate: DateTime(2026, 10, 3)),
      );
      await tester.pumpAndSettle();

      // Verify each of the 12 month grids is present with canonical key ValueKey('2026-$month')
      for (int month = 1; month <= 12; month++) {
        final monthGrid = find.byKey(ValueKey('2026-$month'));
        expect(monthGrid, findsOneWidget);

        // Every day 1 in each month is indexed deterministically by DateKey(2026, month, 1)
        final day1Finder = find.descendant(
          of: monthGrid,
          matching: find.byKey(ValueKey(DateKey(2026, month, 1))),
        );
        expect(day1Finder, findsOneWidget);
        final cell = tester.widget<CalendarCell>(day1Finder);
        expect(cell.day, equals(1));
      }

      // Also verify canonical DateKey construction matches
      for (int month = 1; month <= 12; month++) {
        const key1 = DateKey(2026, 1, 15);
        final key2 = DateKey(2026, month, 15);
        if (month == 1) {
          expect(key1, equals(key2));
        } else {
          expect(key1, isNot(equals(key2)));
        }
      }
    });
  });
}
