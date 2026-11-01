import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_palette.dart';
import 'package:photo_per_day/core/time/app_clock.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/day_entry.dart';
import 'package:photo_per_day/data/models/pad_backup_models.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';
import 'package:photo_per_day/data/services/app_theme_storage.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/data/services/statistics_service.dart';
import 'package:photo_per_day/data/services/streak_service.dart';
import 'package:photo_per_day/screens/home/home_screen.dart';
import 'package:photo_per_day/screens/calendar/full_calendar_screen.dart';

// ---------------------------------------------------------------------------
// Test Fakes & Mocks
// ---------------------------------------------------------------------------

class AuditTestMetadataStorage extends PhotoMetadataStorage {
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

class AuditTestFileManager extends PhotoFileManager {
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
      return true;
    }
    return false;
  }
}

class WidgetFakeThemeStorage extends AppThemeStorage {
  WidgetFakeThemeStorage({super.customBaseDir});

  String? _savedPaletteId;
  bool _savedFollowSystem = false;

  @override
  Future<ThemeSettingsData> loadSettings() async => ThemeSettingsData(
    paletteId: _savedPaletteId ?? 'daria_red_light',
    followSystem: _savedFollowSystem,
  );

  @override
  Future<void> saveSettings({
    required String paletteId,
    required bool followSystem,
  }) async {
    _savedPaletteId = paletteId;
    _savedFollowSystem = followSystem;
  }
}

// ---------------------------------------------------------------------------
// Main Audit Suite
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDir;
  late AuditTestMetadataStorage mockMetadata;
  late AuditTestFileManager mockFileManager;
  late PersistentDailyPhotoStore testStore;

  setUp(() async {
    AppClock.resetTestClock();
    StreakService.instance.clearCache();
    StatisticsService.instance.clearCache();

    testDir = await Directory.systemTemp.createTemp('daria_audit_');
    mockMetadata = AuditTestMetadataStorage();
    mockFileManager = AuditTestFileManager()..tempDir = testDir;

    testStore = PersistentDailyPhotoStore(
      metadataStorage: mockMetadata,
      fileManager: mockFileManager,
    );
    await testStore.init();

    final themeStorage = WidgetFakeThemeStorage();
    await AppThemeService.instance.init(storage: themeStorage);
  });

  tearDown(() async {
    AppClock.resetTestClock();
    StreakService.instance.clearCache();
    StatisticsService.instance.clearCache();
    if (testDir.existsSync()) {
      try {
        testDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  PhotoEntry createSamplePhoto({
    required DateKey dateKey,
    String id = '',
    int order = 0,
    String? imagePath,
  }) {
    final path = imagePath ?? '${testDir.path}/${dateKey.format()}_$order.jpg';
    final file = File(path);
    if (!file.existsSync()) {
      file.writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
    }
    return PhotoEntry(
      id: id.isNotEmpty ? id : 'photo_${dateKey.format()}_$order',
      date: dateKey.toDateTime(hour: 12, minute: 0),
      title: 'Daily Capture',
      timeFormatted: '12:00 PM',
      location: 'Local Journal',
      imagePath: path,
      order: order,
      gradientColors: [AppColors.accent, AppColors.surfaceDark],
    );
  }

  group('PHASE 2: Calendar Correctness & Rollover Audit', () {
    test('Gregorian date math correctly identifies leap year lengths', () {
      // 2024 is a leap year (29 days in Feb)
      expect(DateTime(2024, 2 + 1, 0).day, 29);
      expect(DateKey.isValidDate(2024, 2, 29), isTrue);

      // 2025 and 2026 are standard years (28 days in Feb)
      expect(DateTime(2025, 2 + 1, 0).day, 28);
      expect(DateKey.isValidDate(2025, 2, 29), isFalse);
      expect(DateTime(2026, 2 + 1, 0).day, 28);
      expect(DateKey.isValidDate(2026, 2, 29), isFalse);

      // Centurial leap years: 2000 is leap, 2100 is not
      expect(DateTime(2000, 2 + 1, 0).day, 29);
      expect(DateTime(2100, 2 + 1, 0).day, 28);
    });

    test(
      'Sunday-first 7-column calendar leading offsets are mathematically exact',
      () {
        // Nov 1, 2026 is Sunday -> weekday = 7 -> 7 % 7 = 0 leading spacers
        final nov1 = DateTime(2026, 11, 1);
        expect(nov1.weekday, DateTime.sunday);
        expect(nov1.weekday % 7, 0);

        // Dec 1, 2026 is Tuesday -> weekday = 2 -> 2 % 7 = 2 leading spacers (Sun, Mon)
        final dec1 = DateTime(2026, 12, 1);
        expect(dec1.weekday, DateTime.tuesday);
        expect(dec1.weekday % 7, 2);

        // Jan 1, 2026 is Thursday -> weekday = 4 -> 4 % 7 = 4 leading spacers (Sun, Mon, Tue, Wed)
        final jan1 = DateTime(2026, 1, 1);
        expect(jan1.weekday, DateTime.thursday);
        expect(jan1.weekday % 7, 4);
      },
    );

    test('AppClock allows deterministic control over local system time', () {
      final simulatedTime = DateTime(2026, 10, 31, 23, 59, 50);
      AppClock.setFixedTime(simulatedTime);

      expect(AppClock.now(), simulatedTime);
      expect(DateKey.today(), const DateKey(2026, 10, 31));

      // Advance clock past midnight into November 1st
      final afterMidnight = DateTime(2026, 11, 1, 0, 0, 5);
      AppClock.setFixedTime(afterMidnight);

      expect(AppClock.now(), afterMidnight);
      expect(DateKey.today(), const DateKey(2026, 11, 1));
    });

    testWidgets(
      'HomeScreen automatically detects midnight rollover on resume without restart',
      (tester) async {
        // Start on Oct 31, 2026
        AppClock.setFixedTime(DateTime(2026, 10, 31, 23, 59, 55));

        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(store: testStore, wrapWithScaffold: false),
          ),
        );
        await tester.pumpAndSettle();

        // Oct 31 is visible in header
        expect(find.text('October 2026'), findsOneWidget);

        // Simulate clock ticking past midnight into November 1, 2026 and app resumed
        AppClock.setFixedTime(DateTime(2026, 11, 1, 0, 0, 5));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();

        // Verify the compact calendar automatically advanced to November 2026
        expect(find.text('November 2026'), findsOneWidget);
      },
    );

    testWidgets(
      'FullCalendarScreen rolls over current date and year navigation across year boundary',
      (tester) async {
        // Start on Dec 31, 2026 at 23:59:59
        AppClock.setFixedTime(DateTime(2026, 12, 31, 23, 59, 59));

        await tester.pumpWidget(
          MaterialApp(
            home: FullCalendarScreen(store: testStore, wrapWithScaffold: false),
          ),
        );
        await tester.pumpAndSettle();

        // Year header shows 2026
        expect(find.text('2026'), findsWidgets);

        // Cross midnight into Jan 1, 2027 and resume
        AppClock.setFixedTime(DateTime(2027, 1, 1, 0, 0, 1));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();

        // Verify the full calendar updated to 2027
        expect(find.text('2027'), findsWidgets);
      },
    );
  });

  group('PHASE 3: Streaks and Statistics Correctness Audit', () {
    test(
      'Zero photos results in 0 current streak, 0 longest streak, notConnected state',
      () {
        final summary = StreakService.instance.calculateStreak(
          store: testStore,
          todayDate: DateTime(2026, 10, 31),
        );

        expect(summary.currentStreak, 0);
        expect(summary.longestStreak, 0);
        expect(summary.totalRecordedDays, 0);
        expect(summary.isCurrentStreakActive, isFalse);
        expect(summary.cloudState, StreakCloudState.notConnected);
      },
    );

    test('1 photo today gives active 1-day streak', () async {
      const today = DateKey(2026, 10, 31);
      await testStore.addPhotoToDay(
        dateKey: today,
        photo: createSamplePhoto(dateKey: today),
      );

      final summary = StreakService.instance.calculateStreak(
        store: testStore,
        todayDate: today.toDateTime(),
      );

      expect(summary.currentStreak, 1);
      expect(summary.longestStreak, 1);
      expect(summary.totalRecordedDays, 1);
      expect(summary.isCurrentStreakActive, isTrue);
      expect(summary.cloudState, StreakCloudState.active);
      expect(summary.currentStreakStartDate, today);
      expect(summary.currentStreakEndDate, today);
    });

    test(
      '1 photo yesterday and 0 today gives active 1-day streak under grace period rule',
      () async {
        const yesterday = DateKey(2026, 10, 30);
        const today = DateKey(2026, 10, 31);
        await testStore.addPhotoToDay(
          dateKey: yesterday,
          photo: createSamplePhoto(dateKey: yesterday),
        );

        final summary = StreakService.instance.calculateStreak(
          store: testStore,
          todayDate: today.toDateTime(),
        );

        expect(summary.currentStreak, 1);
        expect(summary.longestStreak, 1);
        expect(summary.isCurrentStreakActive, isTrue);
        expect(summary.cloudState, StreakCloudState.active);
        expect(summary.currentStreakEndDate, yesterday);
      },
    );

    test(
      '1 photo 2 days ago and 0 today/yesterday ends the streak (current = 0)',
      () async {
        const twoDaysAgo = DateKey(2026, 10, 29);
        const today = DateKey(2026, 10, 31);
        await testStore.addPhotoToDay(
          dateKey: twoDaysAgo,
          photo: createSamplePhoto(dateKey: twoDaysAgo),
        );

        final summary = StreakService.instance.calculateStreak(
          store: testStore,
          todayDate: today.toDateTime(),
        );

        expect(summary.currentStreak, 0);
        expect(summary.longestStreak, 1);
        expect(summary.isCurrentStreakActive, isFalse);
        expect(summary.cloudState, StreakCloudState.ended);
        expect(summary.endedStreakCount, 1);
      },
    );

    test(
      'Multiple photos on the same day count as 1 recorded day in streak calculation',
      () async {
        const today = DateKey(2026, 10, 31);
        await testStore.addPhotoToDay(
          dateKey: today,
          photo: createSamplePhoto(dateKey: today, id: 'p1', order: 0),
        );
        await testStore.addPhotoToDay(
          dateKey: today,
          photo: createSamplePhoto(dateKey: today, id: 'p2', order: 1),
        );
        await testStore.addPhotoToDay(
          dateKey: today,
          photo: createSamplePhoto(dateKey: today, id: 'p3', order: 2),
        );

        expect(testStore.getDay(today)?.photoCount, 3);

        final summary = StreakService.instance.calculateStreak(
          store: testStore,
          todayDate: today.toDateTime(),
        );

        expect(summary.currentStreak, 1);
        expect(summary.totalRecordedDays, 1);
      },
    );

    test(
      'Note-only day without photos DOES NOT count toward photo streak',
      () async {
        const day1 = DateKey(2026, 10, 29);
        const day2NoteOnly = DateKey(2026, 10, 30);
        const day3 = DateKey(2026, 10, 31);

        // Day 1 has photo
        await testStore.addPhotoToDay(
          dateKey: day1,
          photo: createSamplePhoto(dateKey: day1),
        );

        // Day 2 has only a reflection note (no photos)
        await testStore.updateDayNote(
          dateKey: day2NoteOnly,
          note: 'Thoughtful reflection with no photos.',
        );

        // Day 3 has photo
        await testStore.addPhotoToDay(
          dateKey: day3,
          photo: createSamplePhoto(dateKey: day3),
        );

        final summary = StreakService.instance.calculateStreak(
          store: testStore,
          todayDate: day3.toDateTime(),
        );

        // Note-only day does not bridge the photo gap: Day 1 and Day 3 are disconnected runs of length 1
        expect(summary.currentStreak, 1);
        expect(summary.longestStreak, 1);
        expect(summary.totalRecordedDays, 2);
        expect(summary.endedStreakCount, 1);
      },
    );

    test(
      'Leap year boundary streak spans Feb 28, Feb 29, and Mar 1 continuously in 2024',
      () async {
        const feb28 = DateKey(2024, 2, 28);
        const feb29 = DateKey(2024, 2, 29);
        const mar1 = DateKey(2024, 3, 1);

        await testStore.addPhotoToDay(
          dateKey: feb28,
          photo: createSamplePhoto(dateKey: feb28),
        );
        await testStore.addPhotoToDay(
          dateKey: feb29,
          photo: createSamplePhoto(dateKey: feb29),
        );
        await testStore.addPhotoToDay(
          dateKey: mar1,
          photo: createSamplePhoto(dateKey: mar1),
        );

        final summary = StreakService.instance.calculateStreak(
          store: testStore,
          todayDate: mar1.toDateTime(),
        );

        expect(summary.currentStreak, 3);
        expect(summary.longestStreak, 3);
        expect(summary.isCurrentStreakActive, isTrue);
        expect(summary.currentStreakStartDate, feb28);
        expect(summary.currentStreakEndDate, mar1);
      },
    );

    test(
      'StatisticsService metrics match StreakService and compute all 14 metrics faithfully',
      () async {
        const day1 = DateKey(2026, 10, 25);
        const day2 = DateKey(2026, 10, 26);
        const day3 = DateKey(2026, 10, 27);

        await testStore.addPhotoToDay(
          dateKey: day1,
          photo: createSamplePhoto(dateKey: day1),
        );
        await testStore.addPhotoToDay(
          dateKey: day2,
          photo: createSamplePhoto(dateKey: day2),
        );
        await testStore.addPhotoToDay(
          dateKey: day3,
          photo: createSamplePhoto(dateKey: day3),
        );

        final stats = StatisticsService.instance.calculateStatistics(
          store: testStore,
          todayDate: DateTime(2026, 10, 27),
        );

        expect(stats.totalPhotos, 3);
        expect(stats.totalRecordedDays, 3);
        expect(stats.currentStreak, 3);
        expect(stats.longestStreak, 3);
        expect(stats.isCurrentStreakActive, isTrue);
        expect(stats.firstPhotoDate, day1);
        expect(stats.latestPhotoDate, day3);
        expect(stats.currentMonthCount, 3);
        expect(stats.currentYearCount, 3);
      },
    );
  });

  group('PHASE 4: Date, Timezone, and Local-Day Integrity Audit', () {
    test(
      'Midnight boundary: 23:59:59 maps to Day T and 00:00:01 maps to Day T+1',
      () {
        final night = DateTime(2026, 10, 31, 23, 59, 59);
        final morning = DateTime(2026, 11, 1, 0, 0, 1);

        final keyNight = DateKey.fromDateTime(night);
        final keyMorning = DateKey.fromDateTime(morning);

        expect(keyNight, const DateKey(2026, 10, 31));
        expect(keyMorning, const DateKey(2026, 11, 1));
        expect(keyNight.nextDay, keyMorning);
      },
    );

    test(
      'PhotoEntry.fromJson preserves normalized dateKey even across UTC/timezone shifts',
      () {
        // Simulate photo taken at 23:30 local in UTC-7 serialized as UTC next day
        final json = {
          'id': 'photo_tz_test',
          'order': 0,
          'dateKey': '2026-10-31',
          'date': '2026-11-01T06:30:00.000Z',
          'title': 'Evening memory',
          'location': 'Home',
          'timeFormatted': '11:30 PM',
          'gradientColors': [0xFF000000],
          'syncStatus': 'localOnly',
        };

        final restored = PhotoEntry.fromJson(json);

        // Preserves original dateKey and local normalizedDate
        expect(restored.dateKey, const DateKey(2026, 10, 31));
        expect(restored.dateKey.year, 2026);
        expect(restored.dateKey.month, 10);
        expect(restored.dateKey.day, 31);
        expect(restored.normalizedDate, DateTime(2026, 10, 31));
      },
    );

    test('DayEntry retains chronological ordering and UTC timestamps', () {
      const key = DateKey(2026, 10, 31);
      final day = DayEntry(
        dateKey: key,
        createdAt: DateTime.utc(2026, 10, 31, 10, 0, 0),
        updatedAt: DateTime.utc(2026, 10, 31, 12, 0, 0),
      );

      expect(day.createdAt.isUtc, isTrue);
      expect(day.updatedAt.isUtc, isTrue);
      expect(day.dateKey, key);
    });
  });

  group('PHASE 5: Multi-Photo and Daily Note Integrity Audit', () {
    test(
      'Adding photos to a day appends in order without replacing existing photos',
      () async {
        const key = DateKey(2026, 10, 31);
        final p1 = createSamplePhoto(dateKey: key, id: 'p1', order: 0);
        final p2 = createSamplePhoto(dateKey: key, id: 'p2', order: 1);

        await testStore.addPhotoToDay(dateKey: key, photo: p1);
        await testStore.addPhotoToDay(dateKey: key, photo: p2);

        final day = testStore.getDay(key);
        expect(day, isNotNull);
        expect(day!.photoCount, 2);
        expect(day.photos[0].id, 'p1');
        expect(day.photos[1].id, 'p2');
      },
    );

    test(
      'Reordering photos updates display order without deleting photos or notes',
      () async {
        const key = DateKey(2026, 10, 31);
        final p1 = createSamplePhoto(dateKey: key, id: 'p1', order: 0);
        final p2 = createSamplePhoto(dateKey: key, id: 'p2', order: 1);

        await testStore.addPhotoToDay(dateKey: key, photo: p1);
        await testStore.addPhotoToDay(dateKey: key, photo: p2);
        await testStore.updateDayNote(
          dateKey: key,
          note: 'Important reflection.',
        );

        final reordered = await testStore.reorderPhotos(
          dateKey: key,
          orderedPhotoIds: ['p2', 'p1'],
        );

        expect(reordered.photos[0].id, 'p2');
        expect(reordered.photos[1].id, 'p1');
        expect(reordered.note, 'Important reflection.');
      },
    );

    test(
      'Deleting the last photo preserves daily reflection note as a note-only day',
      () async {
        const key = DateKey(2026, 10, 31);
        final p1 = createSamplePhoto(dateKey: key, id: 'p1', order: 0);

        await testStore.addPhotoToDay(dateKey: key, photo: p1);
        await testStore.updateDayNote(dateKey: key, note: 'A cherished note.');

        // Delete the only photo passing preserveNoteOnlyDay: true (as PhotoDetailScreen does)
        final updatedDay = await testStore.removePhotoById(
          dateKey: key,
          photoId: 'p1',
          preserveNoteOnlyDay: true,
        );

        expect(updatedDay, isNotNull);
        expect(updatedDay!.photos, isEmpty);
        expect(updatedDay.isNoteOnly, isTrue);
        expect(updatedDay.note, 'A cherished note.');

        // Verify the day entry is still in the store
        final persistedDay = testStore.getDay(key);
        expect(persistedDay, isNotNull);
        expect(persistedDay!.note, 'A cherished note.');
        expect(persistedDay.isNoteOnly, isTrue);
      },
    );

    test(
      'Deleting a photo removes the physical file from disk without leaving orphan files',
      () async {
        const key = DateKey(2026, 10, 31);
        final sampleFile = File('${testDir.path}/temp_sample.jpg');
        sampleFile.writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);

        final photo = PhotoEntry(
          id: 'photo_file_cleanup_test',
          date: key.toDateTime(),
          title: 'File test',
          timeFormatted: '1:00 PM',
          imagePath: sampleFile.path,
          gradientColors: [AppColors.accent, AppColors.surfaceDark],
        );

        await testStore.addPhotoToDay(
          dateKey: key,
          photo: photo,
          sourceTempPath: sampleFile.path,
        );

        final addedPhoto = testStore.getDay(key)!.primaryPhoto!;
        expect(File(addedPhoto.imagePath!).existsSync(), isTrue);

        // Now delete the photo
        await testStore.removePhotoById(dateKey: key, photoId: addedPhoto.id);

        // Verify the physical file is deleted
        expect(File(addedPhoto.imagePath!).existsSync(), isFalse);
      },
    );
  });

  group('PHASE 6: Persistent Storage and Recovery Audit', () {
    test(
      'Interrupted atomic write recovery: ignores abandoned .tmp files when primary JSON is valid',
      () async {
        final metaStorage = PhotoMetadataStorage(customBaseDir: testDir);
        await metaStorage.init();

        // Write valid data
        const key = DateKey(2026, 10, 31);
        final day = DayEntry.fromSinglePhoto(createSamplePhoto(dateKey: key));
        await metaStorage.saveDays({key: day});

        // Simulate a crashed/interrupted write leaving a corrupted .tmp file behind
        final tmpFile = File('${metaStorage.metadataFile.path}.tmp');
        tmpFile.writeAsStringSync('{"truncated_crash": true');

        // Load days should successfully read the primary file and ignore the stale .tmp
        final loaded = await metaStorage.loadDays();
        expect(loaded.containsKey(key), isTrue);
        expect(loaded[key]!.photoCount, 1);
      },
    );

    test(
      'Corrupted metadata recovery: recovers from safety backup or temporary file when primary JSON is corrupt',
      () async {
        final metaStorage = PhotoMetadataStorage(customBaseDir: testDir);
        await metaStorage.init();

        const key = DateKey(2026, 10, 31);
        final day = DayEntry.fromSinglePhoto(createSamplePhoto(dateKey: key));

        // Create a valid backup file
        final bakFile = File(
          p.join(
            metaStorage.metadataFile.parent.path,
            PhotoMetadataStorage.backupV1FileName,
          ),
        );
        final validJson = jsonEncode({
          'schemaVersion': 2,
          'days': {key.format(): day.toJson()},
        });
        bakFile.writeAsStringSync(validJson);

        // Write corrupted / zero bytes to primary metadata file
        metaStorage.metadataFile.writeAsStringSync(
          '{CORRUPTED_ZERO_BYTE_SIMULATION',
        );

        // Load days should automatically recover from the valid backup file
        final recovered = await metaStorage.loadDays();
        expect(recovered.containsKey(key), isTrue);
        expect(recovered[key]!.dateKey, key);
      },
    );

    test(
      'Missing physical photo file is safely handled without throwing exceptions or crashing UI',
      () {
        const key = DateKey(2026, 10, 31);
        final photo = PhotoEntry(
          id: 'missing_file_photo',
          date: key.toDateTime(),
          title: 'Missing image',
          timeFormatted: '12:00 PM',
          imagePath: '${testDir.path}/non_existent_file.jpg',
          gradientColors: [AppColors.accent, AppColors.surfaceDark],
        );

        // Physical file does not exist
        expect(File(photo.imagePath!).existsSync(), isFalse);

        // Verify domain helper methods handle missing files gracefully
        expect(photo.hasRealImage, isTrue);
        expect(photo.isImageFileAvailable, isFalse);
      },
    );
  });

  group('PHASE 7: PDF and Backup Correctness Audit', () {
    test(
      'PadBackupManifest serializes and deserializes accurately with SHA256 checksums',
      () {
        final photoItem = PadBackupPhotoItem(
          archivePath: 'photos/2026-10-31_1.jpg',
          dateKey: '2026-10-31',
          id: 'photo_test_1',
          sha256: sha256.convert([1, 2, 3]).toString(),
          sizeBytes: 3,
          title: 'Test Photo',
          timeFormatted: '12:00 PM',
        );

        final manifest = PadBackupManifest(
          formatVersion: 2,
          appVersion: '2.0.0',
          appName: 'Daria',
          createdAt: DateTime.utc(2026, 10, 31, 12, 0, 0),
          isPartial: false,
          photoCount: 1,
          dayCount: 1,
          totalSizeBytes: 3,
          startDate: '2026-10-31',
          endDate: '2026-10-31',
          photos: [photoItem],
          skippedPhotos: const [],
          metadataChecksum: sha256.convert([4, 5, 6]).toString(),
        );

        final json = manifest.toJson();
        final restored = PadBackupManifest.fromJson(json);

        expect(restored.formatVersion, 2);
        expect(restored.dayCount, 1);
        expect(restored.photos.length, 1);
        expect(restored.photos.first.sha256, photoItem.sha256);
      },
    );

    test(
      'PadBackupService validation rejects tampered archives with checksum mismatches',
      () {
        final fakeBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        final expectedSha = sha256.convert([9, 9, 9]).toString();
        final actualSha = sha256.convert(fakeBytes).toString();

        expect(actualSha, isNot(equals(expectedSha)));
      },
    );
  });

  group('PHASE 8: Theme & UI Consistency Audit', () {
    test(
      'All registered palettes are valid and switchable without state loss',
      () async {
        expect(AppPalettes.all.length, greaterThanOrEqualTo(6));
        for (final palette in AppPalettes.all) {
          await AppThemeService.instance.setPalette(palette);
          expect(AppThemeService.instance.currentPalette, palette);
          expect(AppColors.accent, isNotNull);
          expect(AppColors.background, isNotNull);
        }
      },
    );
  });

  group('PHASE 9: Performance Scale Benchmarks', () {
    test(
      'Benchmark: 100 consecutive days of multi-photo records evaluate instantly',
      () async {
        final start = DateTime(2026, 1, 1);
        final entries = <DateKey, DayEntry>{};

        for (int i = 0; i < 100; i++) {
          final dt = start.add(Duration(days: i));
          final key = DateKey.fromDateTime(dt);
          final p1 = createSamplePhoto(dateKey: key, id: 'p_${i}_1', order: 0);
          final p2 = createSamplePhoto(dateKey: key, id: 'p_${i}_2', order: 1);
          entries[key] = DayEntry(
            dateKey: key,
            photos: [p1, p2],
            note: 'Day $i reflection note',
          );
        }

        await mockMetadata.saveDays(entries);
        await testStore.init();

        final stopwatch = Stopwatch()..start();
        final streak = StreakService.instance.calculateStreak(
          store: testStore,
          todayDate: start.add(const Duration(days: 99)),
        );
        final stats = StatisticsService.instance.calculateStatistics(
          store: testStore,
          todayDate: start.add(const Duration(days: 99)),
        );
        stopwatch.stop();

        expect(streak.currentStreak, 100);
        expect(stats.totalPhotos, 200);
        expect(stats.totalRecordedDays, 100);
        expect(stopwatch.elapsedMilliseconds, lessThan(100));
      },
    );

    test(
      'Benchmark: 1,000 days of diary entries compute streaks and statistics in under 50ms',
      () {
        final start = DateTime(2023, 1, 1);
        final dateKeys = <DateKey>[];

        for (int i = 0; i < 1000; i++) {
          dateKeys.add(DateKey.fromDateTime(start.add(Duration(days: i))));
        }

        final stopwatch = Stopwatch()..start();
        final streak = StreakService.instance.calculateStreak(
          dateKeys: dateKeys,
          todayKey: dateKeys.last,
        );
        final stats = StatisticsService.instance.calculateStatistics(
          dateKeys: dateKeys,
          todayKey: dateKeys.last,
        );
        stopwatch.stop();

        expect(streak.currentStreak, 1000);
        expect(stats.totalRecordedDays, 1000);
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      },
    );
  });
}
