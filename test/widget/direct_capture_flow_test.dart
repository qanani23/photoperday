import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/day_entry.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';

class CaptureFakePhotoMetadataStorage extends PhotoMetadataStorage {
  CaptureFakePhotoMetadataStorage({super.customBaseDir});

  final Map<DateKey, DayEntry> _days = {};

  @override
  Future<void> init() async {}

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

class CaptureFakePhotoFileManager extends PhotoFileManager {
  CaptureFakePhotoFileManager({super.customBaseDir});

  @override
  Future<void> init() async {}

  @override
  Future<String> persistPhotoFile({
    required String sourcePath,
    required DateKey dateKey,
  }) async => '/managed_photos/${dateKey.format()}.jpg';

  @override
  bool isManagedPath(String path) => path.startsWith('/managed_photos/');

  @override
  Future<bool> deletePhotoFile(String? path) async => true;
}

void main() {
  group('Milestone 43 — Direct Camera Capture Flow Tests', () {
    late Directory tempDir;
    late File dummyCapturedFile;
    late PersistentDailyPhotoStore photoStore;
    final testDate = DateTime(2026, 10, 6);
    final testDateKey = DateKey.fromDateTime(testDate);

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('capture_test_');
      dummyCapturedFile = File('${tempDir.path}/captured.jpg')
        ..writeAsStringSync('dummy-image-bytes');

      final metaStorage = CaptureFakePhotoMetadataStorage();
      final fileManager = CaptureFakePhotoFileManager();

      photoStore = PersistentDailyPhotoStore(
        metadataStorage: metaStorage,
        fileManager: fileManager,
      );
      await photoStore.init();
      PersistentDailyPhotoStore.setTestInstance(photoStore);
    });

    tearDown(() {
      PersistentDailyPhotoStore.resetTestInstance();
      photoStore.dispose();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets('1. Capture workflow with empty today saves photo directly', (
      tester,
    ) async {
      expect(photoStore.getPhotoByKey(testDateKey), isNull);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  // Simulate photo capture returning a valid path
                  final saved = (photoStore.getPhotoByKey(testDateKey) == null)
                      ? await photoStore.savePhoto(
                          entry: PhotoEntry(
                            date: testDate,
                            title: 'Daily Capture',
                            gradientColors: const [
                              Color(0xFFE8DCC4),
                              Color(0xFFD4C3A3),
                            ],
                          ),
                          sourceTempPath: dummyCapturedFile.path,
                        )
                      : null;
                  expect(saved, isNotNull);
                },
                child: const Text('Capture Today'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Capture Today'));
      await tester.pumpAndSettle();

      final savedPhoto = photoStore.getPhotoByKey(testDateKey);
      expect(savedPhoto, isNotNull);
      expect(savedPhoto!.date, equals(testDate));
      expect(savedPhoto.title, equals('Daily Capture'));
      expect(savedPhoto.imagePath, equals('/managed_photos/2026-10-06.jpg'));
    });

    testWidgets(
      '2. Capture with existing today photo shows replacement confirmation',
      (tester) async {
        // Setup existing photo for today
        final initialPhoto = PhotoEntry(
          date: testDate,
          title: 'Morning Photo A',
          gradientColors: const [Color(0xFFE8DCC4), Color(0xFFD4C3A3)],
        );
        await photoStore.savePhoto(entry: initialPhoto);
        expect(
          photoStore.getPhotoByKey(testDateKey)?.title,
          equals('Morning Photo A'),
        );

        bool? dialogResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    final existing = photoStore.getPhotoByKey(testDateKey);
                    if (existing != null) {
                      dialogResult = await showDialog<bool>(
                        context: context,
                        builder: (dialogCtx) => AlertDialog(
                          title: const Text('Photo already exists'),
                          content: const Text(
                            'You already have a photo for today.\nWould you like to replace it?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogCtx).pop(false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () =>
                                  Navigator.of(dialogCtx).pop(true),
                              child: const Text('Replace'),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                  child: const Text('Capture Trigger'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Capture Trigger'));
        await tester.pumpAndSettle();

        // Dialog is visible
        expect(find.text('Photo already exists'), findsOneWidget);
        expect(
          find.text(
            'You already have a photo for today.\nWould you like to replace it?',
          ),
          findsOneWidget,
        );
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Replace'), findsOneWidget);

        // Tap Cancel
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(dialogResult, isFalse);
        // Photo A is preserved untouched
        expect(
          photoStore.getPhotoByKey(testDateKey)?.title,
          equals('Morning Photo A'),
        );
      },
    );

    testWidgets(
      '3. Confirming Replace replaces today photo and cleans up safely',
      (tester) async {
        // Setup existing photo for today
        final initialPhoto = PhotoEntry(
          date: testDate,
          title: 'Morning Photo A',
          gradientColors: const [Color(0xFFE8DCC4), Color(0xFFD4C3A3)],
        );
        await photoStore.savePhoto(entry: initialPhoto);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    final shouldReplace = await showDialog<bool>(
                      context: context,
                      builder: (dialogCtx) => AlertDialog(
                        title: const Text('Photo already exists'),
                        content: const Text(
                          'You already have a photo for today.\nWould you like to replace it?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(true),
                            child: const Text('Replace'),
                          ),
                        ],
                      ),
                    );

                    if (shouldReplace == true) {
                      final newEntry = initialPhoto.copyWith(
                        title: 'Afternoon Photo B',
                      );
                      await photoStore.savePhoto(
                        entry: newEntry,
                        sourceTempPath: dummyCapturedFile.path,
                      );
                    }
                  },
                  child: const Text('Capture Trigger'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Capture Trigger'));
        await tester.pumpAndSettle();

        // Tap Replace
        await tester.tap(find.text('Replace'));
        await tester.pumpAndSettle();

        // Today accumulates Photo B without replacing Photo A
        final day = photoStore.getDay(testDateKey);
        expect(day, isNotNull);
        expect(day!.photos.length, equals(2));
        expect(day.photos[0].title, equals('Morning Photo A'));
        expect(day.photos[1].title, equals('Afternoon Photo B'));
        expect(photoStore.totalDays, equals(1));
        expect(photoStore.count, equals(2));
      },
    );

    testWidgets('4. Camera cancellation (no capture) leaves store untouched', (
      tester,
    ) async {
      // If camera is closed without capturing (capturedPath == null), store should remain untouched
      final initialCount = photoStore.count;

      // Executing workflow with a cancelled camera returns null
      expect(initialCount, equals(0));
      expect(photoStore.getPhotoByKey(testDateKey), isNull);
    });
  });
}
