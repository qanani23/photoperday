import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/app.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/day_entry.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/screens/calendar/full_calendar_screen.dart';
import 'package:photo_per_day/screens/camera/camera_screen.dart';
import 'package:photo_per_day/screens/home/home_screen.dart';
import 'package:photo_per_day/screens/profile/profile_screen.dart';
import 'package:photo_per_day/widgets/bottom_nav_dock.dart';

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
  Future<bool> deletePhotoFile(String? path) async => true;

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
    tempDir = Directory.systemTemp.createTempSync('cal_dock_test_');
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

  group('Full Calendar Bottom Nav Dock Interactivity & Navigation', () {
    testWidgets(
      'Tapping Home tab in dock from FullCalendarScreen pops back to HomeScreen',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(const PhotoPerDayApp());
        await tester.pumpAndSettle();

        expect(find.byType(HomeScreen), findsOneWidget);

        // Open Full Calendar
        await tester.tap(
          find.byKey(const ValueKey('home_full_calendar_button')),
        );
        await tester.pumpAndSettle();

        expect(find.byType(FullCalendarScreen), findsOneWidget);

        // Dock is visible
        final homeTab = find.byKey(const ValueKey('dock_home_tab'));
        expect(homeTab, findsOneWidget);

        // Tap Home in dock
        await tester.tap(homeTab);
        await tester.pumpAndSettle();

        // Should return to HomeScreen
        expect(find.byType(FullCalendarScreen), findsNothing);
        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );

    testWidgets(
      'Tapping Me tab in dock from FullCalendarScreen pops and switches to ProfileScreen',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(const PhotoPerDayApp());
        await tester.pumpAndSettle();

        expect(find.byType(HomeScreen), findsOneWidget);

        // Open Full Calendar
        await tester.tap(
          find.byKey(const ValueKey('home_full_calendar_button')),
        );
        await tester.pumpAndSettle();

        expect(find.byType(FullCalendarScreen), findsOneWidget);

        // Me tab in dock
        final meTab = find.byKey(const ValueKey('dock_me_tab'));
        expect(meTab, findsOneWidget);

        // Tap Me in dock
        await tester.tap(meTab);
        await tester.pumpAndSettle();

        // Should pop FullCalendarScreen and reveal ProfileScreen
        expect(find.byType(FullCalendarScreen), findsNothing);
        expect(find.byType(ProfileScreen), findsOneWidget);

        // Bottom dock on ProfileScreen should have currentIndex == 2
        final dock = tester.widget<BottomNavDock>(find.byType(BottomNavDock));
        expect(dock.currentIndex, equals(2));

        // Tapping Home from ProfileScreen should switch back to HomeScreen
        await tester.tap(find.byKey(const ValueKey('dock_home_tab')));
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );

    testWidgets(
      'Tapping Capture tab in dock from FullCalendarScreen launches Camera workflow',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(const PhotoPerDayApp());
        await tester.pumpAndSettle();

        expect(find.byType(HomeScreen), findsOneWidget);

        // Open Full Calendar
        await tester.tap(
          find.byKey(const ValueKey('home_full_calendar_button')),
        );
        await tester.pumpAndSettle();

        expect(find.byType(FullCalendarScreen), findsOneWidget);

        // Capture tab in dock
        final captureTab = find.byKey(const ValueKey('dock_capture_tab'));
        expect(captureTab, findsOneWidget);

        // Tap Capture in dock - should push CameraScreen
        await tester.tap(captureTab);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(CameraScreen), findsOneWidget);
      },
    );

    testWidgets(
      'Standalone FullCalendarScreen executes provided callbacks on dock taps',
      (tester) async {
        bool meTapped = false;
        bool captureTapped = false;

        await tester.pumpWidget(
          MaterialApp(
            home: FullCalendarScreen(
              wrapWithScaffold: true,
              store: testStore,
              initialDate: DateTime(2026, 6, 15),
              onNavigateToProfile: () => meTapped = true,
              onCaptureTap: () => captureTapped = true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap Me tab
        await tester.tap(find.byKey(const ValueKey('dock_me_tab')));
        await tester.pumpAndSettle();
        expect(meTapped, isTrue);

        // Tap Capture tab
        await tester.tap(find.byKey(const ValueKey('dock_capture_tab')));
        await tester.pumpAndSettle();
        expect(captureTapped, isTrue);
      },
    );
  });
}
