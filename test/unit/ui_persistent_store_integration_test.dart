import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/mock_photo_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';

void main() {
  group('Milestone 13 — UI to PersistentDailyPhotoStore Integration Tests', () {
    late Directory tempDir;
    late PhotoFileManager fileManager;
    late PhotoMetadataStorage metadataStorage;
    late PersistentDailyPhotoStore store;

    File createDummySourcePhoto(String name) {
      final sourceDir = Directory('${tempDir.path}/temp_sources');
      if (!sourceDir.existsSync()) sourceDir.createSync(recursive: true);
      final file = File('${sourceDir.path}/$name');
      file.writeAsStringSync('dummy-image-bytes-for-$name');
      return file;
    }

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('m13_ui_integration_test_');
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

    test(
      '1. Calendar resolution: Real persistent photo takes precedence over mock photo',
      () async {
        final testDate = DateTime(2026, 3, 1);
        final mockPhoto = MockPhotoService.instance.getPhoto(testDate);
        expect(mockPhoto, isNotNull);
        expect(mockPhoto!.title, 'Morning Roast');

        // Before saving real photo: store has no photo, mock photo is the fallback
        expect(store.getPhoto(testDate), isNull);
        final resolvedBefore = store.getPhoto(testDate) ?? mockPhoto;
        expect(resolvedBefore.title, 'Morning Roast');

        // Save real user photo for this date
        final dummy = createDummySourcePhoto('real_march1.jpg');
        final realEntry = PhotoEntry(
          date: testDate,
          title: 'Real Captured Latte Art',
          caption: 'My actual morning coffee captured on camera',
          location: 'Home Kitchen',
          gradientColors: const [Colors.brown, Colors.orange],
        );
        await store.savePhoto(entry: realEntry, sourceTempPath: dummy.path);

        // After saving: store has real photo, taking precedence over mock photo
        final resolvedAfter = store.getPhoto(testDate) ?? mockPhoto;
        expect(resolvedAfter.title, 'Real Captured Latte Art');
        expect(
          resolvedAfter.caption,
          'My actual morning coffee captured on camera',
        );
        expect(resolvedAfter.hasRealImage, isTrue);
        expect(resolvedAfter.isImageFileAvailable, isTrue);
      },
    );

    test(
      '2. PhotoDetail editing: Editing title, caption, location persists and survives restart',
      () async {
        final testDate = DateTime(2026, 3, 15);
        final dummy = createDummySourcePhoto('today_original.jpg');
        final initialEntry = PhotoEntry(
          date: testDate,
          title: 'Initial Title',
          caption: 'Initial Caption',
          location: 'Initial Location',
          gradientColors: const [Colors.amber, Colors.deepOrange],
        );
        final saved = await store.savePhoto(
          entry: initialEntry,
          sourceTempPath: dummy.path,
        );

        // Simulate PhotoDetailScreen editing
        final editedEntry = saved.copyWith(
          title: 'Edited Title in Detail Screen',
          caption: 'Updated reflection from evening review',
          location: 'Griffith Observatory',
        );
        store.setPhoto(editedEntry);

        // Ensure async disk flush completes deterministically
        await store.flush();
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // In-memory verification
        final loadedMem = store.getPhoto(testDate);
        expect(loadedMem, isNotNull);
        expect(loadedMem!.title, 'Edited Title in Detail Screen');
        expect(loadedMem.caption, 'Updated reflection from evening review');
        expect(loadedMem.location, 'Griffith Observatory');

        // Simulate App Restart (reinitializing store from disk metadata)
        final restoredStore = PersistentDailyPhotoStore(
          fileManager: fileManager,
          metadataStorage: metadataStorage,
        );
        await restoredStore.init(customBaseDir: tempDir);

        final loadedDisk = restoredStore.getPhoto(testDate);
        expect(loadedDisk, isNotNull);
        expect(loadedDisk!.title, 'Edited Title in Detail Screen');
        expect(loadedDisk.caption, 'Updated reflection from evening review');
        expect(loadedDisk.location, 'Griffith Observatory');
        expect(loadedDisk.hasRealImage, isTrue);
        expect(loadedDisk.isImageFileAvailable, isTrue);
      },
    );

    test(
      '3. PhotoDetail deletion: Deleting memory cleans up metadata, file, and updates listeners',
      () async {
        final testDate = DateTime(2026, 3, 10);
        final dummy = createDummySourcePhoto('to_delete.jpg');
        final entry = PhotoEntry(
          date: testDate,
          title: 'Memory to delete',
          gradientColors: const [Colors.red, Colors.pink],
        );
        final saved = await store.savePhoto(
          entry: entry,
          sourceTempPath: dummy.path,
        );
        final persistentFilePath = saved.imagePath!;
        expect(File(persistentFilePath).existsSync(), isTrue);

        bool listenerNotified = false;
        store.addListener(() {
          listenerNotified = true;
        });

        // PhotoDetailScreen delete confirmation
        await store.removePhotoAsync(testDate);
        expect(listenerNotified, isTrue);
        expect(store.getPhoto(testDate), isNull);

        // Persistent file must be cleaned up
        expect(File(persistentFilePath).existsSync(), isFalse);

        // Disk metadata must reflect deletion after app restart
        final restoredStore = PersistentDailyPhotoStore(
          fileManager: fileManager,
          metadataStorage: metadataStorage,
        );
        await restoredStore.init(customBaseDir: tempDir);
        expect(restoredStore.getPhoto(testDate), isNull);
      },
    );

    test(
      '4. TodayScreen reactivity: TodayScreen reflects save and delete via store notifications',
      () async {
        final todayDate = DateTime(2026, 3, 15);
        final dummy = createDummySourcePhoto('today_test.jpg');

        int notifyCount = 0;
        store.addListener(() {
          notifyCount++;
        });

        // 1. Initially no real photo in persistent store
        expect(store.getPhoto(todayDate), isNull);

        // 2. User captures or selects photo for today
        final todayPhoto = PhotoEntry(
          date: todayDate,
          title: 'Today Capture',
          gradientColors: const [Colors.teal, Colors.blue],
        );
        await store.savePhoto(entry: todayPhoto, sourceTempPath: dummy.path);

        expect(notifyCount, greaterThanOrEqualTo(1));
        final currentToday = store.getPhoto(todayDate);
        expect(currentToday, isNotNull);
        expect(currentToday!.title, 'Today Capture');

        // 3. User deletes today photo from detail screen
        await store.removePhotoAsync(todayDate);
        expect(store.getPhoto(todayDate), isNull);
      },
    );

    test(
      '5. CalendarCell and DayPreviewCard resilience: Missing image file falls back safely',
      () async {
        final testDate = DateTime(2026, 3, 5);
        final dummy = createDummySourcePhoto('will_be_missing.jpg');
        final entry = PhotoEntry(
          date: testDate,
          title: 'Missing File Test',
          gradientColors: const [Colors.indigo, Colors.purple],
        );
        final saved = await store.savePhoto(
          entry: entry,
          sourceTempPath: dummy.path,
        );
        expect(saved.isImageFileAvailable, isTrue);

        // Artificially delete image file to simulate missing/corrupted file
        File(saved.imagePath!).deleteSync();

        final rechecked = store.getPhoto(testDate);
        expect(rechecked, isNotNull);
        expect(rechecked!.hasRealImage, isTrue);
        // isImageFileAvailable must safely return false without throwing
        expect(rechecked.isImageFileAvailable, isFalse);
      },
    );

    test(
      '6. Replacement preserves one-photo-per-day across UI operations',
      () async {
        final testDate = DateTime(2026, 3, 8);
        final dummy1 = createDummySourcePhoto('shot1.jpg');
        final dummy2 = createDummySourcePhoto('shot2.jpg');

        final first = PhotoEntry(
          date: testDate,
          title: 'First Shot',
          gradientColors: const [Colors.blue, Colors.cyan],
        );
        final saved1 = await store.savePhoto(
          entry: first,
          sourceTempPath: dummy1.path,
        );
        final firstPath = saved1.imagePath!;

        // Replace with second photo
        final second = PhotoEntry(
          date: testDate,
          title: 'Second Replaced Shot',
          gradientColors: const [Colors.green, Colors.teal],
        );
        final saved2 = await store.savePhoto(
          entry: second,
          sourceTempPath: dummy2.path,
        );
        final secondPath = saved2.imagePath!;

        expect(store.count, 1);
        expect(store.getPhoto(testDate)!.title, 'Second Replaced Shot');
        expect(firstPath, isNot(equals(secondPath)));
        expect(File(secondPath).existsSync(), isTrue);

        // Old file cleaned up
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(File(firstPath).existsSync(), isFalse);
      },
    );
  });
}
