import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_operation_type.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/data/services/sync_queue.dart';
import 'package:photo_per_day/data/services/sync_queue_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PhotoFileManager fileManager;
  late PhotoMetadataStorage metadataStorage;
  late SyncQueue syncQueue;
  late PersistentDailyPhotoStore photoStore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('diary_metadata_test_');
    fileManager = PhotoFileManager(customBaseDir: tempDir);
    metadataStorage = PhotoMetadataStorage(customBaseDir: tempDir);
    syncQueue = SyncQueue(storage: SyncQueueStorage(customBaseDir: tempDir));
    photoStore = PersistentDailyPhotoStore(
      fileManager: fileManager,
      metadataStorage: metadataStorage,
      syncQueue: syncQueue,
    );
    await photoStore.init();
    PersistentDailyPhotoStore.setTestInstance(photoStore);
  });

  tearDown(() async {
    PersistentDailyPhotoStore.resetTestInstance();
    photoStore.dispose();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  Future<PhotoEntry> createAndSaveSamplePhoto({
    required DateKey dateKey,
    String title = 'Morning Sunrise',
    String? caption = 'A gentle quiet morning with warm light.',
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
      caption: caption,
      location: location,
      timeFormatted: '7:30 AM',
      gradientColors: const [Colors.amber, Colors.orange],
      syncStatus: syncStatus,
      imagePath: imageFile.path,
      driveFileId: driveFileId,
      authorizedEmail: authorizedEmail,
    );

    final saved = await photoStore.savePhoto(entry: entry);

    // If a specific sync status was requested (like synced or failed), set it
    if (syncStatus != SyncStatus.localOnly) {
      return await photoStore.updateSyncStatus(
        dateKey: dateKey,
        status: syncStatus,
        driveFileId: driveFileId,
        authorizedEmail: authorizedEmail,
      );
    }
    return saved;
  }

  group('Milestone 27 — Diary Metadata & Captions', () {
    test(
      '1. Metadata editing: Title, multiline caption, and location update and persist',
      () async {
        const dateKey = DateKey(2026, 3, 1);
        await createAndSaveSamplePhoto(dateKey: dateKey);

        const newTitle = 'Reflections on the Water';
        const newMultilineCaption =
            'Paragraph 1: The sun broke through the clouds.\n\nParagraph 2: A quiet heron landed near the reeds.';
        const newLocation = 'Silver Lake Reservoir';

        final updated = await photoStore.updatePhotoMetadata(
          dateKey: dateKey,
          title: newTitle,
          caption: newMultilineCaption,
          location: newLocation,
        );

        expect(updated.title, equals(newTitle));
        expect(updated.caption, equals(newMultilineCaption));
        expect(updated.location, equals(newLocation));

        // Verify in-memory retrieval
        final cached = photoStore.getPhotoByKey(dateKey);
        expect(cached?.title, equals(newTitle));
        expect(cached?.caption, equals(newMultilineCaption));
        expect(cached?.location, equals(newLocation));
      },
    );

    test('2. Empty metadata behavior: clearing caption and location', () async {
      const dateKey = DateKey(2026, 3, 2);
      await createAndSaveSamplePhoto(
        dateKey: dateKey,
        caption: 'Initial note',
        location: 'Initial place',
      );

      // Clear both caption and location
      final updated = await photoStore.updatePhotoMetadata(
        dateKey: dateKey,
        title: 'Still Has Title',
        caption: '',
        clearCaption: true,
        location: '',
        clearLocation: true,
      );

      expect(updated.title, equals('Still Has Title'));
      expect(updated.caption, isNull);
      expect(updated.location, isNull);

      final cached = photoStore.getPhotoByKey(dateKey);
      expect(cached?.caption, isNull);
      expect(cached?.location, isNull);
    });

    test(
      '3. Whitespace handling: trims inputs and treats whitespace-only caption/location as empty',
      () async {
        const dateKey = DateKey(2026, 3, 3);
        await createAndSaveSamplePhoto(
          dateKey: dateKey,
          title: 'Original Title',
          caption: 'Original Caption',
          location: 'Original Location',
        );

        // Whitespace title should preserve existing title; whitespace caption/location should clear
        final updated = await photoStore.updatePhotoMetadata(
          dateKey: dateKey,
          title: '   Trimmed Title   ',
          caption: '   \n  \t  ',
          location: '   ',
        );

        expect(updated.title, equals('Trimmed Title'));
        expect(updated.caption, isNull);
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
        caption: 'New caption',
      );

      expect(updated.title, equals('Preserved Title'));
      expect(updated.caption, equals('New caption'));
    });

    test(
      '5. Long text validation: handles 80-char title, 1000-char caption, and 100-char location',
      () async {
        const dateKey = DateKey(2026, 3, 5);
        await createAndSaveSamplePhoto(dateKey: dateKey);

        final longTitle = 'T' * 80;
        final longCaption = 'C' * 1000;
        final longLocation = 'L' * 100;

        final updated = await photoStore.updatePhotoMetadata(
          dateKey: dateKey,
          title: longTitle,
          caption: longCaption,
          location: longLocation,
        );

        expect(updated.title, equals(longTitle));
        expect(updated.caption, equals(longCaption));
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
          caption: 'New thought',
        );

        expect(updated.imagePath, equals(originalPath));
        final fileAfter = File(originalPath);
        expect(fileAfter.existsSync(), isTrue);
        expect(fileAfter.lengthSync(), equals(originalLength));
      },
    );

    test(
      '8. Synced photo metadata edit marks photo pending and enqueues update operation',
      () async {
        const dateKey = DateKey(2026, 3, 8);
        await createAndSaveSamplePhoto(
          dateKey: dateKey,
          syncStatus: SyncStatus.synced,
          driveFileId: 'drive_file_abc123',
          authorizedEmail: 'user@example.com',
        );

        // Verify photo is currently synced
        expect(
          photoStore.getPhotoByKey(dateKey)?.syncStatus,
          equals(SyncStatus.synced),
        );

        // Edit metadata
        final updated = await photoStore.updatePhotoMetadata(
          dateKey: dateKey,
          title: 'Edited After Cloud Sync',
        );

        // Invariants:
        // 1. syncStatus transitions to pending
        expect(updated.syncStatus, equals(SyncStatus.pending));
        // 2. driveFileId is preserved
        expect(updated.driveFileId, equals('drive_file_abc123'));
        // 3. SyncQueue has an update operation enqueued
        final ops = photoStore.syncQueue.operations
            .where((op) => op.dateKey == dateKey)
            .toList();
        expect(ops.any((op) => op.type == SyncOperationType.update), isTrue);
        final updateOp = ops.firstWhere(
          (op) => op.type == SyncOperationType.update,
        );
        expect(updateOp.driveFileId, equals('drive_file_abc123'));
      },
    );

    test(
      '9. Local-only photo metadata edit preserves localOnly status and does not enqueue sync',
      () async {
        const dateKey = DateKey(2026, 3, 9);
        await createAndSaveSamplePhoto(
          dateKey: dateKey,
          syncStatus: SyncStatus.localOnly,
        );

        final updated = await photoStore.updatePhotoMetadata(
          dateKey: dateKey,
          title: 'Offline Local Edit',
          caption: 'Just on this phone',
        );

        // Invariants:
        expect(updated.syncStatus, equals(SyncStatus.localOnly));
        final ops = photoStore.syncQueue.operations
            .where((op) => op.dateKey == dateKey)
            .toList();
        expect(ops.isEmpty, isTrue);
      },
    );

    test(
      '10. Failed-sync photo metadata edit transitions to pending and clears previous syncError',
      () async {
        const dateKey = DateKey(2026, 3, 10);
        await createAndSaveSamplePhoto(
          dateKey: dateKey,
          syncStatus: SyncStatus.failed,
          driveFileId: 'drive_fail_123',
        );

        await photoStore.updateSyncStatus(
          dateKey: dateKey,
          status: SyncStatus.failed,
          syncError: '503 Service Unavailable',
        );

        expect(
          photoStore.getPhotoByKey(dateKey)?.syncError,
          equals('503 Service Unavailable'),
        );

        final updated = await photoStore.updatePhotoMetadata(
          dateKey: dateKey,
          title: 'Edited Failed Memory',
        );

        expect(updated.syncStatus, equals(SyncStatus.pending));
        expect(updated.syncError, isNull);
      },
    );

    test(
      '11. Partial edit preserves omitted fields (title only leaves caption and location intact)',
      () async {
        const dateKey = DateKey(2026, 3, 11);
        await createAndSaveSamplePhoto(
          dateKey: dateKey,
          title: 'Original Title',
          caption: 'Original Diary Note',
          location: 'Original Location',
        );

        // Only update title, leaving caption and location unspecified (null)
        final updated = await photoStore.updatePhotoMetadata(
          dateKey: dateKey,
          title: 'New Title Only',
        );

        expect(updated.title, equals('New Title Only'));
        expect(updated.caption, equals('Original Diary Note'));
        expect(updated.location, equals('Original Location'));
      },
    );

    test(
      '12. Cold restart persistence: edited diary metadata survives store recreation',
      () async {
        const dateKey = DateKey(2026, 3, 12);
        await createAndSaveSamplePhoto(dateKey: dateKey);

        const expectedTitle = 'Survived Cold Restart';
        const expectedCaption =
            'Line 1: Stored in atomic metadata.\nLine 2: Reloaded fresh from disk.';
        const expectedLocation = 'Griffith Observatory';

        await photoStore.updatePhotoMetadata(
          dateKey: dateKey,
          title: expectedTitle,
          caption: expectedCaption,
          location: expectedLocation,
        );

        // Simulate cold app restart: dispose active store and instantiate fresh
        photoStore.dispose();

        photoStore = PersistentDailyPhotoStore(
          fileManager: fileManager,
          metadataStorage: metadataStorage,
          syncQueue: syncQueue,
        );
        await photoStore.init();

        final reloadedEntry = photoStore.getPhotoByKey(dateKey);
        expect(reloadedEntry, isNotNull);
        expect(reloadedEntry?.title, equals(expectedTitle));
        expect(reloadedEntry?.caption, equals(expectedCaption));
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

    test(
      '14. PhotoEntry.copyWith supports clearCaption and clearLocation flags',
      () {
        final entry = PhotoEntry(
          date: DateTime(2026, 3, 14),
          title: 'Test Entry',
          caption: 'Has caption',
          location: 'Has location',
          gradientColors: const [Colors.blue, Colors.purple],
        );

        // Using copyWith with clearCaption
        final clearedCaption = entry.copyWith(clearCaption: true);
        expect(clearedCaption.caption, isNull);
        expect(clearedCaption.location, equals('Has location'));

        // Using copyWith with clearLocation
        final clearedLocation = entry.copyWith(clearLocation: true);
        expect(clearedLocation.location, isNull);
        expect(clearedLocation.caption, equals('Has caption'));

        // Using copyWith with both cleared
        final clearedBoth = entry.copyWith(
          clearCaption: true,
          clearLocation: true,
        );
        expect(clearedBoth.caption, isNull);
        expect(clearedBoth.location, isNull);
      },
    );
  });
}
