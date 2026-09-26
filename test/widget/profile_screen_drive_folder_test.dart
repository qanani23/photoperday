import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/auth_user.dart';
import 'package:photo_per_day/data/models/drive_folder_reference.dart';
import 'package:photo_per_day/data/models/drive_folder_result.dart';
import 'package:photo_per_day/data/models/drive_photo_upload_response.dart';
import 'package:photo_per_day/data/services/drive_api_adapter.dart';
import 'package:photo_per_day/data/services/drive_auth_storage.dart';
import 'package:photo_per_day/data/services/drive_folder_storage.dart';
import 'package:photo_per_day/data/services/google_auth_service.dart';
import 'package:photo_per_day/data/services/google_drive_auth_service.dart';
import 'package:photo_per_day/data/services/google_drive_service.dart';
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

class WidgetTestFakeDriveApiAdapter implements DriveApiAdapter {
  DriveFolderReference? existingFolder;
  DriveApiException? shouldThrow;
  int findCalls = 0;
  int createCalls = 0;

  @override
  Future<DriveFolderReference?> findFolder({
    required String folderName,
    required Map<String, String> authHeaders,
    String? accountEmail,
  }) async {
    findCalls++;
    if (shouldThrow != null) throw shouldThrow!;
    return existingFolder;
  }

  @override
  Future<DriveFolderReference> createFolder({
    required String folderName,
    required Map<String, String> authHeaders,
    String? accountEmail,
  }) async {
    createCalls++;
    if (shouldThrow != null) throw shouldThrow!;
    return DriveFolderReference(
      folderId: 'created_widget_folder_1',
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
      fileId: 'mock_widget_upload_id',
      revision: '1',
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
      revision: '2',
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
  late WidgetTestFakeGoogleSignInDelegate fakeSignInDelegate;
  late WidgetTestFakeDriveAuthDelegate fakeDriveDelegate;
  late WidgetTestFakeDriveApiAdapter fakeApiAdapter;
  late GoogleDriveService driveService;

  const testUser = AuthUser(
    id: '12345',
    email: 'test@example.com',
    displayName: 'Test User',
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('widget_folder_test_');

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

    fakeApiAdapter = WidgetTestFakeDriveApiAdapter();
    final folderStorage = DriveFolderStorage(customBaseDir: tempDir.path);
    driveService = GoogleDriveService(
      adapter: fakeApiAdapter,
      storage: folderStorage,
    );
    await driveService.init();

    GoogleDriveService.setTestInstance(driveService);
  });

  tearDown(() async {
    GoogleDriveService.resetInstance();
    await GoogleDriveAuthService.instance.clearAuthorization();
    await GoogleAuthService.instance.signOut();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Widget createWidget() {
    return const MaterialApp(home: Scaffold(body: ProfileScreen()));
  }

  testWidgets(
    '1. Displays "Setup required" and "Set Up" button when authorized but folder uninitialized',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('Google Drive Backup'), findsOneWidget);
      expect(find.text('Drive authorized • Setup required'), findsOneWidget);
      expect(find.text('Set Up'), findsOneWidget);
    },
  );

  testWidgets(
    '2. Tapping "Set Up" creates folder and transitions to "Photo a Day folder ready"',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Set Up'));
      await tester.pumpAndSettle();

      expect(fakeApiAdapter.findCalls, 1);
      expect(fakeApiAdapter.createCalls, 1);
      expect(
        find.text('Google Drive • Photo a Day folder ready'),
        findsOneWidget,
      );
      expect(find.text('Details'), findsOneWidget);
      expect(
        find.text('Created "Photo a Day" folder in Google Drive!'),
        findsOneWidget,
      );
    },
  );

  testWidgets('3. Displays error message and "Retry" when folder setup fails', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    fakeApiAdapter.shouldThrow = const DriveApiException(
      'Network timeout connecting to Drive',
      errorType: DriveFolderErrorType.networkError,
    );

    await tester.pumpWidget(createWidget());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Set Up'));
    await tester.pumpAndSettle();

    expect(find.text('Network timeout connecting to Drive'), findsWidgets);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets(
    '4. Details dialog displays folder info and emphasizes local-first safety',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Setup folder
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Set Up'));
      await tester.pumpAndSettle();

      // Tap Details
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();

      expect(find.text('Google Drive Backup'), findsWidgets);
      expect(find.textContaining('Photo a Day'), findsWidgets);
      expect(
        find.textContaining('No photos have been uploaded yet'),
        findsOneWidget,
      );
      expect(find.text('Got It'), findsOneWidget);

      await tester.tap(find.text('Got It'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No photos have been uploaded yet'),
        findsNothing,
      );
    },
  );
}
