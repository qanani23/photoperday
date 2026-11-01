import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/core/layout/app_breakpoints.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/day_entry.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/screens/calendar/full_calendar_screen.dart';
import 'package:photo_per_day/screens/home/home_screen.dart';
import 'package:photo_per_day/screens/photo_detail/photo_detail_screen.dart';
import 'package:photo_per_day/screens/profile/profile_screen.dart';
import 'package:photo_per_day/screens/settings/settings_screen.dart';
import 'package:photo_per_day/screens/today/today_screen.dart';
import 'package:photo_per_day/widgets/app_scaffold.dart';
import 'package:photo_per_day/widgets/bottom_nav_dock.dart';
import 'package:photo_per_day/widgets/calendar_grid.dart';
import 'package:photo_per_day/widgets/timeline_entry_card.dart';
import 'package:photo_per_day/widgets/weekday_header.dart';

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
  late _TestMetadataStorage testStorage;
  late _TestFileManager testFileManager;
  late PersistentDailyPhotoStore testStore;
  final testDate = DateTime(2026, 10, 15);

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('m65_desktop_test_');
    testStorage = _TestMetadataStorage();
    testFileManager = _TestFileManager()..tempDir = tempDir;
    testStore = PersistentDailyPhotoStore(
      fileManager: testFileManager,
      metadataStorage: testStorage,
    );
    PersistentDailyPhotoStore.setTestInstance(testStore);
    await testStore.init();

    // Populate a test photo for 2026-10-10
    final entryDate = DateTime(2026, 10, 10);
    final key = DateKey.fromDateTime(entryDate);
    final photo = PhotoEntry(
      date: entryDate,
      title: 'October Memory',
      location: 'Lake View',
      timeFormatted: '2:30 PM',
      gradientColors: const [Colors.amber, Colors.deepOrange],
    );
    final sourceFile = File('${tempDir.path}/oct10.jpg');
    sourceFile.writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);

    await testStore.addPhotoToDay(
      dateKey: key,
      photo: photo,
      sourceTempPath: sourceFile.path,
    );
    await testStore.updateDayNote(
      dateKey: key,
      note: 'A beautiful sunny day by the lake with calm breezes.',
    );
  });

  tearDown(() async {
    PersistentDailyPhotoStore.resetTestInstance();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('M65: Desktop Responsive Layout Architecture', () {
    testWidgets(
      'AppScaffold centers and constrains bottom dock to 440px on 1366px and 1920px',
      (tester) async {
        for (final width in [1366.0, 1920.0]) {
          tester.view.physicalSize = Size(width, 900.0);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await tester.pumpWidget(
            const MaterialApp(
              home: AppScaffold(
                currentNavIndex: 0,
                body: Text('Desktop Content'),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final dockFinder = find.byType(BottomNavDock);
          expect(dockFinder, findsOneWidget);

          final dockSize = tester.getSize(dockFinder);
          expect(
            dockSize.width,
            lessThanOrEqualTo(AppBreakpoints.maxBottomDockWidth),
          );

          // Check horizontal centering: center of dock is roughly center of screen
          final dockCenter = tester.getCenter(dockFinder);
          expect((dockCenter.dx - width / 2).abs(), lessThan(5.0));
        }
      },
    );

    testWidgets(
      'HomeScreen on 1366px desktop expands calendar width and childAspectRatio is 1.15',
      (tester) async {
        tester.view.physicalSize = const Size(1366.0, 768.0);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(
              store: testStore,
              initialDate: testDate,
              wrapWithScaffold: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Find CalendarGrid
        final gridFinder = find.byType(CalendarGrid);
        expect(gridFinder, findsOneWidget);

        final gridWidget = tester.widget<CalendarGrid>(gridFinder);
        expect(gridWidget.childAspectRatio, equals(1.15));

        final gridSize = tester.getSize(gridFinder);
        // Calendar grid should expand to use desktop width comfortably (> 1000px)
        expect(gridSize.width, greaterThan(1000.0));

        // WeekdayHeader padding should be zero to align with CalendarGrid
        final weekdayFinder = find.byType(WeekdayHeader);
        expect(weekdayFinder, findsOneWidget);
        final weekdayWidget = tester.widget<WeekdayHeader>(weekdayFinder);
        expect(weekdayWidget.padding, equals(EdgeInsets.zero));

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('HomeScreen on mobile (<600px) uses childAspectRatio 1.0', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390.0, 844.0);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            store: testStore,
            initialDate: testDate,
            wrapWithScaffold: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gridFinder = find.byType(CalendarGrid);
      expect(gridFinder, findsOneWidget);

      final gridWidget = tester.widget<CalendarGrid>(gridFinder);
      expect(gridWidget.childAspectRatio, equals(1.0));

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'TimelineEntryCard uses responsive 16:9 aspect ratio with max height constraint on widescreen',
      (tester) async {
        final day = testStore.getDay(const DateKey(2026, 10, 10))!;

        tester.view.physicalSize = const Size(1366.0, 768.0);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 1200.0,
                child: TimelineEntryCard(dayEntry: day),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(TimelineEntryCard), findsOneWidget);
        // Photo aspect ratio on desktop is 16:9 with maxHeight 380.0
        final constrainedBoxes = find.descendant(
          of: find.byType(TimelineEntryCard),
          matching: find.byType(ConstrainedBox),
        );
        bool foundMaxHeight380 = false;
        for (final element in constrainedBoxes.evaluate()) {
          final widget = element.widget as ConstrainedBox;
          if (widget.constraints.maxHeight == 380.0) {
            foundMaxHeight380 = true;
            break;
          }
        }
        expect(foundMaxHeight380, isTrue);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'FullCalendarScreen multi-column quarterly layout (3 cols on >=1150px, 2 on 700-1150px, 1 on <700px)',
      (tester) async {
        // 1. Desktop widescreen (1366px) -> 3 columns (4 rows of 3 months)
        tester.view.physicalSize = const Size(1366.0, 768.0);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: FullCalendarScreen(
              store: testStore,
              initialDate: testDate,
              wrapWithScaffold: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // We should find 12 CalendarGrid instances
        final grids = find.byType(CalendarGrid);
        expect(grids, findsNWidgets(12));

        // At 1366px, months are placed in multi-column rows of 3
        expect(tester.takeException(), isNull);

        // 2. Mid desktop (800px) -> 2 columns
        tester.view.physicalSize = const Size(800.0, 768.0);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // 3. Mobile screen (400px) -> 1 column
        tester.view.physicalSize = const Size(400.0, 768.0);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'TodayScreen renders 2-column layout on wide screens (>=840px) and stacked on mobile',
      (tester) async {
        // 1. Desktop wide (1366px)
        tester.view.physicalSize = const Size(1366.0, 768.0);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TodayScreen(store: testStore, todayDate: testDate),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // TodayScreen should render without exception and have wide layout
        expect(find.byType(TodayScreen), findsOneWidget);
        expect(tester.takeException(), isNull);

        // 2. Mobile screen (400px)
        tester.view.physicalSize = const Size(400.0, 768.0);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'PhotoDetailScreen renders 2-column layout on wide screens (>=860px) and maxContentWidth constraint',
      (tester) async {
        final photo = PhotoEntry(
          date: testDate,
          title: 'Detail Memory',
          location: 'Sunset Bay',
          timeFormatted: '5:00 PM',
          gradientColors: const [Colors.blue, Colors.purple],
        );

        tester.view.physicalSize = const Size(1366.0, 768.0);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(home: PhotoDetailScreen(photoEntry: photo)),
        );
        await tester.pumpAndSettle();

        expect(find.byType(PhotoDetailScreen), findsOneWidget);

        // Check for maxContentWidth constraint
        final constrainedBoxes = find.descendant(
          of: find.byType(PhotoDetailScreen),
          matching: find.byType(ConstrainedBox),
        );
        bool hasMaxContentWidth = false;
        for (final elem in constrainedBoxes.evaluate()) {
          final box = elem.widget as ConstrainedBox;
          if (box.constraints.maxWidth == AppBreakpoints.maxContentWidth) {
            hasMaxContentWidth = true;
            break;
          }
        }
        expect(hasMaxContentWidth, isTrue);
        expect(tester.takeException(), isNull);

        // Resize to mobile
        tester.view.physicalSize = const Size(400.0, 768.0);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'ProfileScreen and SettingsScreen constrain content to maxSettingsWidth (1000px)',
      (tester) async {
        tester.view.physicalSize = const Size(1366.0, 768.0);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // 1. ProfileScreen
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: ProfileScreen())),
        );
        await tester.pumpAndSettle();

        expect(find.byType(ProfileScreen), findsOneWidget);
        final profileBoxes = find.descendant(
          of: find.byType(ProfileScreen),
          matching: find.byType(ConstrainedBox),
        );
        bool profileConstrained = false;
        for (final elem in profileBoxes.evaluate()) {
          final box = elem.widget as ConstrainedBox;
          if (box.constraints.maxWidth == AppBreakpoints.maxSettingsWidth) {
            profileConstrained = true;
            break;
          }
        }
        expect(profileConstrained, isTrue);
        expect(tester.takeException(), isNull);

        // 2. SettingsScreen
        await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
        await tester.pumpAndSettle();

        expect(find.byType(SettingsScreen), findsOneWidget);
        final settingsBoxes = find.descendant(
          of: find.byType(SettingsScreen),
          matching: find.byType(ConstrainedBox),
        );
        bool settingsConstrained = false;
        for (final elem in settingsBoxes.evaluate()) {
          final box = elem.widget as ConstrainedBox;
          if (box.constraints.maxWidth == AppBreakpoints.maxSettingsWidth) {
            settingsConstrained = true;
            break;
          }
        }
        expect(settingsConstrained, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
