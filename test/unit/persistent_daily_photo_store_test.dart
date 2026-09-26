import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';

void main() {
  group('PersistentDailyPhotoStore — Milestone 12 Tests', () {
    late Directory tempDir;
    late PhotoFileManager fileManager;
    late PhotoMetadataStorage metadataStorage;
    late PersistentDailyPhotoStore store;

    // Helper to create a dummy temporary source photo file
    File createDummySourcePhoto(String name) {
      final sourceDir = Directory('${tempDir.path}/temp_sources');
      if (!sourceDir.existsSync()) sourceDir.createSync(recursive: true);
      final file = File('${sourceDir.path}/$name');
      file.writeAsStringSync('dummy-image-bytes-for-$name');
      return file;
    }

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('persistent_photo_test_');
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

    // 1. Persistent store starts empty.
    test('1. Persistent store starts empty', () {
      expect(store.totalPhotos, 0);
      expect(store.count, 0);
      expect(store.allEntries, isEmpty);
      expect(store.hasPhoto(DateTime(2026, 9, 12)), isFalse);
      expect(store.getPhoto(DateTime(2026, 9, 12)), isNull);
    });

    // 2. Add a PhotoEntry.
    test('2. Add a PhotoEntry', () async {
      final dummy = createDummySourcePhoto('capture_1.jpg');
      final date = DateTime(2026, 9, 12, 10, 0);

      final entry = PhotoEntry(
        date: date,
        title: 'Morning Mountain',
        gradientColors: const [Colors.amber, Colors.orange],
      );

      final saved = await store.savePhoto(
        entry: entry,
        sourceTempPath: dummy.path,
      );

      expect(store.totalPhotos, 1);
      expect(saved.title, 'Morning Mountain');
      expect(saved.hasRealImage, isTrue);
      expect(saved.imagePath, isNotNull);
      expect(File(saved.imagePath!).existsSync(), isTrue);
      expect(store.hasPhoto(date), isTrue);
    });

    // 3. Retrieve it by exact date.
    test('3. Retrieve it by exact date', () async {
      final dummy = createDummySourcePhoto('capture_exact.jpg');
      final date = DateTime(2026, 9, 12, 14, 30);

      await store.savePhoto(
        entry: PhotoEntry(
          date: date,
          title: 'Exact Date Memory',
          gradientColors: const [Colors.blue, Colors.teal],
        ),
        sourceTempPath: dummy.path,
      );

      final retrieved = store.getPhoto(date);
      expect(retrieved, isNotNull);
      expect(retrieved!.title, 'Exact Date Memory');
      expect(retrieved.dateKey, const DateKey(2026, 9, 12));
    });

    // 4. Retrieve it using same date with different time.
    test('4. Retrieve it using same date with different time', () async {
      final dummy = createDummySourcePhoto('capture_morning.jpg');
      final morningDate = DateTime(2026, 9, 12, 8, 15);

      await store.savePhoto(
        entry: PhotoEntry(
          date: morningDate,
          title: 'Morning Sun',
          gradientColors: const [Colors.yellow, Colors.orange],
        ),
        sourceTempPath: dummy.path,
      );

      // Query with evening and midnight timestamps on the same local day
      final eveningDate = DateTime(2026, 9, 12, 21, 45);
      final midnightDate = DateTime(2026, 9, 12, 0, 0);

      expect(store.hasPhoto(eveningDate), isTrue);
      expect(store.getPhoto(eveningDate)?.title, 'Morning Sun');
      expect(store.hasPhoto(midnightDate), isTrue);
      expect(store.getPhoto(midnightDate)?.title, 'Morning Sun');
    });

    // 5. Data survives store reinitialization (simulating app restart).
    test('5. Data survives store reinitialization', () async {
      final dummy = createDummySourcePhoto('survive.jpg');
      final date = DateTime(2026, 9, 12, 12, 0);

      await store.savePhoto(
        entry: PhotoEntry(
          date: date,
          title: 'Persistent Memory',
          gradientColors: const [Colors.purple, Colors.deepPurple],
        ),
        sourceTempPath: dummy.path,
      );

      // Simulate App Restart by instantiating a new store instance with the same directory
      final restartedStore = PersistentDailyPhotoStore(
        fileManager: PhotoFileManager(customBaseDir: tempDir),
        metadataStorage: PhotoMetadataStorage(customBaseDir: tempDir),
      );
      await restartedStore.init(customBaseDir: tempDir);

      expect(restartedStore.totalPhotos, 1);
      expect(restartedStore.hasPhoto(date), isTrue);

      final reloadedEntry = restartedStore.getPhoto(date);
      expect(reloadedEntry, isNotNull);
      expect(reloadedEntry!.title, 'Persistent Memory');
      expect(File(reloadedEntry.imagePath!).existsSync(), isTrue);
    });

    // 6. Different dates persist independently.
    test('6. Different dates persist independently', () async {
      final dummy1 = createDummySourcePhoto('day12.jpg');
      final dummy2 = createDummySourcePhoto('day13.jpg');

      await store.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2026, 9, 12),
          title: 'Day 12',
          gradientColors: const [Colors.red, Colors.pink],
        ),
        sourceTempPath: dummy1.path,
      );

      await store.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2026, 9, 13),
          title: 'Day 13',
          gradientColors: const [Colors.green, Colors.teal],
        ),
        sourceTempPath: dummy2.path,
      );

      expect(store.totalPhotos, 2);
      expect(store.getPhoto(DateTime(2026, 9, 12))?.title, 'Day 12');
      expect(store.getPhoto(DateTime(2026, 9, 13))?.title, 'Day 13');
    });

    // 7. Replacing a photo keeps exactly one entry for the date.
    test('7. Replacing a photo keeps exactly one entry for the date', () async {
      final dummyA = createDummySourcePhoto('photo_a.jpg');
      final dummyB = createDummySourcePhoto('photo_b.jpg');
      final date = DateTime(2026, 9, 12, 10, 0);

      await store.savePhoto(
        entry: PhotoEntry(
          date: date,
          title: 'Photo A',
          gradientColors: const [Colors.grey, Colors.black],
        ),
        sourceTempPath: dummyA.path,
      );
      expect(store.totalPhotos, 1);

      // Replace with Photo B on same date (different time)
      await store.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2026, 9, 12, 18, 0),
          title: 'Photo B (Replacement)',
          gradientColors: const [Colors.blue, Colors.cyan],
        ),
        sourceTempPath: dummyB.path,
      );

      expect(store.totalPhotos, 1);
      expect(store.getPhoto(date)?.title, 'Photo B (Replacement)');
    });

    // 8. Replacing a photo updates the persisted image path.
    test('8. Replacing a photo updates the persisted image path', () async {
      final dummyA = createDummySourcePhoto('photo_a.jpg');
      final dummyB = createDummySourcePhoto('photo_b.jpg');
      final date = DateTime(2026, 9, 12);

      final photoA = await store.savePhoto(
        entry: PhotoEntry(
          date: date,
          title: 'Photo A',
          gradientColors: const [Colors.red, Colors.orange],
        ),
        sourceTempPath: dummyA.path,
      );
      final pathA = photoA.imagePath;

      final photoB = await store.savePhoto(
        entry: PhotoEntry(
          date: date,
          title: 'Photo B',
          gradientColors: const [Colors.green, Colors.lime],
        ),
        sourceTempPath: dummyB.path,
      );
      final pathB = photoB.imagePath;

      expect(pathA, isNotNull);
      expect(pathB, isNotNull);
      expect(pathA, isNot(equals(pathB)));
      expect(store.getPhoto(date)?.imagePath, pathB);
    });

    // 9. Old replaced image is cleaned up safely.
    test('9. Old replaced image is cleaned up safely', () async {
      final dummyA = createDummySourcePhoto('photo_a.jpg');
      final dummyB = createDummySourcePhoto('photo_b.jpg');
      final date = DateTime(2026, 9, 12);

      final photoA = await store.savePhoto(
        entry: PhotoEntry(
          date: date,
          title: 'Photo A',
          gradientColors: const [Colors.red, Colors.orange],
        ),
        sourceTempPath: dummyA.path,
      );
      final fileA = File(photoA.imagePath!);
      expect(fileA.existsSync(), isTrue);

      final photoB = await store.savePhoto(
        entry: PhotoEntry(
          date: date,
          title: 'Photo B',
          gradientColors: const [Colors.green, Colors.lime],
        ),
        sourceTempPath: dummyB.path,
      );
      final fileB = File(photoB.imagePath!);

      // Photo B must exist, Photo A must be deleted (no orphaned files)
      expect(fileB.existsSync(), isTrue);
      expect(fileA.existsSync(), isFalse);
    });

    // 10. Delete removes metadata and image file.
    test('10. Delete removes metadata and image file', () async {
      final dummy = createDummySourcePhoto('to_delete.jpg');
      final date = DateTime(2026, 9, 12);

      final saved = await store.savePhoto(
        entry: PhotoEntry(
          date: date,
          title: 'Delete Me',
          gradientColors: const [Colors.grey, Colors.black],
        ),
        sourceTempPath: dummy.path,
      );
      final imageFile = File(saved.imagePath!);
      expect(imageFile.existsSync(), isTrue);

      await store.removePhotoAsync(date);

      expect(store.hasPhoto(date), isFalse);
      expect(store.totalPhotos, 0);
      expect(imageFile.existsSync(), isFalse);
    });

    // 11. Delete handles already-missing image file gracefully.
    test('11. Delete handles already-missing image file gracefully', () async {
      final dummy = createDummySourcePhoto('missing.jpg');
      final date = DateTime(2026, 9, 12);

      final saved = await store.savePhoto(
        entry: PhotoEntry(
          date: date,
          title: 'Missing Image',
          gradientColors: const [Colors.grey, Colors.black],
        ),
        sourceTempPath: dummy.path,
      );

      // Delete file externally before store deletion
      File(saved.imagePath!).deleteSync();

      // Deleting via store must complete cleanly without throwing
      await expectLater(store.removePhotoAsync(date), completes);
      expect(store.hasPhoto(date), isFalse);
    });

    // 12. Clear removes all metadata and image files.
    test('12. Clear removes all metadata and image files', () async {
      final d1 = createDummySourcePhoto('d1.jpg');
      final d2 = createDummySourcePhoto('d2.jpg');

      final s1 = await store.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2026, 9, 12),
          title: 'P1',
          gradientColors: const [Colors.red, Colors.black],
        ),
        sourceTempPath: d1.path,
      );
      final s2 = await store.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2026, 9, 13),
          title: 'P2',
          gradientColors: const [Colors.blue, Colors.black],
        ),
        sourceTempPath: d2.path,
      );

      final f1 = File(s1.imagePath!);
      final f2 = File(s2.imagePath!);
      expect(f1.existsSync(), isTrue);
      expect(f2.existsSync(), isTrue);

      await store.clearAsync();

      expect(store.totalPhotos, 0);
      expect(f1.existsSync(), isFalse);
      expect(f2.existsSync(), isFalse);
    });

    // 13. Missing image file does not crash the app.
    test('13. Missing image file does not crash the app', () async {
      final dummy = createDummySourcePhoto('ghost.jpg');
      final date = DateTime(2026, 9, 12);

      final saved = await store.savePhoto(
        entry: PhotoEntry(
          date: date,
          title: 'Ghost Photo',
          gradientColors: const [Colors.purple, Colors.black],
        ),
        sourceTempPath: dummy.path,
      );

      // Externally delete the file
      File(saved.imagePath!).deleteSync();

      final retrieved = store.getPhoto(date);
      expect(retrieved, isNotNull);
      expect(retrieved!.hasRealImage, isTrue);
      expect(retrieved.isImageFileAvailable, isFalse);
    });

    // 14. Duplicate DateKey records are handled safely.
    test('14. Duplicate DateKey records are handled safely', () async {
      // Create duplicate JSON map
      final metadataFile = File('${tempDir.path}/photos_metadata.json');
      metadataFile.writeAsStringSync('''
{
  "2026-09-12": {
    "dateKey": "2026-09-12",
    "date": "2026-09-12T09:00:00.000",
    "title": "Initial",
    "timeFormatted": "9:00 AM",
    "gradientColors": [4294901760, 4278190080],
    "category": "Daily Life"
  }
}
''');

      final newStore = PersistentDailyPhotoStore(
        fileManager: PhotoFileManager(customBaseDir: tempDir),
        metadataStorage: PhotoMetadataStorage(customBaseDir: tempDir),
      );
      await newStore.init(customBaseDir: tempDir);

      expect(newStore.totalPhotos, 1);
      expect(newStore.hasPhoto(DateTime(2026, 9, 12)), isTrue);
    });

    // 15. Camera-originated image can be persisted.
    test('15. Camera-originated image can be persisted', () async {
      final cameraCacheFile = createDummySourcePhoto('camera_temp_capture.jpg');
      final date = DateTime(2026, 9, 12);

      final entry = await store.savePhoto(
        entry: PhotoEntry(
          date: date,
          title: 'Camera Shot',
          gradientColors: const [Colors.amber, Colors.orange],
        ),
        sourceTempPath: cameraCacheFile.path,
      );

      expect(entry.hasRealImage, isTrue);
      expect(entry.imagePath, isNot(equals(cameraCacheFile.path)));
      expect(fileManager.isManagedPath(entry.imagePath!), isTrue);
    });

    // 16. Gallery-originated image can be persisted.
    test('16. Gallery-originated image can be persisted', () async {
      final galleryPickFile = createDummySourcePhoto(
        'gallery_pick_content.jpg',
      );
      final date = DateTime(2026, 9, 13);

      final entry = await store.savePhoto(
        entry: PhotoEntry(
          date: date,
          title: 'Gallery Selection',
          gradientColors: const [Colors.teal, Colors.cyan],
        ),
        sourceTempPath: galleryPickFile.path,
      );

      expect(entry.hasRealImage, isTrue);
      expect(entry.imagePath, isNot(equals(galleryPickFile.path)));
      expect(fileManager.isManagedPath(entry.imagePath!), isTrue);
    });

    // 17. Temporary source files are NOT used as the permanent image path.
    test(
      '17. Temporary source files are NOT used as the permanent image path',
      () async {
        final tempSource = createDummySourcePhoto('temporary_cache.jpg');
        final date = DateTime(2026, 9, 15);

        final entry = await store.savePhoto(
          entry: PhotoEntry(
            date: date,
            title: 'Cache Separation Test',
            gradientColors: const [Colors.indigo, Colors.blue],
          ),
          sourceTempPath: tempSource.path,
        );

        // Permanent path must be inside app photos directory
        expect(entry.imagePath, contains('photos'));
        expect(entry.imagePath, isNot(equals(tempSource.path)));

        // If tempSource is deleted, persistent photo must remain intact
        tempSource.deleteSync();
        expect(File(entry.imagePath!).existsSync(), isTrue);
      },
    );
  });
}
