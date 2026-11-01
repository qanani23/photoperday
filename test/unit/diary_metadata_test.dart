import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PhotoFileManager fileManager;
  late PhotoMetadataStorage metadataStorage;
  late PersistentDailyPhotoStore photoStore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('diary_meta_test_');
    fileManager = PhotoFileManager(customBaseDir: tempDir);
    metadataStorage = PhotoMetadataStorage(customBaseDir: tempDir);
    photoStore = PersistentDailyPhotoStore(
      fileManager: fileManager,
      metadataStorage: metadataStorage,
    );
    await photoStore.init();
  });

  tearDown(() async {
    photoStore.dispose();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<PhotoEntry> createAndSaveSamplePhoto({
    required DateKey dateKey,
    String title = 'Morning Sunrise',
    String? location = 'Echo Park Lake',
    SyncStatus syncStatus = SyncStatus.localOnly,
    String? driveFileId,
    String? authorizedEmail,
  }) async {
    final imageFile = File('${tempDir.path}/photo_${dateKey.format()}.jpg');
    await imageFile.writeAsBytes(List.generate(100, (i) => i % 256));

    final entry = PhotoEntry(
      date: dateKey.toDateTime(),
      title: title,
      location: location,
      timeFormatted: '7:30 AM',
      gradientColors: const [Colors.amber, Colors.orange],
      syncStatus: syncStatus,
      imagePath: imageFile.path,
      driveFileId: driveFileId,
      authorizedEmail: authorizedEmail,
    );

    return await photoStore.savePhoto(entry: entry);
  }

  group('Milestone 27 & M44 — Diary Metadata (Title & Location)', () {
    test(
      '1. Metadata editing: Title and location update and persist',
      () async {
        const dateKey = DateKey(2026, 3, 1);
        await createAndSaveSamplePhoto(dateKey: dateKey);

        const newTitle = 'Reflections on the Water';
        const newLocation = 'Silver Lake Reservoir';

        final updated = await photoStore.updatePhotoMetadata(
          dateKey: dateKey,
          title: newTitle,
          location: newLocation,
        );

        expect(updated.title, equals(newTitle));
        expect(updated.location, equals(newLocation));

        // Verify in-memory retrieval
        final cached = photoStore.getPhotoByKey(dateKey);
        expect(cached?.title, equals(newTitle));
        expect(cached?.location, equals(newLocation));
      },
    );

    test('2. Empty metadata behavior: clearing location', () async {
      const dateKey = DateKey(2026, 3, 2);
      await createAndSaveSamplePhoto(
        dateKey: dateKey,
        location: 'Initial place',
      );

      // Clear location
      final updated = await photoStore.updatePhotoMetadata(
        dateKey: dateKey,
        title: 'Still Has Title',
        location: '',
        clearLocation: true,
      );

      expect(updated.title, equals('Still Has Title'));
      expect(updated.location, isNull);

      final cached = photoStore.getPhotoByKey(dateKey);
      expect(cached?.location, isNull);
    });

    test(
      '3. Whitespace handling: trims inputs and treats whitespace-only location as empty',
      () async {
        const dateKey = DateKey(2026, 3, 3);
        await createAndSaveSamplePhoto(
          dateKey: dateKey,
          title: 'Original Title',
          location: 'Original Location',
        );

        final updated = await photoStore.updatePhotoMetadata(
          dateKey: dateKey,
          title: '   Trimmed Title   ',
          location: '   ',
        );

        expect(updated.title, equals('Trimmed Title'));
        expect(updated.location, isNull);
      },
    );

    test('4. Empty/whitespace-only title preserves existing title', () async {
      const dateKey = DateKey(2026, 3, 4);
      await createAndSaveSamplePhoto(
        dateKey: dateKey,
        title: 'Preserved Title',
      );

      final updated = await photoStore.updatePhotoMetadata(
        dateKey: dateKey,
        title: '   ', // whitespace only
        location: 'New location',
      );

      expect(updated.title, equals('Preserved Title'));
      expect(updated.location, equals('New location'));
    });

    test(
      '5. Long text validation: handles 80-char title and 100-char location',
      () async {
        const dateKey = DateKey(2026, 3, 5);
        await createAndSaveSamplePhoto(dateKey: dateKey);

        final longTitle = 'T' * 80;
        final longLocation = 'L' * 100;

        final updated = await photoStore.updatePhotoMetadata(
          dateKey: dateKey,
          title: longTitle,
          location: longLocation,
        );

        expect(updated.title, equals(longTitle));
        expect(updated.location, equals(longLocation));
      },
    );

    test(
      '6. Metadata edits preserve DateKey identity and do not create duplicates',
      () async {
        const dateKey = DateKey(2026, 3, 6);
        await createAndSaveSamplePhoto(dateKey: dateKey);

        final initialCount = photoStore.totalPhotos;

        final updated = await photoStore.updatePhotoMetadata(
          dateKey: dateKey,
          title: 'Updated Title',
        );

        expect(updated.dateKey, equals(dateKey));
        expect(photoStore.totalPhotos, equals(initialCount));
        expect(photoStore.hasPhotoByKey(dateKey), isTrue);
      },
    );

    test(
      '7. Metadata edits preserve the local photo file without deletion or alteration',
      () async {
        const dateKey = DateKey(2026, 3, 7);
        final initialEntry = await createAndSaveSamplePhoto(dateKey: dateKey);

        final originalPath = initialEntry.imagePath!;
        final originalLength = File(originalPath).lengthSync();

        final updated = await photoStore.updatePhotoMetadata(
          dateKey: dateKey,
          title: 'Updated Without File Touch',
        );

        expect(updated.imagePath, equals(originalPath));
        final fileAfter = File(originalPath);
        expect(fileAfter.existsSync(), isTrue);
        expect(fileAfter.lengthSync(), equals(originalLength));
      },
    );

    test(
      '8. Photo metadata edit updates entry while preserving image and key',
      () async {
        const dateKey = DateKey(2026, 3, 8);
        await createAndSaveSamplePhoto(
          dateKey: dateKey,
          driveFileId: 'drive_file_abc123',
          authorizedEmail: 'user@example.com',
        );

        // Edit metadata
        final updated = await photoStore.updatePhotoMetadata(
          dateKey: dateKey,
          title: 'Edited Title',
        );

        // Invariants:
        expect(updated.title, equals('Edited Title'));
        expect(updated.dateKey, equals(dateKey));
        expect(
          photoStore.getPhotoByKey(dateKey)?.title,
          equals('Edited Title'),
        );
      },
    );

    test(
      '9. Local-only photo metadata edit preserves localOnly status',
      () async {
        const dateKey = DateKey(2026, 3, 9);
        await createAndSaveSamplePhoto(
          dateKey: dateKey,
          syncStatus: SyncStatus.localOnly,
        );

        final updated = await photoStore.updatePhotoMetadata(
          dateKey: dateKey,
          title: 'Offline Local Edit',
        );

        // Invariants:
        expect(updated.syncStatus, equals(SyncStatus.localOnly));
        expect(updated.title, equals('Offline Local Edit'));
      },
    );

    test('10. Photo metadata edit persists title change to store', () async {
      const dateKey = DateKey(2026, 3, 10);
      await createAndSaveSamplePhoto(dateKey: dateKey);

      final updated = await photoStore.updatePhotoMetadata(
        dateKey: dateKey,
        title: 'Edited Memory',
      );

      expect(updated.title, equals('Edited Memory'));
      expect(photoStore.getPhotoByKey(dateKey)?.title, equals('Edited Memory'));
    });

    test(
      '11. Partial edit preserves omitted fields (title only leaves location intact)',
      () async {
        const dateKey = DateKey(2026, 3, 11);
        await createAndSaveSamplePhoto(
          dateKey: dateKey,
          title: 'Original Title',
          location: 'Original Location',
        );

        // Only update title, leaving location unspecified (null)
        final updated = await photoStore.updatePhotoMetadata(
          dateKey: dateKey,
          title: 'New Title Only',
        );

        expect(updated.title, equals('New Title Only'));
        expect(updated.location, equals('Original Location'));
      },
    );

    test(
      '12. Cold restart persistence: edited diary metadata survives store recreation',
      () async {
        const dateKey = DateKey(2026, 3, 12);
        await createAndSaveSamplePhoto(dateKey: dateKey);

        const expectedTitle = 'Survived Cold Restart';
        const expectedLocation = 'Griffith Observatory';

        await photoStore.updatePhotoMetadata(
          dateKey: dateKey,
          title: expectedTitle,
          location: expectedLocation,
        );

        // Simulate cold app restart: dispose active store and instantiate fresh
        photoStore.dispose();

        photoStore = PersistentDailyPhotoStore(
          fileManager: fileManager,
          metadataStorage: metadataStorage,
        );
        await photoStore.init();

        final reloadedEntry = photoStore.getPhotoByKey(dateKey);
        expect(reloadedEntry, isNotNull);
        expect(reloadedEntry?.title, equals(expectedTitle));
        expect(reloadedEntry?.location, equals(expectedLocation));
      },
    );

    test('13. Non-existent DateKey throws StateError', () async {
      const nonExistentKey = DateKey(2099, 12, 31);
      expect(
        () => photoStore.updatePhotoMetadata(
          dateKey: nonExistentKey,
          title: 'Ghost Photo',
        ),
        throwsStateError,
      );
    });

    test('14. PhotoEntry.copyWith supports clearLocation flag', () {
      final entry = PhotoEntry(
        date: DateTime(2026, 3, 14),
        title: 'Test Entry',
        location: 'Has location',
        gradientColors: const [Colors.blue, Colors.purple],
      );

      // Using copyWith with clearLocation
      final clearedLocation = entry.copyWith(clearLocation: true);
      expect(clearedLocation.location, isNull);
      expect(clearedLocation.title, equals('Test Entry'));
    });
  });
}
