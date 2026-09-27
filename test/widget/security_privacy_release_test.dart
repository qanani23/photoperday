import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/auth_user.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/daily_reminder_settings.dart';
import 'package:photo_per_day/data/models/drive_auth_state.dart';
import 'package:photo_per_day/data/models/drive_folder_reference.dart';
import 'package:photo_per_day/data/models/drive_photo_upload_response.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_operation.dart';
import 'package:photo_per_day/data/models/sync_operation_status.dart';
import 'package:photo_per_day/data/models/sync_operation_type.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/models/sync_tombstone.dart';
import 'package:photo_per_day/data/services/diary_export_service.dart';
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
import 'package:photo_per_day/screens/profile/profile_screen.dart';

// ---------------------------------------------------------------------------
// Fakes for Milestone 39 Verification
// ---------------------------------------------------------------------------

class SecurityFakeGoogleSignInDelegate implements GoogleSignInDelegate {
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

class SecurityFakeDriveAuthDelegate implements GoogleDriveAuthDelegate {
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

class SecurityFakeDriveApiAdapter implements DriveApiAdapter {
  DriveFolderReference? existingFolder;
  final List<String> trashedFiles = <String>[];

  @override
  Future<DriveFolderReference?> findFolder({
    required String folderName,
    required Map<String, String> authHeaders,
    String? accountEmail,
  }) async {
    return existingFolder ??
        DriveFolderReference(
          folderId: 'app_folder_123',
          folderName: folderName,
          authorizedEmail: accountEmail,
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
      folderId: 'app_folder_123',
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
      fileId: 'uploaded_${file.path.hashCode}',
      revision: 'rev_1',
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
      revision: 'rev_2',
      filename: filename ?? 'photo.jpg',
      uploadedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> trashPhotoFile({
    required String fileId,
    required Map<String, String> authHeaders,
  }) async {
    trashedFiles.add(fileId);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PersistentDailyPhotoStore store;
  late SyncQueue queue;
  late PhotoFileManager fileManager;
  late PhotoMetadataStorage metadataStorage;
  late SyncQueueStorage queueStorage;
  late SecurityFakeGoogleSignInDelegate signInDelegate;
  late SecurityFakeDriveAuthDelegate driveAuthDelegate;
  late SecurityFakeDriveApiAdapter driveApiAdapter;
  late GoogleDriveService driveService;
  late GoogleDrivePhotoUploadService uploadService;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('m39_security_test_');

    fileManager = PhotoFileManager(customBaseDir: tempDir);
    await fileManager.init();

    metadataStorage = PhotoMetadataStorage(customBaseDir: tempDir);
    queueStorage = SyncQueueStorage(customBaseDir: tempDir);
    queue = SyncQueue(storage: queueStorage);
    await queue.init();

    store = PersistentDailyPhotoStore(
      fileManager: fileManager,
      metadataStorage: metadataStorage,
      syncQueue: queue,
    );
    await store.init();
    PersistentDailyPhotoStore.setTestInstance(store);

    signInDelegate = SecurityFakeGoogleSignInDelegate();
    GoogleAuthService.instance.delegate = signInDelegate;

    driveAuthDelegate = SecurityFakeDriveAuthDelegate();
    GoogleDriveAuthService.instance.delegate = driveAuthDelegate;
    GoogleDriveAuthService.instance.storage = DriveAuthStorage(
      customBaseDir: tempDir.path,
    );

    driveApiAdapter = SecurityFakeDriveApiAdapter();
    final folderStorage = DriveFolderStorage(customBaseDir: tempDir.path);
    driveService = GoogleDriveService(
      adapter: driveApiAdapter,
      storage: folderStorage,
    );
    await driveService.init();
    GoogleDriveService.setTestInstance(driveService);

    uploadService = GoogleDrivePhotoUploadService(
      adapter: driveApiAdapter,
      authService: GoogleAuthService.instance,
      driveAuthService: GoogleDriveAuthService.instance,
      driveService: driveService,
      photoStore: store,
    );
    GoogleDrivePhotoUploadService.setTestInstance(uploadService);
  });

  tearDown(() async {
    PersistentDailyPhotoStore.resetTestInstance();
    GoogleDriveService.resetInstance();
    GoogleDrivePhotoUploadService.resetInstance();

    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('1. Google Authentication & Drive OAuth Scope Security', () {
    test(
      'OAuth scope is strictly restricted to https://www.googleapis.com/auth/drive.file',
      () {
        const expectedScope = 'https://www.googleapis.com/auth/drive.file';
        expect(GoogleAuthService.driveFileScope, equals(expectedScope));

        // Ensure forbidden scopes are not present
        expect(
          GoogleAuthService.driveFileScope,
          isNot(contains('https://www.googleapis.com/auth/drive\n')),
        );
        expect(
          GoogleAuthService.driveFileScope,
          isNot(equals('https://www.googleapis.com/auth/drive')),
        );
        expect(
          GoogleAuthService.driveFileScope,
          isNot(contains('drive.appdata')),
        );
      },
    );
  });

  group('2. Sensitive Data & Token Leakage Protections', () {
    test(
      'PhotoEntry serialization contains zero OAuth tokens or auth headers',
      () {
        final entry = PhotoEntry(
          date: DateTime.utc(2026, 9, 27),
          title: 'Morning Sunshine',
          caption: 'A gentle dawn',
          location: 'Garden Patio',
          gradientColors: const [Colors.amber, Colors.orange],
          imagePath: '/path/to/local/photo.jpg',
          syncStatus: SyncStatus.synced,
          driveFileId: 'drive_file_id_12345',
          driveFileRevision: 'rev_1',
          authorizedEmail: 'user@example.com',
        );

        final jsonMap = entry.toJson();
        final jsonString = jsonEncode(jsonMap);

        expect(jsonString, isNot(contains('accessToken')));
        expect(jsonString, isNot(contains('refreshToken')));
        expect(jsonString, isNot(contains('Bearer ')));
        expect(jsonString, isNot(contains('Authorization')));
        expect(jsonString, isNot(contains('secret')));
      },
    );

    test(
      'SyncOperation serialization contains zero tokens or authorization codes',
      () {
        final op = SyncOperation(
          id: 'op_123',
          type: SyncOperationType.upload,
          dateKey: const DateKey(2026, 9, 27),
          createdAt: DateTime.utc(2026, 9, 27, 10, 0),
          status: SyncOperationStatus.pending,
          driveFileId: 'drive_file_id_abc',
          authorizedEmail: 'user@example.com',
        );

        final jsonMap = op.toJson();
        final jsonString = jsonEncode(jsonMap);

        expect(jsonString, isNot(contains('token')));
        expect(jsonString, isNot(contains('Bearer')));
        expect(jsonString, isNot(contains('secret')));
        expect(jsonString, isNot(contains('authHeaders')));
      },
    );

    test(
      'DriveAuthState and DriveFolderReference serialize only non-sensitive flags',
      () {
        final authState = DriveAuthState(
          hasAuthorizedDrive: true,
          authorizedEmail: 'user@example.com',
          lastAuthorizedAt: DateTime.utc(2026, 9, 27, 8, 0),
        );

        final folderRef = DriveFolderReference(
          folderId: 'folder_xyz_987',
          folderName: 'Photo a Day',
          authorizedEmail: 'user@example.com',
          resolvedAt: DateTime.utc(2026, 9, 27, 8, 5),
        );

        final authJson = jsonEncode(authState.toJson());
        final folderJson = jsonEncode(folderRef.toJson());

        expect(authJson, isNot(contains('token')));
        expect(authJson, isNot(contains('Bearer')));
        expect(folderJson, isNot(contains('token')));
        expect(folderJson, isNot(contains('Bearer')));
        expect(folderJson, isNot(contains('secret')));
      },
    );

    test(
      'DailyReminderSettings contains only schedule flags without tracking data',
      () {
        const settings = DailyReminderSettings(
          enabled: true,
          hour: 20,
          minute: 30,
        );
        final jsonString = jsonEncode(settings.toJson());
        expect(jsonString, equals('{"enabled":true,"hour":20,"minute":30}'));
      },
    );

    test(
      'SyncTombstone serialization contains zero OAuth tokens or secrets',
      () {
        final tombstone = SyncTombstone(
          dateKey: const DateKey(2026, 9, 27),
          driveFileId: 'drive_file_id_deleted_999',
          deletedAt: DateTime.utc(2026, 9, 27, 9, 30),
          authorizedEmail: 'user@example.com',
        );

        final jsonString = jsonEncode(tombstone.toJson());
        expect(jsonString, isNot(contains('token')));
        expect(jsonString, isNot(contains('Bearer')));
        expect(jsonString, isNot(contains('secret')));
        expect(jsonString, isNot(contains('authHeaders')));
      },
    );
  });

  group('3. Account Switch & Ownership Protection in SyncWorker', () {
    test(
      'SyncWorker marks operation failed if queued for Account A but active session is Account B',
      () async {
        signInDelegate.mockUser = const AuthUser(
          id: 'user_b',
          email: 'account_b@example.com',
          displayName: 'User B',
        );
        await GoogleAuthService.instance.signIn();
        await GoogleDriveAuthService.instance.authorizeDrive();
        await driveService.setupFolder();

        // Enqueue an operation tied to Account A
        final opA = await queue.enqueueUpload(
          const DateKey(2026, 9, 25),
          authorizedEmail: 'account_a@example.com',
        );

        final worker = SyncWorker(
          syncQueue: queue,
          photoStore: store,
          authService: GoogleAuthService.instance,
          driveAuthService: GoogleDriveAuthService.instance,
          driveService: driveService,
          uploadService: uploadService,
          driveAdapter: driveApiAdapter,
        );

        final result = await worker.syncNow();
        expect(result.failedCount, equals(1));

        final queuedOp = queue.getOperation(opA.id);
        expect(queuedOp?.status, equals(SyncOperationStatus.failed));
        expect(
          queuedOp?.lastError,
          contains('Operation was queued for account account_a@example.com'),
        );
      },
    );
  });

  group('4. Export Privacy & Safe Content Manifest', () {
    test(
      'DiaryExportService creates a sanitized manifest without internal sync tokens or credentials',
      () async {
        final dummyFile = File('${tempDir.path}/test_source.jpg');
        dummyFile.writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4]));

        final sampleEntry = PhotoEntry(
          date: DateTime(2026, 9, 20),
          title: 'Export Day',
          caption: 'Secret Notes',
          location: 'Secret Location',
          imagePath: dummyFile.path,
          gradientColors: const [Colors.blue, Colors.purple],
        );
        await store.savePhoto(entry: sampleEntry);

        final exportService = DiaryExportService(
          store: store,
          defaultExportDir: tempDir,
        );

        final result = await exportService.exportDiary();
        expect(result.isSuccess, isTrue);
        expect(result.zipFile, isNotNull);

        final bytes = await result.zipFile!.readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);

        final manifestFile = archive.findFile('manifest.json');
        expect(manifestFile, isNotNull);

        final manifestJson = utf8.decode(manifestFile!.content as List<int>);
        final manifestMap = jsonDecode(manifestJson) as Map<String, dynamic>;

        expect(manifestMap['appName'], equals('Photo a Day'));
        expect(manifestMap['totalPhotos'], equals(1));

        // Strict privacy check: Manifest MUST NOT contain tokens, drive IDs, or queue state
        expect(manifestJson, isNot(contains('accessToken')));
        expect(manifestJson, isNot(contains('refreshToken')));
        expect(manifestJson, isNot(contains('Bearer')));
        expect(manifestJson, isNot(contains('driveFileId')));
        expect(manifestJson, isNot(contains('syncQueue')));
      },
    );

    test(
      'Temporary exports are cleanly removed by cleanTemporaryExports',
      () async {
        final exportService = DiaryExportService(
          store: store,
          defaultExportDir: tempDir,
        );

        final dummyExportFile = File(
          '${tempDir.path}/photo_a_day_export_12345678.zip',
        );
        dummyExportFile.writeAsStringSync('zip content');
        expect(dummyExportFile.existsSync(), isTrue);

        final deleted = await exportService.cleanTemporaryExports(
          customExportDir: tempDir,
        );
        expect(deleted, greaterThanOrEqualTo(1));
        expect(dummyExportFile.existsSync(), isFalse);
      },
    );
  });

  group('5. Cloud vs Local Deletion Safety Boundaries', () {
    test(
      'deleteDriveBackup safely moves remote folder to Trash without touching local photos',
      () async {
        final dummyFile = File('${tempDir.path}/local_photo.jpg');
        dummyFile.writeAsBytesSync(Uint8List.fromList([10, 20, 30]));

        final sampleEntry = PhotoEntry(
          date: DateTime(2026, 9, 15),
          title: 'Keep Me Local',
          imagePath: dummyFile.path,
          gradientColors: const [Colors.teal, Colors.cyan],
        );
        await store.savePhoto(entry: sampleEntry);

        expect(store.totalPhotos, equals(1));
        final savedPath = store
            .getPhotoByKey(const DateKey(2026, 9, 15))!
            .imagePath!;
        expect(File(savedPath).existsSync(), isTrue);

        signInDelegate.mockUser = const AuthUser(
          id: 'user_1',
          email: 'user@example.com',
          displayName: 'User',
        );
        await GoogleAuthService.instance.signIn();
        await GoogleDriveAuthService.instance.authorizeDrive();
        await driveService.setupFolder();

        final deleteResult = await driveService.deleteDriveBackup(
          photoStore: store,
        );
        expect(deleteResult is DriveDeleteSuccess, isTrue);

        // Remote folder was moved to Trash
        expect(driveApiAdapter.trashedFiles, contains('app_folder_123'));

        // Local photo and entry MUST remain 100% intact on disk and store
        expect(store.totalPhotos, equals(1));
        expect(File(savedPath).existsSync(), isTrue);
      },
    );
  });

  group('6. Production vs Debug Feature Gating', () {
    testWidgets(
      'ProfileScreen does not expose "Upload Test Photo" in default production mode',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: ProfileScreen(showDeveloperTools: false)),
          ),
        );
        await tester.pump();

        expect(find.text('Upload Test Photo'), findsNothing);
      },
    );
  });

  group('7. Platform Permission Declarations Integrity', () {
    test(
      'Android manifest contains required permissions without unneeded scopes',
      () {
        final manifestFile = File('android/app/src/main/AndroidManifest.xml');
        expect(manifestFile.existsSync(), isTrue);

        final content = manifestFile.readAsStringSync();
        expect(content, contains('android.permission.CAMERA'));
        expect(content, contains('android.permission.INTERNET'));
        expect(content, contains('android.permission.POST_NOTIFICATIONS'));

        // Ensure no location or microphone permissions were added
        expect(
          content,
          isNot(contains('android.permission.ACCESS_FINE_LOCATION')),
        );
        expect(content, isNot(contains('android.permission.RECORD_AUDIO')));
      },
    );

    test(
      'iOS Info.plist has valid structure and required usage descriptions',
      () {
        final plistFile = File('ios/Runner/Info.plist');
        expect(plistFile.existsSync(), isTrue);

        final content = plistFile.readAsStringSync();
        expect(content, contains('NSCameraUsageDescription'));
        expect(content, contains('NSPhotoLibraryUsageDescription'));
        // Verify valid XML structure (closing tags match)
        expect(
          content.contains('<array>') && content.contains('</array>'),
          isTrue,
        );
        expect(content.trim().endsWith('</plist>'), isTrue);
      },
    );
  });
}
