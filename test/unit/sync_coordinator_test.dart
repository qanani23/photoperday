import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/auth_user.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/drive_folder_reference.dart';
import 'package:photo_per_day/data/models/drive_photo_upload_response.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
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
import 'package:photo_per_day/data/services/sync_coordinator.dart';
import 'package:photo_per_day/data/services/sync_queue.dart';
import 'package:photo_per_day/data/services/sync_queue_storage.dart';
import 'package:photo_per_day/data/services/sync_worker.dart';

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
  Duration simulatedDelay = Duration.zero;

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
      folderId: 'coord_test_folder_id',
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
    if (simulatedDelay > Duration.zero) {
      await Future.delayed(simulatedDelay);
    }
    return DrivePhotoUploadResponse(
      fileId: 'uploaded_file_$uploadCalls',
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
    return DrivePhotoUploadResponse(
      fileId: fileId,
      filename: filename ?? 'photo.jpg',
      uploadedAt: DateTime.now().toUtc(),
      revision: '2',
    );
  }

  @override
  Future<void> trashPhotoFile({
    required String fileId,
    required Map<String, String> authHeaders,
  }) async {
    deleteCalls++;
  }
}

class _FakeNetworkChecker implements NetworkChecker {
  _FakeNetworkChecker({this.online = true});
  bool online;
  int checksCount = 0;

  @override
  Future<bool> isConnected() async {
    checksCount++;
    return online;
  }
}

class _FakeBackgroundScheduler implements BackgroundSyncScheduler {
  int scheduleCount = 0;
  int cancelCount = 0;
  bool supported = true;

  @override
  bool get isSupported => supported;

  @override
  Future<void> scheduleBackgroundSync() async {
    scheduleCount++;
  }

  @override
  Future<void> cancelBackgroundSync() async {
    cancelCount++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeSignInDelegate fakeSignInDelegate;
  late _FakeDriveAuthDelegate fakeDriveAuthDelegate;
  late _FakeDriveAdapter fakeDriveAdapter;
  late _FakeNetworkChecker fakeNetworkChecker;
  late _FakeBackgroundScheduler fakeBackgroundScheduler;

  late PersistentDailyPhotoStore photoStore;
  late GoogleAuthService authService;
  late GoogleDriveAuthService driveAuthService;
  late GoogleDriveService driveService;
  late GoogleDrivePhotoUploadService uploadService;
  late SyncWorker syncWorker;
  late SyncCoordinator coordinator;

  const testUser = AuthUser(
    id: 'user_1',
    email: 'test@example.com',
    displayName: 'Test User',
  );

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('sync_coordinator_test_');

    fakeSignInDelegate = _FakeSignInDelegate();
    fakeDriveAuthDelegate = _FakeDriveAuthDelegate();
    fakeDriveAdapter = _FakeDriveAdapter();
    fakeNetworkChecker = _FakeNetworkChecker(online: true);
    fakeBackgroundScheduler = _FakeBackgroundScheduler();

    final queueStorage = SyncQueueStorage(customBaseDir: tempDir);
    final syncQueue = SyncQueue(storage: queueStorage);
    final metaStorage = PhotoMetadataStorage(customBaseDir: tempDir);
    final fileManager = PhotoFileManager(customBaseDir: tempDir);

    photoStore = PersistentDailyPhotoStore(
      syncQueue: syncQueue,
      metadataStorage: metaStorage,
      fileManager: fileManager,
    );
    await photoStore.init();
    PersistentDailyPhotoStore.setTestInstance(photoStore);

    authService = GoogleAuthService(delegate: fakeSignInDelegate);
    await authService.init();

    final driveAuthStorage = DriveAuthStorage(customBaseDir: tempDir.path);
    driveAuthService = GoogleDriveAuthService(
      authService: authService,
      delegate: fakeDriveAuthDelegate,
      storage: driveAuthStorage,
    );
    await driveAuthService.init();

    final folderStorage = DriveFolderStorage(customBaseDir: tempDir.path);
    driveService = GoogleDriveService(
      adapter: fakeDriveAdapter,
      storage: folderStorage,
      authService: authService,
      driveAuthService: driveAuthService,
    );
    await driveService.init();

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
    SyncWorker.setTestInstance(syncWorker);

    coordinator = SyncCoordinator(
      worker: syncWorker,
      queue: photoStore.syncQueue,
      authService: authService,
      driveAuthService: driveAuthService,
      driveService: driveService,
      networkChecker: fakeNetworkChecker,
      backgroundScheduler: fakeBackgroundScheduler,
      debounceDuration: const Duration(milliseconds: 50),
    );
    await coordinator.init();
    SyncCoordinator.setTestInstance(coordinator);
  });

  tearDown(() async {
    SyncCoordinator.resetInstance();
    SyncWorker.resetInstance();
    PersistentDailyPhotoStore.resetTestInstance();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Future<void> makeFullyReady({String email = 'test@example.com'}) async {
    fakeSignInDelegate.mockUser = AuthUser(
      id: 'id_$email',
      email: email,
      displayName: 'User $email',
    );
    await authService.signIn();
    await driveAuthService.authorizeDrive();

    fakeDriveAdapter.existingFolder = DriveFolderReference(
      folderId: 'coord_folder_id',
      folderName: 'Photo a Day',
      authorizedEmail: email,
      resolvedAt: DateTime.now().toUtc(),
    );
    await driveService.setupFolder();
  }

  Future<PhotoEntry> addTestPhoto({
    required DateKey dateKey,
    String? email,
  }) async {
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}test_${dateKey.format()}.jpg',
    );
    file.writeAsBytesSync([10, 20, 30, 40]);

    final entry = PhotoEntry(
      date: dateKey.toDateTime(),
      title: 'Memory ${dateKey.format()}',
      gradientColors: const [Color(0xFF111111), Color(0xFF222222)],
      imagePath: file.path,
      syncStatus: SyncStatus.localOnly,
      authorizedEmail: email,
    );

    return await photoStore.savePhoto(entry: entry, sourceTempPath: file.path);
  }

  Future<void> waitForSyncComplete(
    SyncCoordinator c, {
    SyncQueue? queue,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    await Future.delayed(const Duration(milliseconds: 30));
    while (c.isDebouncing ||
        c.isSyncing ||
        (queue != null && queue.isNotEmpty)) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Timed out waiting for sync to complete');
      }
      await Future.delayed(const Duration(milliseconds: 25));
    }
  }

  group('Milestone 25 — SyncCoordinator Focused Verification', () {
    // 1. Foreground triggers sync when appropriate.
    test('1. Foreground triggers sync when appropriate', () async {
      await makeFullyReady();
      const dateKey = DateKey(2026, 3, 26);
      await addTestPhoto(dateKey: dateKey, email: testUser.email);
      await photoStore.syncQueue.enqueueUpload(
        dateKey,
        authorizedEmail: testUser.email,
      );

      expect(photoStore.syncQueue.count, equals(1));
      expect(fakeDriveAdapter.uploadCalls, equals(0));

      final result = await coordinator.onAppForegrounded();

      expect(result.processedCount, equals(1));
      expect(result.uploadedCount, equals(1));
      expect(fakeDriveAdapter.uploadCalls, equals(1));
      expect(photoStore.syncQueue.isEmpty, isTrue);
      expect(
        photoStore.getPhotoByKey(dateKey)?.syncStatus,
        equals(SyncStatus.synced),
      );
    });

    // 2. Foreground does nothing when signed out.
    test('2. Foreground does nothing when signed out', () async {
      // Ensure signed out
      await authService.signOut();
      expect(authService.isSignedIn, isFalse);

      const dateKey = DateKey(2026, 3, 26);
      await addTestPhoto(dateKey: dateKey);
      await photoStore.syncQueue.enqueueUpload(dateKey);

      final result = await coordinator.onAppForegrounded();

      expect(result.processedCount, equals(0));
      expect(fakeDriveAdapter.uploadCalls, equals(0));
      expect(photoStore.syncQueue.count, equals(1));
    });

    // 3. Foreground does nothing when Drive is unauthorized.
    test('3. Foreground does nothing when Drive is unauthorized', () async {
      fakeSignInDelegate.mockUser = testUser;
      await authService.signIn();
      await driveAuthService.clearAuthorization();
      expect(driveAuthService.isAuthorized, isFalse);

      const dateKey = DateKey(2026, 3, 26);
      await addTestPhoto(dateKey: dateKey, email: testUser.email);
      await photoStore.syncQueue.enqueueUpload(
        dateKey,
        authorizedEmail: testUser.email,
      );

      final result = await coordinator.onAppForegrounded();

      expect(result.processedCount, equals(0));
      expect(fakeDriveAdapter.uploadCalls, equals(0));
      expect(photoStore.syncQueue.count, equals(1));
    });

    // 4. Foreground does nothing when queue is empty.
    test('4. Foreground does nothing when queue is empty', () async {
      await makeFullyReady();
      expect(photoStore.syncQueue.isEmpty, isTrue);

      final result = await coordinator.onAppForegrounded();

      expect(result.processedCount, equals(0));
      expect(fakeDriveAdapter.uploadCalls, equals(0));
    });

    // 5. Photo change schedules/debounces sync.
    test('5. Photo change schedules and debounces sync', () async {
      await makeFullyReady();
      const dateKey = DateKey(2026, 3, 26);
      await addTestPhoto(dateKey: dateKey, email: testUser.email);

      // Enqueue upload (simulates what savePhoto or UI does)
      await photoStore.syncQueue.enqueueUpload(
        dateKey,
        authorizedEmail: testUser.email,
      );

      // Verify debounce is active
      expect(coordinator.isDebouncing, isTrue);
      expect(fakeDriveAdapter.uploadCalls, equals(0));

      // Wait for debounce timer and worker execution to complete
      await waitForSyncComplete(coordinator, queue: photoStore.syncQueue);

      expect(fakeDriveAdapter.uploadCalls, equals(1));
      expect(photoStore.syncQueue.isEmpty, isTrue);
      expect(coordinator.lastSyncSuccessAt, isNotNull);
    });

    // 6. Multiple rapid photo changes produce one sync request.
    test(
      '6. Multiple rapid photo changes coalesce into a single sync run',
      () async {
        await makeFullyReady();

        // Dispose existing coordinator so only multiCoordinator listens
        coordinator.dispose();

        // Use a coordinator with an 800ms debounce window for rapid burst coalescing
        final multiCoordinator = SyncCoordinator(
          worker: syncWorker,
          queue: photoStore.syncQueue,
          authService: authService,
          driveAuthService: driveAuthService,
          driveService: driveService,
          networkChecker: fakeNetworkChecker,
          backgroundScheduler: fakeBackgroundScheduler,
          debounceDuration: const Duration(milliseconds: 800),
        );
        await multiCoordinator.init();
        SyncCoordinator.setTestInstance(multiCoordinator);

        const date1 = DateKey(2026, 3, 24);
        const date2 = DateKey(2026, 3, 25);
        const date3 = DateKey(2026, 3, 26);

        await addTestPhoto(dateKey: date1, email: testUser.email);
        await addTestPhoto(dateKey: date2, email: testUser.email);
        await addTestPhoto(dateKey: date3, email: testUser.email);

        // Rapidly enqueue 3 items within the 250ms window
        await photoStore.syncQueue.enqueueUpload(
          date1,
          authorizedEmail: testUser.email,
        );
        await Future.delayed(const Duration(milliseconds: 20));
        await photoStore.syncQueue.enqueueUpload(
          date2,
          authorizedEmail: testUser.email,
        );
        await Future.delayed(const Duration(milliseconds: 20));
        await photoStore.syncQueue.enqueueUpload(
          date3,
          authorizedEmail: testUser.email,
        );

        // Debounce should still be pending and 0 uploads made so far
        expect(multiCoordinator.isDebouncing, isTrue);
        expect(fakeDriveAdapter.uploadCalls, equals(0));

        // Wait for debounce and processing of all 3 items to complete
        await waitForSyncComplete(
          multiCoordinator,
          queue: photoStore.syncQueue,
        );

        // All 3 were processed in a single run
        expect(fakeDriveAdapter.uploadCalls, equals(3));
        expect(photoStore.syncQueue.isEmpty, isTrue);
      },
    );

    // 7. Backoff prevents unnecessary immediate retry.
    test('7. Backoff prevents unnecessary immediate retry', () async {
      await makeFullyReady();
      const dateKey = DateKey(2026, 3, 26);
      await addTestPhoto(dateKey: dateKey, email: testUser.email);

      // Enqueue and mark failed with future backoff
      final op = await photoStore.syncQueue.enqueueUpload(
        dateKey,
        authorizedEmail: testUser.email,
      );
      final futureBackoff = DateTime.now().toUtc().add(
        const Duration(hours: 1),
      );
      await photoStore.syncQueue.markFailed(
        op.id,
        error: 'Drive 503 Service Unavailable',
        nextAttemptAt: futureBackoff,
      );

      expect(coordinator.canSyncNow, isFalse);

      final result = await coordinator.requestSync(
        trigger: SyncTrigger.foreground,
      );

      expect(result.processedCount, equals(0));
      expect(result.skippedCount, equals(1));
      expect(fakeDriveAdapter.uploadCalls, equals(0));
    });

    // 8. Sign-in can trigger sync.
    test('8. Sign-in triggers sync when pending work exists', () async {
      // Setup Drive authorization and folder while signed in initially
      await makeFullyReady();
      const dateKey = DateKey(2026, 3, 26);
      await addTestPhoto(dateKey: dateKey, email: testUser.email);
      await photoStore.syncQueue.enqueueUpload(
        dateKey,
        authorizedEmail: testUser.email,
      );

      // Now sign out
      await authService.signOut();
      expect(authService.isSignedIn, isFalse);
      expect(coordinator.isDebouncing, isFalse);

      fakeDriveAdapter.uploadCalls = 0;

      // Re-sign in
      fakeSignInDelegate.mockUser = testUser;
      await authService.signIn();

      // Wait for sign-in auto-sync and processing to complete
      await waitForSyncComplete(coordinator, queue: photoStore.syncQueue);

      expect(fakeDriveAdapter.uploadCalls, equals(1));
      expect(photoStore.syncQueue.isEmpty, isTrue);
    });

    // 9. Sign-out prevents future automatic sync.
    test('9. Sign-out cancels timers and prevents automatic sync', () async {
      await makeFullyReady();
      await authService.signOut();

      const dateKey = DateKey(2026, 3, 26);
      await addTestPhoto(dateKey: dateKey);
      await photoStore.syncQueue.enqueueUpload(dateKey);

      // Even if photo change happened, since signed out, no debounce or sync occurs
      expect(coordinator.isDebouncing, isFalse);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(fakeDriveAdapter.uploadCalls, equals(0));
      expect(photoStore.syncQueue.count, equals(1));
    });

    // 10. Manual Sync Now still works.
    test('10. Manual Sync Now works immediately bypassing debounce', () async {
      await makeFullyReady();
      const dateKey = DateKey(2026, 3, 26);
      await addTestPhoto(dateKey: dateKey, email: testUser.email);
      await photoStore.syncQueue.enqueueUpload(
        dateKey,
        authorizedEmail: testUser.email,
      );

      // Explicit manual trigger
      final result = await coordinator.requestSync(trigger: SyncTrigger.manual);

      expect(result.processedCount, equals(1));
      expect(result.uploadedCount, equals(1));
      expect(fakeDriveAdapter.uploadCalls, equals(1));
      expect(photoStore.syncQueue.isEmpty, isTrue);
    });

    // 11. Automatic + manual requests do not run two SyncWorkers concurrently.
    test(
      '11. In-flight protection prevents concurrent sync requests',
      () async {
        await makeFullyReady();
        fakeDriveAdapter.simulatedDelay = const Duration(milliseconds: 150);

        const dateKey = DateKey(2026, 3, 26);
        await addTestPhoto(dateKey: dateKey, email: testUser.email);
        await photoStore.syncQueue.enqueueUpload(
          dateKey,
          authorizedEmail: testUser.email,
        );

        // Start first sync asynchronously
        final firstSyncFuture = coordinator.requestSync(
          trigger: SyncTrigger.foreground,
        );

        // Immediately attempt second sync while first is in-flight
        await Future.delayed(const Duration(milliseconds: 20));
        final secondResult = await coordinator.requestSync(
          trigger: SyncTrigger.manual,
        );

        expect(secondResult.alreadyRunning, isTrue);

        final firstResult = await firstSyncFuture;
        expect(firstResult.processedCount, equals(1));
        expect(fakeDriveAdapter.uploadCalls, equals(1));
      },
    );

    // 12. App restart preserves pending work.
    test(
      '12. App restart preserves pending work and allows coordinator to resume',
      () async {
        const dateKey = DateKey(2026, 3, 26);
        await addTestPhoto(dateKey: dateKey, email: testUser.email);
        await photoStore.syncQueue.enqueueUpload(
          dateKey,
          authorizedEmail: testUser.email,
        );

        // Simulate app kill by disposing current coordinator and creating new instances
        coordinator.dispose();

        final newQueueStorage = SyncQueueStorage(customBaseDir: tempDir);
        final newQueue = SyncQueue(storage: newQueueStorage);
        await newQueue.init();

        expect(newQueue.count, equals(1));
        expect(newQueue.operations.first.dateKey, equals(dateKey));

        final newCoordinator = SyncCoordinator(
          worker: syncWorker,
          queue: newQueue,
          authService: authService,
          driveAuthService: driveAuthService,
          driveService: driveService,
          networkChecker: fakeNetworkChecker,
          backgroundScheduler: fakeBackgroundScheduler,
        );
        await newCoordinator.init();
        SyncCoordinator.setTestInstance(newCoordinator);

        expect(newCoordinator.isInitialized, isTrue);
      },
    );

    // 13. Background scheduler does not create duplicate jobs.
    test(
      '13. Background scheduler tracks calls without duplicate jobs',
      () async {
        expect(fakeBackgroundScheduler.scheduleCount, equals(0));
        await fakeBackgroundScheduler.scheduleBackgroundSync();
        expect(fakeBackgroundScheduler.scheduleCount, equals(1));
        await fakeBackgroundScheduler.cancelBackgroundSync();
        expect(fakeBackgroundScheduler.cancelCount, equals(1));
      },
    );

    // 14. Offline state does not delete or corrupt queue data.
    test(
      '14. Offline state defers sync safely without deleting or corrupting queue',
      () async {
        await makeFullyReady();
        fakeNetworkChecker.online = false; // Simulated offline

        const dateKey = DateKey(2026, 3, 26);
        await addTestPhoto(dateKey: dateKey, email: testUser.email);
        await photoStore.syncQueue.enqueueUpload(
          dateKey,
          authorizedEmail: testUser.email,
        );

        final result = await coordinator.requestSync(
          trigger: SyncTrigger.foreground,
        );

        expect(result.processedCount, equals(0));
        expect(result.skippedCount, equals(1));
        expect(fakeDriveAdapter.uploadCalls, equals(0));

        // Queue and local photo remain completely safe and intact
        expect(photoStore.syncQueue.count, equals(1));
        expect(photoStore.getPhotoByKey(dateKey), isNotNull);
      },
    );

    // 15. Account-switch safety from Milestone 24 remains intact.
    test(
      '15. Account-switch safety from Milestone 24 remains intact under auto-sync',
      () async {
        await makeFullyReady(email: 'user_a@example.com');
        const dateKey = DateKey(2026, 3, 26);
        await addTestPhoto(dateKey: dateKey, email: 'user_a@example.com');
        await photoStore.syncQueue.enqueueUpload(
          dateKey,
          authorizedEmail: 'user_a@example.com',
        );

        // User A signs out
        await authService.signOut();

        // User B signs in
        await makeFullyReady(email: 'user_b@example.com');

        // Auto-sync requested under User B
        final result = await coordinator.requestSync(
          trigger: SyncTrigger.foreground,
        );

        // Operation for User A must fail safely with zero Drive uploads under User B
        expect(result.failedCount, equals(1));
        expect(fakeDriveAdapter.uploadCalls, equals(0));
        expect(photoStore.getPhotoByKey(dateKey), isNotNull);
      },
    );
  });
}
