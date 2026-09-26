import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/auth_user.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/drive_auth_status.dart';
import 'package:photo_per_day/data/models/drive_folder_reference.dart';
import 'package:photo_per_day/data/models/drive_photo_upload_response.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_presentation_model.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/drive_api_adapter.dart';
import 'package:photo_per_day/data/services/drive_auth_storage.dart';
import 'package:photo_per_day/data/services/drive_folder_storage.dart';
import 'package:photo_per_day/data/services/google_auth_service.dart';
import 'package:photo_per_day/data/services/google_drive_auth_service.dart';
import 'package:photo_per_day/data/services/google_drive_photo_upload_service.dart';
import 'package:photo_per_day/data/services/google_drive_service.dart';
import 'package:photo_per_day/data/services/local_storage_calculator.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/data/services/sync_coordinator.dart';
import 'package:photo_per_day/data/services/sync_queue.dart';
import 'package:photo_per_day/data/services/sync_queue_storage.dart';
import 'package:photo_per_day/data/services/sync_worker.dart';
import 'package:photo_per_day/utils/time_ago_formatter.dart';

// Test doubles
class _FakeSignInDelegate implements GoogleSignInDelegate {
  AuthUser? mockUser;
  bool driveScopeGranted = true;

  @override
  Future<AuthUser?> signInSilently() async => mockUser;

  @override
  Future<AuthUser?> signIn() async => mockUser;

  @override
  Future<void> signOut() async => mockUser = null;

  @override
  Future<void> disconnect() async => mockUser = null;

  @override
  Future<bool> canAccessDriveScope() async => true;

  @override
  Future<bool> requestDriveScope() async => driveScopeGranted;

  @override
  Future<Map<String, String>> getAuthHeaders() async => {
    'Authorization': 'Bearer fake_token',
    'X-Goog-AuthUser': '0',
  };
}

class _FakeDriveAuthDelegate implements GoogleDriveAuthDelegate {
  bool driveScopeGranted = true;

  @override
  Future<bool> canAccessDriveScope() async => true;

  @override
  Future<bool> requestDriveScope() async => driveScopeGranted;

  @override
  Future<Map<String, String>> getAuthHeaders() async => {
    'Authorization': 'Bearer fake_token',
    'X-Goog-AuthUser': '0',
  };
}

class _FakeDriveAdapter implements DriveApiAdapter {
  DriveFolderReference? existingFolder;
  int uploadCalls = 0;
  int updateCalls = 0;
  int deleteCalls = 0;

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
      folderId: 'fake_folder_id',
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
    String? description,
    void Function(double progress)? onProgress,
  }) async {
    uploadCalls++;
    onProgress?.call(1.0);
    return DrivePhotoUploadResponse(
      fileId: 'uploaded_${filename}_id',
      filename: filename,
      uploadedAt: DateTime.now().toUtc(),
      revision: '1',
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
    void Function(double progress)? onProgress,
  }) async {
    updateCalls++;
    onProgress?.call(1.0);
    return DrivePhotoUploadResponse(
      fileId: fileId,
      filename: filename ?? 'photo.jpg',
      uploadedAt: DateTime.now().toUtc(),
      revision: '2',
    );
  }

  @override
  Future<bool> trashPhotoFile({
    required String fileId,
    required Map<String, String> authHeaders,
  }) async {
    deleteCalls++;
    return true;
  }
}

class _AlwaysOnlineNetworkChecker implements NetworkChecker {
  const _AlwaysOnlineNetworkChecker();
  @override
  Future<bool> isConnected() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeSignInDelegate fakeSignIn;
  late _FakeDriveAuthDelegate fakeDriveAuth;
  late _FakeDriveAdapter fakeDriveAdapter;
  late GoogleAuthService authService;
  late GoogleDriveAuthService driveAuthService;
  late GoogleDriveService driveService;
  late GoogleDrivePhotoUploadService uploadService;
  late PersistentDailyPhotoStore photoStore;
  late SyncWorker syncWorker;
  late SyncCoordinator coordinator;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_ux_test_');

    fakeSignIn = _FakeSignInDelegate();
    fakeDriveAuth = _FakeDriveAuthDelegate();
    fakeDriveAdapter = _FakeDriveAdapter();

    authService = GoogleAuthService(delegate: fakeSignIn);
    driveAuthService = GoogleDriveAuthService(
      authService: authService,
      delegate: fakeDriveAuth,
      storage: DriveAuthStorage(customBaseDir: tempDir.path),
    );
    driveService = GoogleDriveService(
      authService: authService,
      driveAuthService: driveAuthService,
      adapter: fakeDriveAdapter,
      storage: DriveFolderStorage(customBaseDir: tempDir.path),
    );
    final fileManager = PhotoFileManager(customBaseDir: tempDir);
    final metadataStorage = PhotoMetadataStorage(customBaseDir: tempDir);
    final syncQueue = SyncQueue(
      storage: SyncQueueStorage(customBaseDir: tempDir),
    );

    photoStore = PersistentDailyPhotoStore(
      fileManager: fileManager,
      metadataStorage: metadataStorage,
      syncQueue: syncQueue,
    );
    await photoStore.init();
    PersistentDailyPhotoStore.setTestInstance(photoStore);

    uploadService = GoogleDrivePhotoUploadService(
      authService: authService,
      driveAuthService: driveAuthService,
      driveService: driveService,
      photoStore: photoStore,
      adapter: fakeDriveAdapter,
    );

    syncWorker = SyncWorker(
      syncQueue: photoStore.syncQueue,
      photoStore: photoStore,
      authService: authService,
      driveAuthService: driveAuthService,
      driveService: driveService,
      uploadService: uploadService,
      driveAdapter: fakeDriveAdapter,
    );

    coordinator = SyncCoordinator(
      worker: syncWorker,
      queue: photoStore.syncQueue,
      authService: authService,
      driveAuthService: driveAuthService,
      driveService: driveService,
      networkChecker: const _AlwaysOnlineNetworkChecker(),
      debounceDuration: const Duration(milliseconds: 10),
    );
    await coordinator.init();
  });

  tearDown(() async {
    PersistentDailyPhotoStore.resetTestInstance();
    coordinator.dispose();
    syncWorker.dispose();
    uploadService.dispose();
    driveService.dispose();
    driveAuthService.dispose();
    authService.dispose();
    photoStore.dispose();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  PhotoEntry createSampleEntry({
    required DateKey dateKey,
    SyncStatus status = SyncStatus.localOnly,
    String? authorizedEmail,
    String? imagePath,
  }) {
    return PhotoEntry(
      date: dateKey.toDateTime(),
      title: 'Memory for ${dateKey.format()}',
      caption: 'A wonderful moment',
      location: 'Home',
      timeFormatted: '12:00 PM',
      gradientColors: const [Colors.amber, Colors.orange],
      syncStatus: status,
      authorizedEmail: authorizedEmail,
      imagePath: imagePath,
    );
  }

  group('Milestone 26 — Sync UX & Storage Transparency', () {
    test('1. localOnly presentation maps to "On this device"', () {
      final entry = createSampleEntry(
        dateKey: const DateKey(2026, 3, 1),
        status: SyncStatus.localOnly,
      );
      final presentation = PhotoSyncPresentation.forEntry(entry);

      expect(presentation.state, equals(PhotoSyncDisplayState.localOnly));
      expect(presentation.label, equals('On this device'));
      expect(presentation.detailLabel, equals('On this device'));
      expect(presentation.semanticLabel, contains('device only'));
      expect(presentation.isBackingUp, isFalse);
      expect(presentation.isFailed, isFalse);
    });

    test('2. pending presentation maps to "Waiting to back up"', () {
      final entry = createSampleEntry(
        dateKey: const DateKey(2026, 3, 2),
        status: SyncStatus.pending,
      );
      final presentation = PhotoSyncPresentation.forEntry(entry);

      expect(presentation.state, equals(PhotoSyncDisplayState.pending));
      expect(presentation.label, equals('Waiting to back up'));
      expect(presentation.detailLabel, equals('Waiting to back up'));
      expect(presentation.semanticLabel, contains('waiting to be backed up'));
      expect(presentation.isBackingUp, isFalse);
      expect(presentation.isFailed, isFalse);
    });

    test(
      '3. synced presentation maps to "Backed up" and "Backed up to Google Drive"',
      () {
        final entry = createSampleEntry(
          dateKey: const DateKey(2026, 3, 3),
          status: SyncStatus.synced,
        );
        final presentation = PhotoSyncPresentation.forEntry(entry);

        expect(presentation.state, equals(PhotoSyncDisplayState.synced));
        expect(presentation.label, equals('Backed up'));
        expect(presentation.detailLabel, equals('Backed up to Google Drive'));
        expect(
          presentation.semanticLabel,
          equals('Photo backed up to Google Drive'),
        );
        expect(presentation.isBackingUp, isFalse);
        expect(presentation.isFailed, isFalse);
      },
    );

    test('4. failed presentation maps to "Backup failed"', () {
      final entry = createSampleEntry(
        dateKey: const DateKey(2026, 3, 4),
        status: SyncStatus.failed,
      );
      final presentation = PhotoSyncPresentation.forEntry(entry);

      expect(presentation.state, equals(PhotoSyncDisplayState.failed));
      expect(presentation.label, equals('Backup failed'));
      expect(presentation.detailLabel, equals('Backup failed'));
      expect(presentation.semanticLabel, equals('Photo backup failed'));
      expect(presentation.isFailed, isTrue);
      expect(presentation.isBackingUp, isFalse);
    });

    test('5. backing-up presentation if actively in flight', () {
      final entry = createSampleEntry(
        dateKey: const DateKey(2026, 3, 5),
        status: SyncStatus.pending,
      );

      // Explicitly flagged as active sync
      final presentation = PhotoSyncPresentation.forEntry(
        entry,
        isSyncing: true,
      );

      expect(presentation.state, equals(PhotoSyncDisplayState.backingUp));
      expect(presentation.label, equals('Backing up...'));
      expect(presentation.detailLabel, equals('Backing up to Google Drive...'));
      expect(presentation.isBackingUp, isTrue);
      expect(presentation.isFailed, isFalse);
    });

    test('6. Profile summary counts derived from store and queue', () async {
      await photoStore.savePhoto(
        entry: createSampleEntry(
          dateKey: const DateKey(2026, 3, 1),
          status: SyncStatus.localOnly,
        ),
      );
      await photoStore.savePhoto(
        entry: createSampleEntry(
          dateKey: const DateKey(2026, 3, 2),
          status: SyncStatus.pending,
        ),
      );
      await photoStore.savePhoto(
        entry: createSampleEntry(
          dateKey: const DateKey(2026, 3, 3),
          status: SyncStatus.synced,
        ),
      );
      await photoStore.savePhoto(
        entry: createSampleEntry(
          dateKey: const DateKey(2026, 3, 4),
          status: SyncStatus.failed,
        ),
      );

      final summary = SyncSummary.compute(
        store: photoStore,
        queue: photoStore.syncQueue,
      );

      expect(summary.totalPhotos, equals(4));
      expect(summary.localOnlyCount, equals(1));
      expect(summary.waitingCount, equals(1));
      expect(summary.backedUpCount, equals(1));
      expect(summary.failedCount, equals(1));
    });

    test(
      '7. pending count represents actual active work, ignoring completed history',
      () async {
        const dateKey = DateKey(2026, 3, 10);
        final op = await photoStore.syncQueue.enqueueUpload(dateKey);

        expect(photoStore.syncQueue.pendingOperations.length, equals(1));

        // Mark operation as completed
        await photoStore.syncQueue.markCompleted(op.id);

        final summary = SyncSummary.compute(
          store: photoStore,
          queue: photoStore.syncQueue,
        );

        expect(summary.pendingQueueCount, equals(0));
        expect(summary.waitingCount, equals(0));
      },
    );

    test('8. failed count accuracy for failed photos and operations', () async {
      const dateKey = DateKey(2026, 3, 11);
      await photoStore.savePhoto(
        entry: createSampleEntry(dateKey: dateKey, status: SyncStatus.failed),
      );
      final op = await photoStore.syncQueue.enqueueUpload(dateKey);
      await photoStore.syncQueue.markFailed(op.id, error: 'Connection refused');

      final summary = SyncSummary.compute(
        store: photoStore,
        queue: photoStore.syncQueue,
      );

      expect(summary.failedCount, equals(1));
      expect(summary.pendingQueueCount, equals(1));
    });

    test(
      '9. local storage size calculation sums actual on-disk byte sizes',
      () async {
        final testFile1 = File('${tempDir.path}/photo1.jpg');
        await testFile1.writeAsBytes(List.generate(1024, (i) => i % 256));

        final testFile2 = File('${tempDir.path}/photo2.jpg');
        await testFile2.writeAsBytes(List.generate(2048, (i) => i % 256));

        await photoStore.savePhoto(
          entry: createSampleEntry(
            dateKey: const DateKey(2026, 3, 12),
            imagePath: testFile1.path,
          ),
        );
        await photoStore.savePhoto(
          entry: createSampleEntry(
            dateKey: const DateKey(2026, 3, 13),
            imagePath: testFile2.path,
          ),
        );

        final totalBytes =
            await LocalStorageCalculator.calculateTotalPhotoBytes(
              store: photoStore,
            );

        expect(totalBytes, equals(3072));
        expect(
          LocalStorageCalculator.formatBytes(totalBytes),
          equals('3 KB used'),
        );

        // Format 142 MB test
        expect(
          LocalStorageCalculator.formatBytes(142 * 1024 * 1024),
          equals('142 MB used'),
        );
      },
    );

    test(
      '10. missing, zero-byte, and unreadable local files handled gracefully',
      () async {
        final validSource = File('${tempDir.path}/valid_source.jpg');
        await validSource.writeAsBytes([1, 2, 3, 4]);

        // Save two valid photos first
        await photoStore.savePhoto(
          entry: createSampleEntry(
            dateKey: const DateKey(2026, 3, 14),
            imagePath: validSource.path,
          ),
        );
        await photoStore.savePhoto(
          entry: createSampleEntry(
            dateKey: const DateKey(2026, 3, 15),
            imagePath: validSource.path,
          ),
        );

        final entry1 = photoStore.getPhotoByKey(const DateKey(2026, 3, 14))!;
        final entry2 = photoStore.getPhotoByKey(const DateKey(2026, 3, 15))!;

        // Simulate file corruption: truncate entry1 file to 0 bytes
        await File(entry1.imagePath!).writeAsBytes([]);

        // Simulate missing file: delete entry2 file from disk
        await File(entry2.imagePath!).delete();

        final totalBytes =
            await LocalStorageCalculator.calculateTotalPhotoBytes(
              store: photoStore,
            );

        expect(totalBytes, equals(0));
        expect(
          LocalStorageCalculator.formatBytes(totalBytes),
          equals('0 B used'),
        );
      },
    );

    test('11. signed-out state correctly reflected', () async {
      await authService.signOut();

      expect(authService.isSignedIn, isFalse);
      expect(authService.currentUser, isNull);

      final summary = SyncSummary.compute(
        store: photoStore,
        queue: photoStore.syncQueue,
        currentAccountEmail: null,
      );
      expect(summary.isUpToDate, isTrue); // Empty store is clean
    });

    test('12. signed-in account display shows authorized email', () async {
      fakeSignIn.mockUser = const AuthUser(
        id: '123',
        email: 'photographer@gmail.com',
        displayName: 'Daily Journaler',
      );
      await authService.signIn();

      expect(authService.isSignedIn, isTrue);
      expect(authService.currentUser?.email, equals('photographer@gmail.com'));
    });

    test(
      '13. Drive unauthorized state reflected when signed in without Drive scope',
      () async {
        fakeSignIn.mockUser = const AuthUser(
          id: '123',
          email: 'photographer@gmail.com',
        );
        fakeDriveAuth.driveScopeGranted = false;
        await authService.signIn();

        expect(driveAuthService.status, equals(DriveAuthStatus.notAuthorized));
        expect(driveAuthService.isAuthorized, isFalse);
      },
    );

    test('14. Try Again requests existing sync path via coordinator', () async {
      const dateKey = DateKey(2026, 3, 16);
      final dummyFile = File('${tempDir.path}/upload_test.jpg');
      await dummyFile.writeAsBytes([1, 2, 3, 4, 5]);

      await photoStore.savePhoto(
        entry: createSampleEntry(dateKey: dateKey, imagePath: dummyFile.path),
      );
      await photoStore.updateSyncStatus(
        dateKey: dateKey,
        status: SyncStatus.failed,
        syncError: 'Network timeout',
      );
      await photoStore.syncQueue.enqueueUpload(
        dateKey,
        authorizedEmail: 'user@example.com',
      );

      fakeSignIn.mockUser = const AuthUser(
        id: '123',
        email: 'user@example.com',
      );
      await authService.signIn();
      await driveAuthService.authorizeDrive();
      await driveService.setupFolder();

      // Trigger "Try Again"
      final result = await coordinator.requestSync(trigger: SyncTrigger.manual);

      expect(result.processedCount, equals(1));
      expect(fakeDriveAdapter.uploadCalls, equals(1));
      expect(
        photoStore.getPhotoByKey(dateKey)?.syncStatus,
        equals(SyncStatus.synced),
      );
    });

    test(
      '15. account-switch safety preserves local photos and prevents cross-user backup claim',
      () async {
        const dateKey = DateKey(2026, 3, 17);
        // Photo was synced by User A
        await photoStore.savePhoto(
          entry: createSampleEntry(
            dateKey: dateKey,
            status: SyncStatus.synced,
            authorizedEmail: 'user_a@example.com',
          ),
        );

        // Now User B is the active account
        final summary = SyncSummary.compute(
          store: photoStore,
          queue: photoStore.syncQueue,
          currentAccountEmail: 'user_b@example.com',
        );

        // User A's photo must NOT be counted as backed up for User B
        expect(summary.backedUpCount, equals(0));
        expect(summary.localOnlyCount, equals(1));
      },
    );

    test('16. no false "Up to date" state when work remains', () async {
      const dateKey = DateKey(2026, 3, 18);

      // Case A: Pending queue operation exists
      await photoStore.syncQueue.enqueueUpload(dateKey);
      var summary = SyncSummary.compute(
        store: photoStore,
        queue: photoStore.syncQueue,
      );
      expect(summary.isUpToDate, isFalse);

      // Case B: Local-only photo exists
      await photoStore.syncQueue.flush();
      await photoStore.syncQueue.removeOperationsForDate(dateKey);
      await photoStore.savePhoto(
        entry: createSampleEntry(
          dateKey: dateKey,
          status: SyncStatus.localOnly,
        ),
      );
      summary = SyncSummary.compute(
        store: photoStore,
        queue: photoStore.syncQueue,
      );
      expect(summary.isUpToDate, isFalse);

      // Case C: Failed photo exists
      await photoStore.updateSyncStatus(
        dateKey: dateKey,
        status: SyncStatus.failed,
      );
      summary = SyncSummary.compute(
        store: photoStore,
        queue: photoStore.syncQueue,
      );
      expect(summary.isUpToDate, isFalse);

      // Case D: Photo is fully synced and queue is empty
      await photoStore.updateSyncStatus(
        dateKey: dateKey,
        status: SyncStatus.synced,
        driveFileId: 'drive_123',
      );
      summary = SyncSummary.compute(
        store: photoStore,
        queue: photoStore.syncQueue,
      );
      expect(summary.isUpToDate, isTrue);
    });

    test('TimeAgoFormatter accurately formats relative backup times', () {
      final now = DateTime.utc(2026, 3, 15, 12, 0, 0);

      expect(
        TimeAgoFormatter.format(
          now.subtract(const Duration(seconds: 30)),
          clock: now,
        ),
        equals('just now'),
      );
      expect(
        TimeAgoFormatter.format(
          now.subtract(const Duration(minutes: 1)),
          clock: now,
        ),
        equals('1 minute ago'),
      );
      expect(
        TimeAgoFormatter.format(
          now.subtract(const Duration(minutes: 5)),
          clock: now,
        ),
        equals('5 minutes ago'),
      );
      expect(
        TimeAgoFormatter.format(
          now.subtract(const Duration(hours: 2)),
          clock: now,
        ),
        equals('2 hours ago'),
      );
      expect(
        TimeAgoFormatter.format(
          now.subtract(const Duration(days: 1)),
          clock: now,
        ),
        equals('yesterday'),
      );
      expect(
        TimeAgoFormatter.format(
          now.subtract(const Duration(days: 3)),
          clock: now,
        ),
        equals('3 days ago'),
      );
    });
  });
}
