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
import 'package:photo_per_day/screens/profile/profile_screen.dart';

class WidgetTestFakeGoogleSignInDelegate implements GoogleSignInDelegate {
  AuthUser? mockUser;

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
    'Authorization': 'Bearer fake_token',
    'X-Goog-AuthUser': '0',
  };
}

class WidgetTestFakeDriveAuthDelegate implements GoogleDriveAuthDelegate {
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

class WidgetTestUploadDriveApiAdapter implements DriveApiAdapter {
  DriveFolderReference? existingFolder;
  DriveApiException? shouldThrow;
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
    if (shouldThrow != null) throw shouldThrow!;
    if (onProgress != null) {
      onProgress(0.5);
      onProgress(1.0);
    }
    return DrivePhotoUploadResponse(
      fileId: 'widget_uploaded_file_id_42',
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

class WidgetTestFakePhotoMetadataStorage extends PhotoMetadataStorage {
  WidgetTestFakePhotoMetadataStorage({super.customBaseDir});

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

class WidgetTestFakePhotoFileManager extends PhotoFileManager {
  WidgetTestFakePhotoFileManager({super.customBaseDir});

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

class WidgetTestFakeSyncQueueStorage extends SyncQueueStorage {
  WidgetTestFakeSyncQueueStorage({super.customBaseDir});

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
  late WidgetTestFakeGoogleSignInDelegate fakeSignInDelegate;
  late WidgetTestFakeDriveAuthDelegate fakeDriveDelegate;
  late WidgetTestUploadDriveApiAdapter fakeApiAdapter;
  late GoogleDriveService driveService;
  late PersistentDailyPhotoStore photoStore;
  late GoogleDrivePhotoUploadService uploadService;

  const testUser = AuthUser(
    id: 'user_widget_1',
    email: 'widget_user@example.com',
    displayName: 'Widget User',
  );

  const testColors = [Color(0xFF333333), Color(0xFF555555)];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('widget_upload_test_');

    fakeSignInDelegate = WidgetTestFakeGoogleSignInDelegate();
    fakeSignInDelegate.mockUser = testUser;
    GoogleAuthService.instance.delegate = fakeSignInDelegate;
    await GoogleAuthService.instance.signIn();

    fakeDriveDelegate = WidgetTestFakeDriveAuthDelegate();
    GoogleDriveAuthService.instance.delegate = fakeDriveDelegate;
    GoogleDriveAuthService.instance.storage = DriveAuthStorage(
      customBaseDir: tempDir.path,
    );
    await GoogleDriveAuthService.instance.authorizeDrive();

    fakeApiAdapter = WidgetTestUploadDriveApiAdapter();
    final folderStorage = DriveFolderStorage(customBaseDir: tempDir.path);
    driveService = GoogleDriveService(
      adapter: fakeApiAdapter,
      storage: folderStorage,
    );
    await driveService.init();
    GoogleDriveService.setTestInstance(driveService);

    final fakeFileManager = WidgetTestFakePhotoFileManager(
      customBaseDir: tempDir,
    );
    final fakeMetadataStorage = WidgetTestFakePhotoMetadataStorage(
      customBaseDir: tempDir,
    );
    final fakeSyncQueueStorage = WidgetTestFakeSyncQueueStorage(
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
    ProfileScreen.enableDeveloperTools = true;
  });

  tearDown(() async {
    ProfileScreen.enableDeveloperTools = false;
    PersistentDailyPhotoStore.resetTestInstance();
    GoogleDrivePhotoUploadService.resetInstance();
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

  testWidgets('1. "Upload Test Photo" tile is hidden when Drive is not ready', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // Drive is authorized but folder not setup
    await tester.pumpWidget(createWidget());
    await tester.pumpAndSettle();

    expect(find.text('Google Drive Backup'), findsOneWidget);
    expect(find.text('Upload Test Photo'), findsNothing);
  });

  testWidgets(
    '2. "Upload Test Photo" tile appears when Drive folder is ready',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await makeDriveReady();

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('Google Drive Backup'), findsOneWidget);
      expect(find.text('Upload Test Photo'), findsOneWidget);
      expect(
        find.text('Proof of concept • Upload 1 photo to Drive'),
        findsOneWidget,
      );
      expect(find.text('Upload'), findsOneWidget);
    },
  );

  testWidgets(
    '3. Shows SnackBar if no local photos exist when Upload is tapped',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await makeDriveReady();

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      // Tap Upload button
      await tester.tap(find.text('Upload'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'No local photo available to upload. Capture or add a photo first.',
        ),
        findsOneWidget,
      );
      expect(fakeApiAdapter.uploadCalls, 0);
    },
  );

  testWidgets(
    '4. Shows confirmation dialog when local photo exists and cancels on Cancel',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await makeDriveReady();
      await addLocalPhoto(dateKey: const DateKey(2026, 3, 10));

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Upload'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Dialog is displayed
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text('Upload Test Photo'),
        findsNWidgets(2),
      ); // One in tile, one in dialog title
      expect(find.text('Cancel'), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AlertDialog), findsNothing);
      expect(fakeApiAdapter.uploadCalls, 0);
    },
  );

  testWidgets(
    '5. Confirms upload, executes uploadPhoto, and shows success SnackBar',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await makeDriveReady();
      const dateKey = DateKey(2026, 3, 15);
      await addLocalPhoto(dateKey: dateKey);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      final uploadBtn = find.text('Upload');
      await tester.tap(uploadBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final dialogUpload = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Upload'),
      );
      await tester.tap(dialogUpload);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(fakeApiAdapter.uploadCalls, 1);
      expect(
        find.textContaining('Uploaded "photo_2026-03-15.jpg" successfully!'),
        findsOneWidget,
      );

      final entry = photoStore.getPhotoByKey(dateKey);
      expect(entry?.syncStatus, SyncStatus.synced);
      expect(entry?.driveFileId, 'widget_uploaded_file_id_42');
    },
  );

  testWidgets('6. Shows already synced SnackBar if photo is already synced', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await makeDriveReady();
    const dateKey = DateKey(2026, 3, 20);
    await addLocalPhoto(
      dateKey: dateKey,
      syncStatus: SyncStatus.synced,
      driveFileId: 'already_existing_id',
    );
    await photoStore.updateSyncStatus(
      dateKey: dateKey,
      status: SyncStatus.synced,
      driveFileId: 'already_existing_id',
    );

    await tester.pumpWidget(createWidget());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Upload'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Dialog confirmation
    final dialogUploadFinder = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Upload'),
    );
    await tester.tap(dialogUploadFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Photo for 2026-03-20 is already synced to Google Drive.'),
      findsOneWidget,
    );
    expect(fakeApiAdapter.uploadCalls, 0);
  });
}
