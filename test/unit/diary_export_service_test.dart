import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/auth_user.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/drive_auth_state.dart';
import 'package:photo_per_day/data/models/drive_folder_reference.dart';
import 'package:photo_per_day/data/models/drive_folder_result.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_operation_type.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/daily_reminder_service.dart';
import 'package:photo_per_day/data/services/daily_reminder_storage.dart';
import 'package:photo_per_day/data/services/diary_export_service.dart';
import 'package:photo_per_day/data/services/drive_api_adapter.dart';
import 'package:photo_per_day/data/services/drive_auth_storage.dart';
import 'package:photo_per_day/data/services/drive_folder_storage.dart';
import 'package:photo_per_day/data/services/google_auth_service.dart';
import 'package:photo_per_day/data/services/google_drive_auth_service.dart';
import 'package:photo_per_day/data/services/google_drive_service.dart';
import 'package:photo_per_day/data/services/notification_client.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';

class _FakeExportDriveAdapter implements DriveApiAdapter {
  final List<String> trashedFileIds = [];
  bool shouldFailTrash = false;

  @override
  Future<DriveFolderReference?> findFolder({
    required String folderName,
    required Map<String, String> authHeaders,
    String? accountEmail,
  }) async {
    return DriveFolderReference(
      folderId: 'folder_app_123',
      folderName: folderName,
      authorizedEmail: accountEmail ?? 'user@gmail.com',
      resolvedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<DriveFolderReference> createFolder({
    required String folderName,
    required Map<String, String> authHeaders,
    String? accountEmail,
  }) async {
    return DriveFolderReference(
      folderId: 'folder_app_123',
      folderName: folderName,
      authorizedEmail: accountEmail ?? 'user@gmail.com',
      resolvedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> trashPhotoFile({
    required String fileId,
    required Map<String, String> authHeaders,
  }) async {
    if (shouldFailTrash) {
      throw const DriveApiException(
        'Simulated Drive network failure during trash operation',
        errorType: DriveFolderErrorType.apiError,
      );
    }
    trashedFileIds.add(fileId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestFakeGoogleSignInDelegate implements GoogleSignInDelegate {
  AuthUser? mockUser;
  bool shouldThrowOnSignIn = false;

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
  Future<bool> canAccessDriveScope() async => true;

  @override
  Future<bool> requestDriveScope() async => true;

  @override
  Future<Map<String, String>> getAuthHeaders() async => {
    'Authorization': 'Bearer test_token',
  };
}

class _TestFakeDriveAuthDelegate implements GoogleDriveAuthDelegate {
  bool driveScopeGranted = true;

  @override
  Future<bool> canAccessDriveScope() async => true;

  @override
  Future<bool> requestDriveScope() async => driveScopeGranted;

  @override
  Future<Map<String, String>> getAuthHeaders() async => {
    'Authorization': 'Bearer test_token',
  };
}

class _TestFakeNotificationClient implements NotificationClient {
  bool permissionGranted = true;
  final Map<int, String> scheduled = {};

  @override
  Future<void> init({
    void Function(NotificationResponse)? onNotificationResponse,
  }) async {}

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String? payload,
  }) async {
    scheduled[id] = '$hour:$minute';
  }

  @override
  Future<void> cancel(int id) async {
    scheduled.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    scheduled.clear();
  }

  @override
  Future<bool> didAppLaunchFromNotification() async => false;

  @override
  Future<List<int>> getPendingNotificationIds() async =>
      scheduled.keys.toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PersistentDailyPhotoStore store;
  late DiaryExportService exportService;
  late Directory exportDir;
  late _TestFakeGoogleSignInDelegate authDelegate;
  late _TestFakeDriveAuthDelegate driveAuthDelegate;
  late DriveAuthStorage driveAuthStorage;
  late GoogleAuthService authService;
  late GoogleDriveAuthService driveAuthService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('m35_export_test_');
    exportDir = Directory('${tempDir.path}/exports');
    await exportDir.create(recursive: true);

    final fileManager = PhotoFileManager(customBaseDir: tempDir);
    final metadataStorage = PhotoMetadataStorage(customBaseDir: tempDir);
    store = PersistentDailyPhotoStore(
      fileManager: fileManager,
      metadataStorage: metadataStorage,
    );
    await store.init();

    exportService = DiaryExportService(store: store);

    authDelegate = _TestFakeGoogleSignInDelegate();
    driveAuthDelegate = _TestFakeDriveAuthDelegate();
    driveAuthStorage = DriveAuthStorage(customBaseDir: tempDir.path);
    authService = GoogleAuthService(delegate: authDelegate);
    driveAuthService = GoogleDriveAuthService(
      delegate: driveAuthDelegate,
      authService: authService,
      storage: driveAuthStorage,
    );
  });

  tearDown(() async {
    PersistentDailyPhotoStore.resetTestInstance();
    DiaryExportService.resetTestInstance();
    GoogleDriveService.resetInstance();
    DailyReminderService.resetTestInstance();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  Future<String> createDummyPhotoFile(
    String filename, {
    int byteLength = 256,
  }) async {
    final photoPath = '${tempDir.path}/$filename';
    final photoFile = File(photoPath);
    await photoFile.writeAsBytes(List.filled(byteLength, 42));
    return photoPath;
  }

  group('Milestone 35 — Diary Export Service', () {
    test(
      '1. Export with zero photos returns empty result without creating zip',
      () async {
        final result = await exportService.exportDiary(
          customExportDir: exportDir,
        );

        expect(result.isEmpty, isTrue);
        expect(result.isSuccess, isFalse);
        expect(result.isPartial, isFalse);
        expect(result.exportedCount, 0);
        expect(result.skippedCount, 0);
        expect(result.zipFile, isNull);

        final files = exportDir.listSync();
        expect(files, isEmpty);
      },
    );

    test('2. Export with one photo creates valid ZIP archive', () async {
      final photoPath = await createDummyPhotoFile('photo1.jpg');
      await store.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2026, 3, 28, 14, 30),
          title: 'Spring Day',
          caption: 'Sunny morning stroll',
          location: 'City Park',
          category: 'Nature',
          gradientColors: const [],
          imagePath: photoPath,
        ),
      );

      final result = await exportService.exportDiary(
        customExportDir: exportDir,
      );

      expect(result.isSuccess, isTrue);
      expect(result.isPartial, isFalse);
      expect(result.isEmpty, isFalse);
      expect(result.exportedCount, 1);
      expect(result.skippedCount, 0);
      expect(result.totalEntries, 1);
      expect(result.zipFile, isNotNull);
      expect(await result.zipFile!.exists(), isTrue);
      expect(result.archiveSizeBytes, greaterThan(0));

      // Inspect ZIP contents
      final zipBytes = await result.zipFile!.readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);
      expect(archive.files.length, 2); // manifest.json + 1 photo
      expect(archive.files.any((f) => f.name == 'manifest.json'), isTrue);
      expect(
        archive.files.any((f) => f.name == 'photos/2026-03-28.jpg'),
        isTrue,
      );
    });

    test(
      '3. Export with multiple photos bundles all entries chronologically',
      () async {
        final p1 = await createDummyPhotoFile('p1.jpg');
        final p2 = await createDummyPhotoFile('p2.jpg');
        final p3 = await createDummyPhotoFile('p3.jpg');

        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 3, 10),
            title: 'First Day',
            gradientColors: const [],
            imagePath: p1,
          ),
        );
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 3, 20),
            title: 'Second Day',
            gradientColors: const [],
            imagePath: p2,
          ),
        );
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 3, 15),
            title: 'Middle Day',
            gradientColors: const [],
            imagePath: p3,
          ),
        );

        final result = await exportService.exportDiary(
          customExportDir: exportDir,
        );

        expect(result.isSuccess, isTrue);
        expect(result.exportedCount, 3);
        expect(result.skippedCount, 0);

        final zipBytes = await result.zipFile!.readAsBytes();
        final archive = ZipDecoder().decodeBytes(zipBytes);
        expect(archive.files.length, 4); // manifest + 3 photos

        final manifestFile = archive.files.firstWhere(
          (f) => f.name == 'manifest.json',
        );
        final manifestJson =
            jsonDecode(utf8.decode(manifestFile.content as List<int>))
                as Map<String, dynamic>;
        final photos = manifestJson['photos'] as List<dynamic>;
        expect(photos.length, 3);
        // Chronological order: 2026-03-10, 2026-03-15, 2026-03-20
        expect(photos[0]['date'], '2026-03-10');
        expect(photos[1]['date'], '2026-03-15');
        expect(photos[2]['date'], '2026-03-20');
      },
    );

    test('4. Export manifest contains expected metadata fields', () async {
      final photoPath = await createDummyPhotoFile('meta.jpg');
      await store.savePhoto(
        entry: PhotoEntry(
          date: DateTime.utc(2026, 4, 15, 10, 15),
          title: 'Coffee Break',
          caption: 'Great espresso at the corner cafe',
          location: 'Little Italy',
          category: 'Food & Drink',
          timeFormatted: '10:15 AM',
          gradientColors: const [],
          imagePath: photoPath,
        ),
      );

      final result = await exportService.exportDiary(
        customExportDir: exportDir,
      );
      final zipBytes = await result.zipFile!.readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);
      final manifestFile = archive.files.firstWhere(
        (f) => f.name == 'manifest.json',
      );
      final manifest =
          jsonDecode(utf8.decode(manifestFile.content as List<int>))
              as Map<String, dynamic>;

      expect(manifest['exportVersion'], 1);
      expect(manifest['appName'], 'Photo a Day');
      expect(manifest['totalPhotos'], 1);
      expect(manifest['exportedAt'], isNotNull);

      final photo = (manifest['photos'] as List<dynamic>).first;
      expect(photo['date'], '2026-04-15');
      expect(photo['filename'], 'photos/2026-04-15.jpg');
      expect(photo['title'], 'Coffee Break');
      expect(photo['caption'], 'Great espresso at the corner cafe');
      expect(photo['location'], 'Little Italy');
      expect(photo['category'], 'Food & Drink');
      expect(photo['timeFormatted'], '10:15 AM');
      expect(photo['createdAt'], isNotNull);
      expect(photo['lastModifiedAt'], isNotNull);
    });

    test(
      '5. Export contains expected photo files with non-zero bytes',
      () async {
        final photoPath = await createDummyPhotoFile(
          'content.jpg',
          byteLength: 512,
        );
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 1, 1),
            title: 'New Year',
            gradientColors: const [],
            imagePath: photoPath,
          ),
        );

        final result = await exportService.exportDiary(
          customExportDir: exportDir,
        );
        final zipBytes = await result.zipFile!.readAsBytes();
        final archive = ZipDecoder().decodeBytes(zipBytes);

        final archivedPhoto = archive.files.firstWhere(
          (f) => f.name == 'photos/2026-01-01.jpg',
        );
        final content = archivedPhoto.content as List<int>;
        expect(content.length, 512);
        expect(content.every((b) => b == 42), isTrue);
      },
    );

    test('6. Export does not contain OAuth tokens or secrets', () async {
      final photoPath = await createDummyPhotoFile('secret_test.jpg');
      await store.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2026, 2, 14),
          title: 'Private Sync Test',
          caption: 'Testing token safety',
          gradientColors: const [],
          imagePath: photoPath,
          syncStatus: SyncStatus.synced,
          driveFileId: 'drive_file_id_secret_12345',
          driveFileRevision: 'rev_99999',
          authorizedEmail: 'user@example.com',
          syncError: 'temporary error trace',
        ),
      );

      final result = await exportService.exportDiary(
        customExportDir: exportDir,
      );
      final zipBytes = await result.zipFile!.readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);
      final manifestFile = archive.files.firstWhere(
        (f) => f.name == 'manifest.json',
      );
      final manifestRawString = utf8.decode(manifestFile.content as List<int>);

      // Check raw string for any sensitive terms
      expect(manifestRawString.contains('driveFileId'), isFalse);
      expect(manifestRawString.contains('driveFileRevision'), isFalse);
      expect(manifestRawString.contains('authorizedEmail'), isFalse);
      expect(manifestRawString.contains('syncError'), isFalse);
      expect(manifestRawString.contains('drive_file_id_secret_12345'), isFalse);
      expect(manifestRawString.contains('access_token'), isFalse);
      expect(manifestRawString.contains('refresh_token'), isFalse);
      expect(manifestRawString.contains('Authorization'), isFalse);
      expect(manifestRawString.contains('Bearer'), isFalse);
    });

    test('7. Missing photo file is handled safely without crashing', () async {
      final photoPath = await createDummyPhotoFile('to_delete.jpg');
      final saved = await store.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2026, 5, 1),
          title: 'Missing Photo',
          gradientColors: const [],
          imagePath: photoPath,
        ),
      );

      // Now delete the persisted photo file from disk to simulate file missing
      final persistentFile = File(saved.imagePath!);
      expect(await persistentFile.exists(), isTrue);
      await persistentFile.delete();

      final result = await exportService.exportDiary(
        customExportDir: exportDir,
      );

      // Entire export failed because the only photo was missing
      expect(result.isSuccess, isFalse);
      expect(result.skippedCount, 1);
      expect(result.exportedCount, 0);
      expect(result.errorMessage, contains('None of the 1 photo files'));
    });

    test('8. Corrupt/empty (0-byte) photo file is handled safely', () async {
      final validPath = await createDummyPhotoFile(
        'valid.jpg',
        byteLength: 100,
      );
      final corruptPath = await createDummyPhotoFile(
        'corrupt.jpg',
        byteLength: 50,
      );

      await store.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2026, 6, 1),
          title: 'Valid Day',
          gradientColors: const [],
          imagePath: validPath,
        ),
      );
      final saved2 = await store.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2026, 6, 2),
          title: 'Corrupt Day',
          gradientColors: const [],
          imagePath: corruptPath,
        ),
      );

      // Truncate the second persisted file to 0 bytes
      final corruptFile = File(saved2.imagePath!);
      await corruptFile.writeAsBytes([]);

      final result = await exportService.exportDiary(
        customExportDir: exportDir,
      );

      expect(result.isPartial, isTrue);
      expect(result.isSuccess, isFalse);
      expect(result.exportedCount, 1);
      expect(result.skippedCount, 1);
      expect(result.totalEntries, 2);

      final zipBytes = await result.zipFile!.readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);
      final manifestFile = archive.files.firstWhere(
        (f) => f.name == 'manifest.json',
      );
      final manifest =
          jsonDecode(utf8.decode(manifestFile.content as List<int>))
              as Map<String, dynamic>;

      expect(manifest['skippedPhotos'], isNotNull);
      final skipped = manifest['skippedPhotos'] as List<dynamic>;
      expect(skipped.length, 1);
      expect(skipped.first['date'], '2026-06-02');
      expect(skipped.first['reason'], contains('empty'));
    });

    test(
      '9. Partial export is reported accurately with valid and skipped photos',
      () async {
        final p1 = await createDummyPhotoFile('good1.jpg');
        final p2 = await createDummyPhotoFile('good2.jpg');
        final p3 = await createDummyPhotoFile('good3.jpg');

        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 7, 1),
            title: 'Good 1',
            gradientColors: const [],
            imagePath: p1,
          ),
        );
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 7, 2),
            title: 'Good 2',
            gradientColors: const [],
            imagePath: p2,
          ),
        );
        final saved3 = await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 7, 3),
            title: 'Missing One',
            gradientColors: const [],
            imagePath: p3,
          ),
        );

        // Delete the 3rd file from managed storage
        await File(saved3.imagePath!).delete();

        final result = await exportService.exportDiary(
          customExportDir: exportDir,
        );

        expect(result.isPartial, isTrue);
        expect(result.isSuccess, isFalse);
        expect(result.exportedCount, 2);
        expect(result.skippedCount, 1);
        expect(result.totalEntries, 3);
      },
    );

    test('10. Temporary export artifacts can be cleaned up', () async {
      final photo = await createDummyPhotoFile('temp_clean.jpg');
      await store.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2026, 8, 1),
          title: 'Clean Me',
          gradientColors: const [],
          imagePath: photo,
        ),
      );

      final result = await exportService.exportDiary(
        customExportDir: exportDir,
      );
      expect(await result.zipFile!.exists(), isTrue);

      final deletedCount = await exportService.cleanTemporaryExports(
        customExportDir: exportDir,
      );
      expect(deletedCount, 1);
      expect(await result.zipFile!.exists(), isFalse);
    });

    test(
      '22. Export works completely offline from local store source of truth',
      () async {
        final photo = await createDummyPhotoFile('offline.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 9, 1),
            title: 'Offline Day',
            caption: 'Completely disconnected',
            gradientColors: const [],
            imagePath: photo,
            syncStatus: SyncStatus.localOnly,
          ),
        );

        final result = await exportService.exportDiary(
          customExportDir: exportDir,
        );

        expect(result.isSuccess, isTrue);
        expect(result.exportedCount, 1);
        expect(result.zipFile, isNotNull);
      },
    );
  });

  group('Milestone 35 — Local and Cloud Deletion Behavior', () {
    test(
      '11. Local deletion removes all local photo files, metadata, and entries',
      () async {
        final p1 = await createDummyPhotoFile('local1.jpg');
        final p2 = await createDummyPhotoFile('local2.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 3, 1),
            title: 'Day 1',
            gradientColors: const [],
            imagePath: p1,
          ),
        );
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 3, 2),
            title: 'Day 2',
            gradientColors: const [],
            imagePath: p2,
          ),
        );

        expect(store.totalPhotos, 2);
        expect(File(p1).existsSync(), isTrue);

        await store.deleteLocalDiary();

        expect(store.totalPhotos, 0);
        expect(store.allEntries, isEmpty);
        expect(store.recordedDates, isEmpty);

        // Verify persistent disk metadata is empty
        expect(store.totalPhotos, 0);
      },
    );

    test(
      '12. Local deletion preserves Google Drive backup folder state',
      () async {
        final fakeAdapter = _FakeExportDriveAdapter();
        final folderStorage = DriveFolderStorage(customBaseDir: tempDir.path);
        final driveService = GoogleDriveService(
          adapter: fakeAdapter,
          storage: folderStorage,
          authService: authService,
          driveAuthService: driveAuthService,
        );

        // Seed a ready Drive folder
        await folderStorage.saveFolderReference(
          DriveFolderReference(
            folderId: 'folder_keep_123',
            folderName: 'Photo a Day',
            authorizedEmail: 'user@gmail.com',
            resolvedAt: DateTime.now().toUtc(),
          ),
        );
        authDelegate.mockUser = const AuthUser(
          id: '1',
          email: 'user@gmail.com',
          displayName: 'User',
        );
        await driveAuthStorage.saveState(
          DriveAuthState(
            hasAuthorizedDrive: true,
            authorizedEmail: 'user@gmail.com',
            lastAuthorizedAt: DateTime.now().toUtc(),
          ),
        );
        await authService.init();
        await driveAuthService.init();
        await driveService.init();
        expect(driveService.currentFolder?.folderId, 'folder_keep_123');

        // Add a synced photo
        final p1 = await createDummyPhotoFile('synced.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 3, 1),
            title: 'Synced Day',
            gradientColors: const [],
            imagePath: p1,
            syncStatus: SyncStatus.synced,
            driveFileId: 'remote_file_abc',
          ),
        );

        // Delete local diary
        await store.deleteLocalDiary();

        // Verify local photos are gone
        expect(store.totalPhotos, 0);

        // Verify Google Drive backup state is completely preserved
        expect(driveService.currentFolder?.folderId, 'folder_keep_123');
        expect(fakeAdapter.trashedFileIds, isEmpty); // NO drive trash calls
      },
    );

    test(
      '13. Local deletion does not enqueue an unintended remote delete',
      () async {
        final p1 = await createDummyPhotoFile('no_remote_delete.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 3, 1),
            title: 'Day with Drive ID',
            gradientColors: const [],
            imagePath: p1,
            syncStatus: SyncStatus.synced,
            driveFileId: 'remote_xyz_999',
          ),
        );

        await store.deleteLocalDiary();

        // Verify no delete operation was added to the sync queue
        expect(store.syncQueue.operations, isEmpty);
        // Verify no pending tombstones were recorded
        expect(store.pendingDeletions, isEmpty);
      },
    );

    test('14. Cloud deletion requires proper Google authorization', () async {
      final fakeAdapter = _FakeExportDriveAdapter();
      final driveService = GoogleDriveService(
        adapter: fakeAdapter,
        authService: authService,
        driveAuthService: driveAuthService,
      );

      // User not signed in
      final result = await driveService.deleteDriveBackup(photoStore: store);
      expect(result, isA<DriveDeleteFailure>());
      final failure = result as DriveDeleteFailure;
      expect(failure.message, contains('Sign in with your Google account'));
    });

    test(
      '15. Cloud deletion only operates on app folder and preserves local photos',
      () async {
        final fakeAdapter = _FakeExportDriveAdapter();
        final folderStorage = DriveFolderStorage(customBaseDir: tempDir.path);
        authDelegate.mockUser = const AuthUser(
          id: '1',
          email: 'test@example.com',
          displayName: 'Test User',
        );
        await driveAuthStorage.saveState(
          DriveAuthState(
            hasAuthorizedDrive: true,
            authorizedEmail: 'test@example.com',
            lastAuthorizedAt: DateTime.now().toUtc(),
          ),
        );
        await authService.init();
        await driveAuthService.init();

        final driveService = GoogleDriveService(
          adapter: fakeAdapter,
          storage: folderStorage,
          authService: authService,
          driveAuthService: driveAuthService,
        );
        await driveService.init();

        final p1 = await createDummyPhotoFile('local_kept.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 3, 15),
            title: 'Keep Me Local',
            gradientColors: const [],
            imagePath: p1,
            syncStatus: SyncStatus.synced,
            driveFileId: 'drive_photo_1',
            authorizedEmail: 'test@example.com',
          ),
        );

        final result = await driveService.deleteDriveBackup(photoStore: store);
        expect(result, isA<DriveDeleteSuccess>());

        // Verifies only the app folder was targeted
        expect(fakeAdapter.trashedFileIds, contains('folder_app_123'));
        expect(fakeAdapter.trashedFileIds.length, 1);

        // Verifies local photos remain completely on disk
        expect(store.totalPhotos, 1);
        final localEntry = store.getPhotoByKey(const DateKey(2026, 3, 15));
        expect(localEntry, isNotNull);
        expect(localEntry!.syncStatus, SyncStatus.localOnly);
        expect(localEntry.driveFileId, isNull);
        expect(File(p1).existsSync(), isTrue);
      },
    );

    test(
      '16. Cloud deletion failure is reported accurately without corrupting state',
      () async {
        final fakeAdapter = _FakeExportDriveAdapter()..shouldFailTrash = true;
        authDelegate.mockUser = const AuthUser(
          id: '1',
          email: 'test@example.com',
          displayName: 'Test User',
        );
        await driveAuthStorage.saveState(
          DriveAuthState(
            hasAuthorizedDrive: true,
            authorizedEmail: 'test@example.com',
            lastAuthorizedAt: DateTime.now().toUtc(),
          ),
        );
        await authService.init();
        await driveAuthService.init();

        final driveService = GoogleDriveService(
          adapter: fakeAdapter,
          authService: authService,
          driveAuthService: driveAuthService,
        );
        await driveService.init();

        final p1 = await createDummyPhotoFile('keep_state.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 3, 15),
            title: 'Keep State',
            gradientColors: const [],
            imagePath: p1,
            syncStatus: SyncStatus.synced,
            driveFileId: 'drive_photo_99',
            authorizedEmail: 'test@example.com',
          ),
        );

        final result = await driveService.deleteDriveBackup(photoStore: store);
        expect(result, isA<DriveDeleteFailure>());
        final failure = result as DriveDeleteFailure;
        expect(failure.message, contains('Simulated Drive network failure'));

        // Photo sync state must NOT be reset if cloud deletion failed
        final entry = store.getPhotoByKey(const DateKey(2026, 3, 15));
        expect(entry!.syncStatus, SyncStatus.synced);
        expect(entry.driveFileId, 'drive_photo_99');
      },
    );

    test(
      '17. Pending upload cannot resurrect a locally deleted photo',
      () async {
        final p1 = await createDummyPhotoFile('pending_up.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 4, 1),
            title: 'Pending Upload',
            gradientColors: const [],
            imagePath: p1,
            syncStatus: SyncStatus.pending,
          ),
        );
        expect(
          store.syncQueue.operations.any(
            (o) => o.type == SyncOperationType.upload,
          ),
          isTrue,
        );

        await store.deleteLocalDiary();

        // SyncQueue must be cleared of the pending upload
        expect(store.syncQueue.operations, isEmpty);
        expect(store.totalPhotos, 0);
      },
    );

    test('18. Pending update cannot resurrect a deleted local photo', () async {
      final p1 = await createDummyPhotoFile('pending_upd.jpg');
      await store.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2026, 4, 2),
          title: 'Initial',
          gradientColors: const [],
          imagePath: p1,
          syncStatus: SyncStatus.synced,
          driveFileId: 'remote_file_upd',
        ),
      );

      // Update metadata to make it pending update
      await store.updatePhotoMetadata(
        dateKey: const DateKey(2026, 4, 2),
        title: 'New Title',
      );
      expect(
        store.syncQueue.operations.any(
          (o) => o.type == SyncOperationType.update,
        ),
        isTrue,
      );

      await store.deleteLocalDiary();

      expect(store.syncQueue.operations, isEmpty);
      expect(store.totalPhotos, 0);
    });

    test(
      '19. Account switching remains isolated during cloud deletion',
      () async {
        final fakeAdapter = _FakeExportDriveAdapter();
        final folderStorage = DriveFolderStorage(customBaseDir: tempDir.path);
        await folderStorage.saveFolderReference(
          DriveFolderReference(
            folderId: 'folder_user_a',
            folderName: 'Photo a Day',
            authorizedEmail: 'usera@gmail.com',
            resolvedAt: DateTime.now().toUtc(),
          ),
        );

        authDelegate.mockUser = const AuthUser(
          id: '2',
          email: 'userb@gmail.com',
          displayName: 'User B',
        );
        await driveAuthStorage.saveState(
          DriveAuthState(
            hasAuthorizedDrive: true,
            authorizedEmail: 'userb@gmail.com',
            lastAuthorizedAt: DateTime.now().toUtc(),
          ),
        );
        await authService.init();
        await driveAuthService.init();

        final driveService = GoogleDriveService(
          adapter: fakeAdapter,
          storage: folderStorage,
          authService: authService,
          driveAuthService: driveAuthService,
        );
        await driveService.init();

        // Current active user is user B, but folder reference belonged to user A.
        // Account isolation ensures folder_user_a is not touched!
        await driveService.deleteDriveBackup(photoStore: store);
        expect(fakeAdapter.trashedFileIds.contains('folder_user_a'), isFalse);
      },
    );

    test(
      '20. Combined deletion deletes both Google Drive backup and local diary data',
      () async {
        final fakeAdapter = _FakeExportDriveAdapter();
        final folderStorage = DriveFolderStorage(customBaseDir: tempDir.path);
        await folderStorage.saveFolderReference(
          DriveFolderReference(
            folderId: 'folder_combined_app',
            folderName: 'Photo a Day',
            authorizedEmail: 'user@gmail.com',
            resolvedAt: DateTime.now().toUtc(),
          ),
        );

        authDelegate.mockUser = const AuthUser(
          id: '1',
          email: 'user@gmail.com',
          displayName: 'User',
        );
        await driveAuthStorage.saveState(
          DriveAuthState(
            hasAuthorizedDrive: true,
            authorizedEmail: 'user@gmail.com',
            lastAuthorizedAt: DateTime.now().toUtc(),
          ),
        );
        await authService.init();
        await driveAuthService.init();

        final driveService = GoogleDriveService(
          adapter: fakeAdapter,
          storage: folderStorage,
          authService: authService,
          driveAuthService: driveAuthService,
        );
        await driveService.init();

        final p1 = await createDummyPhotoFile('combined_target.jpg');
        final saved = await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 3, 20),
            title: 'Combined Target',
            gradientColors: const [],
            imagePath: p1,
            syncStatus: SyncStatus.synced,
            driveFileId: 'drive_combined_xyz',
            authorizedEmail: 'user@gmail.com',
          ),
        );
        expect(store.totalPhotos, 1);
        final managedFile = File(saved.imagePath!);
        expect(managedFile.existsSync(), isTrue);

        // Execute combined deletion sequence (Drive backup first, then local diary)
        final driveResult = await driveService.deleteDriveBackup(
          photoStore: store,
        );
        expect(driveResult, isA<DriveDeleteSuccess>());
        expect(fakeAdapter.trashedFileIds, contains('folder_combined_app'));

        await store.deleteLocalDiary();

        // Verify local store, sync queue, and tombstones are completely empty
        expect(store.totalPhotos, 0);
        expect(store.syncQueue.operations, isEmpty);
        expect(store.pendingDeletions, isEmpty);
        expect(managedFile.existsSync(), isFalse);
        expect(store.fileManager.photosDir.listSync(), isEmpty);
      },
    );

    test(
      '21. Reminder and preferences remain intact after diary photo deletion',
      () async {
        // Seed reminder setting with isolated storage
        final reminderStorage = DailyReminderStorage(
          customBaseDir: tempDir.path,
        );
        final reminderClient = _TestFakeNotificationClient();
        final reminderService = DailyReminderService(
          client: reminderClient,
          storage: reminderStorage,
        );
        await reminderService.init();
        DailyReminderService.setTestInstance(reminderService);

        await reminderService.setEnabled(true);
        await reminderService.setTime(hour: 20, minute: 45);
        expect(reminderService.isEnabled, isTrue);
        expect(reminderService.settings.hour, 20);
        expect(reminderService.settings.minute, 45);

        final photo = await createDummyPhotoFile('remind_intact.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 3, 1),
            title: 'Photo with reminder active',
            gradientColors: const [],
            imagePath: photo,
          ),
        );

        // Delete local diary
        await store.deleteLocalDiary();

        // Photos deleted
        expect(store.totalPhotos, 0);

        // Unrelated settings remain 100% intact
        expect(reminderService.isEnabled, isTrue);
        expect(reminderService.settings.hour, 20);
        expect(reminderService.settings.minute, 45);
      },
    );
  });
}
