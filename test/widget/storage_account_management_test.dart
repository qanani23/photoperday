import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/data/models/auth_user.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/drive_folder_reference.dart';
import 'package:photo_per_day/data/models/drive_photo_upload_response.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_operation.dart';
import 'package:photo_per_day/data/models/sync_operation_status.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/models/sync_tombstone.dart';
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
import 'package:photo_per_day/screens/profile/profile_screen.dart';

class TestFakeGoogleSignInDelegate implements GoogleSignInDelegate {
  AuthUser? mockUser;
  bool shouldThrowOnSignIn = false;

  @override
  Future<AuthUser?> signInSilently() async => mockUser;

  @override
  Future<AuthUser?> signIn() async {
    if (shouldThrowOnSignIn) throw Exception('network_error');
    return mockUser;
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> canAccessDriveScope() async => true;

  @override
  Future<bool> requestDriveScope() async => true;

  @override
  Future<Map<String, String>> getAuthHeaders() async => {
    'Authorization': 'Bearer test_token',
    'X-Goog-AuthUser': '0',
  };
}

class TestFakeDriveAuthDelegate implements GoogleDriveAuthDelegate {
  bool driveScopeGranted = true;
  int requestScopeCalls = 0;

  @override
  Future<bool> canAccessDriveScope() async => true;

  @override
  Future<bool> requestDriveScope() async {
    requestScopeCalls++;
    return driveScopeGranted;
  }

  @override
  Future<Map<String, String>> getAuthHeaders() async => {
    'Authorization': 'Bearer test_token',
    'X-Goog-AuthUser': '0',
  };
}

class TestFakeDriveApiAdapter implements DriveApiAdapter {
  DriveFolderReference? existingFolder;
  int uploadCalls = 0;

  @override
  Future<DriveFolderReference?> findFolder({
    required String folderName,
    required Map<String, String> authHeaders,
    String? accountEmail,
  }) async {
    return existingFolder;
  }

  @override
  Future<DriveFolderReference> createFolder({
    required String folderName,
    required Map<String, String> authHeaders,
    String? accountEmail,
  }) async {
    return DriveFolderReference(
      folderId: 'test_folder_id',
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
    if (onProgress != null) {
      onProgress(0.5);
      onProgress(1.0);
    }
    return DrivePhotoUploadResponse(
      fileId: 'remote_file_$uploadCalls',
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
    return DrivePhotoUploadResponse(
      fileId: fileId,
      revision: '2',
      filename: filename ?? 'photo.jpg',
      uploadedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> trashPhotoFile({
    required String fileId,
    required Map<String, String> authHeaders,
  }) async {}
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
  Future<bool> deletePhotoFile(String? path) async {
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
    return true;
  }

  @override
  Future<List<String>> pruneUnreferencedPhotos(
    Set<String> referencedPaths,
  ) async => [];
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
  Future<void> clear() async {
    _ops.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late TestFakeGoogleSignInDelegate fakeSignInDelegate;
  late TestFakeDriveAuthDelegate fakeDriveDelegate;
  late TestFakeDriveApiAdapter fakeApiAdapter;
  late GoogleDriveService driveService;
  late PersistentDailyPhotoStore photoStore;
  late GoogleDrivePhotoUploadService uploadService;
  late SyncWorker syncWorker;

  const testUser = AuthUser(
    id: 'user_m34',
    email: 'm34.photouser@gmail.com',
    displayName: 'Memory Keeper',
  );

  const testColors = [Color(0xFF333333), Color(0xFF555555)];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('storage_account_m34_');

    fakeSignInDelegate = TestFakeGoogleSignInDelegate();
    GoogleAuthService.instance.delegate = fakeSignInDelegate;
    await GoogleAuthService.instance.signOut();

    fakeDriveDelegate = TestFakeDriveAuthDelegate();
    GoogleDriveAuthService.instance.delegate = fakeDriveDelegate;
    GoogleDriveAuthService.instance.storage = DriveAuthStorage(
      customBaseDir: tempDir.path,
    );
    await GoogleDriveAuthService.instance.clearAuthorization();

    fakeApiAdapter = TestFakeDriveApiAdapter();
    final folderStorage = DriveFolderStorage(customBaseDir: tempDir.path);
    driveService = GoogleDriveService(
      adapter: fakeApiAdapter,
      storage: folderStorage,
    );
    await driveService.init();
    GoogleDriveService.setTestInstance(driveService);

    final fileManager = TestFakePhotoFileManager(customBaseDir: tempDir);
    final metadataStorage = TestFakePhotoMetadataStorage(
      customBaseDir: tempDir,
    );
    final syncQueueStorage = TestFakeSyncQueueStorage(customBaseDir: tempDir);
    photoStore = PersistentDailyPhotoStore(
      fileManager: fileManager,
      metadataStorage: metadataStorage,
      syncQueue: SyncQueue(storage: syncQueueStorage),
    );
    await photoStore.init();
    PersistentDailyPhotoStore.setTestInstance(photoStore);

    uploadService = GoogleDrivePhotoUploadService(
      adapter: fakeApiAdapter,
      authService: GoogleAuthService.instance,
      driveAuthService: GoogleDriveAuthService.instance,
      driveService: driveService,
      photoStore: photoStore,
    );
    GoogleDrivePhotoUploadService.setTestInstance(uploadService);

    syncWorker = SyncWorker(
      syncQueue: photoStore.syncQueue,
      photoStore: photoStore,
      authService: GoogleAuthService.instance,
      driveAuthService: GoogleDriveAuthService.instance,
      driveService: driveService,
      uploadService: uploadService,
      driveAdapter: fakeApiAdapter,
    );
    SyncWorker.setTestInstance(syncWorker);
  });

  tearDown(() async {
    ProfileScreen.enableDeveloperTools = false;
    SyncWorker.resetInstance();
    GoogleDrivePhotoUploadService.resetInstance();
    PersistentDailyPhotoStore.resetTestInstance();
    GoogleDriveService.resetInstance();
    try {
      await GoogleDriveAuthService.instance.clearAuthorization();
    } catch (_) {}
    try {
      await GoogleAuthService.instance.signOut();
    } catch (_) {}
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Widget buildTestWidget({bool showDeveloperTools = false}) {
    return MaterialApp(
      home: Scaffold(
        body: ProfileScreen(showDeveloperTools: showDeveloperTools),
      ),
    );
  }

  Future<PhotoEntry> createLocalPhoto({
    required DateKey dateKey,
    int byteSize = 1024,
    SyncStatus syncStatus = SyncStatus.localOnly,
    String? authorizedEmail,
    String? driveFileId,
  }) async {
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}photo_${dateKey.year}_${dateKey.month}_${dateKey.day}.jpg',
    );
    file.writeAsBytesSync(List.filled(byteSize, 42));

    final entry = PhotoEntry(
      date: dateKey.toDateTime(),
      title: 'Memory ${dateKey.format()}',
      gradientColors: testColors,
      imagePath: file.path,
      syncStatus: syncStatus,
      authorizedEmail: authorizedEmail,
      driveFileId: driveFileId,
    );

    return await photoStore.savePhoto(entry: entry, sourceTempPath: file.path);
  }

  group('Milestone 34 — Account Management UI & Lifecycle', () {
    testWidgets('1. Signed-out state is displayed correctly', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Google Account'), findsOneWidget);
      expect(find.text('Sign in to enable future cloud sync'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);

      expect(find.text('Google Drive Backup'), findsOneWidget);
      expect(find.text('Not connected • Cloud storage'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
    });

    testWidgets('2. Signed-in Google account is displayed correctly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      fakeSignInDelegate.mockUser = testUser;
      await GoogleAuthService.instance.signIn();

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Memory Keeper'), findsOneWidget);
      expect(find.text('m34.photouser@gmail.com'), findsOneWidget);
      expect(find.text('Sign Out'), findsOneWidget);
    });

    testWidgets(
      '3. Signed-in but Drive unauthorized state is displayed correctly',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        fakeSignInDelegate.mockUser = testUser;
        await GoogleAuthService.instance.signIn();

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Google Drive Backup'), findsOneWidget);
        expect(find.text('Not authorized • Cloud storage'), findsOneWidget);
        expect(find.text('Enable Drive Backup'), findsOneWidget);
      },
    );

    testWidgets(
      '4. Signed-in + Drive authorized state is displayed correctly',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        fakeSignInDelegate.mockUser = testUser;
        await GoogleAuthService.instance.signIn();
        await GoogleDriveAuthService.instance.authorizeDrive();

        fakeApiAdapter.existingFolder = DriveFolderReference(
          folderId: 'folder_ready',
          folderName: 'Photo a Day',
          authorizedEmail: testUser.email,
          resolvedAt: DateTime.now().toUtc(),
        );
        await driveService.setupFolder();

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Google Drive Backup'), findsOneWidget);
        expect(
          find.text('Google Drive • Photo a Day folder ready'),
          findsOneWidget,
        );
        expect(find.text('Details'), findsOneWidget);
      },
    );

    testWidgets(
      '5. Sign-out preserves local photos and confirms when operations are pending',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        fakeSignInDelegate.mockUser = testUser;
        await GoogleAuthService.instance.signIn();

        // Create local photo and queue an upload operation
        await createLocalPhoto(
          dateKey: const DateKey(2026, 4, 1),
          byteSize: 2048,
        );
        await photoStore.syncQueue.enqueueUpload(
          const DateKey(2026, 4, 1),
          authorizedEmail: testUser.email,
        );

        expect(photoStore.count, 1);
        expect(photoStore.syncQueue.count, 1);

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // Tap Sign Out with pending operation
        await tester.tap(find.text('Sign Out'));
        await tester.pumpAndSettle();

        // Confirmation dialog appears explaining pending backup and local photo safety
        expect(find.text('Sign Out of Google Account?'), findsOneWidget);
        expect(
          find.textContaining('1 photo waiting to sync to Google Drive'),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Your local photos and diary entries will remain completely safe',
          ),
          findsOneWidget,
        );

        // Tap 'Sign Out' in dialog to confirm
        final dialogSignOutButton = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Sign Out'),
        );
        await tester.tap(dialogSignOutButton);
        await tester.pumpAndSettle();

        // Verify signed out
        expect(GoogleAuthService.instance.isSignedIn, isFalse);
        expect(find.text('Google Account'), findsOneWidget);

        // Local photo and queue are completely preserved
        expect(photoStore.count, 1);
        expect(photoStore.getPhotoByKey(const DateKey(2026, 4, 1)), isNotNull);
        expect(photoStore.syncQueue.count, 1);
      },
    );

    testWidgets('6. Sign-out prevents unauthorized cloud sync', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // While signed out, queue an operation and trigger sync worker directly
      await createLocalPhoto(dateKey: const DateKey(2026, 4, 2));
      await photoStore.syncQueue.enqueueUpload(const DateKey(2026, 4, 2));

      final result = await syncWorker.syncNow();
      expect(result.processedCount, 0);
      expect(fakeApiAdapter.uploadCalls, 0);

      // Verify UI communicates requirement
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Google account sign-in required'), findsOneWidget);
    });

    testWidgets(
      '7. Account switching does not cross-contaminate Drive ownership',
      (tester) async {
        const userA = AuthUser(
          id: 'user_a',
          email: 'user.a@gmail.com',
          displayName: 'User A',
        );
        const userB = AuthUser(
          id: 'user_b',
          email: 'user.b@gmail.com',
          displayName: 'User B',
        );

        // User A signs in and resolves folder
        fakeSignInDelegate.mockUser = userA;
        await GoogleAuthService.instance.signIn();
        await GoogleDriveAuthService.instance.authorizeDrive();

        fakeApiAdapter.existingFolder = DriveFolderReference(
          folderId: 'folder_user_a',
          folderName: 'Photo a Day',
          authorizedEmail: userA.email,
          resolvedAt: DateTime.now().toUtc(),
        );
        await driveService.setupFolder();
        expect(driveService.isReady, isTrue);
        expect(driveService.currentFolder?.authorizedEmail, userA.email);

        // Enqueue upload tagged for User A
        await createLocalPhoto(
          dateKey: const DateKey(2026, 4, 3),
          authorizedEmail: userA.email,
        );
        await photoStore.syncQueue.enqueueUpload(
          const DateKey(2026, 4, 3),
          authorizedEmail: userA.email,
        );

        // Account switches to User B
        await GoogleAuthService.instance.signOut();
        fakeSignInDelegate.mockUser = userB;
        await GoogleAuthService.instance.signIn();

        // DriveService automatically detects account switch and resets folder
        expect(driveService.isReady, isFalse);

        // User B authorizes their Drive
        await GoogleDriveAuthService.instance.authorizeDrive();
        fakeApiAdapter.existingFolder = DriveFolderReference(
          folderId: 'folder_user_b',
          folderName: 'Photo a Day',
          authorizedEmail: userB.email,
          resolvedAt: DateTime.now().toUtc(),
        );
        await driveService.setupFolder();

        // SyncWorker runs under User B - must NOT upload User A's queued photo
        final runResult = await syncWorker.syncNow();
        expect(runResult.uploadedCount, 0);
        expect(fakeApiAdapter.uploadCalls, 0);

        // The operation for User A failed safely due to account mismatch
        final op = photoStore.syncQueue.operations.first;
        expect(op.status, SyncOperationStatus.failed);
        expect(op.lastError, contains(userB.email));
      },
    );

    testWidgets('8. Re-authorization restores appropriate Drive state', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      fakeSignInDelegate.mockUser = testUser;
      await GoogleAuthService.instance.signIn();

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Enable Drive Backup'), findsOneWidget);

      // Tap Enable Drive Backup
      await tester.tap(find.text('Enable Drive Backup'));
      await tester.pumpAndSettle();

      expect(fakeDriveDelegate.requestScopeCalls, 1);
      expect(GoogleDriveAuthService.instance.isAuthorized, isTrue);
    });
  });

  group('Milestone 34 — Storage Transparency & Warning', () {
    testWidgets('9. Actual local photo byte usage is displayed accurately', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Add 2 photos totaling exactly 10,240 bytes (10.0 KB)
      await createLocalPhoto(
        dateKey: const DateKey(2026, 4, 10),
        byteSize: 5120,
      );
      await createLocalPhoto(
        dateKey: const DateKey(2026, 4, 11),
        byteSize: 5120,
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Local Photo Storage'), findsOneWidget);
      expect(find.textContaining('10 KB used'), findsOneWidget);
    });

    testWidgets('10. Actual stored photo count is displayed accurately', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await createLocalPhoto(
        dateKey: const DateKey(2026, 4, 12),
        byteSize: 500,
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.textContaining('1 photo •'), findsOneWidget);
    });

    testWidgets('11. Empty storage displays zero correctly', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Local Photo Storage'), findsOneWidget);
      expect(find.text('0 photos • 0 B used'), findsOneWidget);
    });

    testWidgets('12. No fake device-storage capacity is shown', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await createLocalPhoto(
        dateKey: const DateKey(2026, 4, 13),
        byteSize: 2048,
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Tap on Local Photo Storage tile to open details dialog
      await tester.tap(find.text('Local Photo Storage'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.textContaining(
          'This represents only the storage used by Photo a Day photos, not your entire phone storage.',
        ),
        findsOneWidget,
      );

      // Verify no fabricated device capacity exists anywhere in the dialog
      expect(find.textContaining('GB of'), findsNothing);
      expect(find.textContaining('phone capacity'), findsNothing);
    });

    testWidgets('13. Storage warning uses configured threshold correctly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Below threshold (500 MB): Warning is NOT displayed
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      expect(find.text('Photo storage is getting large'), findsNothing);

      // Verify helper function
      expect(
        LocalStorageCalculator.isStorageWarning(
          bytes: AppConstants.photoStorageWarningThresholdBytes - 1,
        ),
        isFalse,
      );
      expect(
        LocalStorageCalculator.isStorageWarning(
          bytes: AppConstants.photoStorageWarningThresholdBytes,
        ),
        isTrue,
      );
      expect(
        LocalStorageCalculator.isStorageWarning(
          bytes: AppConstants.photoStorageWarningThresholdBytes + 1024,
        ),
        isTrue,
      );
    });
  });

  group('Milestone 34 — Backup Status & Sync Integration', () {
    testWidgets('14. Pending backup count is accurate', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      fakeSignInDelegate.mockUser = testUser;
      await GoogleAuthService.instance.signIn();
      await GoogleDriveAuthService.instance.authorizeDrive();

      fakeApiAdapter.existingFolder = DriveFolderReference(
        folderId: 'folder_pending',
        folderName: 'Photo a Day',
        authorizedEmail: testUser.email,
        resolvedAt: DateTime.now().toUtc(),
      );
      await driveService.setupFolder();

      await createLocalPhoto(dateKey: const DateKey(2026, 4, 20));
      await createLocalPhoto(dateKey: const DateKey(2026, 4, 21));

      await photoStore.syncQueue.enqueueUpload(
        const DateKey(2026, 4, 20),
        authorizedEmail: testUser.email,
      );
      await photoStore.syncQueue.enqueueUpload(
        const DateKey(2026, 4, 21),
        authorizedEmail: testUser.email,
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.textContaining('2 photos waiting to sync'), findsOneWidget);
      expect(find.textContaining('Waiting: 2'), findsOneWidget);
    });

    testWidgets('15. Failed backup state is displayed accurately', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      fakeSignInDelegate.mockUser = testUser;
      await GoogleAuthService.instance.signIn();
      await GoogleDriveAuthService.instance.authorizeDrive();

      fakeApiAdapter.existingFolder = DriveFolderReference(
        folderId: 'folder_failed',
        folderName: 'Photo a Day',
        authorizedEmail: testUser.email,
        resolvedAt: DateTime.now().toUtc(),
      );
      await driveService.setupFolder();

      await createLocalPhoto(dateKey: const DateKey(2026, 4, 22));
      final op = await photoStore.syncQueue.enqueueUpload(
        const DateKey(2026, 4, 22),
        authorizedEmail: testUser.email,
      );
      await photoStore.syncQueue.markFailed(
        op.id,
        error: 'Simulated Drive timeout',
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.textContaining('Backup failed'), findsOneWidget);
      expect(find.textContaining('Failed: 1'), findsOneWidget);
    });

    testWidgets('16. Sync action uses existing SyncCoordinator/SyncWorker', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      fakeSignInDelegate.mockUser = testUser;
      await GoogleAuthService.instance.signIn();
      await GoogleDriveAuthService.instance.authorizeDrive();

      fakeApiAdapter.existingFolder = DriveFolderReference(
        folderId: 'folder_sync',
        folderName: 'Photo a Day',
        authorizedEmail: testUser.email,
        resolvedAt: DateTime.now().toUtc(),
      );
      await driveService.setupFolder();

      await createLocalPhoto(dateKey: const DateKey(2026, 4, 23));
      await photoStore.syncQueue.enqueueUpload(
        const DateKey(2026, 4, 23),
        authorizedEmail: testUser.email,
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Sync Now'), findsOneWidget);
      await tester.tap(find.text('Sync Now'));
      await tester.pumpAndSettle();

      expect(fakeApiAdapter.uploadCalls, 1);
      expect(photoStore.syncQueue.isEmpty, isTrue);
    });

    testWidgets('17. Last-sync information is not fabricated', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      fakeSignInDelegate.mockUser = testUser;
      await GoogleAuthService.instance.signIn();
      await GoogleDriveAuthService.instance.authorizeDrive();

      fakeApiAdapter.existingFolder = DriveFolderReference(
        folderId: 'folder_ready_no_sync',
        folderName: 'Photo a Day',
        authorizedEmail: testUser.email,
        resolvedAt: DateTime.now().toUtc(),
      );
      await driveService.setupFolder();

      // No sync has been performed yet
      expect(SyncCoordinator.instance.lastSyncSuccessAt, isNull);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Must not fabricate a timestamp
      expect(find.textContaining('Last backed up'), findsNothing);
      expect(find.textContaining('Up to date'), findsOneWidget);
    });
  });

  group('Milestone 34 — Local Data Safety & Isolation Boundaries', () {
    testWidgets('18. Disconnecting an account does not delete local photos', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      fakeSignInDelegate.mockUser = testUser;
      await GoogleAuthService.instance.signIn();
      await GoogleDriveAuthService.instance.authorizeDrive();

      // Add local photos
      await createLocalPhoto(dateKey: const DateKey(2026, 4, 25));
      await createLocalPhoto(dateKey: const DateKey(2026, 4, 26));
      expect(photoStore.count, 2);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Tap Disconnect Account
      expect(find.text('Disconnect Account'), findsOneWidget);
      await tester.tap(find.text('Disconnect Account'));
      await tester.pumpAndSettle();

      // Dialog confirms data safety
      expect(find.text('Disconnect Google Account?'), findsOneWidget);
      expect(
        find.textContaining(
          'Your local photos and diary entries will remain completely safe',
        ),
        findsOneWidget,
      );

      // Confirm disconnect
      await tester.tap(find.widgetWithText(TextButton, 'Disconnect'));
      await tester.pumpAndSettle();

      // Account is signed out and Drive unlinked
      expect(GoogleAuthService.instance.isSignedIn, isFalse);
      expect(GoogleDriveAuthService.instance.isAuthorized, isFalse);

      // Local photos remain 100% intact!
      expect(photoStore.count, 2);
      expect(photoStore.getPhotoByKey(const DateKey(2026, 4, 25)), isNotNull);
      expect(photoStore.getPhotoByKey(const DateKey(2026, 4, 26)), isNotNull);
    });

    testWidgets(
      '19. Pending operations are not silently discarded on sign out',
      (tester) async {
        fakeSignInDelegate.mockUser = testUser;
        await GoogleAuthService.instance.signIn();

        await createLocalPhoto(dateKey: const DateKey(2026, 4, 27));
        await photoStore.syncQueue.enqueueUpload(
          const DateKey(2026, 4, 27),
          authorizedEmail: testUser.email,
        );

        expect(photoStore.syncQueue.count, 1);

        // Sign out
        await GoogleAuthService.instance.signOut();

        // Outbox operations remain intact for resumption
        expect(photoStore.syncQueue.count, 1);
        final op = photoStore.syncQueue.operations.first;
        expect(op.dateKey, const DateKey(2026, 4, 27));
      },
    );

    testWidgets('20. No Drive operation runs without valid authorization', (
      tester,
    ) async {
      // Enqueue operation but Drive auth is false
      await createLocalPhoto(dateKey: const DateKey(2026, 4, 28));
      await photoStore.syncQueue.enqueueUpload(const DateKey(2026, 4, 28));

      final result = await syncWorker.syncNow();
      expect(result.processedCount, 0);
      expect(fakeApiAdapter.uploadCalls, 0);
    });

    testWidgets('21. No OAuth token is written to local persistence', (
      tester,
    ) async {
      fakeSignInDelegate.mockUser = testUser;
      await GoogleAuthService.instance.signIn();
      await GoogleDriveAuthService.instance.authorizeDrive();

      // Check all files written into tempDir
      final allFiles = tempDir.listSync(recursive: true).whereType<File>();
      for (final file in allFiles) {
        final content = file.readAsStringSync();
        expect(
          content.contains('test_token'),
          isFalse,
          reason: 'File ${file.path} contains OAuth token!',
        );
        expect(
          content.contains('Bearer'),
          isFalse,
          reason: 'File ${file.path} contains Bearer token!',
        );
      }
    });

    testWidgets(
      '22. Developer/test upload controls are not exposed in normal production UI',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        fakeSignInDelegate.mockUser = testUser;
        await GoogleAuthService.instance.signIn();
        await GoogleDriveAuthService.instance.authorizeDrive();

        fakeApiAdapter.existingFolder = DriveFolderReference(
          folderId: 'folder_prod',
          folderName: 'Photo a Day',
          authorizedEmail: testUser.email,
          resolvedAt: DateTime.now().toUtc(),
        );
        await driveService.setupFolder();
        expect(driveService.isReady, isTrue);

        // Render normal production ProfileScreen
        await tester.pumpWidget(buildTestWidget(showDeveloperTools: false));
        await tester.pumpAndSettle();

        // Gated developer control must NOT be visible
        expect(find.text('Upload Test Photo'), findsNothing);
        expect(
          find.text('Proof of concept • Upload 1 photo to Drive'),
          findsNothing,
        );
      },
    );
  });
}
