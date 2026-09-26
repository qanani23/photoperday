import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/auth_user.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/drive_folder_reference.dart';
import 'package:photo_per_day/data/models/drive_folder_result.dart';
import 'package:photo_per_day/data/models/drive_photo_upload_response.dart';
import 'package:photo_per_day/data/models/drive_photo_upload_result.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_operation_type.dart';
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

/// Fake implementation of [DriveApiAdapter] for upload testing.
class FakeUploadDriveApiAdapter implements DriveApiAdapter {
  DriveFolderReference? existingFolder;
  DrivePhotoUploadResponse? uploadResponse;
  DriveApiException? errorOnUpload;
  int uploadCalls = 0;
  File? lastUploadedFile;
  String? lastFilename;
  String? lastMimeType;
  String? lastParentFolderId;
  Map<String, String>? lastAuthHeaders;
  Completer<void>? uploadBlocker;
  List<double>? simulatedProgressValues;

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
      folderId: 'created_folder_id',
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
    lastUploadedFile = file;
    lastFilename = filename;
    lastMimeType = mimeType;
    lastParentFolderId = parentFolderId;
    lastAuthHeaders = authHeaders;

    if (uploadBlocker != null) {
      await uploadBlocker!.future;
    }

    if (simulatedProgressValues != null && onProgress != null) {
      for (final p in simulatedProgressValues!) {
        onProgress(p);
      }
    }

    if (errorOnUpload != null) {
      throw errorOnUpload!;
    }

    return uploadResponse ??
        DrivePhotoUploadResponse(
          fileId: 'mock_drive_file_id_$uploadCalls',
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late FakeGoogleSignInDelegate fakeSignInDelegate;
  late GoogleAuthService authService;
  late DriveAuthStorage driveAuthStorage;
  late GoogleDriveAuthService driveAuthService;
  late DriveFolderStorage driveFolderStorage;
  late GoogleDriveService driveService;
  late FakeUploadDriveApiAdapter fakeAdapter;
  late PersistentDailyPhotoStore photoStore;
  late GoogleDrivePhotoUploadService uploadService;

  const testUser = AuthUser(
    id: 'user_123',
    email: 'journaler@example.com',
    displayName: 'Journal User',
  );

  const testColors = [Color(0xFF111111), Color(0xFF222222)];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('drive_upload_test_');

    fakeSignInDelegate = FakeGoogleSignInDelegate();
    authService = GoogleAuthService(delegate: fakeSignInDelegate);

    driveAuthStorage = DriveAuthStorage(customBaseDir: tempDir.path);

    driveAuthService = GoogleDriveAuthService(
      authService: authService,
      storage: driveAuthStorage,
    );
    await driveAuthService.init();

    fakeAdapter = FakeUploadDriveApiAdapter();

    driveFolderStorage = DriveFolderStorage(customBaseDir: tempDir.path);

    driveService = GoogleDriveService(
      adapter: fakeAdapter,
      authService: authService,
      driveAuthService: driveAuthService,
      storage: driveFolderStorage,
    );
    await driveService.init();

    photoStore = PersistentDailyPhotoStore(
      fileManager: PhotoFileManager(customBaseDir: tempDir),
      metadataStorage: PhotoMetadataStorage(customBaseDir: tempDir),
    );
    await photoStore.init(customBaseDir: tempDir);

    uploadService = GoogleDrivePhotoUploadService(
      adapter: fakeAdapter,
      authService: authService,
      driveAuthService: driveAuthService,
      driveService: driveService,
      photoStore: photoStore,
    );
  });

  tearDown(() async {
    photoStore.clear();
    await photoStore.flush();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Helper to configure fully authenticated and ready Google Drive state
  Future<void> setupReadyDriveState() async {
    fakeSignInDelegate.mockUser = testUser;
    fakeSignInDelegate.driveScopeGranted = true;
    fakeSignInDelegate.canAccessScopeResult = true;

    await authService.signIn();
    await driveAuthService.authorizeDrive();

    // Establish existing ready folder
    fakeAdapter.existingFolder = DriveFolderReference(
      folderId: 'photo_a_day_drive_folder_id',
      folderName: 'Photo a Day',
      authorizedEmail: testUser.email,
      resolvedAt: DateTime.now().toUtc(),
    );
    await driveService.setupFolder();
    expect(driveService.isReady, isTrue);
    expect(driveService.currentFolder?.folderId, 'photo_a_day_drive_folder_id');
  }

  /// Helper to create a local photo file and register it in photoStore
  Future<PhotoEntry> createLocalPhoto({
    required DateKey dateKey,
    String filename = 'photo.jpg',
    List<int> bytes = const [1, 2, 3, 4, 5, 6, 7, 8],
    SyncStatus syncStatus = SyncStatus.pending,
    String? driveFileId,
  }) async {
    final photoFile = File('${tempDir.path}${Platform.pathSeparator}$filename');
    await photoFile.writeAsBytes(bytes);

    final entry = PhotoEntry(
      date: dateKey.toDateTime(),
      title: 'Memory for ${dateKey.format()}',
      gradientColors: testColors,
      imagePath: photoFile.path,
      syncStatus: syncStatus,
      driveFileId: driveFileId,
    );

    return await photoStore.savePhoto(
      entry: entry,
      sourceTempPath: photoFile.path,
    );
  }

  group('GoogleDrivePhotoUploadService - Happy Path', () {
    test(
      'uploads exactly ONE photo to ready Google Drive folder and marks it synced',
      () async {
        await setupReadyDriveState();

        const dateKey = DateKey(2026, 3, 15);
        final savedEntry = await createLocalPhoto(
          dateKey: dateKey,
          filename: 'img_march15.jpg',
          bytes: [10, 20, 30, 40, 50],
        );

        expect(savedEntry.syncStatus, SyncStatus.pending);
        expect(
          photoStore.getPhotoByKey(dateKey)?.syncStatus,
          SyncStatus.pending,
        );

        fakeAdapter.uploadResponse = DrivePhotoUploadResponse(
          fileId: 'drive_file_999',
          revision: '1',
          filename: 'photo_2026-03-15.jpg',
          uploadedAt: DateTime.utc(2026, 3, 15, 12, 0, 0),
        );

        final result = await uploadService.uploadPhoto(entry: savedEntry);

        expect(result, isA<DrivePhotoUploadSuccess>());
        final success = result as DrivePhotoUploadSuccess;
        expect(success.fileId, 'drive_file_999');
        expect(success.revision, '1');
        expect(success.remoteFilename, 'photo_2026-03-15.jpg');

        // Check adapter call
        expect(fakeAdapter.uploadCalls, 1);
        expect(fakeAdapter.lastParentFolderId, 'photo_a_day_drive_folder_id');
        expect(fakeAdapter.lastFilename, 'photo_2026-03-15.jpg');
        expect(fakeAdapter.lastMimeType, 'image/jpeg');
        expect(
          fakeAdapter.lastAuthHeaders?['Authorization'],
          contains('Bearer'),
        );

        // Check local store updated to Synced
        final updatedEntry = photoStore.getPhotoByKey(dateKey);
        expect(updatedEntry, isNotNull);
        expect(updatedEntry!.syncStatus, SyncStatus.synced);
        expect(updatedEntry.driveFileId, 'drive_file_999');
        expect(updatedEntry.driveFileRevision, '1');
        expect(updatedEntry.syncError, isNull);

        // Verify local file still exists
        expect(File(updatedEntry.imagePath!).existsSync(), isTrue);
      },
    );

    test(
      'determines correct MIME type and remote filename for PNG images',
      () async {
        await setupReadyDriveState();

        const dateKey = DateKey(2026, 4, 1);
        final savedEntry = await createLocalPhoto(
          dateKey: dateKey,
          filename: 'drawing.png',
          bytes: [0x89, 0x50, 0x4E, 0x47, 1, 2, 3],
        );

        final result = await uploadService.uploadPhoto(entry: savedEntry);

        expect(result, isA<DrivePhotoUploadSuccess>());
        expect(fakeAdapter.lastFilename, 'photo_2026-04-01.png');
        expect(fakeAdapter.lastMimeType, 'image/png');
      },
    );

    test('notifies progress during upload via onProgress callback', () async {
      await setupReadyDriveState();

      const dateKey = DateKey(2026, 5, 20);
      final savedEntry = await createLocalPhoto(dateKey: dateKey);

      fakeAdapter.simulatedProgressValues = [0.25, 0.50, 0.75, 1.0];
      final capturedProgress = <double>[];

      final result = await uploadService.uploadPhoto(
        entry: savedEntry,
        onProgress: (progress) {
          capturedProgress.add(progress);
        },
      );

      expect(result, isA<DrivePhotoUploadSuccess>());
      expect(capturedProgress, [0.25, 0.50, 0.75, 1.0]);
    });
  });

  group('GoogleDrivePhotoUploadService - Preconditions', () {
    test('fails if user is not signed in to Google', () async {
      const dateKey = DateKey(2026, 1, 1);
      final savedEntry = await createLocalPhoto(dateKey: dateKey);

      final result = await uploadService.uploadPhoto(entry: savedEntry);

      expect(result, isA<DrivePhotoUploadFailure>());
      final failure = result as DrivePhotoUploadFailure;
      expect(failure.errorType, DrivePhotoUploadErrorType.notSignedIn);
      expect(fakeAdapter.uploadCalls, 0);
    });

    test('fails if Drive scope is not authorized', () async {
      fakeSignInDelegate.mockUser = testUser;
      fakeSignInDelegate.driveScopeGranted = false;
      await authService.signIn();

      const dateKey = DateKey(2026, 1, 2);
      final savedEntry = await createLocalPhoto(dateKey: dateKey);

      final result = await uploadService.uploadPhoto(entry: savedEntry);

      expect(result, isA<DrivePhotoUploadFailure>());
      final failure = result as DrivePhotoUploadFailure;
      expect(failure.errorType, DrivePhotoUploadErrorType.notAuthorized);
      expect(fakeAdapter.uploadCalls, 0);
    });

    test('fails if Drive folder is not ready', () async {
      fakeSignInDelegate.mockUser = testUser;
      fakeSignInDelegate.driveScopeGranted = true;
      fakeSignInDelegate.canAccessScopeResult = true;
      await authService.signIn();
      await driveAuthService.authorizeDrive();

      const dateKey = DateKey(2026, 1, 3);
      final savedEntry = await createLocalPhoto(dateKey: dateKey);

      final result = await uploadService.uploadPhoto(entry: savedEntry);

      expect(result, isA<DrivePhotoUploadFailure>());
      final failure = result as DrivePhotoUploadFailure;
      expect(failure.errorType, DrivePhotoUploadErrorType.folderNotReady);
      expect(fakeAdapter.uploadCalls, 0);
    });

    test('fails if PhotoEntry has no real image path', () async {
      await setupReadyDriveState();

      final emptyEntry = PhotoEntry(
        date: DateTime.utc(2026, 1, 4),
        title: 'Empty Memory',
        gradientColors: testColors,
        imagePath: null,
      );

      final result = await uploadService.uploadPhoto(entry: emptyEntry);

      expect(result, isA<DrivePhotoUploadFailure>());
      final failure = result as DrivePhotoUploadFailure;
      expect(failure.errorType, DrivePhotoUploadErrorType.invalidMetadata);
      expect(fakeAdapter.uploadCalls, 0);
    });

    test('fails if local image file is missing on disk', () async {
      await setupReadyDriveState();

      final missingEntry = PhotoEntry(
        date: DateTime.utc(2026, 1, 5),
        title: 'Missing File Memory',
        gradientColors: testColors,
        imagePath: '${tempDir.path}${Platform.pathSeparator}non_existent.jpg',
      );

      final result = await uploadService.uploadPhoto(entry: missingEntry);

      expect(result, isA<DrivePhotoUploadFailure>());
      final failure = result as DrivePhotoUploadFailure;
      expect(failure.errorType, DrivePhotoUploadErrorType.fileMissing);
      expect(fakeAdapter.uploadCalls, 0);
    });

    test('fails if local image file is 0 bytes', () async {
      await setupReadyDriveState();

      final emptyFile = File(
        '${tempDir.path}${Platform.pathSeparator}empty.jpg',
      );
      await emptyFile.writeAsBytes([]);

      final emptyEntry = PhotoEntry(
        date: DateTime.utc(2026, 1, 6),
        title: 'Empty Bytes Memory',
        gradientColors: testColors,
        imagePath: emptyFile.path,
      );

      final result = await uploadService.uploadPhoto(entry: emptyEntry);

      expect(result, isA<DrivePhotoUploadFailure>());
      final failure = result as DrivePhotoUploadFailure;
      expect(failure.errorType, DrivePhotoUploadErrorType.fileEmpty);
      expect(fakeAdapter.uploadCalls, 0);
    });
  });

  group(
    'GoogleDrivePhotoUploadService - Duplicate and Concurrency Protections',
    () {
      test(
        'short-circuits when photo is already synced without making API calls',
        () async {
          await setupReadyDriveState();

          const dateKey = DateKey(2026, 6, 1);
          await createLocalPhoto(
            dateKey: dateKey,
            syncStatus: SyncStatus.synced,
            driveFileId: 'existing_drive_id_123',
          );

          await photoStore.updateSyncStatus(
            dateKey: dateKey,
            status: SyncStatus.synced,
            driveFileId: 'existing_drive_id_123',
          );

          final syncedEntry = photoStore.getPhotoByKey(dateKey)!;
          expect(syncedEntry.syncStatus, SyncStatus.synced);
          expect(syncedEntry.driveFileId, 'existing_drive_id_123');

          final result = await uploadService.uploadPhoto(entry: syncedEntry);

          expect(result, isA<DrivePhotoUploadAlreadySynced>());
          final alreadySynced = result as DrivePhotoUploadAlreadySynced;
          expect(alreadySynced.fileId, 'existing_drive_id_123');
          expect(alreadySynced.dateKey, dateKey);
          expect(fakeAdapter.uploadCalls, 0);
        },
      );

      test('blocks concurrent in-flight upload for the same DateKey', () async {
        await setupReadyDriveState();

        const dateKey = DateKey(2026, 7, 1);
        final savedEntry = await createLocalPhoto(dateKey: dateKey);

        fakeAdapter.uploadBlocker = Completer<void>();

        final firstUploadFuture = uploadService.uploadPhoto(entry: savedEntry);

        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(uploadService.isUploading(dateKey), isTrue);
        expect(uploadService.hasActiveUpload, isTrue);

        final secondResult = await uploadService.uploadPhoto(entry: savedEntry);

        expect(secondResult, isA<DrivePhotoUploadFailure>());
        final failure = secondResult as DrivePhotoUploadFailure;
        expect(failure.errorType, DrivePhotoUploadErrorType.alreadyInProgress);

        fakeAdapter.uploadBlocker!.complete();
        final firstResult = await firstUploadFuture;

        expect(firstResult, isA<DrivePhotoUploadSuccess>());
        expect(uploadService.isUploading(dateKey), isFalse);
        expect(uploadService.hasActiveUpload, isFalse);
      });
    },
  );

  group(
    'GoogleDrivePhotoUploadService - Error Handling & Local Preservation',
    () {
      test(
        'marks local photo as failed and preserves local image file on API error',
        () async {
          await setupReadyDriveState();

          const dateKey = DateKey(2026, 8, 10);
          final savedEntry = await createLocalPhoto(
            dateKey: dateKey,
            bytes: [1, 2, 3, 4, 5],
          );

          fakeAdapter.errorOnUpload = const DriveApiException(
            'HTTP 401 Unauthorized: token expired',
            errorType: DriveFolderErrorType.unauthorized,
          );

          final result = await uploadService.uploadPhoto(entry: savedEntry);

          expect(result, isA<DrivePhotoUploadFailure>());
          final failure = result as DrivePhotoUploadFailure;
          expect(failure.errorType, DrivePhotoUploadErrorType.unauthorized);
          expect(failure.message, contains('401 Unauthorized'));

          final updatedEntry = photoStore.getPhotoByKey(dateKey);
          expect(updatedEntry, isNotNull);
          expect(updatedEntry!.syncStatus, SyncStatus.failed);
          expect(
            updatedEntry.syncError,
            'HTTP 401 Unauthorized: token expired',
          );

          // CRITICAL: Local photo file MUST be preserved!
          final localFile = File(updatedEntry.imagePath!);
          expect(localFile.existsSync(), isTrue);
          expect(await localFile.length(), 5);
        },
      );

      test(
        'handles network error cleanly and sets local photo to failed',
        () async {
          await setupReadyDriveState();

          const dateKey = DateKey(2026, 8, 11);
          final savedEntry = await createLocalPhoto(dateKey: dateKey);

          fakeAdapter.errorOnUpload = const DriveApiException(
            'SocketException: Connection refused',
            errorType: DriveFolderErrorType.networkError,
          );

          final result = await uploadService.uploadPhoto(entry: savedEntry);

          expect(result, isA<DrivePhotoUploadFailure>());
          final failure = result as DrivePhotoUploadFailure;
          expect(failure.errorType, DrivePhotoUploadErrorType.networkError);

          final updatedEntry = photoStore.getPhotoByKey(dateKey);
          expect(updatedEntry?.syncStatus, SyncStatus.failed);
          expect(File(updatedEntry!.imagePath!).existsSync(), isTrue);
        },
      );
    },
  );

  group('GoogleDrivePhotoUploadService - Queue Invariance & Security', () {
    test(
      'uploading one photo only satisfies its own outbox queue item without draining unrelated entries',
      () async {
        await setupReadyDriveState();

        const dateKey1 = DateKey(2026, 9, 1);
        const dateKey2 = DateKey(2026, 9, 2);

        final entry1 = await createLocalPhoto(dateKey: dateKey1);
        await createLocalPhoto(dateKey: dateKey2);

        expect(photoStore.syncQueue.operations.length, 2);

        final result = await uploadService.uploadPhoto(entry: entry1);
        expect(result, isA<DrivePhotoUploadSuccess>());

        expect(
          photoStore.getPhotoByKey(dateKey1)?.syncStatus,
          SyncStatus.synced,
        );
        expect(
          photoStore.getPhotoByKey(dateKey2)?.syncStatus,
          SyncStatus.pending,
        );

        // Queue invariance: entry2 upload operation is STILL in the queue!
        final remainingOps = photoStore.syncQueue.operations;
        expect(remainingOps.length, 1);
        expect(remainingOps.first.dateKey, dateKey2);
        expect(remainingOps.first.type, SyncOperationType.upload);
      },
    );

    test(
      'zero OAuth tokens or auth headers are persisted to local storage',
      () async {
        await setupReadyDriveState();

        const dateKey = DateKey(2026, 10, 1);
        final savedEntry = await createLocalPhoto(dateKey: dateKey);

        await uploadService.uploadPhoto(entry: savedEntry);

        final metadataFile = File(
          '${tempDir.path}${Platform.pathSeparator}photos_metadata.json',
        );
        expect(metadataFile.existsSync(), isTrue);

        final rawJson = await metadataFile.readAsString();
        expect(rawJson, isNot(contains('Bearer')));
        expect(rawJson, isNot(contains('fake_mock_access_token')));
        expect(rawJson, isNot(contains('Authorization')));
        expect(rawJson, isNot(contains('client_secret')));
      },
    );
  });
}
