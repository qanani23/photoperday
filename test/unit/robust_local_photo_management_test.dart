import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';

void main() {
  group('Milestone 14 — Robust Local Photo Management & Optimization Tests', () {
    late Directory tempDir;
    late PhotoFileManager fileManager;
    late PhotoMetadataStorage metadataStorage;
    late PersistentDailyPhotoStore store;

    File createDummySourcePhoto(
      String name, {
      String content = 'sample-photo-data',
    }) {
      final sourceDir = Directory('${tempDir.path}/temp_sources');
      if (!sourceDir.existsSync()) sourceDir.createSync(recursive: true);
      final file = File('${sourceDir.path}/$name');
      file.writeAsStringSync(content);
      return file;
    }

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('m14_robust_photo_test_');
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
    // 1. PERSISTENT METADATA EDITING
    // ==========================================
    group('1. Persistent Metadata Editing', () {
      test('updates title, location and survives restart', () async {
        final date = DateTime(2026, 3, 10);
        final dummy = createDummySourcePhoto('orig.jpg');
        final initial = await store.savePhoto(
          entry: PhotoEntry(
            date: date,
            title: 'Initial Sunset',
            location: 'Griffith Park',
            gradientColors: const [Colors.orange, Colors.purple],
          ),
          sourceTempPath: dummy.path,
        );

        final origImagePath = initial.imagePath!;

        // Update metadata atomically
        final updated = await store.updatePhotoMetadata(
          dateKey: initial.dateKey,
          title: 'Vibrant Sunset Panorama',
          location: 'Observatory Peak',
        );

        expect(updated.title, 'Vibrant Sunset Panorama');
        expect(updated.location, 'Observatory Peak');
        // Image path must be completely untouched
        expect(updated.imagePath, equals(origImagePath));

        // Simulate app restart
        final restartedStore = PersistentDailyPhotoStore(
          fileManager: fileManager,
          metadataStorage: metadataStorage,
        );
        await restartedStore.init(customBaseDir: tempDir);

        final restored = restartedStore.getPhoto(date);
        expect(restored, isNotNull);
        expect(restored!.title, 'Vibrant Sunset Panorama');
        expect(restored.location, 'Observatory Peak');
        expect(restored.imagePath, equals(origImagePath));
        expect(restartedStore.count, 1);
      });

      test(
        'editing preserves DateKey identity and never duplicates photos',
        () async {
          final date = DateTime(2026, 3, 11);
          final dummy = createDummySourcePhoto('photo11.jpg');
          await store.savePhoto(
            entry: PhotoEntry(
              date: date,
              title: 'Original Title',
              gradientColors: const [Colors.blue, Colors.green],
            ),
            sourceTempPath: dummy.path,
          );

          expect(store.count, 1);

          // Multiple consecutive edits
          await store.updatePhotoMetadata(
            dateKey: DateKey.fromDateTime(date),
            title: 'First Edit',
          );
          await store.updatePhotoMetadata(
            dateKey: DateKey.fromDateTime(date),
            title: 'Second Edit',
            location: 'Added location',
          );

          expect(store.count, 1);
          expect(store.getPhoto(date)!.title, 'Second Edit');
          expect(store.getPhoto(date)!.location, 'Added location');
        },
      );

      test(
        'updating metadata on non-existent date throws StateError safely',
        () async {
          const unrecordedKey = DateKey(2026, 1, 1);
          expect(
            () => store.updatePhotoMetadata(
              dateKey: unrecordedKey,
              title: 'Ghost Photo',
            ),
            throwsStateError,
          );
        },
      );
    });

    // ==========================================
    // 2. SAFE PHOTO REPLACEMENT
    // ==========================================
    group('2. Safe Photo Replacement', () {
      test(
        'rejects non-existent source file and preserves existing photo',
        () async {
          final date = DateTime(2026, 3, 12);
          final dummy = createDummySourcePhoto(
            'first.jpg',
            content: 'initial-data',
          );
          final initial = await store.savePhoto(
            entry: PhotoEntry(
              date: date,
              title: 'Original Photo',
              gradientColors: const [Colors.red, Colors.yellow],
            ),
            sourceTempPath: dummy.path,
          );

          final initialPath = initial.imagePath!;
          expect(File(initialPath).existsSync(), isTrue);

          // Attempt replace with missing source file
          expect(
            () => store.savePhoto(
              entry: PhotoEntry(
                date: date,
                title: 'Failed Replacement',
                gradientColors: const [Colors.black, Colors.white],
              ),
              sourceTempPath: '${tempDir.path}/non_existent_file.jpg',
            ),
            throwsA(isA<FileSystemException>()),
          );

          // Existing photo MUST remain 100% intact
          final current = store.getPhoto(date);
          expect(current, isNotNull);
          expect(current!.title, 'Original Photo');
          expect(current.imagePath, equals(initialPath));
          expect(File(initialPath).existsSync(), isTrue);
        },
      );

      test(
        'rejects empty (0-byte) source file and preserves existing photo',
        () async {
          final date = DateTime(2026, 3, 13);
          final dummy = createDummySourcePhoto(
            'good.jpg',
            content: 'valid-data',
          );
          final initial = await store.savePhoto(
            entry: PhotoEntry(
              date: date,
              title: 'Valid Photo',
              gradientColors: const [Colors.cyan, Colors.blue],
            ),
            sourceTempPath: dummy.path,
          );

          final initialPath = initial.imagePath!;

          // Create 0-byte file
          final emptyFile = createDummySourcePhoto('empty.jpg', content: '');
          expect(emptyFile.lengthSync(), 0);

          expect(
            () => store.savePhoto(
              entry: PhotoEntry(
                date: date,
                title: 'Empty Replacement',
                gradientColors: const [Colors.black, Colors.grey],
              ),
              sourceTempPath: emptyFile.path,
            ),
            throwsA(isA<FileSystemException>()),
          );

          // Existing photo MUST remain 100% intact
          final current = store.getPhoto(date);
          expect(current, isNotNull);
          expect(current!.title, 'Valid Photo');
          expect(current.imagePath, equals(initialPath));
          expect(File(initialPath).existsSync(), isTrue);
        },
      );

      test(
        'saving a second photo to the same date preserves first photo and file (multi-photo accumulation)',
        () async {
          final date = DateTime(2026, 3, 14);
          final dummy1 = createDummySourcePhoto(
            'shot1.jpg',
            content: 'photo-1',
          );
          final dummy2 = createDummySourcePhoto(
            'shot2.jpg',
            content: 'photo-2',
          );

          final first = await store.savePhoto(
            entry: PhotoEntry(
              date: date,
              title: 'First Shot',
              gradientColors: const [Colors.amber, Colors.orange],
            ),
            sourceTempPath: dummy1.path,
          );
          final firstPath = first.imagePath!;
          expect(File(firstPath).existsSync(), isTrue);

          // Add second photo to same date
          final second = await store.savePhoto(
            entry: PhotoEntry(
              date: date,
              title: 'Second Shot',
              gradientColors: const [Colors.teal, Colors.indigo],
            ),
            sourceTempPath: dummy2.path,
          );
          final secondPath = second.imagePath!;

          expect(secondPath, isNot(equals(firstPath)));
          expect(File(secondPath).existsSync(), isTrue);
          expect(
            File(firstPath).existsSync(),
            isTrue,
            reason: 'First photo file must be preserved',
          );
          expect(store.count, 2);
          expect(store.totalDays, 1);
          final day = store.getDayByDate(date);
          expect(day!.photos.length, 2);
        },
      );
    });

    // ==========================================
    // 3. SAFE PHOTO DELETION
    // ==========================================
    group('3. Safe Photo Deletion', () {
      test('normal deletion removes metadata and file safely', () async {
        final date = DateTime(2026, 3, 15);
        final dummy = createDummySourcePhoto('del.jpg');
        final saved = await store.savePhoto(
          entry: PhotoEntry(
            date: date,
            title: 'To Delete',
            gradientColors: const [Colors.purple, Colors.pink],
          ),
          sourceTempPath: dummy.path,
        );
        final imagePath = saved.imagePath!;
        expect(File(imagePath).existsSync(), isTrue);

        await store.removePhotoAsync(date);

        expect(store.getPhoto(date), isNull);
        expect(store.count, 0);
        expect(File(imagePath).existsSync(), isFalse);
      });

      test(
        'deletion when image file is already missing succeeds without crashing',
        () async {
          final date = DateTime(2026, 3, 16);
          final dummy = createDummySourcePhoto('del_missing.jpg');
          final saved = await store.savePhoto(
            entry: PhotoEntry(
              date: date,
              title: 'Missing File Deletion',
              gradientColors: const [Colors.red, Colors.orange],
            ),
            sourceTempPath: dummy.path,
          );
          final imagePath = saved.imagePath!;

          // Manually delete file behind the store's back
          File(imagePath).deleteSync();
          expect(File(imagePath).existsSync(), isFalse);

          // removePhotoAsync must not throw
          await store.removePhotoAsync(date);

          expect(store.getPhoto(date), isNull);
          expect(store.count, 0);
        },
      );

      test('repeated deletion is safe and idempotent', () async {
        final date = DateTime(2026, 3, 17);

        // Delete date that never had a photo
        await store.removePhotoAsync(date);
        expect(store.getPhoto(date), isNull);

        // Add then delete twice
        final dummy = createDummySourcePhoto('repeat.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: date,
            title: 'Repeat Test',
            gradientColors: const [Colors.brown, Colors.amber],
          ),
          sourceTempPath: dummy.path,
        );
        expect(store.count, 1);

        await store.removePhotoAsync(date);
        expect(store.count, 0);

        // Second deletion
        await store.removePhotoAsync(date);
        expect(store.count, 0);
      });

      test('deleting one date leaves other dates completely intact', () async {
        final date1 = DateTime(2026, 3, 18);
        final date2 = DateTime(2026, 3, 19);
        final dummy1 = createDummySourcePhoto('multi1.jpg');
        final dummy2 = createDummySourcePhoto('multi2.jpg');

        final photo1 = await store.savePhoto(
          entry: PhotoEntry(
            date: date1,
            title: 'Stay Alive',
            gradientColors: const [Colors.green, Colors.teal],
          ),
          sourceTempPath: dummy1.path,
        );
        final photo2 = await store.savePhoto(
          entry: PhotoEntry(
            date: date2,
            title: 'Delete Me',
            gradientColors: const [Colors.red, Colors.pink],
          ),
          sourceTempPath: dummy2.path,
        );

        expect(store.count, 2);

        // Delete photo2
        await store.removePhotoAsync(date2);

        expect(store.count, 1);
        expect(store.getPhoto(date2), isNull);
        expect(File(photo2.imagePath!).existsSync(), isFalse);

        // Photo1 must be completely unaffected
        final check1 = store.getPhoto(date1);
        expect(check1, isNotNull);
        expect(check1!.title, 'Stay Alive');
        expect(File(photo1.imagePath!).existsSync(), isTrue);
      });

      test(
        'deletion followed by recreation creates a fresh photo successfully',
        () async {
          final date = DateTime(2026, 3, 20);
          final dummy1 = createDummySourcePhoto('cycle1.jpg');
          final dummy2 = createDummySourcePhoto('cycle2.jpg');

          await store.savePhoto(
            entry: PhotoEntry(
              date: date,
              title: 'Cycle 1',
              gradientColors: const [Colors.grey, Colors.blueGrey],
            ),
            sourceTempPath: dummy1.path,
          );
          expect(store.count, 1);

          await store.removePhotoAsync(date);
          expect(store.count, 0);

          // Recreate on same date
          final recreated = await store.savePhoto(
            entry: PhotoEntry(
              date: date,
              title: 'Cycle 2 Fresh',
              gradientColors: const [Colors.lime, Colors.green],
            ),
            sourceTempPath: dummy2.path,
          );

          expect(store.count, 1);
          expect(recreated.title, 'Cycle 2 Fresh');
          expect(File(recreated.imagePath!).existsSync(), isTrue);
        },
      );
    });

    // ==========================================
    // 4. ORPHANED FILE RECONCILIATION
    // ==========================================
    group('4. Orphaned File Reconciliation', () {
      test(
        'identifies and deletes unreferenced app-managed photo files',
        () async {
          final date = DateTime(2026, 3, 21);
          final dummy = createDummySourcePhoto('active.jpg');
          final activePhoto = await store.savePhoto(
            entry: PhotoEntry(
              date: date,
              title: 'Active Photo',
              gradientColors: const [Colors.amber, Colors.orange],
            ),
            sourceTempPath: dummy.path,
          );

          // Create an orphan file matching app naming pattern in photosDir
          final photosDir = fileManager.photosDir;
          final orphanFile = File(
            p.join(photosDir.path, '2026-03-21_999999999999.jpg'),
          );
          orphanFile.writeAsStringSync('abandoned-photo-bytes');
          expect(orphanFile.existsSync(), isTrue);

          // Create an unrelated file that does NOT match app pattern
          final foreignFile = File(p.join(photosDir.path, 'notes.txt'));
          foreignFile.writeAsStringSync('do-not-delete-me');
          expect(foreignFile.existsSync(), isTrue);

          // Run reconciliation
          final pruned = await store.reconcileOrphanFiles();

          expect(pruned, contains(orphanFile.path));
          expect(orphanFile.existsSync(), isFalse);

          // Active referenced photo MUST NOT be deleted
          expect(File(activePhoto.imagePath!).existsSync(), isTrue);

          // Foreign non-matching file MUST NOT be deleted
          expect(foreignFile.existsSync(), isTrue);
        },
      );
    });

    // ==========================================
    // 5. IMAGE OPTIMIZATION & DECODE RESILIENCE
    // ==========================================
    group('5. Image Optimization & Decode Resilience', () {
      test(
        'isImageFileAvailable safely returns false when file is deleted or corrupt',
        () async {
          final date = DateTime(2026, 3, 22);
          final dummy = createDummySourcePhoto('corrupt.jpg');
          final saved = await store.savePhoto(
            entry: PhotoEntry(
              date: date,
              title: 'Corrupt Test',
              gradientColors: const [Colors.deepOrange, Colors.brown],
            ),
            sourceTempPath: dummy.path,
          );

          expect(saved.isImageFileAvailable, isTrue);

          // Delete file
          File(saved.imagePath!).deleteSync();

          final fetched = store.getPhoto(date);
          expect(fetched, isNotNull);
          expect(fetched!.hasRealImage, isTrue);
          expect(fetched.isImageFileAvailable, isFalse);
        },
      );

      test('ResizeImage constraints thumbnail provider without throwing', () {
        final file = File('${tempDir.path}/test_thumb.jpg');
        file.writeAsStringSync('dummy');

        final provider = FileImage(file);
        final resized = ResizeImage(
          provider,
          width: 140,
          height: 140,
          allowUpscaling: false,
        );

        expect(resized.width, 140);
        expect(resized.height, 140);
        expect(resized.allowUpscaling, isFalse);
      });
    });
  });
}
