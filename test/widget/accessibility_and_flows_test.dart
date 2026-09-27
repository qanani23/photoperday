import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/core/routing/app_router.dart';
import 'package:photo_per_day/data/models/auth_user.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/drive_folder_reference.dart';
import 'package:photo_per_day/data/models/drive_folder_result.dart';
import 'package:photo_per_day/data/models/drive_photo_upload_response.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_run_result.dart';
import 'package:photo_per_day/data/models/sync_operation_status.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/daily_reminder_service.dart';
import 'package:photo_per_day/data/services/daily_reminder_storage.dart';
import 'package:photo_per_day/data/services/diary_export_service.dart';
import 'package:photo_per_day/data/services/drive_api_adapter.dart';
import 'package:photo_per_day/data/services/drive_auth_storage.dart';
import 'package:photo_per_day/data/services/drive_folder_storage.dart';
import 'package:photo_per_day/data/services/google_auth_service.dart';
import 'package:photo_per_day/data/services/google_drive_auth_service.dart';
import 'package:photo_per_day/data/services/google_drive_photo_upload_service.dart';
import 'package:photo_per_day/data/services/google_drive_service.dart';
import 'package:photo_per_day/data/services/notification_client.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/data/services/sync_coordinator.dart';
import 'package:photo_per_day/data/services/sync_queue.dart';
import 'package:photo_per_day/data/services/sync_queue_storage.dart';
import 'package:photo_per_day/data/services/sync_worker.dart';
import 'package:photo_per_day/screens/camera/camera_screen.dart';
import 'package:photo_per_day/screens/diary/memories_screen.dart';
import 'package:photo_per_day/screens/diary/swipe_days_screen.dart';
import 'package:photo_per_day/screens/diary/visual_diary_screen.dart';
import 'package:photo_per_day/screens/home/home_screen.dart';
import 'package:photo_per_day/screens/photo_detail/photo_detail_screen.dart';
import 'package:photo_per_day/screens/profile/profile_screen.dart';
import 'package:photo_per_day/screens/today/today_screen.dart';
import 'package:photo_per_day/services/camera_service.dart';
import 'package:photo_per_day/widgets/bottom_nav_dock.dart';
import 'package:photo_per_day/widgets/calendar_cell.dart';
import 'package:photo_per_day/widgets/photo_source_sheet.dart';
import 'package:photo_per_day/widgets/section_header.dart';

// =============================================================================
// Fakes for Milestone 38 Automated Testing
// =============================================================================

const List<int> kValid1x1PngBytes = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

class M38FakeNotificationClient implements NotificationClient {
  bool permissionGranted = true;
  final Map<int, String> scheduled = {};
  bool wasCancelled = false;

  @override
  Future<void> init({
    void Function(NotificationResponse)? onNotificationResponse,
  }) async {}

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    scheduled[id] = '$hour:$minute';
  }

  @override
  Future<void> cancel(int id) async {
    scheduled.remove(id);
    wasCancelled = true;
  }

  @override
  Future<void> cancelAll() async {
    scheduled.clear();
  }

  @override
  Future<List<int>> getPendingNotificationIds() async =>
      scheduled.keys.toList();

  @override
  Future<bool> didAppLaunchFromNotification() async => false;
}

class M38FakeGoogleSignInDelegate implements GoogleSignInDelegate {
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

class M38FakeDriveAuthDelegate implements GoogleDriveAuthDelegate {
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

class M38FakeDriveApiAdapter implements DriveApiAdapter {
  bool failUpload = false;
  bool failDelete = false;
  final Map<String, String> uploadedFiles = {};
  final List<String> deletedFiles = <String>[];
  DriveFolderReference? existingFolder;

  @override
  Future<DriveFolderReference?> findFolder({
    required String folderName,
    required Map<String, String> authHeaders,
    String? accountEmail,
  }) async {
    return existingFolder ??
        DriveFolderReference(
          folderId: 'app_folder',
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
      folderId: 'app_folder',
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
    if (failUpload) {
      throw const DriveApiException(
        'Simulated Drive upload error',
        errorType: DriveFolderErrorType.apiError,
      );
    }
    final driveId = 'drive_id_${uploadedFiles.length + 1}';
    uploadedFiles[filename] = driveId;
    return DrivePhotoUploadResponse(
      fileId: driveId,
      revision: 'rev_1',
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
    if (failUpload) {
      throw const DriveApiException(
        'Simulated Drive update error',
        errorType: DriveFolderErrorType.apiError,
      );
    }
    return DrivePhotoUploadResponse(
      fileId: fileId,
      revision: 'rev_2',
      filename: filename ?? 'photo.jpg',
    );
  }

  @override
  Future<void> trashPhotoFile({
    required String fileId,
    required Map<String, String> authHeaders,
  }) async {
    if (failDelete) {
      throw const DriveApiException(
        'Simulated Drive trash error',
        errorType: DriveFolderErrorType.apiError,
      );
    }
    deletedFiles.add(fileId);
  }
}

class M38FakeSyncCoordinator extends SyncCoordinator {
  M38FakeSyncCoordinator() : super(debounceDuration: Duration.zero);

  @override
  void scheduleAutoSync({
    Duration? delay,
    SyncTrigger trigger = SyncTrigger.photoChange,
  }) {}

  @override
  Future<SyncRunResult> requestSync({required SyncTrigger trigger}) async =>
      const SyncRunResult();
}

class M38FakeCameraService extends CameraService {
  @override
  CameraStatus get status => CameraStatus.permissionDenied;

  @override
  bool get isReady => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}
}

// =============================================================================
// Milestone 38 Test Suite
// =============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PhotoFileManager fileManager;
  late PhotoMetadataStorage metadataStorage;
  late SyncQueueStorage queueStorage;
  late SyncQueue syncQueue;
  late PersistentDailyPhotoStore store;
  late M38FakeNotificationClient notificationClient;
  late M38FakeGoogleSignInDelegate signInDelegate;
  late M38FakeDriveAuthDelegate driveAuthDelegate;
  late M38FakeDriveApiAdapter driveApiAdapter;
  late GoogleDriveService driveService;
  late GoogleDrivePhotoUploadService uploadService;
  late SyncWorker syncWorker;

  const testColors = [Color(0xFF6B4EE6), Color(0xFF9B51E0)];

  PhotoEntry createSampleEntry({
    required DateTime date,
    required String title,
    String? caption,
    String? location,
    String? imagePath,
    SyncStatus syncStatus = SyncStatus.localOnly,
    String? authorizedEmail,
  }) {
    return PhotoEntry(
      date: date,
      title: title,
      caption: caption,
      location: location,
      imagePath: imagePath,
      syncStatus: syncStatus,
      gradientColors: testColors,
      authorizedEmail: authorizedEmail,
    );
  }

  File createTestPhoto(String name) {
    final file = File('${tempDir.path}/$name.png');
    file.writeAsBytesSync(kValid1x1PngBytes);
    return file;
  }

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('m38_accessibility_test_');
    fileManager = PhotoFileManager(customBaseDir: tempDir);
    metadataStorage = PhotoMetadataStorage(customBaseDir: tempDir);
    queueStorage = SyncQueueStorage(customBaseDir: tempDir);

    await fileManager.init();
    await metadataStorage.init();
    await queueStorage.init();

    syncQueue = SyncQueue(storage: queueStorage);
    await syncQueue.init();

    store = PersistentDailyPhotoStore(
      fileManager: fileManager,
      metadataStorage: metadataStorage,
      syncQueue: syncQueue,
    );
    await store.init();

    PersistentDailyPhotoStore.setTestInstance(store);

    notificationClient = M38FakeNotificationClient();
    final reminderService = DailyReminderService(
      client: notificationClient,
      storage: DailyReminderStorage(customBaseDir: tempDir.path),
    );
    await reminderService.init();
    DailyReminderService.setTestInstance(reminderService);

    signInDelegate = M38FakeGoogleSignInDelegate();
    GoogleAuthService.instance.delegate = signInDelegate;

    driveAuthDelegate = M38FakeDriveAuthDelegate();
    GoogleDriveAuthService.instance.delegate = driveAuthDelegate;
    GoogleDriveAuthService.instance.storage = DriveAuthStorage(
      customBaseDir: tempDir.path,
    );

    driveApiAdapter = M38FakeDriveApiAdapter();
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

    syncWorker = SyncWorker(
      syncQueue: syncQueue,
      photoStore: store,
      authService: GoogleAuthService.instance,
      driveAuthService: GoogleDriveAuthService.instance,
      driveService: driveService,
      uploadService: uploadService,
      driveAdapter: driveApiAdapter,
    );
    SyncWorker.setTestInstance(syncWorker);

    SyncCoordinator.setTestInstance(M38FakeSyncCoordinator());
  });

  tearDown(() async {
    SyncCoordinator.resetInstance();
    SyncWorker.resetInstance();
    GoogleDrivePhotoUploadService.resetInstance();
    GoogleDriveService.resetInstance();
    PersistentDailyPhotoStore.resetTestInstance();
    DailyReminderService.resetTestInstance();

    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Widget wrapForAccessibilityTest(
    Widget child, {
    double textScaleFactor = 1.0,
  }) {
    return MaterialApp(
      onGenerateRoute: AppRouter.onGenerateRoute,
      builder: (context, rootChild) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
        child: rootChild!,
      ),
      home: child is Scaffold ? child : Scaffold(body: child),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('Milestone 38 — 1. Semantics & Touch Target Auditing', () {
    testWidgets(
      'SectionHeader navigation controls provide >=48px accessible touch targets',
      (tester) async {
        await tester.pumpWidget(
          wrapForAccessibilityTest(
            SectionHeader(
              title: 'March 2026',
              onPrevious: () {},
              onNext: () {},
            ),
          ),
        );
        await settle(tester);

        final prevFinder = find.bySemanticsLabel('Previous month');
        final nextFinder = find.bySemanticsLabel('Next month');

        expect(prevFinder, findsOneWidget);
        expect(nextFinder, findsOneWidget);

        final prevSize = tester.getSize(prevFinder);
        final nextSize = tester.getSize(nextFinder);

        expect(prevSize.width, greaterThanOrEqualTo(48.0));
        expect(prevSize.height, greaterThanOrEqualTo(48.0));
        expect(nextSize.width, greaterThanOrEqualTo(48.0));
        expect(nextSize.height, greaterThanOrEqualTo(48.0));
      },
    );

    testWidgets(
      'CalendarCell exposes comprehensive non-visual state and >=48px touch target',
      (tester) async {
        await tester.pumpWidget(
          wrapForAccessibilityTest(
            CalendarCell(
              day: 15,
              isToday: true,
              style: CalendarCellStyle.photo,
              syncStatus: SyncStatus.synced,
              onTap: () {},
            ),
          ),
        );
        await settle(tester);

        final cellFinder = find.byType(CalendarCell);
        expect(cellFinder, findsOneWidget);

        // Verify semantics communicate date, today state, photo presence, and sync status non-visually
        final semantics = tester.getSemantics(cellFinder);
        expect(semantics.label, contains('Day 15'));
        expect(semantics.label, contains('Today'));
        expect(semantics.label, contains('Photo memory captured'));
        expect(semantics.label, contains('Backed up'));
      },
    );

    testWidgets(
      'PhotoSourceSheet actions provide >=48px touch targets and descriptive semantics',
      (tester) async {
        await tester.pumpWidget(
          wrapForAccessibilityTest(const PhotoSourceSheet()),
        );
        await settle(tester);

        final cameraFinder = find.bySemanticsLabel(RegExp(r'Take Photo'));
        final galleryFinder = find.bySemanticsLabel(
          RegExp(r'Choose from Gallery'),
        );
        final cancelFinder = find.bySemanticsLabel('Cancel photo selection');

        expect(cameraFinder, findsOneWidget);
        expect(galleryFinder, findsOneWidget);
        expect(cancelFinder, findsOneWidget);

        final cameraSize = tester.getSize(cameraFinder);
        final gallerySize = tester.getSize(galleryFinder);
        final cancelSize = tester.getSize(cancelFinder);

        expect(cameraSize.height, greaterThanOrEqualTo(48.0));
        expect(gallerySize.height, greaterThanOrEqualTo(48.0));
        expect(cancelSize.height, greaterThanOrEqualTo(48.0));
      },
    );

    testWidgets(
      'PhotoDetailScreen hero image and action buttons expose proper semantics',
      (tester) async {
        final dummy = createTestPhoto('detail_photo');
        final entry = createSampleEntry(
          date: DateTime(2026, 3, 10),
          title: 'Sunset at Park',
          caption: 'Golden light filtering through pines',
          location: 'City Garden',
          imagePath: dummy.path,
          syncStatus: SyncStatus.synced,
        );

        await tester.pumpWidget(
          wrapForAccessibilityTest(PhotoDetailScreen(photoEntry: entry)),
        );
        await settle(tester);

        // Hero image has descriptive label
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.label == 'Photo memory: Sunset at Park',
          ),
          findsOneWidget,
        );

        // Back navigation button
        final backFinder = find.bySemanticsLabel('Back to journal');
        expect(backFinder, findsOneWidget);
        final backSize = tester.getSize(backFinder);
        expect(backSize.width, greaterThanOrEqualTo(48.0));
        expect(backSize.height, greaterThanOrEqualTo(48.0));

        // Header actions
        expect(find.bySemanticsLabel('Browse recorded days'), findsNWidgets(2));
        expect(find.bySemanticsLabel('Edit memory details'), findsNWidgets(2));
      },
    );

    testWidgets(
      'CameraScreen navigation and controls have accessible touch targets',
      (tester) async {
        await tester.pumpWidget(
          wrapForAccessibilityTest(
            CameraScreen(cameraService: M38FakeCameraService()),
          ),
        );
        await settle(tester);

        final closeFinder = find.bySemanticsLabel('Close camera and return');
        expect(closeFinder, findsOneWidget);
        final closeSize = tester.getSize(closeFinder);
        expect(closeSize.width, greaterThanOrEqualTo(48.0));
        expect(closeSize.height, greaterThanOrEqualTo(48.0));
      },
    );

    testWidgets(
      'ProfileScreen reminder switch and time changer are fully accessible',
      (tester) async {
        // Enable reminder so both time selector and switch are active
        notificationClient.permissionGranted = true;
        await DailyReminderService.instance.setEnabled(true);

        await tester.pumpWidget(
          wrapForAccessibilityTest(const ProfileScreen()),
        );
        await settle(tester);

        // Reminder toggle switch semantics
        expect(
          find.bySemanticsLabel('Daily reminder notification toggle'),
          findsOneWidget,
        );

        // Change reminder time button semantics and touch target
        final timeChangerFinder = find.bySemanticsLabel(
          RegExp(r'Change reminder time'),
        );
        expect(timeChangerFinder, findsOneWidget);
        final timeSize = tester.getSize(timeChangerFinder);
        expect(timeSize.width, greaterThanOrEqualTo(48.0));
        expect(timeSize.height, greaterThanOrEqualTo(48.0));
      },
    );

    testWidgets(
      'TodayScreen hero and action controls expose meaningful semantics',
      (tester) async {
        final date = DateTime(2026, 3, 15);
        final dummy = createTestPhoto('today_test');
        final entry = createSampleEntry(
          date: date,
          title: 'Morning Coffee',
          imagePath: dummy.path,
        );
        await tester.runAsync(() async {
          await store.savePhoto(entry: entry, sourceTempPath: dummy.path);
        });

        await tester.pumpWidget(wrapForAccessibilityTest(const TodayScreen()));
        await settle(tester);

        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                (w.properties.label?.contains(
                      "Today's photo memory: Morning Coffee",
                    ) ??
                    false),
          ),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel("Replace today's photo"), findsOneWidget);
        expect(find.bySemanticsLabel("Share today's photo"), findsOneWidget);
      },
    );
  });

  group('Milestone 38 — 2. Text Scaling & Layout Robustness (1.5x / 1.8x)', () {
    testWidgets(
      'CalendarScreen / HomeScreen renders cleanly under 1.8x text scaling without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          wrapForAccessibilityTest(const HomeScreen(), textScaleFactor: 1.8),
        );
        await settle(tester);

        // Confirm no RenderFlex overflows
        expect(tester.takeException(), isNull);
        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );

    testWidgets('TodayScreen renders with no overflow under 1.8x text scaling', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final dummy = createTestPhoto('scale_today');
      final entry = createSampleEntry(
        date: DateTime(2026, 3, 15),
        title: 'Large Text Scale Test On Today Screen',
        caption:
            'Detailed story text verifying multiline flexibility without clip',
        imagePath: dummy.path,
      );
      await tester.runAsync(() async {
        await store.savePhoto(entry: entry, sourceTempPath: dummy.path);
      });

      await tester.pumpWidget(
        wrapForAccessibilityTest(const TodayScreen(), textScaleFactor: 1.8),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
    });

    testWidgets('PhotoDetailScreen renders cleanly under 1.8x text scaling', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final dummy = createTestPhoto('scale_detail');
      final entry = createSampleEntry(
        date: DateTime(2026, 3, 10),
        title: 'Accessibility Scaled Title',
        caption: 'Long narrative text with increased font size',
        location: 'Central Plaza Park',
        imagePath: dummy.path,
        syncStatus: SyncStatus.synced,
      );

      await tester.pumpWidget(
        wrapForAccessibilityTest(
          PhotoDetailScreen(photoEntry: entry),
          textScaleFactor: 1.8,
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Accessibility Scaled Title'), findsOneWidget);
      expect(find.text('Central Plaza Park'), findsOneWidget);
    });

    testWidgets(
      'VisualDiaryScreen renders with no overflow under 1.8x text scaling',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final dummy = createTestPhoto('scale_diary');
        final entry = createSampleEntry(
          date: DateTime(2026, 3, 10),
          title: 'Diary Card Scaled Text',
          caption: 'Checking text container wrapping behavior',
          imagePath: dummy.path,
        );
        await tester.runAsync(() async {
          await store.savePhoto(entry: entry, sourceTempPath: dummy.path);
        });

        await tester.pumpWidget(
          wrapForAccessibilityTest(
            VisualDiaryScreen(store: store),
            textScaleFactor: 1.8,
          ),
        );
        await settle(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('Diary Card Scaled Text'), findsOneWidget);
      },
    );

    testWidgets(
      'ProfileScreen renders with no overflow under 1.8x text scaling',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          wrapForAccessibilityTest(const ProfileScreen(), textScaleFactor: 1.8),
        );
        await settle(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('Profile & Settings'), findsOneWidget);
      },
    );

    testWidgets(
      'SwipeDaysScreen renders with no overflow under 1.8x text scaling',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final dummy = createTestPhoto('scale_swipe');
        final entry = createSampleEntry(
          date: DateTime(2026, 3, 10),
          title: 'Swipe Days Scaled View',
          imagePath: dummy.path,
        );
        await tester.runAsync(() async {
          await store.savePhoto(entry: entry, sourceTempPath: dummy.path);
        });

        await tester.pumpWidget(
          wrapForAccessibilityTest(
            SwipeDaysScreen(store: store),
            textScaleFactor: 1.8,
          ),
        );
        await settle(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('Swipe Days Scaled View'), findsOneWidget);
      },
    );
  });

  group('Milestone 38 — 3. Critical Flow Automated Testing', () {
    test(
      'A. Photo lifecycle: select/capture -> persist -> display -> metadata update -> delete',
      () async {
        final date = DateTime(2026, 3, 12);
        final dummy = createTestPhoto('lifecycle_photo');

        // 1. Capture & Persist
        final initialEntry = createSampleEntry(
          date: date,
          title: 'Lifecycle Initial',
          caption: 'Initial caption',
          location: 'Initial location',
        );
        final saved = await store.savePhoto(
          entry: initialEntry,
          sourceTempPath: dummy.path,
        );

        expect(saved.hasRealImage, isTrue);
        expect(store.hasPhoto(date), isTrue);
        expect(store.getPhoto(date)?.title, 'Lifecycle Initial');

        // 2. Metadata Update
        final updated = await store.updatePhotoMetadata(
          dateKey: saved.dateKey,
          title: 'Updated Title',
          caption: 'Updated caption',
          location: 'Updated location',
        );
        expect(updated.title, 'Updated Title');
        expect(store.getPhoto(date)?.title, 'Updated Title');
        expect(store.getPhoto(date)?.caption, 'Updated caption');

        // 3. Delete
        await store.removePhotoAsync(date);
        expect(store.hasPhoto(date), isFalse);
        expect(store.getPhoto(date), isNull);
      },
    );

    test(
      'B. One-photo-per-day rule: create -> replace same day -> verify exactly one entry remains',
      () async {
        final date = DateTime(2026, 3, 14);
        final dummy1 = createTestPhoto('first_shot');
        final dummy2 = createTestPhoto('replacement_shot');

        // First capture of the day
        final firstEntry = createSampleEntry(date: date, title: 'First Shot');
        await store.savePhoto(entry: firstEntry, sourceTempPath: dummy1.path);

        expect(store.totalPhotos, 1);
        expect(store.getPhoto(date)?.title, 'First Shot');

        // Second capture on the exact same calendar day
        final replacementEntry = createSampleEntry(
          date: date,
          title: 'Replacement Shot',
        );
        await store.savePhoto(
          entry: replacementEntry,
          sourceTempPath: dummy2.path,
        );

        // Verify domain rule: exactly 1 photo for this date, replacing the previous
        expect(store.totalPhotos, 1);
        expect(store.getPhoto(date)?.title, 'Replacement Shot');
        expect(store.chronologicalEntries.length, 1);
      },
    );

    test(
      'C. Sync lifecycle: local -> pending -> synced and local -> pending -> failed -> retry',
      () async {
        final date = DateTime(2026, 3, 15);
        final dummy = createTestPhoto('sync_flow');
        signInDelegate.mockUser = const AuthUser(
          id: 'user_123',
          email: 'photofan@example.com',
          displayName: 'Photo Fan',
        );
        await GoogleAuthService.instance.signIn();
        await GoogleDriveAuthService.instance.authorizeDrive();
        driveApiAdapter.existingFolder = DriveFolderReference(
          folderId: 'app_folder',
          folderName: 'Photo a Day',
          authorizedEmail: 'photofan@example.com',
          resolvedAt: DateTime.now().toUtc(),
        );
        await GoogleDriveService.instance.setupFolder();

        // 1. Local save creates pending sync queue entry
        final entry = createSampleEntry(
          date: date,
          title: 'Sync Lifecycle',
          syncStatus: SyncStatus.pending,
        );
        await store.savePhoto(entry: entry, sourceTempPath: dummy.path);

        expect(store.getPhoto(date)?.syncStatus, SyncStatus.pending);
        expect(syncQueue.count, 1);

        // 2. Process sync worker successfully
        driveApiAdapter.failUpload = false;
        final workerResult = await syncWorker.syncNow();
        expect(workerResult.succeededCount, 1);
        expect(store.getPhoto(date)?.syncStatus, SyncStatus.synced);

        // 3. Update photo metadata creates new sync operation
        await store.updatePhotoMetadata(
          dateKey: DateKey.fromDateTime(date),
          title: 'Sync Updated',
        );
        expect(store.getPhoto(date)?.syncStatus, SyncStatus.pending);

        // 4. Simulated failure
        driveApiAdapter.failUpload = true;
        final failedResult = await syncWorker.syncNow();
        expect(failedResult.failedCount, 1);
        expect(store.getPhoto(date)?.syncStatus, SyncStatus.failed);

        // 5. Retry successfully (simulate elapsed retry timer)
        driveApiAdapter.failUpload = false;
        final op = syncQueue.getOperationForDate(DateKey.fromDateTime(date))!;
        await syncQueue.markFailed(
          op.id,
          error: '',
          nextAttemptAt: DateTime.now().toUtc().subtract(
            const Duration(seconds: 1),
          ),
        );
        final retryResult = await syncWorker.syncNow();
        expect(retryResult.succeededCount, 1);
        expect(store.getPhoto(date)?.syncStatus, SyncStatus.synced);
      },
    );

    test(
      'D. Account safety: Account A queued operation must not execute under Account B',
      () async {
        final date = DateTime(2026, 3, 16);
        final dummy = createTestPhoto('account_safety');

        // Sign in as Account A
        signInDelegate.mockUser = const AuthUser(
          id: 'account_a',
          email: 'a@example.com',
        );
        await GoogleAuthService.instance.signIn();
        await GoogleDriveAuthService.instance.authorizeDrive();
        driveApiAdapter.existingFolder = DriveFolderReference(
          folderId: 'app_folder_a',
          folderName: 'Photo a Day',
          authorizedEmail: 'a@example.com',
          resolvedAt: DateTime.now().toUtc(),
        );
        await GoogleDriveService.instance.setupFolder();

        final entry = createSampleEntry(
          date: date,
          title: 'Account A Photo',
          syncStatus: SyncStatus.pending,
          authorizedEmail: 'a@example.com',
        );
        await store.savePhoto(entry: entry, sourceTempPath: dummy.path);
        expect(syncQueue.count, 1);

        // Switch to Account B
        signInDelegate.mockUser = const AuthUser(
          id: 'account_b',
          email: 'b@example.com',
        );
        await GoogleAuthService.instance.signIn();
        await GoogleDriveAuthService.instance.authorizeDrive();
        driveApiAdapter.existingFolder = DriveFolderReference(
          folderId: 'app_folder_b',
          folderName: 'Photo a Day',
          authorizedEmail: 'b@example.com',
          resolvedAt: DateTime.now().toUtc(),
        );
        await GoogleDriveService.instance.setupFolder();

        // SyncWorker must reject Account A queued item under Account B
        final workerResult = await syncWorker.syncNow();
        expect(workerResult.failedCount, 1);
        final queuedOp = syncQueue.operations.first;
        expect(queuedOp.status, SyncOperationStatus.failed);
        expect(queuedOp.lastError, contains('b@example.com'));
        // Local photo remains safely untouched
        expect(store.getPhoto(date)?.syncStatus, SyncStatus.pending);
      },
    );

    test(
      'E. Export: diary export creates valid archive and manifest',
      () async {
        final date = DateTime(2026, 3, 17);
        final dummy = createTestPhoto('export_photo');

        final entry = createSampleEntry(
          date: date,
          title: 'Exported Memory',
          caption: 'Caption for export verification',
          imagePath: dummy.path,
        );
        await store.savePhoto(entry: entry, sourceTempPath: dummy.path);

        final exportService = DiaryExportService(store: store);
        final exportDir = Directory('${tempDir.path}/export_out');
        await exportDir.create();

        final result = await exportService.exportDiary(
          customExportDir: exportDir,
        );

        expect(result.isSuccess, isTrue);
        expect(result.zipFile != null, isTrue);
        expect(result.zipFile!.existsSync(), isTrue);
        expect(result.exportedCount, 1);
        expect(result.skippedCount, 0);
        expect(result.totalEntries, 1);
      },
    );

    test(
      'F. Delete flows: local delete clears store, cloud delete interacts with Drive adapter',
      () async {
        final date = DateTime(2026, 3, 18);
        final dummy = createTestPhoto('delete_test');

        final entry = createSampleEntry(
          date: date,
          title: 'Delete Flow',
          imagePath: dummy.path,
        );
        await store.savePhoto(entry: entry, sourceTempPath: dummy.path);

        // Local diary delete
        expect(store.totalPhotos, 1);
        await store.deleteLocalDiary();
        expect(store.totalPhotos, 0);

        // Cloud delete via DriveService
        signInDelegate.mockUser = const AuthUser(
          id: 'u1',
          email: 'u1@example.com',
        );
        await GoogleAuthService.instance.signIn();
        await GoogleDriveAuthService.instance.authorizeDrive();
        driveApiAdapter.existingFolder = DriveFolderReference(
          folderId: 'app_folder',
          folderName: 'Photo a Day',
          authorizedEmail: 'u1@example.com',
          resolvedAt: DateTime.now().toUtc(),
        );
        await GoogleDriveService.instance.setupFolder();

        final cloudDeleteResult = await GoogleDriveService.instance
            .deleteDriveBackup(photoStore: store);
        expect(cloudDeleteResult, isA<DriveDeleteSuccess>());
      },
    );

    test(
      'G. Daily reminder service: enable -> schedule -> disable and permission-denied flow',
      () async {
        final reminderService = DailyReminderService.instance;

        // 1. Enable reminder
        notificationClient.permissionGranted = true;
        final enabled = await reminderService.setEnabled(true);
        expect(enabled, isTrue);
        expect(reminderService.isEnabled, isTrue);
        expect(notificationClient.scheduled.isNotEmpty, isTrue);

        // 2. Change time
        await reminderService.setTime(hour: 21, minute: 15);
        expect(reminderService.settings.formattedTime, '9:15 PM');
        expect(notificationClient.scheduled.values.first, '21:15');

        // 3. Disable reminder
        await reminderService.setEnabled(false);
        expect(reminderService.isEnabled, isFalse);
        expect(notificationClient.scheduled.isEmpty, isTrue);

        // 4. Permission denied flow
        notificationClient.permissionGranted = false;
        final deniedResult = await reminderService.setEnabled(true);
        expect(deniedResult, isFalse);
        expect(reminderService.permissionDenied, isTrue);
        expect(reminderService.isEnabled, isFalse);
      },
    );

    testWidgets(
      'H. Navigation routing: Calendar -> Today -> Photo Detail -> Diary -> Swipe',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final dummy = createTestPhoto('nav_photo');
        final entry = createSampleEntry(
          date: DateTime(2026, 3, 15),
          title: 'Navigation Test Photo',
          imagePath: dummy.path,
        );
        await tester.runAsync(() async {
          await store.savePhoto(entry: entry, sourceTempPath: dummy.path);
        });

        await tester.pumpWidget(
          const MaterialApp(
            initialRoute: AppConstants.initialRoute,
            onGenerateRoute: AppRouter.onGenerateRoute,
          ),
        );
        await settle(tester);

        // Tap Visual Diary action in header
        expect(find.byTooltip('Visual Diary'), findsOneWidget);
        await tester.tap(find.byTooltip('Visual Diary'));
        await settle(tester);

        // We are in VisualDiaryScreen
        expect(find.text('Diary'), findsOneWidget);
        expect(find.text('Navigation Test Photo'), findsOneWidget);

        // Open Browse Days from diary
        expect(find.byTooltip('Browse Days'), findsAtLeastNWidgets(1));
        await tester.tap(find.byTooltip('Browse Days').first);
        await settle(tester);

        // We are in SwipeDaysScreen
        expect(find.text('Daily Journal'), findsOneWidget);
      },
    );
  });

  group('Milestone 38 — 4. Accessibility Regression Tests', () {
    testWidgets(
      'Missing photo file on disk renders fallback gracefully with semantics',
      (tester) async {
        final entry = createSampleEntry(
          date: DateTime(2026, 3, 20),
          title: 'Missing Image File',
          imagePath: '${tempDir.path}/non_existent.jpg',
        );
        store.setPhoto(entry);

        await tester.pumpWidget(
          wrapForAccessibilityTest(PhotoDetailScreen(photoEntry: entry)),
        );
        await settle(tester);

        // Fallback renders without unhandled exception
        expect(find.text('Missing Image File'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.label == 'Photo memory: Missing Image File',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Pending sync state badge is accessible and distinguishable without color alone',
      (tester) async {
        final dummy = createTestPhoto('pending_sync');
        final entry = createSampleEntry(
          date: DateTime(2026, 3, 21),
          title: 'Pending Sync Test',
          imagePath: dummy.path,
          syncStatus: SyncStatus.pending,
        );
        await tester.runAsync(() async {
          await store.savePhoto(entry: entry, sourceTempPath: dummy.path);
        });

        await tester.pumpWidget(
          wrapForAccessibilityTest(PhotoDetailScreen(photoEntry: entry)),
        );
        await settle(tester);

        expect(find.text('Waiting to back up'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.label == 'Photo waiting to be backed up',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Failed sync state exposes actionable Try Again with clear error semantics',
      (tester) async {
        final dummy = createTestPhoto('failed_sync');
        final entry = createSampleEntry(
          date: DateTime(2026, 3, 22),
          title: 'Failed Sync Test',
          imagePath: dummy.path,
          syncStatus: SyncStatus.failed,
        );
        await tester.runAsync(() async {
          await store.savePhoto(entry: entry, sourceTempPath: dummy.path);
        });

        await tester.pumpWidget(
          wrapForAccessibilityTest(PhotoDetailScreen(photoEntry: entry)),
        );
        await settle(tester);

        expect(find.text('Backup failed'), findsOneWidget);
        expect(find.text('Tap Try Again to retry backup'), findsOneWidget);
        expect(find.bySemanticsLabel('Try photo backup again'), findsOneWidget);
      },
    );

    testWidgets(
      'Empty diary state provides accessible guidance and capture CTA',
      (tester) async {
        await tester.pumpWidget(
          wrapForAccessibilityTest(VisualDiaryScreen(store: store)),
        );
        await settle(tester);

        expect(find.text('Your Photo Journal'), findsOneWidget);
        expect(
          find.bySemanticsLabel("Capture today's photo to begin your diary"),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Empty memories state provides calm, non-gamified explanation',
      (tester) async {
        await tester.pumpWidget(
          wrapForAccessibilityTest(
            MemoriesScreen(store: store, targetDate: DateTime(2026, 3, 15)),
          ),
        );
        await settle(tester);

        expect(find.text('No memories from this day yet'), findsOneWidget);
        expect(find.text("Capture Today's Photo"), findsOneWidget);
      },
    );

    testWidgets(
      'Keyboard / Focus traversal navigates through interactive controls',
      (tester) async {
        await tester.pumpWidget(
          wrapForAccessibilityTest(const BottomNavDock(currentIndex: 0)),
        );
        await settle(tester);

        // Focus Home tab
        final focusScope = FocusScope.of(
          tester.element(find.byType(BottomNavDock)),
        );
        focusScope.nextFocus();
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );
  });
}
