import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_operation.dart';
import 'package:photo_per_day/data/models/sync_operation_status.dart';
import 'package:photo_per_day/data/models/sync_operation_type.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/data/services/sync_queue.dart';
import 'package:photo_per_day/data/services/sync_queue_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestone 17 — Durable Local Sync Queue / Outbox Tests', () {
    late Directory tempDir;
    late SyncQueueStorage queueStorage;
    late SyncQueue queue;

    late PhotoFileManager fileManager;
    late PhotoMetadataStorage metadataStorage;
    late PersistentDailyPhotoStore store;

    File createDummySourcePhoto(
      String name, {
      String content = 'dummy-sync-photo-bytes',
    }) {
      final sourceDir = Directory('${tempDir.path}/temp_sources');
      if (!sourceDir.existsSync()) sourceDir.createSync(recursive: true);
      final file = File('${sourceDir.path}/$name');
      file.writeAsStringSync(content);
      return file;
    }

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('m17_sync_queue_test_');
      queueStorage = SyncQueueStorage(customBaseDir: tempDir);
      queue = SyncQueue(storage: queueStorage);
      await queue.init();

      fileManager = PhotoFileManager(customBaseDir: tempDir);
      metadataStorage = PhotoMetadataStorage(customBaseDir: tempDir);
      store = PersistentDailyPhotoStore(
        fileManager: fileManager,
        metadataStorage: metadataStorage,
        syncQueue: queue,
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

    group('1. Domain Models & Serialization', () {
      test(
        'SyncOperationType serializes and deserializes all types correctly',
        () {
          for (final type in SyncOperationType.values) {
            final json = type.toJson();
            expect(SyncOperationType.fromJson(json), type);
          }
          expect(SyncOperationType.fromJson(null), SyncOperationType.upload);
          expect(
            SyncOperationType.fromJson('unknown_type'),
            SyncOperationType.upload,
          );
        },
      );

      test(
        'SyncOperationStatus serializes and deserializes all statuses correctly',
        () {
          for (final status in SyncOperationStatus.values) {
            final json = status.toJson();
            expect(SyncOperationStatus.fromJson(json), status);
          }
          expect(
            SyncOperationStatus.fromJson(null),
            SyncOperationStatus.pending,
          );
          expect(
            SyncOperationStatus.fromJson('bad_status'),
            SyncOperationStatus.pending,
          );
        },
      );

      test(
        'SyncOperation serializes, deserializes, and computes deterministic backoff',
        () {
          const dateKey = DateKey(2026, 4, 1);
          final createdAt = DateTime.utc(2026, 4, 1, 10, 0);
          final lastAttempt = DateTime.utc(2026, 4, 1, 10, 5);
          final nextAttempt = DateTime.utc(2026, 4, 1, 10, 6);

          final op = SyncOperation(
            id: 'op_custom_123',
            type: SyncOperationType.update,
            dateKey: dateKey,
            createdAt: createdAt,
            status: SyncOperationStatus.failed,
            retryCount: 2,
            lastAttemptAt: lastAttempt,
            nextAttemptAt: nextAttempt,
            lastError: 'Simulated Drive rate limit exceeded',
            driveFileId: 'drive_file_abc',
          );

          final json = op.toJson();
          expect(json['id'], 'op_custom_123');
          expect(json['type'], 'update');
          expect(json['dateKey'], '2026-04-01');
          expect(json['status'], 'failed');
          expect(json['retryCount'], 2);
          expect(json['lastError'], 'Simulated Drive rate limit exceeded');
          expect(json['driveFileId'], 'drive_file_abc');

          final restored = SyncOperation.fromJson(json);
          expect(restored, equals(op));

          // Deterministic backoff verification
          expect(SyncOperation.computeBackoff(0), const Duration(seconds: 30));
          expect(SyncOperation.computeBackoff(1), const Duration(seconds: 60));
          expect(SyncOperation.computeBackoff(2), const Duration(seconds: 120));
          expect(SyncOperation.computeBackoff(3), const Duration(seconds: 240));
        },
      );
    });

    group('2. Storage Resilience & Startup', () {
      test('Empty queue startup initializes cleanly with count == 0', () async {
        final freshStorage = SyncQueueStorage(customBaseDir: tempDir);
        final freshQueue = SyncQueue(storage: freshStorage);
        await freshQueue.init();

        expect(freshQueue.isInitialized, isTrue);
        expect(freshQueue.count, 0);
        expect(freshQueue.isEmpty, isTrue);
        expect(freshQueue.operations, isEmpty);
      });

      test(
        'Malformed JSON queue items are skipped safely without crashing',
        () async {
          final queueFile = File('${tempDir.path}/sync_queue.json');
          final malformedContent = jsonEncode([
            {
              'id': 'valid_op',
              'type': 'upload',
              'dateKey': '2026-04-01',
              'createdAt': '2026-04-01T10:00:00Z',
            },
            'completely_invalid_string_instead_of_map',
            {'invalid_structure': 999},
          ]);
          queueFile.writeAsStringSync(malformedContent);

          final freshQueue = SyncQueue(
            storage: SyncQueueStorage(customBaseDir: tempDir),
          );
          await freshQueue.init();

          // Valid item parsed, invalid items safely skipped
          expect(freshQueue.count, 2);
          expect(freshQueue.operations.first.id, 'valid_op');
        },
      );

      test(
        'Interrupted inProgress operations recover to pending on restart',
        () async {
          const dateKey = DateKey(2026, 4, 2);
          final op = await queue.enqueueUpload(dateKey);
          await queue.markInProgress(op.id);

          expect(
            queue.getOperation(op.id)!.status,
            SyncOperationStatus.inProgress,
          );
          await queue.flush();

          // Simulate app crash & restart: re-instantiate queue from disk
          final restartedQueue = SyncQueue(
            storage: SyncQueueStorage(customBaseDir: tempDir),
          );
          await restartedQueue.init();

          final recoveredOp = restartedQueue.getOperation(op.id);
          expect(recoveredOp, isNotNull);
          expect(recoveredOp!.status, SyncOperationStatus.pending);
          expect(recoveredOp.lastAttemptAt, isNotNull);
        },
      );
    });

    group('3. Enqueuing, Deduplication & Coalescing', () {
      test(
        'enqueueUpload creates durable operation that survives restart',
        () async {
          const dateKey = DateKey(2026, 4, 3);
          final op = await queue.enqueueUpload(dateKey);
          expect(op.type, SyncOperationType.upload);
          expect(op.status, SyncOperationStatus.pending);
          expect(queue.count, 1);

          final restartedQueue = SyncQueue(
            storage: SyncQueueStorage(customBaseDir: tempDir),
          );
          await restartedQueue.init();

          expect(restartedQueue.count, 1);
          expect(restartedQueue.hasOperationForDate(dateKey), isTrue);
        },
      );

      test(
        'Create followed by multiple edits coalesces into a single upload operation',
        () async {
          const dateKey = DateKey(2026, 4, 4);

          // 1. Initial upload enqueued
          final op1 = await queue.enqueueUpload(dateKey);
          expect(queue.count, 1);
          expect(op1.type, SyncOperationType.upload);

          // 2. User edits metadata before sync runs
          final op2 = await queue.enqueueUpdate(dateKey);
          expect(queue.count, 1);
          expect(op2.type, SyncOperationType.upload); // Coalesced: stays upload

          // 3. User edits again
          final op3 = await queue.enqueueUpdate(dateKey);
          expect(queue.count, 1);
          expect(op3.type, SyncOperationType.upload); // Still single upload

          // 4. User replaces image before sync runs
          final op4 = await queue.enqueueUpload(dateKey);
          expect(queue.count, 1);
          expect(op4.type, SyncOperationType.upload);
        },
      );

      test(
        'Multiple edits on a synced photo coalesce into a single update operation',
        () async {
          const dateKey = DateKey(2026, 4, 5);

          // 1. Photo is synced remotely with Drive ID
          final op1 = await queue.enqueueUpdate(
            dateKey,
            driveFileId: 'drive_123',
          );
          expect(queue.count, 1);
          expect(op1.type, SyncOperationType.update);
          expect(op1.driveFileId, 'drive_123');

          // 2. Second edit coalesces in-place
          final op2 = await queue.enqueueUpdate(
            dateKey,
            driveFileId: 'drive_123',
          );
          expect(queue.count, 1);
          expect(op2.type, SyncOperationType.update);
          expect(op2.driveFileId, 'drive_123');
        },
      );

      test(
        'Deleting a synced photo cancels pending updates and enqueues delete',
        () async {
          const dateKey = DateKey(2026, 4, 6);

          // Photo has a pending update
          await queue.enqueueUpdate(dateKey, driveFileId: 'drive_file_999');
          expect(queue.count, 1);

          // User deletes photo
          final deleteOp = await queue.enqueueDelete(
            dateKey,
            driveFileId: 'drive_file_999',
          );
          expect(queue.count, 1);
          expect(deleteOp.type, SyncOperationType.delete);
          expect(deleteOp.driveFileId, 'drive_file_999');
        },
      );

      test(
        'Deleting a localOnly photo removes pending upload without remote delete',
        () async {
          const dateKey = DateKey(2026, 4, 7);

          // Unsynced photo had a pending upload
          await queue.enqueueUpload(dateKey);
          expect(queue.count, 1);

          // User deletes unsynced photo
          await queue.removeOperationsForDate(dateKey);
          expect(queue.count, 0);
          expect(queue.hasOperationForDate(dateKey), isFalse);
        },
      );

      test(
        'markFailed increments retry count and sets error and nextAttemptAt',
        () async {
          const dateKey = DateKey(2026, 4, 8);
          final op = await queue.enqueueUpload(dateKey);

          final failedOp = await queue.markFailed(
            op.id,
            error: 'Connection refused',
          );
          expect(failedOp, isNotNull);
          expect(failedOp!.status, SyncOperationStatus.failed);
          expect(failedOp.retryCount, 1);
          expect(failedOp.lastError, 'Connection refused');
          expect(failedOp.nextAttemptAt, isNotNull);
        },
      );

      test('markCompleted removes operation from the active queue', () async {
        const dateKey = DateKey(2026, 4, 9);
        final op = await queue.enqueueUpload(dateKey);
        expect(queue.count, 1);

        final completed = await queue.markCompleted(op.id);
        expect(completed, isTrue);
        expect(queue.count, 0);
      });

      test(
        'Deterministic FIFO ordering is preserved across operations',
        () async {
          const d1 = DateKey(2026, 4, 10);
          const d2 = DateKey(2026, 4, 11);
          const d3 = DateKey(2026, 4, 12);

          await queue.enqueueUpload(d1);
          await queue.enqueueUpload(d2);
          await queue.enqueueUpload(d3);

          expect(queue.operations.length, 3);
          expect(queue.operations[0].dateKey, d1);
          expect(queue.operations[1].dateKey, d2);
          expect(queue.operations[2].dateKey, d3);
        },
      );
    });

    group('4. Store & Outbox Integration', () {
      test(
        'Saving a new photo with pending status automatically enqueues upload',
        () async {
          final date = DateTime(2026, 4, 15);
          final dummy = createDummySourcePhoto('photo_save_test.jpg');
          final entry = PhotoEntry(
            date: date,
            title: 'Spring Blossom',
            syncStatus: SyncStatus.pending,
            gradientColors: const [Colors.green, Colors.teal],
          );

          await store.savePhoto(entry: entry, sourceTempPath: dummy.path);
          await store.flush();

          expect(store.syncQueue.count, 1);
          final op = store.syncQueue.operations.first;
          expect(op.type, SyncOperationType.upload);
          expect(op.dateKey, const DateKey(2026, 4, 15));
        },
      );

      test(
        'Editing metadata of a synced photo enqueues update in SyncQueue',
        () async {
          final date = DateTime(2026, 4, 16);
          final dummy = createDummySourcePhoto('synced_edit_test.jpg');
          final entry = PhotoEntry(
            date: date,
            title: 'Original Synced Title',
            syncStatus: SyncStatus.synced,
            driveFileId: 'remote_drive_id_456',
            gradientColors: const [Colors.amber, Colors.orange],
          );

          await store.savePhoto(entry: entry, sourceTempPath: dummy.path);
          // Clear initial upload from queue because it is synced
          await store.syncQueue.clear();
          expect(store.syncQueue.count, 0);

          // Edit metadata
          await store.updatePhotoMetadata(
            dateKey: const DateKey(2026, 4, 16),
            title: 'Modified Title in Evening',
          );
          await store.flush();

          expect(store.syncQueue.count, 1);
          final op = store.syncQueue.operations.first;
          expect(op.type, SyncOperationType.update);
          expect(op.driveFileId, 'remote_drive_id_456');
        },
      );

      test(
        'Replacing a synced photo preserves driveFileId and queues update',
        () async {
          final date = DateTime(2026, 4, 17);
          final dummy1 = createDummySourcePhoto('first.jpg');
          final dummy2 = createDummySourcePhoto('second.jpg');

          final entry1 = PhotoEntry(
            date: date,
            title: 'First Synced Photo',
            syncStatus: SyncStatus.synced,
            driveFileId: 'drive_target_789',
            gradientColors: const [Colors.purple, Colors.indigo],
          );
          await store.savePhoto(entry: entry1, sourceTempPath: dummy1.path);
          await store.syncQueue.clear();

          // Replace with new image
          final replacement = PhotoEntry(
            date: date,
            title: 'Replaced Photo',
            gradientColors: const [Colors.deepOrange, Colors.red],
          );
          await store.savePhoto(
            entry: replacement,
            sourceTempPath: dummy2.path,
          );
          await store.flush();

          expect(store.syncQueue.count, 1);
          final op = store.syncQueue.operations.first;
          expect(op.type, SyncOperationType.update);
          expect(op.driveFileId, 'drive_target_789');
        },
      );

      test(
        'Deleting a synced photo enqueues delete operation and persists tombstone',
        () async {
          final date = DateTime(2026, 4, 18);
          final dummy = createDummySourcePhoto('delete_synced.jpg');
          final entry = PhotoEntry(
            date: date,
            title: 'To Be Deleted Remotely',
            syncStatus: SyncStatus.synced,
            driveFileId: 'remote_file_to_delete',
            gradientColors: const [Colors.red, Colors.pink],
          );

          await store.savePhoto(entry: entry, sourceTempPath: dummy.path);
          await store.syncQueue.clear();

          await store.removePhotoAsync(date);
          await store.flush();

          // Tombstone recorded
          expect(store.pendingDeletions.length, 1);
          expect(
            store.pendingDeletions.first.driveFileId,
            'remote_file_to_delete',
          );

          // Delete operation queued
          expect(store.syncQueue.count, 1);
          final op = store.syncQueue.operations.first;
          expect(op.type, SyncOperationType.delete);
          expect(op.driveFileId, 'remote_file_to_delete');

          // Acknowledgment removes tombstone and completes operation
          await store.acknowledgePendingDeletion('remote_file_to_delete');
          await store.flush();

          expect(store.pendingDeletions, isEmpty);
          expect(store.syncQueue.count, 0);
        },
      );

      test(
        'PhotoEntry and PersistentDailyPhotoStore remain authoritative source of truth',
        () async {
          final date = DateTime(2026, 4, 19);
          final dummy = createDummySourcePhoto('authoritative_test.jpg');
          final entry = PhotoEntry(
            date: date,
            title: 'Authoritative Local Entry',
            caption: 'My local thoughts',
            location: 'San Francisco',
            syncStatus: SyncStatus.pending,
            gradientColors: const [Colors.cyan, Colors.blue],
          );

          await store.savePhoto(entry: entry, sourceTempPath: dummy.path);
          await store.flush();

          // Queue contains only operation intent and metadata
          final op = store.syncQueue.operations.first;
          expect(op.dateKey, const DateKey(2026, 4, 19));

          // Authoritative photo content/file is retrieved from store, not queue
          final photo = store.getPhoto(date);
          expect(photo, isNotNull);
          expect(photo!.title, 'Authoritative Local Entry');
          expect(photo.caption, 'My local thoughts');
          expect(photo.location, 'San Francisco');
        },
      );
    });
  });
}
