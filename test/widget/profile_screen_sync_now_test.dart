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

class WidgetSyncTestFakeGoogleSignInDelegate implements GoogleSignInDelegate {
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

class WidgetSyncTestFakeDriveAuthDelegate implements GoogleDriveAuthDelegate {
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

class WidgetSyncTestDriveApiAdapter implements DriveApiAdapter {
  DriveFolderReference? existingFolder;
  int uploadCalls = 0;

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
    if (onProgress != null) {
      onProgress(0.5);
      onProgress(1.0);
    }
    return DrivePhotoUploadResponse(
      fileId: 'widget_uploaded_file_id_$uploadCalls',
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

class WidgetSyncTestFakePhotoMetadataStorage extends PhotoMetadataStorage {
  WidgetSyncTestFakePhotoMetadataStorage({super.customBaseDir});

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

class WidgetSyncTestFakePhotoFileManager extends PhotoFileManager {
  WidgetSyncTestFakePhotoFileManager({super.customBaseDir});

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

class WidgetSyncTestFakeSyncQueueStorage extends SyncQueueStorage {
  WidgetSyncTestFakeSyncQueueStorage({super.customBaseDir});

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
  late WidgetSyncTestFakeGoogleSignInDelegate fakeSignInDelegate;
  late WidgetSyncTestFakeDriveAuthDelegate fakeDriveDelegate;
  late WidgetSyncTestDriveApiAdapter fakeApiAdapter;
  late GoogleDriveService driveService;
  late PersistentDailyPhotoStore photoStore;
  late GoogleDrivePhotoUploadService uploadService;
  late SyncWorker syncWorker;

  const testUser = AuthUser(
    id: 'user_widget_sync_1',
    email: 'widget_sync_user@example.com',
    displayName: 'Widget Sync User',
  );

  const testColors = [Color(0xFF333333), Color(0xFF555555)];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('widget_sync_test_');

    fakeSignInDelegate = WidgetSyncTestFakeGoogleSignInDelegate();
    fakeSignInDelegate.mockUser = testUser;
    GoogleAuthService.instance.delegate = fakeSignInDelegate;
    await GoogleAuthService.instance.signIn();

    fakeDriveDelegate = WidgetSyncTestFakeDriveAuthDelegate();
    GoogleDriveAuthService.instance.delegate = fakeDriveDelegate;
    GoogleDriveAuthService.instance.storage = DriveAuthStorage(
      customBaseDir: tempDir.path,
    );
    await GoogleDriveAuthService.instance.authorizeDrive();

    fakeApiAdapter = WidgetSyncTestDriveApiAdapter();
    final folderStorage = DriveFolderStorage(customBaseDir: tempDir.path);
    driveService = GoogleDriveService(
      adapter: fakeApiAdapter,
      storage: folderStorage,
    );
    await driveService.init();
    GoogleDriveService.setTestInstance(driveService);

    final fakeFileManager = WidgetSyncTestFakePhotoFileManager(
      customBaseDir: tempDir,
    );
    final fakeMetadataStorage = WidgetSyncTestFakePhotoMetadataStorage(
      customBaseDir: tempDir,
    );
    final fakeSyncQueueStorage = WidgetSyncTestFakeSyncQueueStorage(
      customBaseDir: tempDir,
    );
    photoStore = PersistentDailyPhotoStore(
      fileManager: fakeFileManager,
      metadataStorage: fakeMetadataStorage,
      syncQueue: SyncQueue(storage: fakeSyncQueueStorage),
    );
    await photoStore.init();
    PersistentDailyPhotoStore.setTestInstance(photoStore);

    uploadService = GoogleDrivePhotoUploadService(
      adapter: fakeApiAdapter,
      authService: GoogleAuthService.instance,
      driveAuthService: GoogleDriveAuthService.instance,
      driveService: GoogleDriveService.instance,
      photoStore: photoStore,
    );
    GoogleDrivePhotoUploadService.setTestInstance(uploadService);

    syncWorker = SyncWorker(
      syncQueue: photoStore.syncQueue,
      photoStore: photoStore,
      authService: GoogleAuthService.instance,
      driveAuthService: GoogleDriveAuthService.instance,
      driveService: GoogleDriveService.instance,
      uploadService: uploadService,
      driveAdapter: fakeApiAdapter,
    );
    SyncWorker.setTestInstance(syncWorker);
  });

  tearDown(() async {
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

  Widget createWidget() {
    return const MaterialApp(home: Scaffold(body: ProfileScreen()));
  }

  Future<void> makeDriveReady() async {
    fakeApiAdapter.existingFolder = DriveFolderReference(
      folderId: 'photo_a_day_drive_folder_id',
      folderName: 'Photo a Day',
      authorizedEmail: testUser.email,
      resolvedAt: DateTime.now().toUtc(),
    );
    await GoogleDriveService.instance.setupFolder();
    expect(GoogleDriveService.instance.isReady, isTrue);
  }

  Future<PhotoEntry> addLocalPhoto({
    required DateKey dateKey,
    String filename = 'test_photo.jpg',
    SyncStatus syncStatus = SyncStatus.pending,
    String? driveFileId,
  }) async {
    final file = File('${tempDir.path}${Platform.pathSeparator}$filename');
    file.writeAsBytesSync([1, 2, 3, 4, 5]);

    final entry = PhotoEntry(
      date: dateKey.toDateTime(),
      title: 'Memory ${dateKey.format()}',
      gradientColors: testColors,
      imagePath: file.path,
      syncStatus: syncStatus,
      driveFileId: driveFileId,
    );

    return await photoStore.savePhoto(entry: entry, sourceTempPath: file.path);
  }

  testWidgets('1. "Manual Cloud Sync" tile renders under Storage & Backup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(createWidget());
    await tester.pumpAndSettle();

    expect(find.text('Manual Cloud Sync'), findsOneWidget);
    expect(find.text('Sync Now'), findsOneWidget);
  });

  testWidgets('2. Shows SnackBar if signed out when Sync Now is tapped', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // Sign out
    fakeSignInDelegate.mockUser = null;
    await GoogleAuthService.instance.signOut();

    await tester.pumpWidget(createWidget());
    await tester.pumpAndSettle();

    final syncNowBtn = find.widgetWithText(OutlinedButton, 'Sync Now');
    await tester.tap(syncNowBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Google account sign-in required to sync.'),
      findsOneWidget,
    );
  });

  testWidgets(
    '3. Shows SnackBar if Drive not authorized when Sync Now is tapped',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await GoogleDriveAuthService.instance.clearAuthorization();

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      final syncNowBtn = find.widgetWithText(OutlinedButton, 'Sync Now');
      await tester.tap(syncNowBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('Google Drive authorization required to sync.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '4. Shows SnackBar if Drive folder is not ready when Sync Now is tapped',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Authorized but folder not ready
      expect(GoogleDriveService.instance.isReady, isFalse);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      final syncNowBtn = find.widgetWithText(OutlinedButton, 'Sync Now');
      await tester.tap(syncNowBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('Google Drive folder setup required to sync.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('5. Shows SnackBar when outbox is empty and Sync Now is tapped', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await makeDriveReady();
    expect(photoStore.syncQueue.isEmpty, isTrue);

    await tester.pumpWidget(createWidget());
    await tester.pumpAndSettle();

    expect(find.text('Outbox is empty • All memories synced'), findsOneWidget);

    final syncNowBtn = find.widgetWithText(OutlinedButton, 'Sync Now');
    await tester.tap(syncNowBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Nothing to sync.'), findsOneWidget);
  });

  testWidgets(
    '6. Executes sync, uploads photo from queue, and displays success SnackBar',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await makeDriveReady();
      const dateKey = DateKey(2026, 8, 1);
      await addLocalPhoto(dateKey: dateKey);
      await photoStore.syncQueue.enqueueUpload(dateKey);

      expect(photoStore.syncQueue.count, 1);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('1 pending memory upload'), findsOneWidget);

      final syncNowBtn = find.widgetWithText(OutlinedButton, 'Sync Now');
      await tester.tap(syncNowBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(fakeApiAdapter.uploadCalls, 1);
      expect(find.text('Synced 1 photo.'), findsOneWidget);

      final photo = photoStore.getPhotoByKey(dateKey);
      expect(photo?.syncStatus, SyncStatus.synced);
      expect(photoStore.syncQueue.isEmpty, isTrue);
    },
  );

  testWidgets(
    '7. Executes sync, updates photo from queue, and displays success SnackBar',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await makeDriveReady();
      const dateKey = DateKey(2026, 8, 2);
      await addLocalPhoto(
        dateKey: dateKey,
        syncStatus: SyncStatus.synced,
        driveFileId: 'drive_file_update_1',
      );
      await photoStore.syncQueue.enqueueUpdate(
        dateKey,
        driveFileId: 'drive_file_update_1',
      );

      expect(photoStore.syncQueue.count, 1);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('1 pending change to sync'), findsOneWidget);

      final syncNowBtn = find.widgetWithText(OutlinedButton, 'Sync Now');
      await tester.tap(syncNowBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Updated 1 photo.'), findsOneWidget);

      final photo = photoStore.getPhotoByKey(dateKey);
      expect(photo?.syncStatus, SyncStatus.synced);
      expect(photoStore.syncQueue.isEmpty, isTrue);
    },
  );

  testWidgets(
    '8. Executes sync, deletes remote photo, and displays success SnackBar',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await makeDriveReady();
      const dateKey = DateKey(2026, 8, 3);
      await addLocalPhoto(
        dateKey: dateKey,
        syncStatus: SyncStatus.synced,
        driveFileId: 'drive_file_del_1',
      );
      await photoStore.removePhotoAsync(dateKey.toDateTime());

      expect(photoStore.syncQueue.count, 1);
      expect(photoStore.pendingDeletions.length, 1);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('1 pending change to sync'), findsOneWidget);

      final syncNowBtn = find.widgetWithText(OutlinedButton, 'Sync Now');
      await tester.tap(syncNowBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Deleted 1 remote photo.'), findsOneWidget);
      expect(photoStore.syncQueue.isEmpty, isTrue);
      expect(photoStore.pendingDeletions.isEmpty, isTrue);
    },
  );
}
