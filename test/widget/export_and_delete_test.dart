import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/auth_user.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/drive_folder_reference.dart';
import 'package:photo_per_day/data/models/drive_photo_upload_response.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_operation.dart';
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

class WidgetTestSignInDelegate implements GoogleSignInDelegate {
  AuthUser? mockUser;
  bool shouldThrow = false;

  @override
  Future<AuthUser?> signInSilently() async => mockUser;

  @override
  Future<AuthUser?> signIn() async {
    if (shouldThrow) throw Exception('sign_in_failed');
    return mockUser;
  }

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
    'Authorization': 'Bearer widget_test_token',
    'X-Goog-AuthUser': '0',
  };
}

class WidgetTestDriveAuthDelegate implements GoogleDriveAuthDelegate {
  bool driveScopeGranted = true;

  @override
  Future<bool> canAccessDriveScope() async => true;

  @override
  Future<bool> requestDriveScope() async => driveScopeGranted;

  @override
  Future<Map<String, String>> getAuthHeaders() async => {
    'Authorization': 'Bearer widget_test_token',
    'X-Goog-AuthUser': '0',
  };
}

class WidgetTestDriveApiAdapter implements DriveApiAdapter {
  DriveFolderReference? existingFolder;
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
    final ref = DriveFolderReference(
      folderId: 'folder_widget_test',
      folderName: folderName,
      authorizedEmail: accountEmail,
      resolvedAt: DateTime.now().toUtc(),
    );
    existingFolder = ref;
    return ref;
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
      fileId: 'cloud_file_1',
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
  }) async {
    trashedFileIds.add(fileId);
  }
}

class WidgetTestPhotoMetadataStorage extends PhotoMetadataStorage {
  WidgetTestPhotoMetadataStorage({super.customBaseDir});

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

class WidgetTestPhotoFileManager extends PhotoFileManager {
  WidgetTestPhotoFileManager({super.customBaseDir});

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

class WidgetTestSyncQueueStorage extends SyncQueueStorage {
  WidgetTestSyncQueueStorage({super.customBaseDir});

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
  late Directory exportDir;
  late WidgetTestSignInDelegate fakeSignIn;
  late WidgetTestDriveAuthDelegate fakeDriveAuth;
  late WidgetTestDriveApiAdapter fakeApiAdapter;
  late DriveFolderStorage folderStorage;
  late DriveAuthStorage driveAuthStorage;
  late GoogleDriveService driveService;
  late PersistentDailyPhotoStore photoStore;
  late GoogleDrivePhotoUploadService uploadService;
  late SyncWorker syncWorker;
  late DiaryExportService exportService;

  const testUser = AuthUser(
    id: 'user_m35_test',
    email: 'm35.user@gmail.com',
    displayName: 'Test User',
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('widget_m35_');
    exportDir = Directory('${tempDir.path}${Platform.pathSeparator}exports');
    await exportDir.create(recursive: true);

    fakeSignIn = WidgetTestSignInDelegate();
    fakeSignIn.mockUser = null;
    GoogleAuthService.instance.delegate = fakeSignIn;
    await GoogleAuthService.instance.signOut();

    driveAuthStorage = DriveAuthStorage(customBaseDir: tempDir.path);
    fakeDriveAuth = WidgetTestDriveAuthDelegate();
    GoogleDriveAuthService.instance.delegate = fakeDriveAuth;
    GoogleDriveAuthService.instance.storage = driveAuthStorage;
    await GoogleDriveAuthService.instance.clearAuthorization();

    fakeApiAdapter = WidgetTestDriveApiAdapter();
    folderStorage = DriveFolderStorage(customBaseDir: tempDir.path);
    driveService = GoogleDriveService(
      adapter: fakeApiAdapter,
      storage: folderStorage,
    );
    await driveService.init();
    GoogleDriveService.setTestInstance(driveService);

    final fileManager = WidgetTestPhotoFileManager(customBaseDir: tempDir);
    final metadataStorage = WidgetTestPhotoMetadataStorage(
      customBaseDir: tempDir,
    );
    final syncQueueStorage = WidgetTestSyncQueueStorage(customBaseDir: tempDir);
    photoStore = PersistentDailyPhotoStore(
      fileManager: fileManager,
      metadataStorage: metadataStorage,
      syncQueue: SyncQueue(storage: syncQueueStorage),
    );
    await photoStore.init();
    PersistentDailyPhotoStore.setTestInstance(photoStore);

    exportService = DiaryExportService(
      store: photoStore,
      defaultExportDir: exportDir,
    );
    DiaryExportService.setTestInstance(exportService);

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
    DiaryExportService.resetTestInstance();
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

  Widget buildTestWidget() {
    return const MaterialApp(
      home: Scaffold(body: ProfileScreen(showDeveloperTools: false)),
    );
  }

  Future<void> addSamplePhoto(DateKey key, {String? driveFileId}) async {
    final photoFile = File(
      '${tempDir.path}${Platform.pathSeparator}photo_${key.year}_${key.month}_${key.day}.jpg',
    );
    photoFile.writeAsBytesSync(List.filled(512, 7));

    await photoStore.savePhoto(
      entry: PhotoEntry(
        date: key.toDateTime(),
        title: 'Memory ${key.format()}',
        caption: 'A wonderful moment',
        location: 'Garden',
        gradientColors: const [Color(0xFF111111), Color(0xFF222222)],
        imagePath: photoFile.path,
        syncStatus: driveFileId != null
            ? SyncStatus.synced
            : SyncStatus.localOnly,
        driveFileId: driveFileId,
        authorizedEmail: driveFileId != null ? testUser.email : null,
      ),
    );
  }

  void setLargeScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  group('Milestone 35 — ProfileScreen Export & Delete UI', () {
    testWidgets(
      'renders Data & Privacy section with all export and delete tiles',
      (tester) async {
        setLargeScreen(tester);
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        final dataPrivacyText = find.text('DATA & PRIVACY');
        expect(dataPrivacyText, findsOneWidget);

        expect(find.text('Export Diary'), findsOneWidget);
        expect(find.text('Delete Local Diary'), findsOneWidget);
        expect(find.text('Delete Google Drive Backup'), findsOneWidget);
        expect(find.text('Delete Local & Cloud Data'), findsOneWidget);
      },
    );

    testWidgets('Export Diary with empty store shows empty notice dialog', (
      tester,
    ) async {
      setLargeScreen(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final exportTile = find.text('Export Diary');
      await tester.ensureVisible(exportTile);
      await tester.tap(exportTile);
      await tester.pumpAndSettle();

      expect(find.text('Export Diary'), findsWidgets);
      expect(
        find.text('Your diary does not contain any photos to export yet.'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await tester.pumpAndSettle();
      expect(
        find.text('Your diary does not contain any photos to export yet.'),
        findsNothing,
      );
    });

    testWidgets(
      'Export Diary with photos prompts confirmation and runs export',
      (tester) async {
        setLargeScreen(tester);
        await addSamplePhoto(const DateKey(2026, 5, 1));
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        final exportTile = find.text('Export Diary');
        await tester.ensureVisible(exportTile);
        await tester.tap(exportTile);
        await tester.pumpAndSettle();

        expect(find.text('Export Your Diary'), findsOneWidget);
        expect(
          find.textContaining('into a standard ZIP archive'),
          findsOneWidget,
        );

        // Tap Export button
        await tester.tap(find.widgetWithText(TextButton, 'Export'));
        await tester.pump();

        // Step pump to advance frames while background export completes
        for (int i = 0; i < 30; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 25));
          });
          await tester.pump(const Duration(milliseconds: 100));
          if (find.text('Export Complete').evaluate().isNotEmpty) {
            break;
          }
        }

        expect(find.text('Export Complete'), findsOneWidget);
        expect(
          find.textContaining('1 photo exported successfully'),
          findsOneWidget,
        );

        // Dismiss dialog
        await tester.tap(find.widgetWithText(TextButton, 'Done'));
        await tester.pumpAndSettle();
        expect(find.text('Export Complete'), findsNothing);
      },
    );

    testWidgets(
      'Delete Local Diary shows confirmation with "Your Google Drive backup will remain."',
      (tester) async {
        setLargeScreen(tester);
        await addSamplePhoto(const DateKey(2026, 5, 2));
        expect(photoStore.totalPhotos, 1);

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        final deleteLocalTile = find.text('Delete Local Diary');
        await tester.ensureVisible(deleteLocalTile);
        await tester.tap(deleteLocalTile);
        await tester.pumpAndSettle();

        // Verify destructive confirmation dialog
        expect(find.text('Delete Local Diary?'), findsOneWidget);
        expect(
          find.textContaining('Your Google Drive backup will remain.'),
          findsOneWidget,
        );

        // Tap Delete Local Diary
        await tester.tap(
          find.widgetWithText(TextButton, 'Delete Local Diary').last,
        );
        await tester.pumpAndSettle();

        // Local diary is now empty
        expect(photoStore.totalPhotos, 0);
        expect(
          find.textContaining('Local diary photos deleted.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('Delete Google Drive Backup requires sign-in check', (
      tester,
    ) async {
      setLargeScreen(tester);
      // User is not signed in
      fakeSignIn.mockUser = null;

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final deleteDriveTile = find.text('Delete Google Drive Backup');
      await tester.ensureVisible(deleteDriveTile);
      await tester.tap(deleteDriveTile);
      await tester.pumpAndSettle();

      expect(find.text('Google Drive Backup'), findsWidgets);
      expect(
        find.textContaining('You must be signed in with your Google account'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('You must be signed in with your Google account'),
        findsNothing,
      );
    });

    testWidgets(
      'Delete Google Drive Backup when signed in asks confirmation and deletes Drive backup',
      (tester) async {
        setLargeScreen(tester);
        fakeSignIn.mockUser = testUser;
        await GoogleAuthService.instance.signIn();
        await GoogleDriveAuthService.instance.authorizeDrive();

        // Create folder and local photo marked synced
        fakeApiAdapter.existingFolder = DriveFolderReference(
          folderId: 'folder_drive_to_trash',
          folderName: 'Photo a Day',
          authorizedEmail: testUser.email,
          resolvedAt: DateTime.now().toUtc(),
        );
        await folderStorage.saveFolderReference(fakeApiAdapter.existingFolder!);

        await addSamplePhoto(
          const DateKey(2026, 5, 3),
          driveFileId: 'drive_photo_1',
        );
        expect(photoStore.totalPhotos, 1);
        expect(
          photoStore.getPhotoByKey(const DateKey(2026, 5, 3))!.driveFileId,
          'drive_photo_1',
        );

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        final deleteDriveTile = find.text('Delete Google Drive Backup');
        await tester.ensureVisible(deleteDriveTile);
        await tester.tap(deleteDriveTile);
        await tester.pumpAndSettle();

        expect(find.text('Delete Google Drive Backup?'), findsOneWidget);
        expect(
          find.textContaining(
            'Your local photos will remain safe on this device.',
          ),
          findsOneWidget,
        );

        // Confirm cloud delete
        await tester.tap(
          find.widgetWithText(TextButton, 'Delete Cloud Backup'),
        );
        await tester.pumpAndSettle();

        // Verify Google Drive folder was trashed
        expect(
          fakeApiAdapter.trashedFileIds,
          contains('folder_drive_to_trash'),
        );

        // Verify local photo remains on device!
        expect(photoStore.totalPhotos, 1);
        final entry = photoStore.getPhotoByKey(const DateKey(2026, 5, 3))!;
        expect(entry.driveFileId, isNull);
        expect(entry.syncStatus, SyncStatus.localOnly);
        expect(File(entry.imagePath!).existsSync(), isTrue);

        expect(
          find.textContaining('Google Drive backup moved to Trash'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Combined deletion requires explicit confirmation and cleans local & cloud',
      (tester) async {
        setLargeScreen(tester);
        fakeSignIn.mockUser = testUser;
        await GoogleAuthService.instance.signIn();
        await GoogleDriveAuthService.instance.authorizeDrive();

        fakeApiAdapter.existingFolder = DriveFolderReference(
          folderId: 'folder_combined_trash',
          folderName: 'Photo a Day',
          authorizedEmail: testUser.email,
          resolvedAt: DateTime.now().toUtc(),
        );
        await folderStorage.saveFolderReference(fakeApiAdapter.existingFolder!);

        await addSamplePhoto(
          const DateKey(2026, 5, 4),
          driveFileId: 'drive_combined_1',
        );
        expect(photoStore.totalPhotos, 1);

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        final deleteCombinedTile = find.text('Delete Local & Cloud Data');
        await tester.ensureVisible(deleteCombinedTile);
        await tester.tap(deleteCombinedTile);
        await tester.pumpAndSettle();

        // Dual-confirmation dialog
        expect(find.text('Delete Local & Cloud Data?'), findsOneWidget);
        expect(
          find.textContaining(
            'Both local memories and cloud backup photos will be removed.',
          ),
          findsOneWidget,
        );

        // Confirm combined delete
        await tester.tap(find.widgetWithText(TextButton, 'Delete Everything'));
        await tester.pumpAndSettle();

        // Both local and cloud are purged
        expect(photoStore.totalPhotos, 0);
        expect(
          fakeApiAdapter.trashedFileIds,
          contains('folder_combined_trash'),
        );
        expect(
          find.text('Local photos and Google Drive backup have been deleted.'),
          findsOneWidget,
        );
      },
    );
  });
}
