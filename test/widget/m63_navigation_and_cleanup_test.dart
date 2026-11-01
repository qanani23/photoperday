import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/app.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/day_entry.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/screens/calendar/full_calendar_screen.dart';
import 'package:photo_per_day/screens/home/home_screen.dart';
import 'package:photo_per_day/screens/today/today_screen.dart';
import 'package:photo_per_day/widgets/bottom_nav_dock.dart';
import 'package:photo_per_day/widgets/calendar_cell.dart';

class _FakeMetadataStorage extends PhotoMetadataStorage {
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

class _FakeFileManager extends PhotoFileManager {
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
  late _FakeMetadataStorage fakeStorage;
  late _FakeFileManager fakeFileManager;
  late PersistentDailyPhotoStore testStore;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('m63_test_');
    fakeStorage = _FakeMetadataStorage();
    fakeFileManager = _FakeFileManager()..tempDir = tempDir;

    testStore = PersistentDailyPhotoStore(
      fileManager: fakeFileManager,
      metadataStorage: fakeStorage,
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

  PhotoEntry createSamplePhoto(DateTime date, {String title = 'Real Memory'}) {
    final dateKey = DateKey.fromDateTime(date);
    final filePath = '${tempDir.path}/real_${dateKey.format()}.jpg';
    File(filePath).writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);

    return PhotoEntry(
      id: 'photo_${dateKey.format()}',
      date: date,
      title: title,
      timeFormatted: '11:00 AM',
      imagePath: filePath,
      gradientColors: const [Color(0xFFB86B35), Color(0xFF2B2823)],
    );
  }

  group('M63 — Issue 1: Full Calendar Return Navigation', () {
    testWidgets(
      'Full Calendar displays a visible back button and returns to Home when tapped',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(const PhotoPerDayApp());
        await tester.pumpAndSettle();

        // 1. Initial screen is Home
        expect(find.byType(HomeScreen), findsOneWidget);

        // 2. Tap "Full calendar" button on Home
        final fullCalButton = find.byKey(
          const ValueKey('home_full_calendar_button'),
        );
        expect(fullCalButton, findsOneWidget);
        await tester.tap(fullCalButton);
        await tester.pumpAndSettle();

        // 3. FullCalendarScreen is now displayed
        expect(find.byType(FullCalendarScreen), findsOneWidget);

        // 4. Visible back button is present in the header
        final backButton = find.byTooltip('Back');
        expect(backButton, findsOneWidget);

        // 5. Tap the back button
        await tester.tap(backButton);
        await tester.pumpAndSettle();

        // 6. Returns to Home screen
        expect(find.byType(FullCalendarScreen), findsNothing);
        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );

    testWidgets('Android system back pops Full Calendar and returns to Home', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const PhotoPerDayApp());
      await tester.pumpAndSettle();

      // Open Full Calendar
      await tester.tap(find.byKey(const ValueKey('home_full_calendar_button')));
      await tester.pumpAndSettle();
      expect(find.byType(FullCalendarScreen), findsOneWidget);

      // Simulate Android system back button
      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await tester.pumpAndSettle();

      // Returned to Home
      expect(find.byType(FullCalendarScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets(
      'Home active indicator and scroll state remain intact after returning from Full Calendar',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(const PhotoPerDayApp());
        await tester.pumpAndSettle();

        // Open Full Calendar
        await tester.tap(
          find.byKey(const ValueKey('home_full_calendar_button')),
        );
        await tester.pumpAndSettle();

        // Return from Full Calendar
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();

        // Verify Home tab is selected and has the active rounded indicator
        final dockFinder = find.byType(BottomNavDock);
        expect(dockFinder, findsOneWidget);
        expect(
          tester.widget<BottomNavDock>(dockFinder).currentIndex,
          equals(0),
        );

        final homeTabFinder = find.byKey(const ValueKey('dock_home_tab'));
        expect(homeTabFinder, findsOneWidget);
        final homeContainer = tester.widget<AnimatedContainer>(
          find.descendant(
            of: homeTabFinder,
            matching: find.byType(AnimatedContainer),
          ),
        );
        expect(
          (homeContainer.decoration as BoxDecoration).color,
          equals(AppColors.surfaceDark),
        );

        // Verify Capture and Me are transparent
        final captureContainer = tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.byKey(const ValueKey('dock_capture_tab')),
            matching: find.byType(AnimatedContainer),
          ),
        );
        expect(
          (captureContainer.decoration as BoxDecoration).color,
          equals(Colors.transparent),
        );

        final meContainer = tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.byKey(const ValueKey('dock_me_tab')),
            matching: find.byType(AnimatedContainer),
          ),
        );
        expect(
          (meContainer.decoration as BoxDecoration).color,
          equals(Colors.transparent),
        );
      },
    );
  });

  group('M63 — Issue 2: Bottom Navigation Active Indicator', () {
    testWidgets(
      'Active rounded indicator follows the selected destination and inactive destinations are transparent',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(const PhotoPerDayApp());
        await tester.pumpAndSettle();

        // 1. Initial state: Home is selected
        final dockFinder = find.byType(BottomNavDock);
        expect(
          tester.widget<BottomNavDock>(dockFinder).currentIndex,
          equals(0),
        );

        final homeTab = find.byKey(const ValueKey('dock_home_tab'));
        final captureTab = find.byKey(const ValueKey('dock_capture_tab'));
        final meTab = find.byKey(const ValueKey('dock_me_tab'));

        // Home has surfaceDark background; Capture and Me have transparent background
        final homeContainer = tester.widget<AnimatedContainer>(
          find.descendant(
            of: homeTab,
            matching: find.byType(AnimatedContainer),
          ),
        );
        final captureContainer = tester.widget<AnimatedContainer>(
          find.descendant(
            of: captureTab,
            matching: find.byType(AnimatedContainer),
          ),
        );
        final meContainer = tester.widget<AnimatedContainer>(
          find.descendant(of: meTab, matching: find.byType(AnimatedContainer)),
        );

        final homeDec = homeContainer.decoration as BoxDecoration;
        final captureDec = captureContainer.decoration as BoxDecoration;
        final meDec = meContainer.decoration as BoxDecoration;

        expect(homeDec.color, equals(AppColors.surfaceDark));
        expect(captureDec.color, equals(Colors.transparent));
        expect(meDec.color, equals(Colors.transparent));

        // 2. Switch to Me tab
        await tester.tap(meTab);
        await tester.pumpAndSettle();

        expect(
          tester.widget<BottomNavDock>(dockFinder).currentIndex,
          equals(2),
        );

        final meContainerAfter = tester.widget<AnimatedContainer>(
          find.descendant(of: meTab, matching: find.byType(AnimatedContainer)),
        );
        final homeContainerAfter = tester.widget<AnimatedContainer>(
          find.descendant(
            of: homeTab,
            matching: find.byType(AnimatedContainer),
          ),
        );
        final captureContainerAfter = tester.widget<AnimatedContainer>(
          find.descendant(
            of: captureTab,
            matching: find.byType(AnimatedContainer),
          ),
        );

        expect(
          (meContainerAfter.decoration as BoxDecoration).color,
          equals(AppColors.surfaceDark),
        );
        expect(
          (homeContainerAfter.decoration as BoxDecoration).color,
          equals(Colors.transparent),
        );
        expect(
          (captureContainerAfter.decoration as BoxDecoration).color,
          equals(Colors.transparent),
        );

        // 3. Switch back to Home tab
        await tester.tap(homeTab);
        await tester.pumpAndSettle();

        expect(
          tester.widget<BottomNavDock>(dockFinder).currentIndex,
          equals(0),
        );
        final homeContainerFinal = tester.widget<AnimatedContainer>(
          find.descendant(
            of: homeTab,
            matching: find.byType(AnimatedContainer),
          ),
        );
        expect(
          (homeContainerFinal.decoration as BoxDecoration).color,
          equals(AppColors.surfaceDark),
        );
      },
    );

    testWidgets(
      'Returning from pushed routes preserves the correct selected destination',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(const PhotoPerDayApp());
        await tester.pumpAndSettle();

        // Navigate to Settings
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();

        // Pop from Settings
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();

        // Home remains selected
        final dockFinder = find.byType(BottomNavDock);
        expect(
          tester.widget<BottomNavDock>(dockFinder).currentIndex,
          equals(0),
        );
        final homeTab = find.byKey(const ValueKey('dock_home_tab'));
        final homeContainer = tester.widget<AnimatedContainer>(
          find.descendant(
            of: homeTab,
            matching: find.byType(AnimatedContainer),
          ),
        );
        expect(
          (homeContainer.decoration as BoxDecoration).color,
          equals(AppColors.surfaceDark),
        );
      },
    );
  });

  group(
    'M63 — Issue 3: Production Data Cleanup (No Synthetic Data in Empty State)',
    () {
      testWidgets(
        'Fresh empty store produces NO fake photo or note entries on Home calendar or timeline',
        (tester) async {
          tester.view.physicalSize = const Size(1080, 2340);
          tester.view.devicePixelRatio = 2.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          // Pump HomeScreen with the empty testStore
          await tester.pumpWidget(
            MaterialApp(
              home: HomeScreen(
                wrapWithScaffold: true,
                store: testStore,
                initialDate: DateTime(2026, 3, 15),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // 1. No fake March 3, 2026 photo cell
          final march3Cell = find.byKey(const ValueKey(DateKey(2026, 3, 3)));
          expect(march3Cell, findsOneWidget);
          final cell = tester.widget<CalendarCell>(march3Cell);
          expect(cell.style, equals(CalendarCellStyle.empty));
          expect(cell.photoCount, equals(0));
          expect(cell.hasNote, isFalse);

          // 2. Timeline displays the real, clean empty state
          expect(
            find.byKey(const ValueKey('home_memories_empty_state')),
            findsOneWidget,
          );
          expect(find.text('No Memories Yet'), findsOneWidget);
          expect(find.text('Add Your First Photo'), findsOneWidget);

          // 3. No fake timeline card for March 3, 2026
          expect(
            find.byKey(const ValueKey('timeline_day_2026-03-03')),
            findsNothing,
          );
        },
      );

      testWidgets(
        'Fresh empty store in Full Calendar has no fake photo indicators',
        (tester) async {
          tester.view.physicalSize = const Size(1080, 2340);
          tester.view.devicePixelRatio = 2.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await tester.pumpWidget(
            MaterialApp(
              home: FullCalendarScreen(
                wrapWithScaffold: true,
                store: testStore,
                initialDate: DateTime(2026, 3, 15),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // March 3, 2026 must be an empty cell, not photo cell
          final march3Cell = find.byKey(const ValueKey(DateKey(2026, 3, 3)));
          expect(march3Cell, findsOneWidget);
          final cell = tester.widget<CalendarCell>(march3Cell);
          expect(cell.style, equals(CalendarCellStyle.empty));
          expect(cell.photoCount, equals(0));
        },
      );

      testWidgets(
        'TodayScreen displays real empty state when no photo has been captured today',
        (tester) async {
          tester.view.physicalSize = const Size(1080, 2340);
          tester.view.devicePixelRatio = 2.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await tester.pumpWidget(
            MaterialApp(
              home: TodayScreen(
                store: testStore,
                todayDate: DateTime(2026, 3, 15),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Empty state is rendered
          expect(find.text("Today hasn't been captured yet"), findsOneWidget);
          expect(find.text("Capture Today's Photo"), findsOneWidget);

          // No fake "Golden Afternoon Reflections"
          expect(find.text('Golden Afternoon Reflections'), findsNothing);
        },
      );

      testWidgets(
        'Adding a real photo renders only that real photo across Home, Calendar, and Timeline',
        (tester) async {
          tester.view.physicalSize = const Size(1080, 2340);
          tester.view.devicePixelRatio = 2.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          final realDate = DateTime(2026, 3, 8);
          final realPhoto = createSamplePhoto(
            realDate,
            title: 'Real Sunday Hike',
          );
          await testStore.addPhotoToDay(
            dateKey: DateKey.fromDateTime(realDate),
            photo: realPhoto,
          );

          await tester.pumpWidget(
            MaterialApp(
              home: HomeScreen(
                wrapWithScaffold: true,
                store: testStore,
                initialDate: DateTime(2026, 3, 15),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Empty state is gone
          expect(
            find.byKey(const ValueKey('home_memories_empty_state')),
            findsNothing,
          );

          // Timeline card exists for March 8, but NOT for March 3
          expect(
            find.byKey(const ValueKey('timeline_day_2026-03-08')),
            findsOneWidget,
          );
          expect(find.text('Real Sunday Hike'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('timeline_day_2026-03-03')),
            findsNothing,
          );

          // Calendar cell for March 8 is photo style
          final march8Cell = find.byKey(const ValueKey(DateKey(2026, 3, 8)));
          expect(march8Cell, findsOneWidget);
          expect(
            tester.widget<CalendarCell>(march8Cell).style,
            equals(CalendarCellStyle.photo),
          );

          // Calendar cell for March 3 is empty style
          final march3Cell = find.byKey(const ValueKey(DateKey(2026, 3, 3)));
          expect(
            tester.widget<CalendarCell>(march3Cell).style,
            equals(CalendarCellStyle.empty),
          );
        },
      );
    },
  );
}
