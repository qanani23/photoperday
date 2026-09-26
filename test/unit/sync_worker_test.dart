import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/auth_user.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/drive_folder_reference.dart';
import 'package:photo_per_day/data/models/drive_folder_result.dart';
import 'package:photo_per_day/data/models/drive_photo_upload_response.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_operation.dart';
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

class TestFakeGoogleSignInDelegate implements GoogleSignInDelegate {
  AuthUser? mockUser;
  bool driveScopeGranted = true;
  bool canAccessScopeResult = true;

  @override
  Future<AuthUser?> signInSilently() async => mockUser;

  @override
  Future<AuthUser?> signIn() async => mockUser;

  @override
  Future<void> signOut() async => mockUser = null;

  @override
  Future<void> disconnect() async => mockUser = null;

  @override
  Future<bool> canAccessDriveScope() async => canAccessScopeResult;

  @override
  Future<bool> requestDriveScope() async => driveScopeGranted;

  @override
  Future<Map<String, String>> getAuthHeaders() async => {
    'Authorization': 'Bearer fake_mock_access_token',
    'X-Goog-AuthUser': '0',
  };
}

class TestFakeDriveApiAdapter implements DriveApiAdapter {
  DriveFolderReference? existingFolder;
  DriveApiException? errorOnUpload;
  int uploadCalls = 0;
  final List<String> uploadOrder = [];
  Completer<void>? uploadBlocker;

  DriveApiException? errorOnUpdate;
  String? errorOnFileId;
  int updateCalls = 0;
  final List<String> updateFileIds = [];
  final List<String?> updateDescriptions = [];

  DriveApiException? errorOnTrash;
  int trashCalls = 0;
  final List<String> trashedFileIds = [];

  @override
  Future<DriveFolderReference?> findFolder({
    required String folderName,
    required Map<String, String> authHeaders,
    String? accountEmail,
  }) async => existingFolder;

  @override
  Future<DriveFolderReference> createFolder({
    required String folderName,
    required Map<String, String> authHeaders,
    String? accountEmail,
  }) async {
    return DriveFolderReference(
      folderId: 'photo_a_day_drive_folder_id',
      folderName: folderName,
      authorizedEmail: accountEmail,
      resolvedAt: DateTime.now().toUtc(),
    );
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
    uploadOrder.add(filename);

    if (uploadBlocker != null) {
      await uploadBlocker!.future;
    }

    if (errorOnUpload != null) {
      throw errorOnUpload!;
    }

    if (onProgress != null) {
      onProgress(0.5);
      onProgress(1.0);
    }

    return DrivePhotoUploadResponse(
      fileId: 'drive_file_id_$uploadCalls',
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

    if (uploadBlocker != null) {
      await uploadBlocker!.future;
    }

    if (errorOnUpdate != null) {
      if (errorOnFileId == null || errorOnFileId == fileId) {
        throw errorOnUpdate!;
      }
    }

    if (onProgress != null) {
      onProgress(0.5);
      onProgress(1.0);
    }

    return DrivePhotoUploadResponse(
      fileId: fileId,
      revision: 'rev_$updateCalls',
      filename: filename ?? 'updated_photo.jpg',
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

    if (uploadBlocker != null) {
      await uploadBlocker!.future;
    }

    if (errorOnTrash != null) {
      throw errorOnTrash!;
    }
  }
}

class TestFakePhotoFileManager extends PhotoFileManager {
  TestFakePhotoFileManager({super.customBaseDir});

  @override
  Future<void> init() async {}

  @override
  Future<String> persistPhotoFile({
    required String sourcePath,
    required DateKey dateKey,
  }) async => sourcePath;

  @override
  bool isManagedPath(String path) => true;

  @override
  Future<bool> deletePhotoFile(String? path) async => true;

  @override
  Future<List<String>> pruneUnreferencedPhotos(
    Set<String> referencedPaths,
  ) async => [];
}

class TestFakePhotoMetadataStorage extends PhotoMetadataStorage {
  TestFakePhotoMetadataStorage({super.customBaseDir});

  final Map<DateKey, PhotoEntry> _memory = {};
  final List<SyncTombstone> _deletions = [];

  @override
  Future<void> init() async {}

  @override
  Future<Map<DateKey, PhotoEntry>> loadAll() async => Map.from(_memory);

  @override
  Future<void> saveAll(Map<DateKey, PhotoEntry> entries) async {
    _memory.clear();
    _memory.addAll(entries);
  }

  @override
  Future<List<SyncTombstone>> loadPendingDeletions() async =>
      List.from(_deletions);

  @override
  Future<void> savePendingDeletions(List<SyncTombstone> deletions) async {
    _deletions.clear();
    _deletions.addAll(deletions);
  }

  @override
  Future<void> clear() async {
    _memory.clear();
    _deletions.clear();
  }
}

class TestFakeSyncQueueStorage extends SyncQueueStorage {
  TestFakeSyncQueueStorage({super.customBaseDir});

  final List<SyncOperation> _ops = [];

  @override
  Future<void> init() async {}

  @override
  Future<List<SyncOperation>> loadQueue() async => List.from(_ops);

  @override
  Future<void> saveQueue(List<SyncOperation> operations) async {
    _ops.clear();
    _ops.addAll(operations);
  }

  @override
  Future<void> clear() async => _ops.clear();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late TestFakeGoogleSignInDelegate fakeSignInDelegate;
  late TestFakeDriveApiAdapter fakeAdapter;
  late GoogleAuthService authService;
  late GoogleDriveAuthService driveAuthService;
  late GoogleDriveService driveService;
  late PersistentDailyPhotoStore photoStore;
  late GoogleDrivePhotoUploadService uploadService;
  late SyncWorker syncWorker;
  late TestFakeSyncQueueStorage fakeSyncQueueStorage;

  const testUser = AuthUser(
    id: 'user_sync_1',
    email: 'sync_user@example.com',
    displayName: 'Sync User',
  );

  const testColors = [Color(0xFF222222), Color(0xFF444444)];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_worker_test_');

    fakeSignInDelegate = TestFakeGoogleSignInDelegate();
    fakeSignInDelegate.mockUser = testUser;
    authService = GoogleAuthService(delegate: fakeSignInDelegate);
    await authService.init();

    driveAuthService = GoogleDriveAuthService(
      authService: authService,
      storage: DriveAuthStorage(customBaseDir: tempDir.path),
    );
    await driveAuthService.init();

    fakeAdapter = TestFakeDriveApiAdapter();
    driveService = GoogleDriveService(
      adapter: fakeAdapter,
      storage: DriveFolderStorage(customBaseDir: tempDir.path),
      authService: authService,
      driveAuthService: driveAuthService,
    );
    await driveService.init();
    GoogleDriveService.setTestInstance(driveService);

    final fakeFileManager = TestFakePhotoFileManager(customBaseDir: tempDir);
    final fakeMetadataStorage = TestFakePhotoMetadataStorage(
      customBaseDir: tempDir,
    );
    fakeSyncQueueStorage = TestFakeSyncQueueStorage(customBaseDir: tempDir);
    final syncQueue = SyncQueue(storage: fakeSyncQueueStorage);

    photoStore = PersistentDailyPhotoStore(
      fileManager: fakeFileManager,
      metadataStorage: fakeMetadataStorage,
      syncQueue: syncQueue,
    );
    await photoStore.init();
    PersistentDailyPhotoStore.setTestInstance(photoStore);

    uploadService = GoogleDrivePhotoUploadService(
      adapter: fakeAdapter,
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
      driveAdapter: fakeAdapter,
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

  Future<void> setupReadyDriveState() async {
    await authService.signIn();
    await driveAuthService.authorizeDrive();

    fakeAdapter.existingFolder = DriveFolderReference(
      folderId: 'photo_a_day_drive_folder_id',
      folderName: 'Photo a Day',
      authorizedEmail: testUser.email,
      resolvedAt: DateTime.now().toUtc(),
    );
    await driveService.setupFolder();

    expect(authService.isSignedIn, isTrue);
    expect(driveAuthService.isAuthorized, isTrue);
    expect(driveService.isReady, isTrue);
  }

  Future<PhotoEntry> createLocalPhoto({
    required DateKey dateKey,
    String filename = 'test_photo.jpg',
    List<int> bytes = const [1, 2, 3, 4, 5],
    SyncStatus syncStatus = SyncStatus.pending,
    String? driveFileId,
    String? title,
    String? caption,
    String? location,
  }) async {
    final file = File('${tempDir.path}${Platform.pathSeparator}$filename');
    file.writeAsBytesSync(bytes);

    final entry = PhotoEntry(
      date: dateKey.toDateTime(),
      title: title ?? 'Memory ${dateKey.format()}',
      caption: caption,
      location: location,
      gradientColors: testColors,
      imagePath: file.path,
      syncStatus: syncStatus,
      driveFileId: driveFileId,
    );

    return await photoStore.savePhoto(entry: entry, sourceTempPath: file.path);
  }

  group('SyncWorker - Happy Path & FIFO', () {
    test(
      '1. processes one pending upload, uploads to Drive, updates photo to synced, and acknowledges queue',
      () async {
        await setupReadyDriveState();

        const dateKey = DateKey(2026, 3, 15);
        await createLocalPhoto(dateKey: dateKey, filename: 'photo_15.jpg');

        // Enqueue upload
        final op = await photoStore.syncQueue.enqueueUpload(dateKey);
        expect(photoStore.syncQueue.count, 1);
        expect(op.status, SyncOperationStatus.pending);

        final result = await syncWorker.syncNow();

        expect(result.isSuccess, isTrue);
        expect(result.processedCount, 1);
        expect(result.succeededCount, 1);
        expect(result.failedCount, 0);
        expect(result.remainingCount, 0);

        // Verify Drive upload was called once
        expect(fakeAdapter.uploadCalls, 1);
        expect(fakeAdapter.uploadOrder, ['photo_2026-03-15.jpg']);

        // Verify photo is marked synced in store with remote ID and revision
        final updatedEntry = photoStore.getPhotoByKey(dateKey);
        expect(updatedEntry?.syncStatus, SyncStatus.synced);
        expect(updatedEntry?.driveFileId, 'drive_file_id_1');
        expect(updatedEntry?.driveFileRevision, '1');

        // Verify queue operation was acknowledged and removed
        expect(photoStore.syncQueue.isEmpty, isTrue);
        expect(photoStore.syncQueue.getOperation(op.id), isNull);
      },
    );

    test(
      '2. FIFO Execution: processes multiple queued uploads in exact FIFO order',
      () async {
        await setupReadyDriveState();

        const keyA = DateKey(2026, 3, 10);
        const keyB = DateKey(2026, 3, 11);
        const keyC = DateKey(2026, 3, 12);

        await createLocalPhoto(dateKey: keyA, filename: 'photo_a.jpg');
        await createLocalPhoto(dateKey: keyB, filename: 'photo_b.jpg');
        await createLocalPhoto(dateKey: keyC, filename: 'photo_c.jpg');

        await photoStore.syncQueue.enqueueUpload(keyA);
        await photoStore.syncQueue.enqueueUpload(keyB);
        await photoStore.syncQueue.enqueueUpload(keyC);

        expect(photoStore.syncQueue.count, 3);

        final result = await syncWorker.syncNow();

        expect(result.isSuccess, isTrue);
        expect(result.processedCount, 3);
        expect(result.succeededCount, 3);
        expect(result.failedCount, 0);
        expect(result.remainingCount, 0);

        // Verify exact FIFO order: A, B, C
        expect(fakeAdapter.uploadCalls, 3);
        expect(fakeAdapter.uploadOrder, [
          'photo_2026-03-10.jpg',
          'photo_2026-03-11.jpg',
          'photo_2026-03-12.jpg',
        ]);

        // Verify all photos synced
        expect(photoStore.getPhotoByKey(keyA)?.syncStatus, SyncStatus.synced);
        expect(photoStore.getPhotoByKey(keyB)?.syncStatus, SyncStatus.synced);
        expect(photoStore.getPhotoByKey(keyC)?.syncStatus, SyncStatus.synced);
        expect(photoStore.syncQueue.isEmpty, isTrue);
      },
    );
  });

  group('SyncWorker - Failure & Offline Preservation', () {
    test(
      '3. failure preserves local photo, keeps operation queued, increments retryCount, and sets nextAttemptAt',
      () async {
        await setupReadyDriveState();

        const dateKey = DateKey(2026, 4, 1);
        final entry = await createLocalPhoto(
          dateKey: dateKey,
          filename: 'photo_err.jpg',
        );
        final op = await photoStore.syncQueue.enqueueUpload(dateKey);

        // Simulate API failure
        fakeAdapter.errorOnUpload = const DriveApiException(
          'HTTP 500 Internal Server Error',
          errorType: DriveFolderErrorType.apiError,
        );

        final result = await syncWorker.syncNow();

        expect(result.hasFailures, isTrue);
        expect(result.processedCount, 1);
        expect(result.succeededCount, 0);
        expect(result.failedCount, 1);
        expect(result.remainingCount, 1);

        // Local photo entry MUST NOT be marked synced
        final localPhoto = photoStore.getPhotoByKey(dateKey);
        expect(localPhoto?.syncStatus, SyncStatus.failed);

        // CRITICAL: Local photo file MUST be preserved!
        expect(File(entry.imagePath!).existsSync(), isTrue);

        // Queue operation MUST remain queued with failure info and retry scheduled
        final queuedOp = photoStore.syncQueue.getOperation(op.id);
        expect(queuedOp, isNotNull);
        expect(queuedOp!.status, SyncOperationStatus.failed);
        expect(queuedOp.retryCount, 1);
        expect(queuedOp.lastError, contains('500 Internal Server Error'));
        expect(queuedOp.nextAttemptAt, isNotNull);
      },
    );

    test(
      '4. skips failed operations that are still waiting for retry backoff',
      () async {
        await setupReadyDriveState();

        const dateKey = DateKey(2026, 4, 5);
        await createLocalPhoto(dateKey: dateKey);
        final op = await photoStore.syncQueue.enqueueUpload(dateKey);

        // Manually simulate an existing failed operation with nextAttemptAt in the future
        final futureAttempt = DateTime.now().toUtc().add(
          const Duration(hours: 2),
        );
        await photoStore.syncQueue.markFailed(
          op.id,
          error: 'Earlier network drop',
          nextAttemptAt: futureAttempt,
        );

        final result = await syncWorker.syncNow();

        expect(result.skippedCount, 1);
        expect(result.processedCount, 0);
        expect(result.succeededCount, 0);
        expect(fakeAdapter.uploadCalls, 0);

        // Operation is still in queue
        expect(photoStore.syncQueue.count, 1);
      },
    );
  });

  group('SyncWorker - Preconditions & Authentication', () {
    test(
      '5. signed-out state aborts sync, does NOT call Drive, and preserves queue operations',
      () async {
        fakeSignInDelegate.mockUser = null;
        await authService.signOut();
        expect(authService.isSignedIn, isFalse);

        const dateKey = DateKey(2026, 5, 1);
        await createLocalPhoto(dateKey: dateKey);
        final op = await photoStore.syncQueue.enqueueUpload(dateKey);

        final result = await syncWorker.syncNow();

        expect(result.notSignedIn, isTrue);
        expect(result.isPreconditionFailure, isTrue);
        expect(fakeAdapter.uploadCalls, 0);

        // Queue operation remains completely untouched
        final queuedOp = photoStore.syncQueue.getOperation(op.id);
        expect(queuedOp?.status, SyncOperationStatus.pending);
        expect(photoStore.syncQueue.count, 1);
      },
    );

    test(
      '6. unauthorized Drive state aborts sync, does NOT call Drive, and preserves queue',
      () async {
        await authService.signIn();
        // Drive scope NOT authorized
        expect(driveAuthService.isAuthorized, isFalse);

        const dateKey = DateKey(2026, 5, 2);
        await createLocalPhoto(dateKey: dateKey);
        final op = await photoStore.syncQueue.enqueueUpload(dateKey);

        final result = await syncWorker.syncNow();

        expect(result.notAuthorized, isTrue);
        expect(fakeAdapter.uploadCalls, 0);
        expect(
          photoStore.syncQueue.getOperation(op.id)?.status,
          SyncOperationStatus.pending,
        );
      },
    );

    test(
      '7. uninitialized Drive folder aborts sync, does NOT call Drive, and preserves queue',
      () async {
        await authService.signIn();
        await driveAuthService.authorizeDrive();
        // Folder not setup
        expect(driveService.isReady, isFalse);

        const dateKey = DateKey(2026, 5, 3);
        await createLocalPhoto(dateKey: dateKey);
        final op = await photoStore.syncQueue.enqueueUpload(dateKey);

        final result = await syncWorker.syncNow();

        expect(result.folderNotReady, isTrue);
        expect(fakeAdapter.uploadCalls, 0);
        expect(
          photoStore.syncQueue.getOperation(op.id)?.status,
          SyncOperationStatus.pending,
        );
      },
    );
  });

  group('SyncWorker - Scope & Queue Isolation', () {
    test(
      '8. processes upload, update, and delete operations in FIFO queue order',
      () async {
        await setupReadyDriveState();

        const keyUpload = DateKey(2026, 6, 1);
        const keyUpdate = DateKey(2026, 6, 2);
        const keyDelete = DateKey(2026, 6, 3);

        await createLocalPhoto(dateKey: keyUpload, filename: 'upload.jpg');
        await createLocalPhoto(
          dateKey: keyUpdate,
          filename: 'update.jpg',
          syncStatus: SyncStatus.synced,
          driveFileId: 'id_upd',
        );

        final uploadOp = await photoStore.syncQueue.enqueueUpload(keyUpload);
        final updateOp = await photoStore.syncQueue.enqueueUpdate(
          keyUpdate,
          driveFileId: 'id_upd',
        );
        final deleteOp = await photoStore.syncQueue.enqueueDelete(
          keyDelete,
          driveFileId: 'id_del',
        );

        expect(photoStore.syncQueue.count, 3);

        final result = await syncWorker.syncNow();

        expect(result.processedCount, 3);
        expect(result.succeededCount, 3);
        expect(result.uploadedCount, 1);
        expect(result.updatedCount, 1);
        expect(result.deletedCount, 1);
        expect(result.unsupportedCount, 0);
        expect(result.remainingCount, 0);

        // Upload executed
        expect(fakeAdapter.uploadCalls, 1);
        expect(fakeAdapter.uploadOrder, ['photo_2026-06-01.jpg']);

        // Update executed
        expect(fakeAdapter.updateCalls, 1);
        expect(fakeAdapter.updateFileIds, ['id_upd']);

        // Delete executed
        expect(fakeAdapter.trashCalls, 1);
        expect(fakeAdapter.trashedFileIds, ['id_del']);

        // All ops acknowledged and removed from queue
        expect(photoStore.syncQueue.getOperation(uploadOp.id), isNull);
        expect(photoStore.syncQueue.getOperation(updateOp.id), isNull);
        expect(photoStore.syncQueue.getOperation(deleteOp.id), isNull);
      },
    );

    test(
      '9. already-synced photo acknowledges queue item without duplicate remote upload',
      () async {
        await setupReadyDriveState();

        const dateKey = DateKey(2026, 6, 10);
        await createLocalPhoto(
          dateKey: dateKey,
          syncStatus: SyncStatus.synced,
          driveFileId: 'already_existing_remote_id',
        );

        final op = await photoStore.syncQueue.enqueueUpload(dateKey);
        expect(photoStore.syncQueue.count, 1);

        final result = await syncWorker.syncNow();

        expect(result.succeededCount, 1);
        expect(result.processedCount, 1);
        expect(result.remainingCount, 0);

        // ZERO Drive API upload calls made!
        expect(fakeAdapter.uploadCalls, 0);

        // Obsolete upload operation acknowledged and removed
        expect(photoStore.syncQueue.getOperation(op.id), isNull);
      },
    );

    test(
      '10. missing local photo marks queue item failed without crashing worker',
      () async {
        await setupReadyDriveState();

        const dateKey = DateKey(2026, 6, 20);
        // Photo is NOT created in photoStore!
        final op = await photoStore.syncQueue.enqueueUpload(dateKey);

        final result = await syncWorker.syncNow();

        expect(result.hasFailures, isTrue);
        expect(result.failedCount, 1);
        expect(result.processedCount, 1);
        expect(fakeAdapter.uploadCalls, 0);

        // Queue op marked failed with diagnostic error message
        final queuedOp = photoStore.syncQueue.getOperation(op.id);
        expect(queuedOp?.status, SyncOperationStatus.failed);
        expect(
          queuedOp?.lastError,
          contains('Local photo memory no longer exists'),
        );
      },
    );
  });

  group('SyncWorker - Concurrency & Progress', () {
    test(
      '11. in-flight lock rejects second concurrent syncNow() call',
      () async {
        await setupReadyDriveState();

        const dateKey = DateKey(2026, 7, 1);
        await createLocalPhoto(dateKey: dateKey);
        await photoStore.syncQueue.enqueueUpload(dateKey);

        fakeAdapter.uploadBlocker = Completer<void>();

        final firstFuture = syncWorker.syncNow();

        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(syncWorker.isSyncing, isTrue);

        // Second call while first is in flight
        final secondResult = await syncWorker.syncNow();

        expect(secondResult.alreadyRunning, isTrue);
        expect(secondResult.errorMessage, contains('already in progress'));

        // Release blocker
        fakeAdapter.uploadBlocker!.complete();
        final firstResult = await firstFuture;

        expect(firstResult.isSuccess, isTrue);
        expect(syncWorker.isSyncing, isFalse);
      },
    );

    test('12. forwards activeProgress during transmission', () async {
      await setupReadyDriveState();

      const dateKey = DateKey(2026, 7, 10);
      await createLocalPhoto(dateKey: dateKey);
      await photoStore.syncQueue.enqueueUpload(dateKey);

      final capturedProgress = <double>[];
      syncWorker.addListener(() {
        if (syncWorker.activeProgress != null) {
          capturedProgress.add(syncWorker.activeProgress!);
        }
      });

      final result = await syncWorker.syncNow();

      expect(result.isSuccess, isTrue);
      expect(capturedProgress, contains(0.5));
      expect(capturedProgress, contains(1.0));
      expect(syncWorker.activeProgress, isNull);
    });

    test(
      '13. empty queue returns clean empty result without making API calls',
      () async {
        await setupReadyDriveState();

        expect(photoStore.syncQueue.isEmpty, isTrue);

        final result = await syncWorker.syncNow();

        expect(result.isEmpty, isTrue);
        expect(result.processedCount, 0);
        expect(result.remainingCount, 0);
        expect(fakeAdapter.uploadCalls, 0);
      },
    );
  });

  group('SyncWorker - Update Operations', () {
    test(
      '14. successfully updates image and metadata, captures revision, marks synced, acknowledges queue',
      () async {
        await setupReadyDriveState();

        const dateKey = DateKey(2026, 8, 1);
        await createLocalPhoto(
          dateKey: dateKey,
          title: 'Sunset Beach',
          caption: 'Beautiful evening',
          location: 'California',
          syncStatus: SyncStatus.synced,
          driveFileId: 'remote_file_update_123',
        );

        final updateOp = await photoStore.syncQueue.enqueueUpdate(
          dateKey,
          driveFileId: 'remote_file_update_123',
        );

        expect(photoStore.syncQueue.count, 1);

        final result = await syncWorker.syncNow();

        expect(result.isSuccess, isTrue);
        expect(result.processedCount, 1);
        expect(result.updatedCount, 1);
        expect(result.succeededCount, 1);
        expect(result.remainingCount, 0);

        expect(fakeAdapter.updateCalls, 1);
        expect(fakeAdapter.updateFileIds, ['remote_file_update_123']);
        expect(
          fakeAdapter.updateDescriptions.first,
          contains('Title: Sunset Beach'),
        );
        expect(
          fakeAdapter.updateDescriptions.first,
          contains('Caption: Beautiful evening'),
        );
        expect(
          fakeAdapter.updateDescriptions.first,
          contains('Location: California'),
        );

        // Local photo is marked synced with captured revision
        final photo = photoStore.getPhotoByKey(dateKey);
        expect(photo?.syncStatus, SyncStatus.synced);
        expect(photo?.driveFileId, 'remote_file_update_123');
        expect(photo?.driveFileRevision, 'rev_1');
        expect(photo?.syncError, isNull);

        // Queue operation acknowledged
        expect(photoStore.syncQueue.getOperation(updateOp.id), isNull);
      },
    );

    test(
      '15. update failure on Drive error preserves local photo and queue operation with retry count',
      () async {
        await setupReadyDriveState();

        const dateKey = DateKey(2026, 8, 2);
        await createLocalPhoto(
          dateKey: dateKey,
          syncStatus: SyncStatus.synced,
          driveFileId: 'remote_file_fail_456',
        );

        final updateOp = await photoStore.syncQueue.enqueueUpdate(
          dateKey,
          driveFileId: 'remote_file_fail_456',
        );

        fakeAdapter.errorOnUpdate = const DriveApiException(
          'Network timeout updating photo',
          errorType: DriveFolderErrorType.networkError,
        );

        final result = await syncWorker.syncNow();

        expect(result.hasFailures, isTrue);
        expect(result.failedCount, 1);
        expect(result.updatedCount, 0);

        // Local photo marked failed with error message
        final photo = photoStore.getPhotoByKey(dateKey);
        expect(photo?.syncStatus, SyncStatus.failed);
        expect(photo?.syncError, contains('Network timeout'));

        // Queue op preserved with retryCount incremented
        final queuedOp = photoStore.syncQueue.getOperation(updateOp.id);
        expect(queuedOp, isNotNull);
        expect(queuedOp?.status, SyncOperationStatus.failed);
        expect(queuedOp?.retryCount, 1);
        expect(queuedOp?.nextAttemptAt, isNotNull);
      },
    );

    test(
      '16. update 404 does not convert to upload, marks operation failed and preserves it in queue',
      () async {
        await setupReadyDriveState();

        const dateKey = DateKey(2026, 8, 3);
        await createLocalPhoto(
          dateKey: dateKey,
          syncStatus: SyncStatus.synced,
          driveFileId: 'remote_file_missing_789',
        );

        final updateOp = await photoStore.syncQueue.enqueueUpdate(
          dateKey,
          driveFileId: 'remote_file_missing_789',
        );

        fakeAdapter.errorOnUpdate = const DriveApiException(
          'Target Drive resource not found.',
          errorType: DriveFolderErrorType.notFound,
        );

        final result = await syncWorker.syncNow();

        expect(result.hasFailures, isTrue);
        expect(result.failedCount, 1);
        expect(fakeAdapter.uploadCalls, 0); // MUST NOT trigger upload!

        final queuedOp = photoStore.syncQueue.getOperation(updateOp.id);
        expect(queuedOp, isNotNull);
        expect(queuedOp?.status, SyncOperationStatus.failed);
        expect(queuedOp?.retryCount, 1);

        final photo = photoStore.getPhotoByKey(dateKey);
        expect(photo?.syncStatus, SyncStatus.failed);
      },
    );

    test(
      '17. update with invalid fileId (root or folderId) fails safely without calling Drive',
      () async {
        await setupReadyDriveState();

        const dateKey = DateKey(2026, 8, 4);
        await createLocalPhoto(
          dateKey: dateKey,
          syncStatus: SyncStatus.synced,
          driveFileId:
              'photo_a_day_drive_folder_id', // Target matches folderId!
        );

        final updateOp = await photoStore.syncQueue.enqueueUpdate(
          dateKey,
          driveFileId: 'photo_a_day_drive_folder_id',
        );

        final result = await syncWorker.syncNow();

        expect(result.hasFailures, isTrue);
        expect(result.failedCount, 1);
        expect(
          fakeAdapter.updateCalls,
          0,
        ); // Never calls Drive API on folder ID!

        final queuedOp = photoStore.syncQueue.getOperation(updateOp.id);
        expect(queuedOp?.status, SyncOperationStatus.failed);
        expect(
          queuedOp?.lastError,
          contains('Invalid or missing target Drive file ID'),
        );
      },
    );

    test(
      '18. update with missing local file fails safely and marks operation failed',
      () async {
        await setupReadyDriveState();

        const dateKey = DateKey(2026, 8, 5);
        // Photo not created in photoStore
        final updateOp = await photoStore.syncQueue.enqueueUpdate(
          dateKey,
          driveFileId: 'valid_remote_id',
        );

        final result = await syncWorker.syncNow();

        expect(result.hasFailures, isTrue);
        expect(result.failedCount, 1);
        expect(fakeAdapter.updateCalls, 0);

        final queuedOp = photoStore.syncQueue.getOperation(updateOp.id);
        expect(queuedOp?.status, SyncOperationStatus.failed);
      },
    );
  });

  group('SyncWorker - Delete Operations', () {
    test(
      '19. successfully trashes remote file, acknowledges queue, and clears tombstone',
      () async {
        await setupReadyDriveState();

        const dateKey = DateKey(2026, 8, 10);
        await createLocalPhoto(
          dateKey: dateKey,
          syncStatus: SyncStatus.synced,
          driveFileId: 'remote_file_del_10',
        );

        // Delete photo via store so tombstone and queue op are created
        await photoStore.removePhotoAsync(dateKey.toDateTime());

        expect(photoStore.pendingDeletions.length, 1);
        expect(
          photoStore.pendingDeletions.first.driveFileId,
          'remote_file_del_10',
        );
        expect(photoStore.syncQueue.count, 1);

        final deleteOp = photoStore.syncQueue.operations.first;
        expect(deleteOp.type, SyncOperationType.delete);

        final result = await syncWorker.syncNow();

        expect(result.isSuccess, isTrue);
        expect(result.deletedCount, 1);
        expect(result.succeededCount, 1);
        expect(result.remainingCount, 0);

        // Trashed on Drive
        expect(fakeAdapter.trashCalls, 1);
        expect(fakeAdapter.trashedFileIds, ['remote_file_del_10']);

        // Queue operation acknowledged
        expect(photoStore.syncQueue.getOperation(deleteOp.id), isNull);

        // Tombstone cleared from store
        expect(photoStore.pendingDeletions.isEmpty, isTrue);
      },
    );

    test(
      '20. delete 404 is treated as idempotent success: acknowledges queue and clears tombstone',
      () async {
        await setupReadyDriveState();

        const dateKey = DateKey(2026, 8, 11);
        await createLocalPhoto(
          dateKey: dateKey,
          syncStatus: SyncStatus.synced,
          driveFileId: 'remote_file_already_deleted_404',
        );

        await photoStore.removePhotoAsync(dateKey.toDateTime());
        expect(photoStore.pendingDeletions.length, 1);

        final deleteOp = photoStore.syncQueue.operations.first;

        fakeAdapter.errorOnTrash = const DriveApiException(
          'Target Drive resource not found.',
          errorType: DriveFolderErrorType.notFound,
        );

        final result = await syncWorker.syncNow();

        // 404 on delete is treated as idempotent success!
        expect(result.isSuccess, isTrue);
        expect(result.deletedCount, 1);
        expect(result.remainingCount, 0);

        expect(photoStore.syncQueue.getOperation(deleteOp.id), isNull);
        expect(photoStore.pendingDeletions.isEmpty, isTrue);
      },
    );

    test(
      '21. delete failure on Drive error preserves queue operation, retryCount, and tombstone',
      () async {
        await setupReadyDriveState();

        const dateKey = DateKey(2026, 8, 12);
        await createLocalPhoto(
          dateKey: dateKey,
          syncStatus: SyncStatus.synced,
          driveFileId: 'remote_file_del_err',
        );

        await photoStore.removePhotoAsync(dateKey.toDateTime());
        final deleteOp = photoStore.syncQueue.operations.first;

        fakeAdapter.errorOnTrash = const DriveApiException(
          'Drive connection timeout',
          errorType: DriveFolderErrorType.networkError,
        );

        final result = await syncWorker.syncNow();

        expect(result.hasFailures, isTrue);
        expect(result.failedCount, 1);
        expect(result.deletedCount, 0);

        // Queue operation retained with retryCount incremented
        final queuedOp = photoStore.syncQueue.getOperation(deleteOp.id);
        expect(queuedOp, isNotNull);
        expect(queuedOp?.status, SyncOperationStatus.failed);
        expect(queuedOp?.retryCount, 1);

        // Tombstone MUST remain intact!
        expect(photoStore.pendingDeletions.length, 1);
        expect(
          photoStore.pendingDeletions.first.driveFileId,
          'remote_file_del_err',
        );
      },
    );

    test(
      '22. delete with invalid fileId (root or folderId) fails safely without calling Drive',
      () async {
        await setupReadyDriveState();

        const dateKey = DateKey(2026, 8, 13);
        final deleteOp = await photoStore.syncQueue.enqueueDelete(
          dateKey,
          driveFileId: 'root', // Target matches root!
        );

        final result = await syncWorker.syncNow();

        expect(result.hasFailures, isTrue);
        expect(result.failedCount, 1);
        expect(
          fakeAdapter.trashCalls,
          0,
        ); // Never calls Drive API to delete root!

        final queuedOp = photoStore.syncQueue.getOperation(deleteOp.id);
        expect(queuedOp?.status, SyncOperationStatus.failed);
        expect(
          queuedOp?.lastError,
          contains('Invalid or missing target Drive file ID'),
        );
      },
    );
  });

  group('SyncWorker - Queue Isolation & Deterministic Ordering', () {
    test(
      '23. mixed queue [UPLOAD, UPDATE, DELETE, UPDATE] processes each independently in FIFO order',
      () async {
        await setupReadyDriveState();

        const keyA = DateKey(2026, 8, 20);
        const keyB = DateKey(2026, 8, 21);
        const keyC = DateKey(2026, 8, 22);
        const keyD = DateKey(2026, 8, 23);

        await createLocalPhoto(dateKey: keyA, filename: 'photoA.jpg');
        await createLocalPhoto(
          dateKey: keyB,
          filename: 'photoB.jpg',
          syncStatus: SyncStatus.synced,
          driveFileId: 'file_id_B',
        );
        await createLocalPhoto(
          dateKey: keyC,
          filename: 'photoC.jpg',
          syncStatus: SyncStatus.synced,
          driveFileId: 'file_id_C',
        );
        await createLocalPhoto(
          dateKey: keyD,
          filename: 'photoD.jpg',
          syncStatus: SyncStatus.synced,
          driveFileId: 'file_id_D',
        );

        // Enqueue operations
        await photoStore.syncQueue.enqueueUpload(keyA);
        await photoStore.syncQueue.enqueueUpdate(
          keyB,
          driveFileId: 'file_id_B',
        );
        await photoStore.removePhotoAsync(
          keyC.toDateTime(),
        ); // generates delete op & tombstone
        await photoStore.syncQueue.enqueueUpdate(
          keyD,
          driveFileId: 'file_id_D',
        );

        expect(photoStore.syncQueue.count, 4);

        final result = await syncWorker.syncNow();

        expect(result.isSuccess, isTrue);
        expect(result.processedCount, 4);
        expect(result.uploadedCount, 1);
        expect(result.updatedCount, 2);
        expect(result.deletedCount, 1);
        expect(result.remainingCount, 0);

        expect(fakeAdapter.uploadCalls, 1);
        expect(fakeAdapter.updateCalls, 2);
        expect(fakeAdapter.trashCalls, 1);
        expect(fakeAdapter.updateFileIds, ['file_id_B', 'file_id_D']);
        expect(fakeAdapter.trashedFileIds, ['file_id_C']);
        expect(photoStore.pendingDeletions.isEmpty, isTrue);
      },
    );

    test(
      '24. failure in one operation does not corrupt subsequent operations',
      () async {
        await setupReadyDriveState();

        const keyA = DateKey(2026, 8, 25);
        const keyB = DateKey(2026, 8, 26);
        const keyC = DateKey(2026, 8, 27);

        await createLocalPhoto(dateKey: keyA, filename: 'photoA.jpg');
        await createLocalPhoto(
          dateKey: keyB,
          filename: 'photoB.jpg',
          syncStatus: SyncStatus.synced,
          driveFileId: 'file_id_B',
        );
        await createLocalPhoto(
          dateKey: keyC,
          filename: 'photoC.jpg',
          syncStatus: SyncStatus.synced,
          driveFileId: 'file_id_C',
        );

        final opA = await photoStore.syncQueue.enqueueUpload(keyA);
        final opB = await photoStore.syncQueue.enqueueUpdate(
          keyB,
          driveFileId: 'file_id_B',
        );
        final opC = await photoStore.syncQueue.enqueueUpdate(
          keyC,
          driveFileId: 'file_id_C',
        );

        // B will fail, but A and C will succeed
        fakeAdapter.errorOnUpdate = const DriveApiException(
          'Temporary failure on B',
          errorType: DriveFolderErrorType.apiError,
        );
        fakeAdapter.errorOnFileId = 'file_id_B';

        final result = await syncWorker.syncNow();

        // A succeeded
        expect(fakeAdapter.uploadCalls, 1);
        expect(photoStore.syncQueue.getOperation(opA.id), isNull);

        // B failed and remains in queue
        expect(
          photoStore.syncQueue.getOperation(opB.id)?.status,
          SyncOperationStatus.failed,
        );

        // C succeeded in the same run!
        expect(fakeAdapter.updateFileIds, contains('file_id_C'));
        expect(photoStore.syncQueue.getOperation(opC.id), isNull);

        expect(result.processedCount, 3);
        expect(result.uploadedCount, 1);
        expect(result.failedCount, 1);
        expect(result.updatedCount, 1);
      },
    );

    test(
      '25. failed update/delete retains retry state across service restart and disk reload',
      () async {
        await setupReadyDriveState();

        const dateKey = DateKey(2026, 8, 28);
        await createLocalPhoto(
          dateKey: dateKey,
          syncStatus: SyncStatus.synced,
          driveFileId: 'file_durability_test',
        );

        final updateOp = await photoStore.syncQueue.enqueueUpdate(
          dateKey,
          driveFileId: 'file_durability_test',
        );

        fakeAdapter.errorOnUpdate = const DriveApiException(
          'Network connection lost',
          errorType: DriveFolderErrorType.networkError,
        );

        await syncWorker.syncNow();

        final failedOp = photoStore.syncQueue.getOperation(updateOp.id);
        expect(failedOp?.status, SyncOperationStatus.failed);
        expect(failedOp?.retryCount, 1);
        expect(failedOp?.nextAttemptAt, isNotNull);

        // Flush and simulate restart: reload queue from storage
        await photoStore.syncQueue.flush();

        final reloadedQueue = SyncQueue(storage: fakeSyncQueueStorage);
        await reloadedQueue.init();

        final reloadedOp = reloadedQueue.getOperation(updateOp.id);
        expect(reloadedOp, isNotNull);
        expect(reloadedOp?.status, SyncOperationStatus.failed);
        expect(reloadedOp?.retryCount, 1);
        expect(reloadedOp?.driveFileId, 'file_durability_test');
      },
    );
  });
}
