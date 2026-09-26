import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/auth_user.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/drive_folder_reference.dart';
import 'package:photo_per_day/data/models/drive_folder_result.dart';
import 'package:photo_per_day/data/models/drive_photo_upload_response.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_operation_status.dart';
import 'package:photo_per_day/data/models/sync_operation_type.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/models/sync_tombstone.dart';
import 'package:photo_per_day/data/services/drive_api_adapter.dart';
import 'package:photo_per_day/data/services/drive_auth_storage.dart';
import 'package:photo_per_day/data/services/drive_folder_storage.dart';
import 'package:photo_per_day/data/services/google_auth_service.dart';
import 'package:photo_per_day/data/services/google_drive_auth_service.dart';
import 'package:photo_per_day/data/services/google_drive_photo_upload_service.dart';
import 'package:photo_per_day/data/services/google_drive_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/data/services/sync_queue.dart';
import 'package:photo_per_day/data/services/sync_queue_storage.dart';
import 'package:photo_per_day/data/services/sync_worker.dart';

class _FakeSignInDelegate implements GoogleSignInDelegate {
  AuthUser? currentUser;
  bool driveGranted = true;

  @override
  Future<AuthUser?> signInSilently() async => currentUser;

  @override
  Future<AuthUser?> signIn() async => currentUser;

  @override
  Future<void> signOut() async => currentUser = null;

  @override
  Future<void> disconnect() async => currentUser = null;

  @override
  Future<bool> canAccessDriveScope() async => driveGranted;

  @override
  Future<bool> requestDriveScope() async => driveGranted;

  @override
  Future<Map<String, String>> getAuthHeaders() async => {
    'Authorization': 'Bearer fake_token_${currentUser?.email}',
  };
}

class _FakeDriveAdapter implements DriveApiAdapter {
  DriveFolderReference? existingFolder;
  int uploadCalls = 0;
  final List<String> uploadFilenames = [];
  final List<String> uploadParentFolderIds = [];

  int updateCalls = 0;
  final List<String> updateFileIds = [];
  final List<String?> updateDescriptions = [];

  int trashCalls = 0;
  final List<String> trashedFileIds = [];

  DriveApiException? errorOnUpload;
  DriveApiException? errorOnUpdate;
  DriveApiException? errorOnTrash;

  @override
  Future<DriveFolderReference?> findFolder({
    required String folderName,
    required Map<String, String> authHeaders,
    String? accountEmail,
  }) async {
    if (existingFolder != null &&
        existingFolder!.authorizedEmail == accountEmail) {
      return existingFolder;
    }
    return null;
  }

  @override
  Future<DriveFolderReference> createFolder({
    required String folderName,
    required Map<String, String> authHeaders,
    String? accountEmail,
  }) async {
    final folder = DriveFolderReference(
      folderId: 'folder_${accountEmail?.replaceAll('@', '_') ?? 'unknown'}',
      folderName: folderName,
      authorizedEmail: accountEmail,
      resolvedAt: DateTime.now().toUtc(),
    );
    existingFolder = folder;
    return folder;
  }

  @override
  Future<DrivePhotoUploadResponse> uploadPhotoFile({
    required File file,
    required String filename,
    required String mimeType,
    required String parentFolderId,
    required Map<String, String> authHeaders,
    DriveUploadProgress? onProgress,
  }) async {
    uploadCalls++;
    uploadFilenames.add(filename);
    uploadParentFolderIds.add(parentFolderId);

    if (errorOnUpload != null) throw errorOnUpload!;

    onProgress?.call(1.0);
    return DrivePhotoUploadResponse(
      fileId: 'file_up_$uploadCalls',
      revision: '1',
      filename: filename,
      uploadedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<DrivePhotoUploadResponse> updatePhotoFile({
    required String fileId,
    required Map<String, String> authHeaders,
    File? file,
    String? filename,
    String? mimeType,
    String? description,
    DriveUploadProgress? onProgress,
  }) async {
    updateCalls++;
    updateFileIds.add(fileId);
    updateDescriptions.add(description);

    if (errorOnUpdate != null) throw errorOnUpdate!;

    onProgress?.call(1.0);
    return DrivePhotoUploadResponse(
      fileId: fileId,
      revision: 'rev_$updateCalls',
      filename: filename ?? 'updated.jpg',
      uploadedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> trashPhotoFile({
    required String fileId,
    required Map<String, String> authHeaders,
  }) async {
    trashCalls++;
    trashedFileIds.add(fileId);

    if (errorOnTrash != null) throw errorOnTrash!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeSignInDelegate signInDelegate;
  late _FakeDriveAdapter driveAdapter;
  late GoogleAuthService authService;
  late GoogleDriveAuthService driveAuthService;
  late GoogleDriveService driveService;
  late PersistentDailyPhotoStore photoStore;
  late GoogleDrivePhotoUploadService uploadService;
  late SyncWorker syncWorker;

  const userA = AuthUser(
    id: 'user_a',
    email: 'user_a@example.com',
    displayName: 'User A',
  );

  const userB = AuthUser(
    id: 'user_b',
    email: 'user_b@example.com',
    displayName: 'User B',
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_hardening_test_');

    signInDelegate = _FakeSignInDelegate();
    signInDelegate.currentUser = userA;
    authService = GoogleAuthService(delegate: signInDelegate);
    await authService.init();

    driveAuthService = GoogleDriveAuthService(
      authService: authService,
      storage: DriveAuthStorage(customBaseDir: tempDir.path),
    );
    await driveAuthService.init();

    driveAdapter = _FakeDriveAdapter();
    driveService = GoogleDriveService(
      adapter: driveAdapter,
      storage: DriveFolderStorage(customBaseDir: tempDir.path),
      authService: authService,
      driveAuthService: driveAuthService,
    );
    await driveService.init();
    GoogleDriveService.setTestInstance(driveService);

    final fileManager = PhotoFileManager(customBaseDir: tempDir);
    final metadataStorage = PhotoMetadataStorage(customBaseDir: tempDir);
    final queueStorage = SyncQueueStorage(customBaseDir: tempDir);
    final syncQueue = SyncQueue(storage: queueStorage);

    photoStore = PersistentDailyPhotoStore(
      fileManager: fileManager,
      metadataStorage: metadataStorage,
      syncQueue: syncQueue,
    );
    await photoStore.init();
    PersistentDailyPhotoStore.setTestInstance(photoStore);

    uploadService = GoogleDrivePhotoUploadService(
      adapter: driveAdapter,
      authService: authService,
      driveAuthService: driveAuthService,
      driveService: driveService,
      photoStore: photoStore,
    );
    GoogleDrivePhotoUploadService.setTestInstance(uploadService);

    syncWorker = SyncWorker(
      syncQueue: photoStore.syncQueue,
      photoStore: photoStore,
      authService: authService,
      driveAuthService: driveAuthService,
      driveService: driveService,
      uploadService: uploadService,
      driveAdapter: driveAdapter,
    );
    SyncWorker.setTestInstance(syncWorker);
  });

  tearDown(() async {
    SyncWorker.resetInstance();
    GoogleDrivePhotoUploadService.resetInstance();
    PersistentDailyPhotoStore.resetTestInstance();
    GoogleDriveService.resetInstance();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Future<void> authorizeAndSetupFolder(AuthUser user) async {
    signInDelegate.currentUser = user;
    await authService.signIn();
    await driveAuthService.authorizeDrive();
    await driveService.setupFolder();
  }

  Future<PhotoEntry> createPhoto(
    DateKey dateKey, {
    String filename = 'photo.jpg',
    List<int> bytes = const [1, 2, 3, 4],
    String? driveFileId,
    String? authorizedEmail,
    SyncStatus syncStatus = SyncStatus.localOnly,
  }) async {
    final file = File('${tempDir.path}${Platform.pathSeparator}$filename');
    file.writeAsBytesSync(bytes);

    final entry = PhotoEntry(
      date: dateKey.toDateTime(),
      title: 'Photo for ${dateKey.format()}',
      gradientColors: const [Colors.blue, Colors.purple],
      imagePath: file.path,
      syncStatus: syncStatus,
      driveFileId: driveFileId,
      authorizedEmail: authorizedEmail,
    );

    return await photoStore.savePhoto(entry: entry, sourceTempPath: file.path);
  }

  group('Milestone 24 — Account Switch Safety', () {
    test(
      '1. User B cannot execute User A queued upload, update, or delete operations',
      () async {
        // User A sets up Drive and queues operations
        await authorizeAndSetupFolder(userA);

        const keyUpload = DateKey(2026, 9, 1);
        const keyUpdate = DateKey(2026, 9, 2);
        const keyDelete = DateKey(2026, 9, 3);

        await createPhoto(keyUpload, filename: 'up_a.jpg');
        await createPhoto(
          keyUpdate,
          filename: 'upd_a.jpg',
          driveFileId: 'drive_a_file_2',
          authorizedEmail: userA.email,
        );

        // Queue operations explicitly tagged with User A's email
        await photoStore.syncQueue.enqueueUpload(
          keyUpload,
          authorizedEmail: userA.email,
        );
        await photoStore.syncQueue.enqueueUpdate(
          keyUpdate,
          driveFileId: 'drive_a_file_2',
          authorizedEmail: userA.email,
        );
        await photoStore.syncQueue.enqueueDelete(
          keyDelete,
          driveFileId: 'drive_a_file_3',
          authorizedEmail: userA.email,
        );

        expect(photoStore.syncQueue.count, 3);

        // User A signs out
        await authService.signOut();

        // User B signs in and sets up their folder
        await authorizeAndSetupFolder(userB);
        expect(driveService.currentFolder?.authorizedEmail, userB.email);
        expect(driveService.currentFolder?.folderId, contains('user_b'));

        // User B executes Sync Now
        final resultB = await syncWorker.syncNow();

        // All 3 operations must fail safely without calling Drive API under User B
        expect(resultB.failedCount, 3);
        expect(driveAdapter.uploadCalls, 0);
        expect(driveAdapter.updateCalls, 0);
        expect(driveAdapter.trashCalls, 0);

        // Operations remain in queue marked failed with account mismatch errors
        for (final op in photoStore.syncQueue.operations) {
          expect(op.status, SyncOperationStatus.failed);
          expect(op.lastError, contains(userA.email));
        }

        // Local photos are NOT deleted
        expect(photoStore.getPhotoByKey(keyUpload), isNotNull);
        expect(photoStore.getPhotoByKey(keyUpdate), isNotNull);
      },
    );

    test(
      '2. Account switch from User A to User B isolates Drive folder state on disk',
      () async {
        await authorizeAndSetupFolder(userA);
        expect(driveService.currentFolder?.authorizedEmail, userA.email);

        // Switch to User B
        await authService.signOut();
        await authorizeAndSetupFolder(userB);

        expect(driveService.currentFolder?.authorizedEmail, userB.email);
        expect(driveService.currentFolder?.folderId, contains('user_b'));

        // Verify folder storage file on disk contains User B's email
        final folderStorage = DriveFolderStorage(customBaseDir: tempDir.path);
        final stored = await folderStorage.loadFolderReference();
        expect(stored?.authorizedEmail, userB.email);
      },
    );

    test(
      '3. User A operations can execute successfully after User A signs back in',
      () async {
        await authorizeAndSetupFolder(userA);

        const keyUpload = DateKey(2026, 9, 5);
        await createPhoto(keyUpload, filename: 'p5.jpg');
        await photoStore.syncQueue.enqueueUpload(
          keyUpload,
          authorizedEmail: userA.email,
        );

        // Switch to User B
        await authService.signOut();
        await authorizeAndSetupFolder(userB);

        // User B syncNow fails safely
        final resultB = await syncWorker.syncNow();
        expect(resultB.failedCount, 1);
        expect(driveAdapter.uploadCalls, 0);

        // User B signs out, User A signs back in
        await authService.signOut();
        await authorizeAndSetupFolder(userA);

        // Re-enqueuing or resetting resets status to pending
        await photoStore.syncQueue.enqueueUpload(
          keyUpload,
          authorizedEmail: userA.email,
        );

        // User A syncNow succeeds!
        final resultA = await syncWorker.syncNow();
        expect(resultA.succeededCount, 1);
        expect(driveAdapter.uploadCalls, 1);
        expect(photoStore.syncQueue.isEmpty, isTrue);
      },
    );
  });

  group('Milestone 24 — Crash & Restart Recovery', () {
    test(
      '4. Interrupted inProgress queue operation is restored to pending upon restart',
      () async {
        await authorizeAndSetupFolder(userA);

        const dateKey = DateKey(2026, 9, 10);
        await createPhoto(dateKey, filename: 'crash_photo.jpg');

        final op = await photoStore.syncQueue.enqueueUpload(dateKey);
        await photoStore.syncQueue.markInProgress(op.id);

        expect(
          photoStore.syncQueue.getOperation(op.id)?.status,
          SyncOperationStatus.inProgress,
        );

        // Flush to simulate disk persistence before crash
        await photoStore.flush();

        // Simulate app restart: re-initialize a brand new SyncQueue from disk
        final newStorage = SyncQueueStorage(customBaseDir: tempDir);
        final restartedQueue = SyncQueue(storage: newStorage);
        await restartedQueue.init();

        // InProgress operation must be automatically recovered to pending
        final recoveredOp = restartedQueue.getOperation(op.id);
        expect(recoveredOp, isNotNull);
        expect(recoveredOp?.status, SyncOperationStatus.pending);
      },
    );

    test(
      '5. Tombstone in pending_deletions.json without queue operation is recovered on init',
      () async {
        // Simulate crash right after tombstone was saved to disk but before enqueueDelete
        const dateKey = DateKey(2026, 9, 11);
        final tombstone = SyncTombstone(
          dateKey: dateKey,
          driveFileId: 'drive_tombstone_crash_id',
          deletedAt: DateTime.now().toUtc(),
          authorizedEmail: userA.email,
        );

        final metaStorage = PhotoMetadataStorage(customBaseDir: tempDir);
        await metaStorage.init();
        await metaStorage.savePendingDeletions([tombstone]);

        // Start fresh PersistentDailyPhotoStore
        final restartedStore = PersistentDailyPhotoStore(
          fileManager: PhotoFileManager(customBaseDir: tempDir),
          metadataStorage: metaStorage,
          syncQueue: SyncQueue(
            storage: SyncQueueStorage(customBaseDir: tempDir),
          ),
        );
        await restartedStore.init();

        // Verify tombstone is loaded AND delete operation is automatically recovered into queue
        expect(restartedStore.pendingDeletions.length, 1);
        expect(restartedStore.hasPendingDeletion(dateKey), isTrue);

        final deleteOp = restartedStore.syncQueue.operations.firstWhere(
          (op) => op.type == SyncOperationType.delete,
        );
        expect(deleteOp.driveFileId, 'drive_tombstone_crash_id');
        expect(deleteOp.status, SyncOperationStatus.pending);

        // Run syncNow to verify full convergence
        await authorizeAndSetupFolder(userA);
        final worker = SyncWorker(
          syncQueue: restartedStore.syncQueue,
          photoStore: restartedStore,
          authService: authService,
          driveAuthService: driveAuthService,
          driveService: driveService,
          uploadService: uploadService,
          driveAdapter: driveAdapter,
        );

        final result = await worker.syncNow();
        expect(result.deletedCount, 1);
        expect(driveAdapter.trashCalls, 1);
        expect(driveAdapter.trashedFileIds, ['drive_tombstone_crash_id']);

        // Tombstone is cleared upon confirmed Drive deletion
        expect(restartedStore.pendingDeletions.isEmpty, isTrue);
        expect(restartedStore.syncQueue.isEmpty, isTrue);
      },
    );
  });

  group('Milestone 24 — Idempotency & Repeated Operations', () {
    test(
      '6. Repeated Sync Now call on empty/cleared queue is a clean no-op',
      () async {
        await authorizeAndSetupFolder(userA);

        const dateKey = DateKey(2026, 9, 15);
        await createPhoto(dateKey, filename: 'p15.jpg');
        await photoStore.syncQueue.enqueueUpload(dateKey);

        // First sync succeeds
        final result1 = await syncWorker.syncNow();
        expect(result1.uploadedCount, 1);
        expect(driveAdapter.uploadCalls, 1);
        expect(photoStore.syncQueue.isEmpty, isTrue);

        // Immediate second sync
        final result2 = await syncWorker.syncNow();
        expect(result2.isEmpty, isTrue);
        expect(result2.processedCount, 0);

        // Zero additional Drive API calls
        expect(driveAdapter.uploadCalls, 1);
      },
    );

    test(
      '7. Upload operation for photo that already has driveFileId updates remote file instead of creating duplicate',
      () async {
        await authorizeAndSetupFolder(userA);

        const dateKey = DateKey(2026, 9, 16);
        // Photo already has a Drive file ID, but syncStatus is pending (e.g. edited image)
        await createPhoto(
          dateKey,
          filename: 'p16.jpg',
          driveFileId: 'existing_drive_id_16',
          authorizedEmail: userA.email,
          syncStatus: SyncStatus.pending,
        );

        // Queue has an upload operation (e.g. from legacy state or coalescing)
        await photoStore.syncQueue.enqueueUpload(dateKey);

        final result = await syncWorker.syncNow();

        // Must NOT call uploadPhotoFile (which would create a duplicate!)
        expect(driveAdapter.uploadCalls, 0);

        // Instead, must update the existing remote file ID!
        expect(driveAdapter.updateCalls, 1);
        expect(driveAdapter.updateFileIds, ['existing_drive_id_16']);
        expect(result.succeededCount, 1);
        expect(result.processedCount, 1);

        // Photo is now marked synced
        final photo = photoStore.getPhotoByKey(dateKey);
        expect(photo?.syncStatus, SyncStatus.synced);
        expect(photo?.driveFileId, 'existing_drive_id_16');
      },
    );

    test(
      '8. Delete on already-trashed file (HTTP 404) is idempotent success and clears tombstone',
      () async {
        await authorizeAndSetupFolder(userA);

        const dateKey = DateKey(2026, 9, 17);
        await createPhoto(
          dateKey,
          driveFileId: 'drive_already_deleted_404',
          authorizedEmail: userA.email,
        );

        // Remove photo locally (creates tombstone and queues delete)
        await photoStore.removePhotoAsync(dateKey.toDateTime());
        expect(photoStore.pendingDeletions.length, 1);
        expect(photoStore.syncQueue.count, 1);

        // Drive returns 404
        driveAdapter.errorOnTrash = const DriveApiException(
          'Target resource not found',
          errorType: DriveFolderErrorType.notFound,
        );

        final result = await syncWorker.syncNow();

        // 404 is treated as idempotent success
        expect(result.deletedCount, 1);
        expect(result.succeededCount, 1);

        // Tombstone and queue item are acknowledged and removed
        expect(photoStore.pendingDeletions.isEmpty, isTrue);
        expect(photoStore.syncQueue.isEmpty, isTrue);
      },
    );
  });

  group('Milestone 24 — Queue & PhotoEntry Consistency', () {
    test(
      '9. Replacing local photo uploads the newest image, not the old image',
      () async {
        await authorizeAndSetupFolder(userA);

        const dateKey = DateKey(2026, 9, 20);

        // 1. Initial capture
        await createPhoto(
          dateKey,
          filename: 'initial.jpg',
          bytes: [10, 20, 30],
        );
        await photoStore.syncQueue.enqueueUpload(dateKey);

        // 2. Replace photo before sync occurs
        final newFile = File(
          '${tempDir.path}${Platform.pathSeparator}replacement.jpg',
        );
        newFile.writeAsBytesSync([100, 200, 250]);

        final newEntry = PhotoEntry(
          date: dateKey.toDateTime(),
          title: 'Replaced Capture',
          gradientColors: const [Colors.red, Colors.orange],
          imagePath: newFile.path,
        );
        await photoStore.savePhoto(
          entry: newEntry,
          sourceTempPath: newFile.path,
        );

        // Queue still coalesced to 1 upload
        expect(photoStore.syncQueue.count, 1);

        // 3. Sync Now
        final result = await syncWorker.syncNow();
        expect(result.uploadedCount, 1);

        // Verify the latest PhotoEntry was uploaded and marked synced
        final latestEntry = photoStore.getPhotoByKey(dateKey);
        expect(latestEntry?.title, 'Replaced Capture');
        expect(latestEntry?.syncStatus, SyncStatus.synced);
        expect(latestEntry?.driveFileId, isNotNull);
      },
    );

    test(
      '10. Multiple metadata edits coalesce into a single update operation with latest metadata',
      () async {
        await authorizeAndSetupFolder(userA);

        const dateKey = DateKey(2026, 9, 21);
        await createPhoto(
          dateKey,
          filename: 'p21.jpg',
          driveFileId: 'drive_21',
          authorizedEmail: userA.email,
          syncStatus: SyncStatus.synced,
        );

        // Multiple consecutive metadata edits
        await photoStore.updatePhotoMetadata(dateKey: dateKey, title: 'Edit 1');
        await photoStore.updatePhotoMetadata(
          dateKey: dateKey,
          title: 'Edit 2',
          caption: 'Caption 2',
        );
        await photoStore.updatePhotoMetadata(
          dateKey: dateKey,
          title: 'Final Title',
          caption: 'Final Caption',
          location: 'Final Location',
        );

        // Coalesced into exactly 1 update operation
        expect(photoStore.syncQueue.count, 1);
        expect(
          photoStore.syncQueue.operations.first.type,
          SyncOperationType.update,
        );

        final result = await syncWorker.syncNow();
        expect(result.updatedCount, 1);
        expect(driveAdapter.updateCalls, 1);

        // Remote description has the latest metadata
        expect(
          driveAdapter.updateDescriptions.first,
          contains('Title: Final Title'),
        );
        expect(
          driveAdapter.updateDescriptions.first,
          contains('Caption: Final Caption'),
        );
        expect(
          driveAdapter.updateDescriptions.first,
          contains('Location: Final Location'),
        );
      },
    );
  });

  group('Milestone 24 — Missing Local Photo Handling', () {
    test(
      '11. Missing local image file marks operation failed and updates PhotoEntry syncStatus to failed',
      () async {
        await authorizeAndSetupFolder(userA);

        const dateKey = DateKey(2026, 9, 25);
        final entry = await createPhoto(dateKey, filename: 'p25.jpg');
        await photoStore.syncQueue.enqueueUpload(dateKey);

        // Delete the underlying image file from disk to simulate file loss
        final imageFile = File(entry.imagePath!);
        imageFile.deleteSync();
        expect(imageFile.existsSync(), isFalse);

        final result = await syncWorker.syncNow();

        // Worker does NOT claim successful sync
        expect(result.failedCount, 1);
        expect(result.uploadedCount, 0);
        expect(driveAdapter.uploadCalls, 0);

        // Queue operation remains failed with retry state
        final op = photoStore.syncQueue.getOperationForDate(dateKey);
        expect(op?.status, SyncOperationStatus.failed);
        expect(op?.lastError, contains('missing or empty'));
        expect(op?.retryCount, 1);

        // PhotoEntry syncStatus is set to failed
        final updatedPhoto = photoStore.getPhotoByKey(dateKey);
        expect(updatedPhoto?.syncStatus, SyncStatus.failed);
        expect(updatedPhoto?.syncError, contains('missing or empty'));
      },
    );
  });

  group('Milestone 24 — Mixed Queue FIFO & Operation Isolation', () {
    test(
      '12. Mixed queue (UPLOAD, UPDATE, DELETE) processes in exact order with failure isolation',
      () async {
        await authorizeAndSetupFolder(userA);

        const key1 = DateKey(2026, 9, 26);
        const key2 = DateKey(2026, 9, 27);
        const key3 = DateKey(2026, 9, 28);
        const key4 = DateKey(2026, 9, 29);

        // 1. Upload op
        await createPhoto(key1, filename: 'p26.jpg');
        await photoStore.syncQueue.enqueueUpload(key1);

        // 2. Update op (will fail due to simulated network timeout)
        await createPhoto(
          key2,
          filename: 'p27.jpg',
          driveFileId: 'drive_fail_27',
          authorizedEmail: userA.email,
        );
        await photoStore.syncQueue.enqueueUpdate(
          key2,
          driveFileId: 'drive_fail_27',
        );

        // 3. Delete op
        await createPhoto(
          key3,
          driveFileId: 'drive_del_28',
          authorizedEmail: userA.email,
        );
        await photoStore.removePhotoAsync(key3.toDateTime());

        // 4. Second Upload op
        await createPhoto(key4, filename: 'p29.jpg');
        await photoStore.syncQueue.enqueueUpload(key4);

        expect(photoStore.syncQueue.count, 4);

        // Simulate update failure on key2
        driveAdapter.errorOnUpdate = const DriveApiException(
          'Timeout updating file',
          errorType: DriveFolderErrorType.networkError,
        );

        final result = await syncWorker.syncNow();

        // 3 succeeded (1 upload, 1 delete, 1 upload), 1 failed (the update)
        expect(result.processedCount, 4);
        expect(result.succeededCount, 3);
        expect(result.uploadedCount, 2);
        expect(result.deletedCount, 1);
        expect(result.failedCount, 1);
        expect(result.remainingCount, 1);

        // Only the failed update operation remains in queue
        final remainingOps = photoStore.syncQueue.operations;
        expect(remainingOps.length, 1);
        expect(remainingOps.first.dateKey, key2);
        expect(remainingOps.first.status, SyncOperationStatus.failed);

        // Other operations acknowledged properly
        expect(photoStore.getPhotoByKey(key1)?.syncStatus, SyncStatus.synced);
        expect(photoStore.getPhotoByKey(key4)?.syncStatus, SyncStatus.synced);
        expect(photoStore.hasPendingDeletion(key3), isFalse);
      },
    );
  });
}
