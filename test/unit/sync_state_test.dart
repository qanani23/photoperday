import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/models/sync_tombstone.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestone 16 — Sync State Architecture Tests', () {
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
      SyncStatus syncStatus = SyncStatus.localOnly,
      String? driveFileId,
      String? driveFileRevision,
      String? syncError,
    }) {
      return PhotoEntry(
        date: date,
        title: title,
        caption: caption,
        location: location,
        imagePath: imagePath,
        syncStatus: syncStatus,
        driveFileId: driveFileId,
        driveFileRevision: driveFileRevision,
        syncError: syncError,
        gradientColors: const [Colors.blue, Colors.purple],
      );
    }

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('m16_sync_test_');
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
    // 1. SYNC STATUS ENUM & TOMBSTONE MODELS
    // ==========================================
    group('1. Domain Model Serialization & Deserialization', () {
      test(
        'SyncStatus enum serializes and deserializes all values correctly',
        () {
          for (final status in SyncStatus.values) {
            final json = status.toJson();
            expect(SyncStatus.fromJson(json), status);
          }
          // Null or unknown string gracefully falls back to localOnly
          expect(SyncStatus.fromJson(null), SyncStatus.localOnly);
          expect(
            SyncStatus.fromJson('invalid_status_xyz'),
            SyncStatus.localOnly,
          );
        },
      );

      test('SyncTombstone serializes and deserializes cleanly', () {
        const dateKey = DateKey(2026, 3, 15);
        final deletedAt = DateTime.utc(2026, 3, 15, 18, 30);
        final tombstone = SyncTombstone(
          dateKey: dateKey,
          driveFileId: 'drive_file_12345',
          deletedAt: deletedAt,
        );

        final json = tombstone.toJson();
        expect(json['dateKey'], '2026-03-15');
        expect(json['driveFileId'], 'drive_file_12345');
        expect(json['deletedAt'], deletedAt.toIso8601String());

        final reconstructed = SyncTombstone.fromJson(json);
        expect(reconstructed.dateKey, dateKey);
        expect(reconstructed.driveFileId, 'drive_file_12345');
        expect(reconstructed.deletedAt, deletedAt);
        expect(reconstructed, tombstone);
      });
    });

    // ==========================================
    // 2. BACKWARD COMPATIBILITY
    // ==========================================
    group('2. Backward Compatibility with Legacy Metadata', () {
      test(
        'Legacy JSON without sync fields deserializes safely with defaults',
        () {
          final legacyJson = <String, dynamic>{
            'date': '2026-03-10T12:00:00.000',
            'title': 'Legacy Photo',
            'caption': 'Captured in Milestone 13',
            'gradientColors': [0xFF123456, 0xFF654321],
            'imagePath': '/path/to/legacy.jpg',
          };

          final entry = PhotoEntry.fromJson(legacyJson);
          expect(entry.title, 'Legacy Photo');
          expect(entry.syncStatus, SyncStatus.localOnly);
          expect(
            entry.effectiveLastModifiedAt,
            DateTime.parse('2026-03-10T12:00:00.000').toUtc(),
          );
          expect(entry.driveFileId, isNull);
          expect(entry.driveFileRevision, isNull);
          expect(entry.syncError, isNull);
        },
      );
    });

    // ==========================================
    // 3. LIFECYCLE & STATE TRANSITIONS
    // ==========================================
    group('3. Sync State Transitions & Store Integration', () {
      test(
        'New photo receives SyncStatus.localOnly and survives restart',
        () async {
          final date = DateTime(2026, 10, 1);
          final dummy = createDummySourcePhoto('new_local.jpg');

          final saved = await store.savePhoto(
            entry: createTestEntry(date: date, title: 'New Local Photo'),
            sourceTempPath: dummy.path,
          );

          expect(saved.syncStatus, SyncStatus.localOnly);
          expect(saved.lastModifiedAt, isNotNull);
          expect(saved.driveFileId, isNull);

          // Cold restart verification
          final restartedStore = PersistentDailyPhotoStore(
            fileManager: fileManager,
            metadataStorage: metadataStorage,
          );
          await restartedStore.init(customBaseDir: tempDir);

          final loaded = restartedStore.getPhoto(date);
          expect(loaded, isNotNull);
          expect(loaded!.syncStatus, SyncStatus.localOnly);
          expect(loaded.lastModifiedAt, isNotNull);
        },
      );

      test('Local-only photo edited retains SyncStatus.localOnly', () async {
        final date = DateTime(2026, 10, 2);
        final dummy = createDummySourcePhoto('local_edit.jpg');

        await store.savePhoto(
          entry: createTestEntry(date: date, title: 'Original Title'),
          sourceTempPath: dummy.path,
        );

        final updated = await store.updatePhotoMetadata(
          dateKey: DateKey.fromDateTime(date),
          title: 'Modified Title',
        );

        expect(updated.title, 'Modified Title');
        expect(updated.syncStatus, SyncStatus.localOnly);
      });

      test(
        'Synced photo metadata edit transitions to SyncStatus.pending',
        () async {
          final date = DateTime(2026, 10, 3);
          final dummy = createDummySourcePhoto('synced_edit.jpg');

          // 1. Create and simulate that photo was synced to Google Drive
          await store.savePhoto(
            entry: createTestEntry(date: date, title: 'Synced Photo'),
            sourceTempPath: dummy.path,
          );

          final synced = await store.updateSyncStatus(
            dateKey: DateKey.fromDateTime(date),
            status: SyncStatus.synced,
            driveFileId: 'drive_abc_789',
            driveFileRevision: 'rev_v1',
          );
          expect(synced.syncStatus, SyncStatus.synced);
          expect(synced.driveFileId, 'drive_abc_789');

          // 2. Perform local metadata edit
          final edited = await store.updatePhotoMetadata(
            dateKey: DateKey.fromDateTime(date),
            title: 'Title Changed Locally',
          );

          // 3. Verify state transitioned to pending while preserving driveFileId
          expect(edited.title, 'Title Changed Locally');
          expect(edited.syncStatus, SyncStatus.pending);
          expect(edited.driveFileId, 'drive_abc_789');
          expect(edited.driveFileRevision, 'rev_v1');

          // 4. Cold restart verification
          final restartedStore = PersistentDailyPhotoStore(
            fileManager: fileManager,
            metadataStorage: metadataStorage,
          );
          await restartedStore.init(customBaseDir: tempDir);

          final restored = restartedStore.getPhoto(date);
          expect(restored!.syncStatus, SyncStatus.pending);
          expect(restored.driveFileId, 'drive_abc_789');
        },
      );

      test(
        'Synced photo replacement transitions to SyncStatus.pending and preserves Drive ID',
        () async {
          final date = DateTime(2026, 10, 4);
          final dummy1 = createDummySourcePhoto('shot1.jpg');
          final dummy2 = createDummySourcePhoto('shot2.jpg');

          // 1. Save and mark synced
          await store.savePhoto(
            entry: createTestEntry(date: date, title: 'First Shot'),
            sourceTempPath: dummy1.path,
          );
          await store.updateSyncStatus(
            dateKey: DateKey.fromDateTime(date),
            status: SyncStatus.synced,
            driveFileId: 'drive_photo_444',
            driveFileRevision: 'rev_1',
          );

          // 2. Replace photo on same DateKey
          final replaced = await store.savePhoto(
            entry: createTestEntry(date: date, title: 'Second Shot'),
            sourceTempPath: dummy2.path,
          );

          // 3. Verification: DateKey preserved, state is pending, Drive ID preserved
          expect(store.totalPhotos, 1);
          expect(replaced.title, 'Second Shot');
          expect(replaced.syncStatus, SyncStatus.pending);
          expect(replaced.driveFileId, 'drive_photo_444');
        },
      );
    });

    // ==========================================
    // 4. DELETION & TOMBSTONE SEAM
    // ==========================================
    group('4. Deletion & Tombstone Seam for Future Milestone 17', () {
      test(
        'Deleting a synced photo generates and persists a SyncTombstone',
        () async {
          final date = DateTime(2026, 10, 5);
          final dummy = createDummySourcePhoto('synced_delete.jpg');

          await store.savePhoto(
            entry: createTestEntry(date: date, title: 'To Delete'),
            sourceTempPath: dummy.path,
          );
          await store.updateSyncStatus(
            dateKey: DateKey.fromDateTime(date),
            status: SyncStatus.synced,
            driveFileId: 'drive_to_delete_999',
          );

          expect(store.pendingDeletions, isEmpty);

          // Delete the photo
          await store.removePhotoAsync(date);

          expect(store.hasPhoto(date), isFalse);
          expect(store.pendingDeletions.length, 1);
          final tombstone = store.pendingDeletions.first;
          expect(tombstone.dateKey, DateKey.fromDateTime(date));
          expect(tombstone.driveFileId, 'drive_to_delete_999');

          // Cold restart verification: tombstone survives app restart
          final restartedStore = PersistentDailyPhotoStore(
            fileManager: fileManager,
            metadataStorage: metadataStorage,
          );
          await restartedStore.init(customBaseDir: tempDir);

          expect(restartedStore.hasPhoto(date), isFalse);
          expect(restartedStore.pendingDeletions.length, 1);
          expect(
            restartedStore.pendingDeletions.first.driveFileId,
            'drive_to_delete_999',
          );
        },
      );

      test('Deleting a localOnly photo does NOT generate a tombstone', () async {
        final date = DateTime(2026, 10, 6);
        final dummy = createDummySourcePhoto('local_delete.jpg');

        await store.savePhoto(
          entry: createTestEntry(date: date, title: 'Local Only Delete'),
          sourceTempPath: dummy.path,
        );

        await store.removePhotoAsync(date);

        expect(store.hasPhoto(date), isFalse);
        // Because it was never uploaded to Google Drive, no remote deletion is required
        expect(store.pendingDeletions, isEmpty);
      });

      test(
        'Acknowledging a pending deletion removes the tombstone from disk',
        () async {
          final date = DateTime(2026, 10, 7);
          final dummy = createDummySourcePhoto('ack_test.jpg');

          await store.savePhoto(
            entry: createTestEntry(date: date, title: 'Synced for Ack'),
            sourceTempPath: dummy.path,
          );
          await store.updateSyncStatus(
            dateKey: DateKey.fromDateTime(date),
            status: SyncStatus.synced,
            driveFileId: 'drive_ack_111',
          );

          await store.removePhotoAsync(date);
          expect(store.pendingDeletions.length, 1);

          // Simulate future Milestone 17 acknowledging remote deletion completion
          await store.acknowledgePendingDeletion('drive_ack_111');
          expect(store.pendingDeletions, isEmpty);

          // Cold restart confirms tombstone was permanently cleared from disk
          final restartedStore = PersistentDailyPhotoStore(
            fileManager: fileManager,
            metadataStorage: metadataStorage,
          );
          await restartedStore.init(customBaseDir: tempDir);
          expect(restartedStore.pendingDeletions, isEmpty);
        },
      );
    });

    // ==========================================
    // 5. SYNC FAILURE REPRESENTATION & FALLBACKS
    // ==========================================
    group('5. Sync Failure Representation & Fallbacks', () {
      test('Failed sync state persists safely with error message', () async {
        final date = DateTime(2026, 10, 8);
        final dummy = createDummySourcePhoto('fail_sync.jpg');

        await store.savePhoto(
          entry: createTestEntry(date: date, title: 'Will Fail Sync'),
          sourceTempPath: dummy.path,
        );

        final failed = await store.updateSyncStatus(
          dateKey: DateKey.fromDateTime(date),
          status: SyncStatus.failed,
          syncError: 'Network unreachable: simulated offline test error',
        );

        expect(failed.syncStatus, SyncStatus.failed);
        expect(failed.syncError, contains('simulated offline test error'));

        // Cold restart verification
        final restartedStore = PersistentDailyPhotoStore(
          fileManager: fileManager,
          metadataStorage: metadataStorage,
        );
        await restartedStore.init(customBaseDir: tempDir);

        final loaded = restartedStore.getPhoto(date);
        expect(loaded!.syncStatus, SyncStatus.failed);
        expect(loaded.syncError, contains('simulated offline test error'));
        // Local photo must remain 100% usable
        expect(loaded.isImageFileAvailable, isTrue);
      });

      test(
        'Editing metadata on a failed photo transitions to pending and clears error',
        () async {
          final date = DateTime(2026, 10, 9);
          final dummy = createDummySourcePhoto('fail_recovery.jpg');

          await store.savePhoto(
            entry: createTestEntry(date: date, title: 'Failed Item'),
            sourceTempPath: dummy.path,
          );
          await store.updateSyncStatus(
            dateKey: DateKey.fromDateTime(date),
            status: SyncStatus.failed,
            syncError: 'Previous timeout error',
          );

          // User edits metadata locally
          final recovered = await store.updatePhotoMetadata(
            dateKey: DateKey.fromDateTime(date),
            title: 'Recovered and Edited',
          );

          expect(recovered.title, 'Recovered and Edited');
          expect(recovered.syncStatus, SyncStatus.pending);
          expect(recovered.syncError, isNull);
        },
      );

      test(
        'DateKey identity is strictly preserved under all sync state changes',
        () async {
          final date = DateTime(2026, 10, 10);
          final expectedKey = DateKey.fromDateTime(date);
          final dummy = createDummySourcePhoto('key_guard.jpg');

          final p1 = await store.savePhoto(
            entry: createTestEntry(date: date, title: 'P1'),
            sourceTempPath: dummy.path,
          );
          expect(p1.dateKey, expectedKey);

          final p2 = await store.updateSyncStatus(
            dateKey: expectedKey,
            status: SyncStatus.synced,
            driveFileId: 'drive_key_test',
          );
          expect(p2.dateKey, expectedKey);

          final p3 = await store.updatePhotoMetadata(
            dateKey: expectedKey,
            title: 'P3 Edited',
          );
          expect(p3.dateKey, expectedKey);

          expect(store.totalPhotos, 1);
          expect(store.recordedDates, [expectedKey]);
        },
      );
    });
  });
}
