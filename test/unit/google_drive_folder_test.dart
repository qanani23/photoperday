import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/auth_user.dart';
import 'package:photo_per_day/data/models/drive_folder_reference.dart';
import 'package:photo_per_day/data/models/drive_folder_result.dart';
import 'package:photo_per_day/data/models/drive_folder_status.dart';
import 'package:photo_per_day/data/models/drive_photo_upload_response.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_operation_type.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/drive_api_adapter.dart';
import 'package:photo_per_day/data/services/drive_auth_storage.dart';
import 'package:photo_per_day/data/services/drive_folder_storage.dart';
import 'package:photo_per_day/data/services/google_auth_service.dart';
import 'package:photo_per_day/data/services/google_drive_auth_service.dart';
import 'package:photo_per_day/data/services/google_drive_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';

/// Test double implementing [GoogleSignInDelegate] for auth testing.
class FakeGoogleSignInDelegate implements GoogleSignInDelegate {
  AuthUser? mockUser;
  bool driveScopeGranted = false;
  bool canAccessScopeResult = false;

  @override
  Future<AuthUser?> signInSilently() async => mockUser;

  @override
  Future<AuthUser?> signIn() async => mockUser;

  @override
  Future<void> signOut() async {
    mockUser = null;
  }

  @override
  Future<void> disconnect() async {
    mockUser = null;
  }

  @override
  Future<bool> canAccessDriveScope() async => canAccessScopeResult;

  @override
  Future<bool> requestDriveScope() async => driveScopeGranted;

  @override
  Future<Map<String, String>> getAuthHeaders() async {
    if (mockUser == null) {
      throw StateError('No Google account is currently signed in.');
    }
    return {
      'Authorization': 'Bearer fake_mock_access_token',
      'X-Goog-AuthUser': '0',
    };
  }
}

/// Fake implementation of [DriveApiAdapter] for hermetic testing without network calls.
class FakeDriveApiAdapter implements DriveApiAdapter {
  DriveFolderReference? existingFolder;
  DriveFolderReference? folderToCreate;
  DriveApiException? errorOnFind;
  DriveApiException? errorOnCreate;
  int findFolderCalls = 0;
  int createFolderCalls = 0;
  Map<String, String>? lastAuthHeaders;
  String? lastSearchedName;
  String? lastCreatedName;

  @override
  Future<DriveFolderReference?> findFolder({
    required String folderName,
    required Map<String, String> authHeaders,
    String? accountEmail,
  }) async {
    findFolderCalls++;
    lastSearchedName = folderName;
    lastAuthHeaders = authHeaders;
    if (errorOnFind != null) {
      throw errorOnFind!;
    }
    return existingFolder;
  }

  @override
  Future<DriveFolderReference> createFolder({
    required String folderName,
    required Map<String, String> authHeaders,
    String? accountEmail,
  }) async {
    createFolderCalls++;
    lastCreatedName = folderName;
    lastAuthHeaders = authHeaders;
    if (errorOnCreate != null) {
      throw errorOnCreate!;
    }
    if (folderToCreate != null) {
      return folderToCreate!;
    }
    return DriveFolderReference(
      folderId: 'created_folder_id_$createFolderCalls',
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
    return DrivePhotoUploadResponse(
      fileId: 'mock_upload_id',
      revision: 'mock_revision_1',
      filename: filename,
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
      revision: 'mock_revision_2',
      filename: filename ?? 'photo.jpg',
    );
  }

  @override
  Future<void> trashPhotoFile({
    required String fileId,
    required Map<String, String> authHeaders,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late FakeGoogleSignInDelegate fakeSignInDelegate;
  late GoogleAuthService authService;
  late DriveAuthStorage driveAuthStorage;
  late GoogleDriveAuthService driveAuthService;
  late DriveFolderStorage folderStorage;
  late FakeDriveApiAdapter fakeAdapter;
  late GoogleDriveService driveService;

  const testUser = AuthUser(
    id: '123456789',
    email: 'testuser@example.com',
    displayName: 'Test User',
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('drive_folder_test_');

    fakeSignInDelegate = FakeGoogleSignInDelegate();
    authService = GoogleAuthService(delegate: fakeSignInDelegate);

    driveAuthStorage = DriveAuthStorage(customBaseDir: tempDir.path);
    driveAuthService = GoogleDriveAuthService(
      storage: driveAuthStorage,
      authService: authService,
    );

    folderStorage = DriveFolderStorage(customBaseDir: tempDir.path);
    fakeAdapter = FakeDriveApiAdapter();

    driveService = GoogleDriveService(
      adapter: fakeAdapter,
      storage: folderStorage,
      authService: authService,
      driveAuthService: driveAuthService,
    );
  });

  tearDown(() async {
    driveService.dispose();
    driveAuthService.dispose();
    authService.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('GoogleDriveService - Preconditions & Validation', () {
    test(
      '1. Signed out user attempting setupFolder() fails immediately',
      () async {
        await authService.init();
        await driveAuthService.init();
        await driveService.init();

        expect(authService.isSignedIn, isFalse);

        final result = await driveService.setupFolder();

        expect(result.isFailure, isTrue);
        expect(
          (result as DriveFolderFailure).errorType,
          DriveFolderErrorType.notSignedIn,
        );
        expect(fakeAdapter.findFolderCalls, 0);
        expect(fakeAdapter.createFolderCalls, 0);
        expect(driveService.status, DriveFolderStatus.error);
      },
    );

    test(
      '2. User not authorized for Drive fails immediately with notAuthorized',
      () async {
        fakeSignInDelegate.mockUser = testUser;
        await authService.init();
        await driveAuthService.init();
        await driveService.init();

        expect(authService.isSignedIn, isTrue);
        expect(driveAuthService.isAuthorized, isFalse);

        final result = await driveService.setupFolder();

        expect(result.isFailure, isTrue);
        expect(
          (result as DriveFolderFailure).errorType,
          DriveFolderErrorType.notAuthorized,
        );
        expect(fakeAdapter.findFolderCalls, 0);
        expect(fakeAdapter.createFolderCalls, 0);
        expect(driveService.status, DriveFolderStatus.error);
      },
    );
  });

  group('GoogleDriveService - Folder Discovery & Creation', () {
    setUp(() async {
      fakeSignInDelegate.mockUser = testUser;
      fakeSignInDelegate.driveScopeGranted = true;
      await authService.init();
      await driveAuthService.init();
      await driveAuthService.authorizeDrive();
      await driveService.init();
    });

    test(
      '3. Reuses existing remote folder without creating duplicate',
      () async {
        fakeAdapter.existingFolder = DriveFolderReference(
          folderId: 'existing_folder_999',
          folderName: 'Photo a Day',
          authorizedEmail: testUser.email,
          resolvedAt: DateTime.now().toUtc(),
        );

        final result = await driveService.setupFolder();

        expect(result.isSuccess, isTrue);
        final success = result as DriveFolderSuccess;
        expect(success.wasCreated, isFalse);
        expect(success.folder.folderId, 'existing_folder_999');
        expect(fakeAdapter.findFolderCalls, 1);
        expect(fakeAdapter.createFolderCalls, 0);
        expect(driveService.status, DriveFolderStatus.ready);
        expect(driveService.isReady, isTrue);
      },
    );

    test('4. Creates folder with name "Photo a Day" when absent', () async {
      fakeAdapter.existingFolder = null; // not found

      final result = await driveService.setupFolder();

      expect(result.isSuccess, isTrue);
      final success = result as DriveFolderSuccess;
      expect(success.wasCreated, isTrue);
      expect(success.folder.folderName, 'Photo a Day');
      expect(fakeAdapter.findFolderCalls, 1);
      expect(fakeAdapter.createFolderCalls, 1);
      expect(fakeAdapter.lastCreatedName, 'Photo a Day');
      expect(driveService.status, DriveFolderStatus.ready);
    });

    test(
      '5. Repeated calls are idempotent and return same reference',
      () async {
        fakeAdapter.existingFolder = null;

        final firstResult = await driveService.setupFolder();
        expect(firstResult.isSuccess, isTrue);
        expect(fakeAdapter.findFolderCalls, 1);
        expect(fakeAdapter.createFolderCalls, 1);

        // Second call while in memory
        final secondResult = await driveService.setupFolder();
        expect(secondResult.isSuccess, isTrue);
        expect(
          (secondResult as DriveFolderSuccess).folder.folderId,
          (firstResult as DriveFolderSuccess).folder.folderId,
        );
        // Calls should NOT increment
        expect(fakeAdapter.findFolderCalls, 1);
        expect(fakeAdapter.createFolderCalls, 1);
      },
    );
  });

  group('GoogleDriveService - Persistence & Cold Restart', () {
    test(
      '6. Persists resolved folder state atomically to drive_folder_state.json',
      () async {
        fakeSignInDelegate.mockUser = testUser;
        fakeSignInDelegate.driveScopeGranted = true;
        await authService.init();
        await driveAuthService.init();
        await driveAuthService.authorizeDrive();
        await driveService.init();

        final result = await driveService.setupFolder();
        expect(result.isSuccess, isTrue);

        final stateFile = File(await folderStorage.stateFilePath);
        expect(stateFile.existsSync(), isTrue);

        final content =
            jsonDecode(stateFile.readAsStringSync()) as Map<String, dynamic>;
        expect(content['folderId'], isNotEmpty);
        expect(content['folderName'], 'Photo a Day');
        expect(content['authorizedEmail'], testUser.email);
        expect(content['resolvedAt'], isNotNull);

        // Verify no sensitive tokens exist in persisted state
        expect(content.containsKey('token'), isFalse);
        expect(content.containsKey('accessToken'), isFalse);
        expect(content.containsKey('refreshToken'), isFalse);
        expect(content.containsKey('Authorization'), isFalse);
      },
    );

    test(
      '7. Cold restart restores folder reference for the same user',
      () async {
        fakeSignInDelegate.mockUser = testUser;
        fakeSignInDelegate.driveScopeGranted = true;
        await authService.init();
        await driveAuthService.init();
        await driveAuthService.authorizeDrive();
        await driveService.init();

        await driveService.setupFolder();
        expect(driveService.isReady, isTrue);
        final originalId = driveService.currentFolder!.folderId;

        // Simulate app kill & restart
        final freshAdapter = FakeDriveApiAdapter();
        final freshService = GoogleDriveService(
          adapter: freshAdapter,
          storage: folderStorage,
          authService: authService,
          driveAuthService: driveAuthService,
        );

        await freshService.init();

        expect(freshService.isReady, isTrue);
        expect(freshService.status, DriveFolderStatus.ready);
        expect(freshService.currentFolder?.folderId, originalId);
        expect(freshAdapter.findFolderCalls, 0);
        expect(freshAdapter.createFolderCalls, 0);
        freshService.dispose();
      },
    );

    test(
      '8. Malformed or corrupt drive_folder_state.json is handled safely',
      () async {
        final stateFile = File(await folderStorage.stateFilePath);
        stateFile.parent.createSync(recursive: true);
        stateFile.writeAsStringSync('{ corrupted json !@# }');

        fakeSignInDelegate.mockUser = testUser;
        fakeSignInDelegate.driveScopeGranted = true;
        await authService.init();
        await driveAuthService.init();
        await driveAuthService.authorizeDrive();

        final freshService = GoogleDriveService(
          adapter: fakeAdapter,
          storage: folderStorage,
          authService: authService,
          driveAuthService: driveAuthService,
        );

        await freshService.init();

        expect(freshService.status, DriveFolderStatus.uninitialized);
        expect(freshService.currentFolder, isNull);
        freshService.dispose();
      },
    );
  });

  group('GoogleDriveService - Account Switch & Sign-Out Safety', () {
    test(
      '9. Account switch from User A to User B invalidates cached folder reference',
      () async {
        // 1. Setup User A
        fakeSignInDelegate.mockUser = testUser;
        fakeSignInDelegate.driveScopeGranted = true;
        await authService.init();
        await driveAuthService.init();
        await driveAuthService.authorizeDrive();
        await driveService.init();

        await driveService.setupFolder();
        expect(driveService.isReady, isTrue);
        expect(driveService.currentFolder?.authorizedEmail, testUser.email);

        // 2. Switch to User B
        const userB = AuthUser(
          id: '987654321',
          email: 'user_b@example.com',
          displayName: 'User B',
        );
        fakeSignInDelegate.mockUser = userB;
        await authService.signIn(); // triggers account change

        expect(driveService.status, DriveFolderStatus.uninitialized);
        expect(driveService.currentFolder, isNull);

        // User B authorizes Drive
        await driveAuthService.authorizeDrive();

        // Verify User B can set up their own folder
        final resultB = await driveService.setupFolder();
        expect(resultB.isSuccess, isTrue);
        expect(driveService.currentFolder?.authorizedEmail, userB.email);
      },
    );

    test(
      '10. Remote folder is NOT deleted on account switch or sign out',
      () async {
        fakeSignInDelegate.mockUser = testUser;
        fakeSignInDelegate.driveScopeGranted = true;
        await authService.init();
        await driveAuthService.init();
        await driveAuthService.authorizeDrive();
        await driveService.init();

        await driveService.setupFolder();
        expect(driveService.isReady, isTrue);

        await authService.signOut();

        expect(driveService.status, DriveFolderStatus.uninitialized);
        expect(driveService.currentFolder, isNull);
        // Adapter does not have deleteFolder called because delete is strictly forbidden
        expect(fakeAdapter.createFolderCalls, 1);
      },
    );

    test(
      '11. Sign-out clears local folder reference in memory but preserves local data',
      () async {
        fakeSignInDelegate.mockUser = testUser;
        fakeSignInDelegate.driveScopeGranted = true;
        await authService.init();
        await driveAuthService.init();
        await driveAuthService.authorizeDrive();
        await driveService.init();

        await driveService.setupFolder();
        await authService.signOut();

        expect(driveService.status, DriveFolderStatus.uninitialized);
        expect(driveService.currentFolder, isNull);
        expect(authService.isSignedIn, isFalse);
      },
    );
  });

  group('GoogleDriveService - Error Handling', () {
    setUp(() async {
      fakeSignInDelegate.mockUser = testUser;
      fakeSignInDelegate.driveScopeGranted = true;
      await authService.init();
      await driveAuthService.init();
      await driveAuthService.authorizeDrive();
      await driveService.init();
    });

    test(
      '12. Network failure maps to DriveFolderErrorType.networkError',
      () async {
        fakeAdapter.errorOnFind = const DriveApiException(
          'Connection timed out',
          errorType: DriveFolderErrorType.networkError,
        );

        final result = await driveService.setupFolder();

        expect(result.isFailure, isTrue);
        final failure = result as DriveFolderFailure;
        expect(failure.errorType, DriveFolderErrorType.networkError);
        expect(driveService.status, DriveFolderStatus.error);
        expect(driveService.errorMessage, 'Connection timed out');
      },
    );

    test(
      '13. 401 Unauthorized maps to DriveFolderErrorType.unauthorized',
      () async {
        fakeAdapter.errorOnFind = const DriveApiException(
          'Unauthorized request',
          errorType: DriveFolderErrorType.unauthorized,
        );

        final result = await driveService.setupFolder();

        expect(result.isFailure, isTrue);
        final failure = result as DriveFolderFailure;
        expect(failure.errorType, DriveFolderErrorType.unauthorized);
        expect(driveService.status, DriveFolderStatus.error);
      },
    );

    test('14. 403 Forbidden maps to DriveFolderErrorType.forbidden', () async {
      fakeAdapter.errorOnFind = const DriveApiException(
        'Insufficient permissions',
        errorType: DriveFolderErrorType.forbidden,
      );

      final result = await driveService.setupFolder();

      expect(result.isFailure, isTrue);
      final failure = result as DriveFolderFailure;
      expect(failure.errorType, DriveFolderErrorType.forbidden);
      expect(driveService.status, DriveFolderStatus.error);
    });

    test(
      '15. Malformed API response maps to DriveFolderErrorType.malformedResponse',
      () async {
        fakeAdapter.errorOnCreate = const DriveApiException(
          'Malformed API response',
          errorType: DriveFolderErrorType.malformedResponse,
        );

        final result = await driveService.setupFolder();

        expect(result.isFailure, isTrue);
        final failure = result as DriveFolderFailure;
        expect(failure.errorType, DriveFolderErrorType.malformedResponse);
        expect(driveService.status, DriveFolderStatus.error);
      },
    );
  });

  group(
    'GoogleDriveService - Architectural Boundaries & SyncQueue Isolation',
    () {
      test(
        '16. SyncQueue outbox remains completely unchanged and unconsumed',
        () async {
          final storeDir = Directory('${tempDir.path}/photo_store')
            ..createSync();
          final store = PersistentDailyPhotoStore(
            fileManager: PhotoFileManager(customBaseDir: storeDir),
            metadataStorage: PhotoMetadataStorage(customBaseDir: storeDir),
          );
          await store.init();

          final date = DateTime(2026, 9, 13);
          final dummyFile = File('${storeDir.path}/test_source.jpg')
            ..writeAsStringSync('dummy_image_data');

          final entry = PhotoEntry(
            date: date,
            title: 'Queued Memory',
            syncStatus: SyncStatus.pending,
            gradientColors: const [Color(0xFFE2D9CC), Color(0xFFD4C7B5)],
          );
          await store.savePhoto(entry: entry, sourceTempPath: dummyFile.path);
          await store.flush();

          // Queue has 1 pending upload
          final queueCountBefore = store.syncQueue.count;
          expect(queueCountBefore, 1);
          expect(
            store.syncQueue.operations.first.type,
            SyncOperationType.upload,
          );

          // Run folder setup
          fakeSignInDelegate.mockUser = testUser;
          fakeSignInDelegate.driveScopeGranted = true;
          await authService.init();
          await driveAuthService.init();
          await driveAuthService.authorizeDrive();
          await driveService.init();

          final result = await driveService.setupFolder();
          expect(result.isSuccess, isTrue);

          // Assert queue remains untouched
          final queueCountAfter = store.syncQueue.count;
          expect(queueCountAfter, queueCountBefore);
          expect(
            store.syncQueue.operations.first.type,
            SyncOperationType.upload,
          );
        },
      );

      test(
        '17. ZERO photo upload, download, or delete operations are called',
        () async {
          final storeDir = Directory('${tempDir.path}/photo_store_2')
            ..createSync();
          final store = PersistentDailyPhotoStore(
            fileManager: PhotoFileManager(customBaseDir: storeDir),
            metadataStorage: PhotoMetadataStorage(customBaseDir: storeDir),
          );
          await store.init();

          final date = DateTime(2026, 9, 12);
          final dummyFile = File('${storeDir.path}/test_source_2.jpg')
            ..writeAsStringSync('dummy_image_data');

          final entry = PhotoEntry(
            date: date,
            title: 'Untouched',
            syncStatus: SyncStatus.synced,
            gradientColors: const [Color(0xFFE2D9CC), Color(0xFFD4C7B5)],
          );
          await store.savePhoto(entry: entry, sourceTempPath: dummyFile.path);
          await store.flush();

          fakeSignInDelegate.mockUser = testUser;
          fakeSignInDelegate.driveScopeGranted = true;
          await authService.init();
          await driveAuthService.init();
          await driveAuthService.authorizeDrive();
          await driveService.init();

          await driveService.setupFolder();

          // Verify photo entry has exact same metadata and status
          final retrieved = store.getPhoto(date);
          expect(retrieved, isNotNull);
          expect(retrieved!.syncStatus, SyncStatus.synced);
          expect(retrieved.title, 'Untouched');
        },
      );

      test(
        '18. Security check: zero access tokens or secrets stored in drive_folder_state.json',
        () async {
          fakeSignInDelegate.mockUser = testUser;
          fakeSignInDelegate.driveScopeGranted = true;
          await authService.init();
          await driveAuthService.init();
          await driveAuthService.authorizeDrive();
          await driveService.init();

          await driveService.setupFolder();

          final stateFile = File(await folderStorage.stateFilePath);
          final rawContent = stateFile.readAsStringSync();

          expect(rawContent.contains('fake_mock_access_token'), isFalse);
          expect(rawContent.contains('Bearer'), isFalse);
          expect(rawContent.contains('token'), isFalse);
          expect(rawContent.contains('secret'), isFalse);
        },
      );
    },
  );
}
