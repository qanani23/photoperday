@Timeout(Duration(seconds: 90))
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/day_entry.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/data/services/statistics_service.dart';
import 'package:photo_per_day/data/services/streak_service.dart';

void main() {
  group('Milestone 58 — Multi-Photo Daily Entries & Daily Notes: Data Layer', () {
    late Directory tempDir;
    late PhotoFileManager fileManager;
    late PhotoMetadataStorage metadataStorage;
    late PersistentDailyPhotoStore store;

    File createDummySourcePhoto(
      String name, {
      String content = 'synthetic-bytes',
    }) {
      final sourceDir = Directory('${tempDir.path}/temp_sources');
      if (!sourceDir.existsSync()) sourceDir.createSync(recursive: true);
      final file = File('${sourceDir.path}/$name');
      file.writeAsStringSync('$content-for-$name');
      return file;
    }

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('m58_multiphoto_test_');
      fileManager = PhotoFileManager(customBaseDir: tempDir);
      metadataStorage = PhotoMetadataStorage(customBaseDir: tempDir);
      await fileManager.init();
      await metadataStorage.init();

      store = PersistentDailyPhotoStore(
        fileManager: fileManager,
        metadataStorage: metadataStorage,
      );
      await store.init(customBaseDir: tempDir);
    });

    tearDown(() {
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    // 1. One photo on a day and multiple photos on the same day
    test(
      '1. One photo and multiple photos on the same day accumulate cleanly',
      () async {
        final date = DateTime(2026, 9, 12, 10, 0);
        final key = DateKey.fromDateTime(date);

        final dummy1 = createDummySourcePhoto('photo1.jpg', content: 'bytes1');
        final first = await store.savePhoto(
          entry: PhotoEntry(
            date: date,
            title: 'Morning Shot',
            gradientColors: const [Colors.amber, Colors.orange],
          ),
          sourceTempPath: dummy1.path,
        );

        expect(store.totalDays, 1);
        expect(store.totalPhotos, 1);
        final day1 = store.getDay(key);
        expect(day1, isNotNull);
        expect(day1!.photoCount, 1);
        expect(day1.primaryPhoto!.id, equals(first.id));
        expect(day1.note, isEmpty);

        // Add a second photo to the same day
        final dummy2 = createDummySourcePhoto('photo2.jpg', content: 'bytes2');
        final second = await store.savePhoto(
          entry: PhotoEntry(
            date: date.add(const Duration(hours: 4)),
            title: 'Afternoon Shot',
            gradientColors: const [Colors.blue, Colors.cyan],
          ),
          sourceTempPath: dummy2.path,
        );

        expect(store.totalDays, 1);
        expect(store.totalPhotos, 2);
        final day2 = store.getDay(key);
        expect(day2!.photoCount, 2);
        expect(day2.photos[0].id, equals(first.id));
        expect(day2.photos[1].id, equals(second.id));

        // Add a third photo via addPhotoToDay
        final dummy3 = createDummySourcePhoto('photo3.jpg', content: 'bytes3');
        final third = await store.addPhotoToDay(
          dateKey: key,
          photo: PhotoEntry(
            date: date.add(const Duration(hours: 8)),
            title: 'Evening Shot',
            gradientColors: const [Colors.purple, Colors.deepPurple],
          ),
          sourceTempPath: dummy3.path,
        );

        expect(store.totalDays, 1);
        expect(store.totalPhotos, 3);
        final day3 = store.getDay(key);
        expect(day3!.photoCount, 3);
        expect(
          day3.photos.map((p) => p.id),
          containsAll([first.id, second.id, third.id]),
        );
      },
    );

    // 2. Adding photos across different days
    test(
      '2. Adding photos across different days maintains separate day entries',
      () async {
        const key1 = DateKey(2026, 9, 12);
        const key2 = DateKey(2026, 9, 13);
        const key3 = DateKey(2026, 9, 14);

        final d1 = createDummySourcePhoto('day1_1.jpg');
        final d2 = createDummySourcePhoto('day1_2.jpg');
        final d3 = createDummySourcePhoto('day2_1.jpg');
        final d4 = createDummySourcePhoto('day3_1.jpg');

        await store.savePhoto(
          entry: PhotoEntry(
            date: key1.toDateTime(hour: 9),
            title: 'Day 1 Photo 1',
            gradientColors: const [Colors.red, Colors.pink],
          ),
          sourceTempPath: d1.path,
        );
        await store.savePhoto(
          entry: PhotoEntry(
            date: key1.toDateTime(hour: 14),
            title: 'Day 1 Photo 2',
            gradientColors: const [Colors.red, Colors.deepOrange],
          ),
          sourceTempPath: d2.path,
        );

        await store.savePhoto(
          entry: PhotoEntry(
            date: key2.toDateTime(hour: 12),
            title: 'Day 2 Photo 1',
            gradientColors: const [Colors.green, Colors.teal],
          ),
          sourceTempPath: d3.path,
        );

        await store.savePhoto(
          entry: PhotoEntry(
            date: key3.toDateTime(hour: 18),
            title: 'Day 3 Photo 1',
            gradientColors: const [Colors.blue, Colors.indigo],
          ),
          sourceTempPath: d4.path,
        );

        expect(store.totalDays, 3);
        expect(store.totalPhotos, 4);
        expect(store.getDay(key1)!.photoCount, 2);
        expect(store.getDay(key2)!.photoCount, 1);
        expect(store.getDay(key3)!.photoCount, 1);
      },
    );

    // 3. Stable IDs and photo ordering
    test(
      '3. Photo IDs remain stable when reordering photos within a day',
      () async {
        const key = DateKey(2026, 9, 15);
        final d1 = createDummySourcePhoto('order1.jpg');
        final d2 = createDummySourcePhoto('order2.jpg');
        final d3 = createDummySourcePhoto('order3.jpg');

        final p1 = await store.savePhoto(
          entry: PhotoEntry(
            date: key.toDateTime(hour: 8),
            title: 'First',
            gradientColors: const [Colors.orange, Colors.red],
          ),
          sourceTempPath: d1.path,
        );
        final p2 = await store.savePhoto(
          entry: PhotoEntry(
            date: key.toDateTime(hour: 12),
            title: 'Second',
            gradientColors: const [Colors.green, Colors.teal],
          ),
          sourceTempPath: d2.path,
        );
        final p3 = await store.savePhoto(
          entry: PhotoEntry(
            date: key.toDateTime(hour: 18),
            title: 'Third',
            gradientColors: const [Colors.blue, Colors.purple],
          ),
          sourceTempPath: d3.path,
        );

        expect(p1.id, isNotEmpty);
        expect(p2.id, isNotEmpty);
        expect(p3.id, isNotEmpty);
        expect({p1.id, p2.id, p3.id}.length, 3);

        final originalDay = store.getDay(key)!;
        expect(originalDay.photos.map((p) => p.id).toList(), [
          p1.id,
          p2.id,
          p3.id,
        ]);

        // Reorder: 3rd photo first, then 1st, then 2nd
        final reorderedDay = await store.reorderPhotos(
          dateKey: key,
          orderedPhotoIds: [p3.id, p1.id, p2.id],
        );

        expect(reorderedDay.photos.map((p) => p.id).toList(), [
          p3.id,
          p1.id,
          p2.id,
        ]);
        expect(reorderedDay.photos[0].id, p3.id);
        expect(reorderedDay.photos[0].imagePath, p3.imagePath);
        expect(reorderedDay.photos[0].order, 0);
        expect(reorderedDay.photos[1].id, p1.id);
        expect(reorderedDay.photos[1].order, 1);
        expect(reorderedDay.photos[2].id, p2.id);
        expect(reorderedDay.photos[2].order, 2);

        // Verify persistence after reload
        final reloadedStore = PersistentDailyPhotoStore(
          fileManager: fileManager,
          metadataStorage: metadataStorage,
        );
        await reloadedStore.init(customBaseDir: tempDir);
        final restoredDay = reloadedStore.getDay(key)!;
        expect(restoredDay.photos.map((p) => p.id).toList(), [
          p3.id,
          p1.id,
          p2.id,
        ]);
      },
    );

    // 4. Note creation, editing, persistence, and restoration after store restart
    test(
      '4. Daily note can be created, updated, persisted, and restored across restarts',
      () async {
        const key = DateKey(2026, 9, 16);
        final dummy = createDummySourcePhoto('note_photo.jpg');

        await store.savePhoto(
          entry: PhotoEntry(
            date: key.toDateTime(),
            title: 'Day with Note',
            gradientColors: const [Colors.teal, Colors.cyan],
          ),
          sourceTempPath: dummy.path,
        );

        expect(store.getDay(key)!.note, isEmpty);

        // Add a note
        await store.updateDayNote(
          dateKey: key,
          note: 'Had a wonderful picnic in the park.',
        );
        expect(store.getDay(key)!.note, 'Had a wonderful picnic in the park.');

        // Update the note
        await store.updateDayNote(
          dateKey: key,
          note: 'Had a wonderful picnic in the park, then watched the sunset!',
        );
        expect(
          store.getDay(key)!.note,
          'Had a wonderful picnic in the park, then watched the sunset!',
        );

        // Cold restart
        final newStore = PersistentDailyPhotoStore(
          fileManager: fileManager,
          metadataStorage: metadataStorage,
        );
        await newStore.init(customBaseDir: tempDir);

        final loadedDay = newStore.getDay(key);
        expect(loadedDay, isNotNull);
        expect(
          loadedDay!.note,
          'Had a wonderful picnic in the park, then watched the sunset!',
        );
        expect(loadedDay.photoCount, 1);
        expect(loadedDay.primaryPhoto!.title, 'Day with Note');
      },
    );

    // 5. Individual photo deletion and deletion of the last photo
    test(
      '5. Individual photo deletion prunes photo file and prunes day entry when last photo is removed',
      () async {
        const key = DateKey(2026, 9, 17);
        final d1 = createDummySourcePhoto('del1.jpg');
        final d2 = createDummySourcePhoto('del2.jpg');

        final p1 = await store.savePhoto(
          entry: PhotoEntry(
            date: key.toDateTime(hour: 10),
            title: 'Photo 1',
            gradientColors: const [Colors.amber, Colors.orange],
          ),
          sourceTempPath: d1.path,
        );
        final p2 = await store.savePhoto(
          entry: PhotoEntry(
            date: key.toDateTime(hour: 15),
            title: 'Photo 2',
            gradientColors: const [Colors.blue, Colors.indigo],
          ),
          sourceTempPath: d2.path,
        );

        final p1Path = p1.imagePath!;
        final p2Path = p2.imagePath!;
        expect(File(p1Path).existsSync(), isTrue);
        expect(File(p2Path).existsSync(), isTrue);

        await store.updateDayNote(dateKey: key, note: 'A day with two photos');

        // Remove photo 1
        final remainingDay = await store.removePhotoById(
          dateKey: key,
          photoId: p1.id,
        );
        expect(remainingDay, isNotNull);
        expect(remainingDay!.photoCount, 1);
        expect(remainingDay.photos.first.id, p2.id);
        expect(remainingDay.note, 'A day with two photos');
        expect(
          File(p1Path).existsSync(),
          isFalse,
          reason: 'Deleted photo file must be pruned',
        );
        expect(
          File(p2Path).existsSync(),
          isTrue,
          reason: 'Other photo file must remain intact',
        );
        expect(store.totalPhotos, 1);
        expect(store.totalDays, 1);

        // Remove photo 2 (the last photo)
        final afterLastDay = await store.removePhotoById(
          dateKey: key,
          photoId: p2.id,
        );
        expect(afterLastDay, isNull, reason: 'Empty day entry must be pruned');
        expect(File(p2Path).existsSync(), isFalse);
        expect(store.totalPhotos, 0);
        expect(store.totalDays, 0);
        expect(store.hasDay(key), isFalse);
      },
    );

    // 6. Explicit confirmation required for deleteDayEntry
    test(
      '6. deleteDayEntry requires explicit confirmation and cleans up all photo files',
      () async {
        const key = DateKey(2026, 9, 18);
        final d1 = createDummySourcePhoto('day_del1.jpg');
        final d2 = createDummySourcePhoto('day_del2.jpg');

        final p1 = await store.savePhoto(
          entry: PhotoEntry(
            date: key.toDateTime(hour: 9),
            title: 'Day Shot 1',
            gradientColors: const [Colors.red, Colors.pink],
          ),
          sourceTempPath: d1.path,
        );
        final p2 = await store.savePhoto(
          entry: PhotoEntry(
            date: key.toDateTime(hour: 16),
            title: 'Day Shot 2',
            gradientColors: const [Colors.deepOrange, Colors.orange],
          ),
          sourceTempPath: d2.path,
        );

        // Unconfirmed deletion does nothing
        final unconfirmedResult = await store.deleteDayEntry(
          dateKey: key,
          confirmed: false,
        );
        expect(unconfirmedResult, isFalse);
        expect(store.hasDay(key), isTrue);
        expect(File(p1.imagePath!).existsSync(), isTrue);
        expect(File(p2.imagePath!).existsSync(), isTrue);

        // Confirmed deletion cleans up day and files
        final confirmedResult = await store.deleteDayEntry(
          dateKey: key,
          confirmed: true,
        );
        expect(confirmedResult, isTrue);
        expect(store.hasDay(key), isFalse);
        expect(store.totalDays, 0);
        expect(store.totalPhotos, 0);
        expect(File(p1.imagePath!).existsSync(), isFalse);
        expect(File(p2.imagePath!).existsSync(), isFalse);
      },
    );

    // 7. Same-day addition never replacing existing photos
    test(
      '7. Same-day additions never replace existing photos or files',
      () async {
        final date = DateTime(2026, 9, 19);
        final d1 = createDummySourcePhoto(
          'preserve1.jpg',
          content: 'unique-bytes-1',
        );
        final d2 = createDummySourcePhoto(
          'preserve2.jpg',
          content: 'unique-bytes-2',
        );

        final first = await store.savePhoto(
          entry: PhotoEntry(
            date: date,
            title: 'First Never Replaced',
            gradientColors: const [Colors.cyan, Colors.blue],
          ),
          sourceTempPath: d1.path,
        );

        final second = await store.savePhoto(
          entry: PhotoEntry(
            date: date,
            title: 'Second Coexists',
            gradientColors: const [Colors.teal, Colors.green],
          ),
          sourceTempPath: d2.path,
        );

        expect(first.imagePath, isNot(equals(second.imagePath)));
        expect(
          File(first.imagePath!).readAsStringSync(),
          'unique-bytes-1-for-preserve1.jpg',
        );
        expect(
          File(second.imagePath!).readAsStringSync(),
          'unique-bytes-2-for-preserve2.jpg',
        );
        expect(store.totalPhotos, 2);
        expect(store.totalDays, 1);
      },
    );

    // 8. Day count versus total photo count
    test(
      '8. Day count and total photo count are calculated separately',
      () async {
        const d1 = DateKey(2026, 9, 20);
        const d2 = DateKey(2026, 9, 21);

        final f1 = createDummySourcePhoto('f1.jpg');
        final f2 = createDummySourcePhoto('f2.jpg');
        final f3 = createDummySourcePhoto('f3.jpg');

        await store.savePhoto(
          entry: PhotoEntry(
            date: d1.toDateTime(hour: 9),
            title: 'D1 P1',
            gradientColors: const [Colors.red, Colors.black],
          ),
          sourceTempPath: f1.path,
        );
        await store.savePhoto(
          entry: PhotoEntry(
            date: d1.toDateTime(hour: 14),
            title: 'D1 P2',
            gradientColors: const [Colors.red, Colors.black],
          ),
          sourceTempPath: f2.path,
        );
        await store.savePhoto(
          entry: PhotoEntry(
            date: d2.toDateTime(hour: 11),
            title: 'D2 P1',
            gradientColors: const [Colors.blue, Colors.black],
          ),
          sourceTempPath: f3.path,
        );

        expect(store.totalDays, 2);
        expect(store.totalPhotos, 3);
        expect(store.count, 3);
      },
    );

    // 9. Streaks and statistics count unique dates
    test(
      '9. Streaks and statistics count unique calendar dates regardless of photo count',
      () async {
        // Create 3 consecutive days, with day 1 having 3 photos, day 2 having 2 photos, day 3 having 1 photo
        final now = DateTime.now();
        final day1 = DateKey.fromDateTime(
          now.subtract(const Duration(days: 2)),
        );
        final day2 = DateKey.fromDateTime(
          now.subtract(const Duration(days: 1)),
        );
        final day3 = DateKey.fromDateTime(now);

        for (int i = 1; i <= 3; i++) {
          final dummy = createDummySourcePhoto('streak_d1_$i.jpg');
          await store.savePhoto(
            entry: PhotoEntry(
              date: day1.toDateTime(hour: 8 + i),
              title: 'D1 Photo $i',
              gradientColors: const [Colors.amber, Colors.orange],
            ),
            sourceTempPath: dummy.path,
          );
        }

        for (int i = 1; i <= 2; i++) {
          final dummy = createDummySourcePhoto('streak_d2_$i.jpg');
          await store.savePhoto(
            entry: PhotoEntry(
              date: day2.toDateTime(hour: 9 + i),
              title: 'D2 Photo $i',
              gradientColors: const [Colors.teal, Colors.cyan],
            ),
            sourceTempPath: dummy.path,
          );
        }

        final dummy3 = createDummySourcePhoto('streak_d3_1.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: day3.toDateTime(hour: 12),
            title: 'D3 Photo 1',
            gradientColors: const [Colors.purple, Colors.indigo],
          ),
          sourceTempPath: dummy3.path,
        );

        expect(store.totalDays, 3);
        expect(store.totalPhotos, 6);

        // Streak calculation
        final streak = StreakService.instance.calculateStreak(store: store);
        expect(
          streak.currentStreak,
          3,
          reason: 'Streak must count unique consecutive calendar days',
        );
        expect(streak.longestStreak, 3);

        // Statistics calculation
        final stats = StatisticsService.instance.calculateStatistics(
          store: store,
        );
        expect(
          stats.totalRecordedDays,
          3,
          reason: 'Stats total recorded days must be 3 calendar days',
        );
        expect(
          stats.totalPhotos,
          6,
          reason: 'Stats total photos must be 6 photos',
        );
      },
    );

    // 10. Migration from Schema 1 (one-photo-per-day metadata) to Schema 2
    test(
      '10. Safely migrates Schema 1 metadata, creates backup, and maps legacy caption to note',
      () async {
        final migrationDir = Directory.systemTemp.createTempSync(
          'm58_migration_test_',
        );
        addTearDown(() {
          try {
            if (migrationDir.existsSync()) {
              migrationDir.deleteSync(recursive: true);
            }
          } catch (_) {}
        });

        // Write synthetic legacy Schema 1 metadata: list of PhotoEntry json objects
        final metadataFile = File('${migrationDir.path}/photos_metadata.json');
        final legacyList = [
          {
            'dateKey': '2026-09-01',
            'date': '2026-09-01T10:00:00.000',
            'title': 'Legacy Sunset',
            'gradientColors': [4294951168, 4294924800],
            'imagePath': '${migrationDir.path}/legacy_sunset.jpg',
            'caption': 'Legacy caption from old version',
            'syncStatus': 'localOnly',
            'createdAt': '2026-09-01T10:00:00.000',
          },
          {
            'dateKey': '2026-09-02',
            'date': '2026-09-02T12:00:00.000',
            'title': 'Legacy Beach',
            'gradientColors': [4278241535, 4278222847],
            'imagePath': null,
            'syncStatus': 'localOnly',
            'createdAt': '2026-09-02T12:00:00.000',
          },
        ];
        await metadataFile.writeAsString(jsonEncode(legacyList));

        final migFileManager = PhotoFileManager(customBaseDir: migrationDir);
        final migMetadataStorage = PhotoMetadataStorage(
          customBaseDir: migrationDir,
        );
        await migFileManager.init();
        await migMetadataStorage.init();

        // Trigger migration by loading days
        final days = await migMetadataStorage.loadDays();
        expect(days.length, 2);

        // Verify backup file exists
        final backupFile = File('${migrationDir.path}/photos_metadata.v1.bak');
        expect(
          backupFile.existsSync(),
          isTrue,
          reason: 'Safety backup must be created before migration',
        );

        final day1 = days[const DateKey(2026, 9, 1)];
        expect(day1, isNotNull);
        expect(day1!.photos.length, 1);
        expect(day1.photos.first.title, 'Legacy Sunset');
        expect(
          day1.note,
          'Legacy caption from old version',
          reason: 'Legacy caption must be mapped to note',
        );

        final day2 = days[const DateKey(2026, 9, 2)];
        expect(day2, isNotNull);
        expect(day2!.photos.length, 1);
        expect(day2.photos.first.title, 'Legacy Beach');
        expect(day2.note, isEmpty);

        // Verify metadata file was upgraded to Schema 2
        final rawMigrated =
            jsonDecode(await metadataFile.readAsString())
                as Map<String, dynamic>;
        expect(rawMigrated['schemaVersion'], 2);
        expect(rawMigrated['days'], isA<Map>());
      },
    );

    // 11. Repeated migration/restart without duplication or data loss (idempotency)
    test(
      '11. Reopening/restarting store repeatedly is idempotent with no data loss or duplicates',
      () async {
        const key = DateKey(2026, 9, 22);
        final dummy = createDummySourcePhoto('idempotent.jpg');

        await store.savePhoto(
          entry: PhotoEntry(
            date: key.toDateTime(hour: 11),
            title: 'Idempotent Photo',
            gradientColors: const [Colors.teal, Colors.green],
          ),
          sourceTempPath: dummy.path,
        );
        await store.updateDayNote(
          dateKey: key,
          note: 'Persistent note content',
        );

        // Reopen 3 times
        for (int i = 0; i < 3; i++) {
          final reloaded = PersistentDailyPhotoStore(
            fileManager: fileManager,
            metadataStorage: metadataStorage,
          );
          await reloaded.init(customBaseDir: tempDir);

          expect(reloaded.totalDays, 1);
          expect(reloaded.totalPhotos, 1);
          final day = reloaded.getDay(key);
          expect(day, isNotNull);
          expect(day!.photos.length, 1);
          expect(day.photos.first.title, 'Idempotent Photo');
          expect(day.note, 'Persistent note content');
        }
      },
    );

    // 12. Simulated metadata-write failure and rollback
    test(
      '12. In-memory store rolls back cleanly if metadata save fails',
      () async {
        const key = DateKey(2026, 9, 23);
        final failingStorage = _FailingMetadataStorage(customBaseDir: tempDir);
        await failingStorage.init();

        final isolatedStore = PersistentDailyPhotoStore(
          fileManager: fileManager,
          metadataStorage: failingStorage,
        );
        await isolatedStore.init(customBaseDir: tempDir);

        final dummy = createDummySourcePhoto('fail_test.jpg');

        // Now enable write failure
        failingStorage.shouldFail = true;

        await expectLater(
          isolatedStore.savePhoto(
            entry: PhotoEntry(
              date: key.toDateTime(),
              title: 'Will Fail',
              gradientColors: const [Colors.red, Colors.black],
            ),
            sourceTempPath: dummy.path,
          ),
          throwsA(isA<IOException>()),
        );

        // Verify in-memory store remains consistent (not corrupted)
        expect(isolatedStore.hasDay(key), isFalse);
        expect(isolatedStore.totalDays, 0);
        expect(isolatedStore.totalPhotos, 0);
      },
    );

    // 13. Preservation of original photo bytes and file paths
    test(
      '13. Adding subsequent photos preserves exact byte content and paths of previous photos',
      () async {
        const key = DateKey(2026, 9, 24);
        final d1 = createDummySourcePhoto(
          'exact1.jpg',
          content: 'EXACT_BYTES_ONE',
        );
        final d2 = createDummySourcePhoto(
          'exact2.jpg',
          content: 'EXACT_BYTES_TWO',
        );

        final p1 = await store.savePhoto(
          entry: PhotoEntry(
            date: key.toDateTime(hour: 9),
            title: 'Photo 1',
            gradientColors: const [Colors.amber, Colors.red],
          ),
          sourceTempPath: d1.path,
        );
        final p1Path = p1.imagePath!;
        final p1BytesBefore = await File(p1Path).readAsString();

        final p2 = await store.savePhoto(
          entry: PhotoEntry(
            date: key.toDateTime(hour: 15),
            title: 'Photo 2',
            gradientColors: const [Colors.blue, Colors.cyan],
          ),
          sourceTempPath: d2.path,
        );
        final p2Path = p2.imagePath!;

        // Verify p1 bytes were unchanged
        final p1BytesAfter = await File(p1Path).readAsString();
        expect(p1BytesAfter, equals(p1BytesBefore));
        expect(p1BytesAfter, contains('EXACT_BYTES_ONE'));

        final p2Bytes = await File(p2Path).readAsString();
        expect(p2Bytes, contains('EXACT_BYTES_TWO'));
        expect(p1Path, isNot(equals(p2Path)));
      },
    );
  });
}

class _FailingMetadataStorage extends PhotoMetadataStorage {
  bool shouldFail = false;

  _FailingMetadataStorage({super.customBaseDir});

  @override
  Future<void> saveDays(Map<DateKey, DayEntry> entries) async {
    if (shouldFail) {
      throw const FileSystemException('Simulated disk failure');
    }
    return super.saveDays(entries);
  }
}
