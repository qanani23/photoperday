import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestone 15 — Offline Reliability & Local-First Hardening Tests', () {
    late Directory tempDir;
    late PhotoFileManager fileManager;
    late PhotoMetadataStorage metadataStorage;
    late PersistentDailyPhotoStore store;

    File createDummySourcePhoto(
      String name, {
      String content = 'dummy-photo-content',
    }) {
      final sourceDir = Directory('${tempDir.path}/temp_sources');
      if (!sourceDir.existsSync()) sourceDir.createSync(recursive: true);
      final file = File('${sourceDir.path}/$name');
      file.writeAsStringSync(content);
      return file;
    }

    PhotoEntry createTestEntry({
      required DateTime date,
      required String title,
      String? caption,
      String? location,
      String? imagePath,
      String timeFormatted = '2:45 PM',
    }) {
      return PhotoEntry(
        date: date,
        title: title,
        caption: caption,
        location: location,
        imagePath: imagePath,
        timeFormatted: timeFormatted,
        gradientColors: const [Colors.blue, Colors.purple],
      );
    }

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('m15_offline_test_');
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

    // ==========================================
    // 1. STARTUP RELIABILITY & TOLERANCE
    // ==========================================
    group('1. Offline Startup Reliability & Tolerance', () {
      test('Store starts cleanly when no metadata file exists', () async {
        final freshDir = Directory.systemTemp.createTempSync(
          'm15_empty_startup_',
        );
        addTearDown(() => freshDir.deleteSync(recursive: true));

        final emptyStore = PersistentDailyPhotoStore();
        await emptyStore.init(customBaseDir: freshDir);

        expect(emptyStore.isInitialized, isTrue);
        expect(emptyStore.totalPhotos, 0);
        expect(emptyStore.allEntries, isEmpty);
      });

      test(
        'Store recovers and initializes gracefully when metadata JSON is corrupt',
        () async {
          final corruptDir = Directory.systemTemp.createTempSync(
            'm15_corrupt_startup_',
          );
          addTearDown(() => corruptDir.deleteSync(recursive: true));

          final metaFile = File('${corruptDir.path}/photos_metadata.json');
          metaFile.writeAsStringSync('{{{ malformed json content !!!');

          final resilientStore = PersistentDailyPhotoStore();
          await resilientStore.init(customBaseDir: corruptDir);

          expect(resilientStore.isInitialized, isTrue);
          expect(resilientStore.totalPhotos, 0);
        },
      );

      test(
        'Non-critical orphan cleanup failure during init does not crash startup',
        () async {
          final testDir = Directory.systemTemp.createTempSync(
            'm15_orphan_fail_startup_',
          );
          addTearDown(() => testDir.deleteSync(recursive: true));

          // Create a faulty file manager that simulates an exception during prune
          final faultyManager = _FailingPhotoFileManager(
            customBaseDir: testDir,
          );
          final faultyMeta = PhotoMetadataStorage(customBaseDir: testDir);

          final safeStore = PersistentDailyPhotoStore(
            fileManager: faultyManager,
            metadataStorage: faultyMeta,
          );

          // Even though orphan cleanup throws an internal exception, init() MUST succeed
          await expectLater(safeStore.init(customBaseDir: testDir), completes);
          expect(safeStore.isInitialized, isTrue);
        },
      );

      test(
        'App restart cleanly restores persisted photo records and DateKeys',
        () async {
          final date = DateTime(2026, 5, 20);
          final dummy = createDummySourcePhoto('restart_test.jpg');
          final entry = createTestEntry(
            date: date,
            title: 'Preserved After Restart',
            caption: 'Local diary record',
            location: 'Home Studio',
          );

          await store.savePhoto(entry: entry, sourceTempPath: dummy.path);
          expect(store.hasPhoto(date), isTrue);

          // Simulate app kill and cold restart
          final restartedStore = PersistentDailyPhotoStore(
            fileManager: fileManager,
            metadataStorage: metadataStorage,
          );
          await restartedStore.init(customBaseDir: tempDir);

          expect(restartedStore.hasPhoto(date), isTrue);
          final loaded = restartedStore.getPhoto(date);
          expect(loaded, isNotNull);
          expect(loaded!.title, 'Preserved After Restart');
          expect(loaded.isImageFileAvailable, isTrue);
        },
      );
    });

    // ==========================================
    // 2. OFFLINE PHOTO DIARY LIFECYCLE
    // ==========================================
    group('2. Offline Photo Diary Lifecycle', () {
      test(
        'Camera-originated photo persists and survives restart completely offline',
        () async {
          final date = DateTime(2026, 6, 1);
          final cameraFile = createDummySourcePhoto('camera_capture_raw.jpg');

          final entry = createTestEntry(
            date: date,
            title: 'Sunset at Beach',
            caption: 'Captured offline via camera',
            location: 'Pacific Beach',
            timeFormatted: '7:42 PM',
          );

          final saved = await store.savePhoto(
            entry: entry,
            sourceTempPath: cameraFile.path,
          );

          expect(saved.hasRealImage, isTrue);
          expect(fileManager.isManagedPath(saved.imagePath!), isTrue);

          // Simulate restart
          final restartedStore = PersistentDailyPhotoStore(
            fileManager: fileManager,
            metadataStorage: metadataStorage,
          );
          await restartedStore.init(customBaseDir: tempDir);

          final restored = restartedStore.getPhoto(date);
          expect(restored, isNotNull);
          expect(restored!.title, 'Sunset at Beach');
          expect(restored.imagePath, saved.imagePath);
        },
      );

      test(
        'Gallery-originated photo is copied to app-owned persistent storage',
        () async {
          final date = DateTime(2026, 6, 2);
          final galleryFile = createDummySourcePhoto(
            'gallery_pick_external.jpg',
          );

          final entry = createTestEntry(
            date: date,
            title: 'Gallery Import',
            caption: 'Selected from photo library',
          );

          final saved = await store.savePhoto(
            entry: entry,
            sourceTempPath: galleryFile.path,
          );

          // Stored path must NOT be the external temporary source path
          expect(saved.imagePath, isNot(equals(galleryFile.path)));
          expect(fileManager.isManagedPath(saved.imagePath!), isTrue);
          expect(File(saved.imagePath!).existsSync(), isTrue);

          // If the external gallery file is deleted, app photo remains safe
          galleryFile.deleteSync();
          expect(File(saved.imagePath!).existsSync(), isTrue);
        },
      );

      test(
        'Editing title, caption, location offline persists and survives restart',
        () async {
          final date = DateTime(2026, 6, 3);
          final dummy = createDummySourcePhoto('edit_test.jpg');
          final initial = createTestEntry(
            date: date,
            title: 'Initial Title',
            caption: 'Initial Caption',
            location: 'Initial Location',
          );

          final saved = await store.savePhoto(
            entry: initial,
            sourceTempPath: dummy.path,
          );

          // Perform edit
          final updated = await store.updatePhotoMetadata(
            dateKey: saved.dateKey,
            title: 'Updated Offline Title',
            caption: 'Updated Offline Caption',
            location: 'Updated Offline Location',
          );

          expect(updated.title, 'Updated Offline Title');
          expect(
            updated.imagePath,
            saved.imagePath,
          ); // File is never duplicated

          // Restart
          final restartedStore = PersistentDailyPhotoStore(
            fileManager: fileManager,
            metadataStorage: metadataStorage,
          );
          await restartedStore.init(customBaseDir: tempDir);

          final restored = restartedStore.getPhoto(date);
          expect(restored!.title, 'Updated Offline Title');
          expect(restored.caption, 'Updated Offline Caption');
          expect(restored.location, 'Updated Offline Location');
        },
      );

      test(
        'Replacing photo offline preserves single-photo-per-day DateKey enforcement',
        () async {
          final date = DateTime(2026, 6, 4);
          final dummy1 = createDummySourcePhoto('first_shot.jpg');
          final dummy2 = createDummySourcePhoto('second_shot.jpg');

          final firstEntry = createTestEntry(date: date, title: 'First Shot');
          final firstSaved = await store.savePhoto(
            entry: firstEntry,
            sourceTempPath: dummy1.path,
          );
          final firstDiskPath = firstSaved.imagePath!;

          // Replace on same date
          final secondEntry = createTestEntry(
            date: date,
            title: 'Replacement Shot',
          );
          final secondSaved = await store.savePhoto(
            entry: secondEntry,
            sourceTempPath: dummy2.path,
          );
          final secondDiskPath = secondSaved.imagePath!;

          expect(store.totalPhotos, 1);
          expect(store.getPhoto(date)!.title, 'Replacement Shot');
          expect(File(secondDiskPath).existsSync(), isTrue);
          expect(
            File(firstDiskPath).existsSync(),
            isFalse,
          ); // Old file cleaned up
        },
      );

      test(
        'Deleting photo offline cleanly removes metadata and file',
        () async {
          final date = DateTime(2026, 6, 5);
          final dummy = createDummySourcePhoto('delete_offline.jpg');

          final saved = await store.savePhoto(
            entry: createTestEntry(date: date, title: 'To Delete'),
            sourceTempPath: dummy.path,
          );
          final diskPath = saved.imagePath!;
          expect(File(diskPath).existsSync(), isTrue);

          await store.removePhotoAsync(date);

          expect(store.hasPhoto(date), isFalse);
          expect(File(diskPath).existsSync(), isFalse);

          // Restart confirms deletion
          final restartedStore = PersistentDailyPhotoStore(
            fileManager: fileManager,
            metadataStorage: metadataStorage,
          );
          await restartedStore.init(customBaseDir: tempDir);
          expect(restartedStore.hasPhoto(date), isFalse);
        },
      );

      test(
        'Deleting and recreating photo on same DateKey offline succeeds and persists',
        () async {
          final date = DateTime(2026, 6, 6);
          final dummy1 = createDummySourcePhoto('original.jpg');
          final dummy2 = createDummySourcePhoto('recreated.jpg');

          // 1. Create photo
          await store.savePhoto(
            entry: createTestEntry(date: date, title: 'Original Memory'),
            sourceTempPath: dummy1.path,
          );

          // 2. Delete photo
          await store.removePhotoAsync(date);
          expect(store.hasPhoto(date), isFalse);

          // 3. Recreate photo on the exact same date
          final recreated = await store.savePhoto(
            entry: createTestEntry(date: date, title: 'Recreated Memory'),
            sourceTempPath: dummy2.path,
          );

          expect(store.totalPhotos, 1);
          expect(store.getPhoto(date)!.title, 'Recreated Memory');
          expect(File(recreated.imagePath!).existsSync(), isTrue);

          // 4. Restart confirms recreation
          final restartedStore = PersistentDailyPhotoStore(
            fileManager: fileManager,
            metadataStorage: metadataStorage,
          );
          await restartedStore.init(customBaseDir: tempDir);
          expect(restartedStore.getPhoto(date)!.title, 'Recreated Memory');
        },
      );
    });

    // ==========================================
    // 3. WRITE QUEUE SERIALIZATION & CONCURRENCY
    // ==========================================
    group('3. Write Serialization & Concurrency', () {
      test(
        'Rapid consecutive metadata edits serialize properly without losing updates',
        () async {
          final date = DateTime(2026, 7, 1);
          final dummy = createDummySourcePhoto('rapid_edit.jpg');
          final initial = createTestEntry(date: date, title: 'Original');
          final saved = await store.savePhoto(
            entry: initial,
            sourceTempPath: dummy.path,
          );

          // Fire multiple edits in rapid un-awaited succession
          final f1 = store.updatePhotoMetadata(
            dateKey: saved.dateKey,
            title: 'Edit 1',
          );
          final f2 = store.updatePhotoMetadata(
            dateKey: saved.dateKey,
            title: 'Edit 2',
          );
          final f3 = store.updatePhotoMetadata(
            dateKey: saved.dateKey,
            title: 'Edit 3 (Final)',
          );

          await Future.wait([f1, f2, f3]);

          expect(store.getPhoto(date)!.title, 'Edit 3 (Final)');

          // Cold restart verification
          final restartedStore = PersistentDailyPhotoStore(
            fileManager: fileManager,
            metadataStorage: metadataStorage,
          );
          await restartedStore.init(customBaseDir: tempDir);
          expect(restartedStore.getPhoto(date)!.title, 'Edit 3 (Final)');
        },
      );

      test(
        'Photo replacement immediately followed by deletion executes cleanly',
        () async {
          final date = DateTime(2026, 7, 2);
          final dummy1 = createDummySourcePhoto('rep_del1.jpg');
          final dummy2 = createDummySourcePhoto('rep_del2.jpg');

          await store.savePhoto(
            entry: createTestEntry(date: date, title: 'First'),
            sourceTempPath: dummy1.path,
          );

          // Fire replacement and immediate deletion concurrently
          final repFuture = store.savePhoto(
            entry: createTestEntry(date: date, title: 'Second Replaced'),
            sourceTempPath: dummy2.path,
          );
          final delFuture = store.removePhotoAsync(date);

          await Future.wait([repFuture, delFuture]);

          expect(store.hasPhoto(date), isFalse);
          expect(store.totalPhotos, 0);

          // Cold restart confirms clean empty state
          final restartedStore = PersistentDailyPhotoStore(
            fileManager: fileManager,
            metadataStorage: metadataStorage,
          );
          await restartedStore.init(customBaseDir: tempDir);
          expect(restartedStore.hasPhoto(date), isFalse);
        },
      );

      test(
        'Double replacement on same DateKey retains only the final photo',
        () async {
          final date = DateTime(2026, 7, 3);
          final d1 = createDummySourcePhoto('double1.jpg');
          final d2 = createDummySourcePhoto('double2.jpg');
          final d3 = createDummySourcePhoto('double3.jpg');

          await store.savePhoto(
            entry: createTestEntry(date: date, title: 'V1'),
            sourceTempPath: d1.path,
          );

          // Fire two rapid replacements concurrently
          final r2 = store.savePhoto(
            entry: createTestEntry(date: date, title: 'V2'),
            sourceTempPath: d2.path,
          );
          final r3 = store.savePhoto(
            entry: createTestEntry(date: date, title: 'V3 (Final)'),
            sourceTempPath: d3.path,
          );

          await Future.wait([r2, r3]);

          expect(store.totalPhotos, 1);
          expect(store.getPhoto(date)!.title, 'V3 (Final)');

          // Only one managed photo file remains in photos directory
          final managedFiles = fileManager.photosDir
              .listSync()
              .whereType<File>()
              .toList();
          expect(managedFiles.length, 1);
        },
      );

      test(
        'Concurrent saves across different dates are safely serialized',
        () async {
          final date1 = DateTime(2026, 8, 1);
          final date2 = DateTime(2026, 8, 2);
          final date3 = DateTime(2026, 8, 3);

          final d1 = createDummySourcePhoto('batch1.jpg');
          final d2 = createDummySourcePhoto('batch2.jpg');
          final d3 = createDummySourcePhoto('batch3.jpg');

          final s1 = store.savePhoto(
            entry: createTestEntry(date: date1, title: 'Day 1'),
            sourceTempPath: d1.path,
          );
          final s2 = store.savePhoto(
            entry: createTestEntry(date: date2, title: 'Day 2'),
            sourceTempPath: d2.path,
          );
          final s3 = store.savePhoto(
            entry: createTestEntry(date: date3, title: 'Day 3'),
            sourceTempPath: d3.path,
          );

          await Future.wait([s1, s2, s3]);

          expect(store.totalPhotos, 3);
          expect(store.hasPhoto(date1), isTrue);
          expect(store.hasPhoto(date2), isTrue);
          expect(store.hasPhoto(date3), isTrue);
        },
      );
    });

    // ==========================================
    // 4. STORAGE FAILURES & DECODE FALLBACKS
    // ==========================================
    group('4. Storage Failures & Fallback Resilience', () {
      test(
        'Missing source file rejects cleanly and preserves existing photo',
        () async {
          final date = DateTime(2026, 9, 1);
          final validDummy = createDummySourcePhoto('existing.jpg');
          final existing = await store.savePhoto(
            entry: createTestEntry(date: date, title: 'Existing Valid'),
            sourceTempPath: validDummy.path,
          );

          // Attempt replace with non-existent file
          await expectLater(
            store.savePhoto(
              entry: createTestEntry(date: date, title: 'Ghost Attempt'),
              sourceTempPath: '${tempDir.path}/does_not_exist_file.jpg',
            ),
            throwsA(isA<FileSystemException>()),
          );

          // Existing photo is preserved untouched
          expect(store.getPhoto(date)!.title, 'Existing Valid');
          expect(store.getPhoto(date)!.imagePath, existing.imagePath);
        },
      );

      test(
        'Empty (0-byte) source photo rejects cleanly and preserves existing photo',
        () async {
          final date = DateTime(2026, 9, 2);
          final validDummy = createDummySourcePhoto('valid_pre.jpg');
          final existing = await store.savePhoto(
            entry: createTestEntry(date: date, title: 'Existing Valid'),
            sourceTempPath: validDummy.path,
          );

          // Create 0-byte file
          final emptyFile = createDummySourcePhoto(
            'empty_0byte.jpg',
            content: '',
          );

          await expectLater(
            store.savePhoto(
              entry: createTestEntry(date: date, title: 'Empty Attempt'),
              sourceTempPath: emptyFile.path,
            ),
            throwsA(isA<FileSystemException>()),
          );

          // Existing photo is preserved
          expect(store.getPhoto(date)!.title, 'Existing Valid');
          expect(store.getPhoto(date)!.imagePath, existing.imagePath);
        },
      );

      test(
        'Rollback on metadata save failure removes newly copied image file',
        () async {
          final date = DateTime(2026, 9, 3);
          final dummy = createDummySourcePhoto('fail_meta.jpg');

          // Create store with failing metadata storage
          final failingMeta = _FailingPhotoMetadataStorage(
            customBaseDir: tempDir,
          );
          await failingMeta.init();

          final failingStore = PersistentDailyPhotoStore(
            fileManager: fileManager,
            metadataStorage: failingMeta,
          );
          await failingStore.init(); // Keep injected failingMeta!

          failingMeta.shouldFail = true;

          await expectLater(
            failingStore.savePhoto(
              entry: createTestEntry(date: date, title: 'Failed Meta'),
              sourceTempPath: dummy.path,
            ),
            throwsException,
          );

          // In-memory cache was not corrupted
          expect(failingStore.hasPhoto(date), isFalse);

          // Newly copied file was pruned by rollback
          final managedFiles = fileManager.photosDir
              .listSync()
              .whereType<File>()
              .toList();
          expect(managedFiles, isEmpty);
        },
      );

      test(
        'Missing disk image file returns isImageFileAvailable == false gracefully',
        () async {
          final date = DateTime(2026, 9, 4);
          final dummy = createDummySourcePhoto('vanish.jpg');
          final saved = await store.savePhoto(
            entry: createTestEntry(date: date, title: 'Vanishing Photo'),
            sourceTempPath: dummy.path,
          );

          expect(saved.isImageFileAvailable, isTrue);

          // Manually delete the file from disk (simulating external cleaner)
          File(saved.imagePath!).deleteSync();

          final fetched = store.getPhoto(date);
          expect(fetched, isNotNull);
          expect(fetched!.hasRealImage, isTrue);
          expect(fetched.isImageFileAvailable, isFalse); // Safe fallback
        },
      );

      test(
        'Orphaned files from interrupted writes are swept cleanly on restart',
        () async {
          // Manually drop an orphaned file into the managed photos directory
          final orphanPath =
              '${fileManager.photosDir.path}/2026-09-05_111111111111.jpg';
          File(orphanPath).writeAsStringSync('abandoned-temp-bytes');
          expect(File(orphanPath).existsSync(), isTrue);

          // Restarting the store runs reconcileOrphanFiles() automatically
          final restartedStore = PersistentDailyPhotoStore(
            fileManager: fileManager,
            metadataStorage: metadataStorage,
          );
          await restartedStore.init(customBaseDir: tempDir);

          // Orphaned file must have been cleanly pruned
          expect(File(orphanPath).existsSync(), isFalse);
        },
      );
    });
  });
}

/// Helper mock for simulating non-critical orphan cleanup errors
class _FailingPhotoFileManager extends PhotoFileManager {
  _FailingPhotoFileManager({super.customBaseDir});

  @override
  Future<List<String>> pruneUnreferencedPhotos(
    Set<String> referencedAbsolutePaths,
  ) async {
    throw const FileSystemException('Simulated disk I/O lock during prune');
  }
}

/// Helper mock for simulating metadata disk write failures
class _FailingPhotoMetadataStorage extends PhotoMetadataStorage {
  _FailingPhotoMetadataStorage({super.customBaseDir});

  bool shouldFail = false;

  @override
  Future<void> saveAll(Map<DateKey, PhotoEntry> entries) async {
    if (shouldFail) {
      throw const FileSystemException('Simulated disk full error');
    }
    return super.saveAll(entries);
  }
}
