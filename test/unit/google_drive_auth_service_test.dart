import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/auth_user.dart';
import 'package:photo_per_day/data/models/drive_auth_state.dart';
import 'package:photo_per_day/data/models/drive_auth_status.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_operation_type.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/drive_auth_storage.dart';
import 'package:photo_per_day/data/services/google_auth_service.dart';
import 'package:photo_per_day/data/services/google_drive_auth_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';

/// Test double implementing [GoogleSignInDelegate] for auth testing.
class FakeGoogleSignInDelegate implements GoogleSignInDelegate {
  AuthUser? mockUser;
  bool shouldThrowOnSignIn = false;
  bool shouldCancelOnSignIn = false;
  bool driveScopeGranted = false;
  bool canAccessScopeResult = false;
  bool shouldThrowOnScopeRequest = false;

  @override
  Future<AuthUser?> signInSilently() async => mockUser;

  @override
  Future<AuthUser?> signIn() async {
    if (shouldThrowOnSignIn) {
      throw Exception('network_error');
    }
    if (shouldCancelOnSignIn) {
      return null;
    }
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
  Future<bool> canAccessDriveScope() async => canAccessScopeResult;

  @override
  Future<bool> requestDriveScope() async {
    if (shouldThrowOnScopeRequest) {
      throw Exception('network_error: connection reset');
    }
    return driveScopeGranted;
  }

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

/// Test double implementing [GoogleDriveAuthDelegate] directly.
class FakeGoogleDriveAuthDelegate implements GoogleDriveAuthDelegate {
  bool driveScopeGranted = false;
  bool canAccessScopeResult = false;
  bool shouldThrowOnScopeRequest = false;
  int requestScopeCallCount = 0;

  @override
  Future<bool> canAccessDriveScope() async => canAccessScopeResult;

  @override
  Future<bool> requestDriveScope() async {
    requestScopeCallCount++;
    if (shouldThrowOnScopeRequest) {
      throw Exception('network_error: socket timeout');
    }
    return driveScopeGranted;
  }

  @override
  Future<Map<String, String>> getAuthHeaders() async {
    return {
      'Authorization': 'Bearer fake_mock_access_token',
      'X-Goog-AuthUser': '0',
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late FakeGoogleSignInDelegate fakeSignInDelegate;
  late GoogleAuthService authService;
  late FakeGoogleDriveAuthDelegate fakeDriveDelegate;
  late DriveAuthStorage driveStorage;
  late GoogleDriveAuthService driveAuthService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('drive_auth_test_');
    fakeSignInDelegate = FakeGoogleSignInDelegate();
    authService = GoogleAuthService(delegate: fakeSignInDelegate);

    fakeDriveDelegate = FakeGoogleDriveAuthDelegate();
    driveStorage = DriveAuthStorage(customBaseDir: tempDir.path);
    driveAuthService = GoogleDriveAuthService(
      authService: authService,
      delegate: fakeDriveDelegate,
      storage: driveStorage,
    );
    await driveAuthService.init();
  });

  tearDown(() async {
    driveAuthService.dispose();
    authService.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Milestone 19 — Google Drive Authorization Tests', () {
    test('1. Initial state defaults to notAuthorized', () {
      expect(driveAuthService.status, DriveAuthStatus.notAuthorized);
      expect(driveAuthService.isAuthorized, isFalse);
      expect(driveAuthService.isAuthorizing, isFalse);
      expect(driveAuthService.errorMessage, isNull);
    });

    test(
      '2. Signed-out authorization attempt fails gracefully without delegate call',
      () async {
        // Ensure user is signed out
        expect(authService.isSignedIn, isFalse);

        final success = await driveAuthService.authorizeDrive();

        expect(success, isFalse);
        expect(driveAuthService.status, DriveAuthStatus.notAuthorized);
        expect(driveAuthService.isAuthorized, isFalse);
        expect(
          driveAuthService.errorMessage,
          contains('Sign in to a Google account'),
        );
        expect(fakeDriveDelegate.requestScopeCallCount, 0);
      },
    );

    test(
      '3. Successful authorization transitions to authorized and persists state',
      () async {
        // Sign in user first
        fakeSignInDelegate.mockUser = const AuthUser(
          id: 'u123',
          email: 'user@gmail.com',
          displayName: 'Test User',
        );
        await authService.signIn();
        expect(authService.isSignedIn, isTrue);

        // Grant scope
        fakeDriveDelegate.driveScopeGranted = true;

        final success = await driveAuthService.authorizeDrive();

        expect(success, isTrue);
        expect(driveAuthService.status, DriveAuthStatus.authorized);
        expect(driveAuthService.isAuthorized, isTrue);
        expect(driveAuthService.errorMessage, isNull);
        expect(driveAuthService.lastAuthorizedAt, isNotNull);
        expect(fakeDriveDelegate.requestScopeCallCount, 1);

        // Verify persisted state
        final persisted = await driveStorage.loadState();
        expect(persisted.hasAuthorizedDrive, isTrue);
        expect(persisted.authorizedEmail, 'user@gmail.com');
        expect(persisted.lastAuthorizedAt, isNotNull);
      },
    );

    test(
      '4. Authorization denial / cancellation transitions to denied',
      () async {
        fakeSignInDelegate.mockUser = const AuthUser(
          id: 'u123',
          email: 'user@gmail.com',
          displayName: 'Test User',
        );
        await authService.signIn();

        // User denies or cancels the consent prompt
        fakeDriveDelegate.driveScopeGranted = false;

        final success = await driveAuthService.authorizeDrive();

        expect(success, isFalse);
        expect(driveAuthService.status, DriveAuthStatus.denied);
        expect(driveAuthService.isAuthorized, isFalse);
        expect(driveAuthService.errorMessage, contains('not granted'));
      },
    );

    test(
      '5. Network error during authorization transitions to error state',
      () async {
        fakeSignInDelegate.mockUser = const AuthUser(
          id: 'u123',
          email: 'user@gmail.com',
          displayName: 'Test User',
        );
        await authService.signIn();

        fakeDriveDelegate.shouldThrowOnScopeRequest = true;

        final success = await driveAuthService.authorizeDrive();

        expect(success, isFalse);
        expect(driveAuthService.status, DriveAuthStatus.error);
        expect(driveAuthService.isAuthorized, isFalse);
        expect(
          driveAuthService.errorMessage,
          'Network connection unavailable. Please check your internet connection.',
        );
      },
    );

    test(
      '6. Already-authorized account is recognized on checkAuthorization',
      () async {
        fakeSignInDelegate.mockUser = const AuthUser(
          id: 'u123',
          email: 'user@gmail.com',
          displayName: 'Test User',
        );
        await authService.signIn();

        fakeDriveDelegate.canAccessScopeResult = true;

        final isAuthorized = await driveAuthService.checkAuthorization();

        expect(isAuthorized, isTrue);
        expect(driveAuthService.status, DriveAuthStatus.authorized);
        expect(driveAuthService.isAuthorized, isTrue);
      },
    );

    test(
      '7. getAuthHeaders returns authenticated map when authorized',
      () async {
        fakeSignInDelegate.mockUser = const AuthUser(
          id: 'u123',
          email: 'user@gmail.com',
          displayName: 'Test User',
        );
        await authService.signIn();
        fakeDriveDelegate.driveScopeGranted = true;
        await driveAuthService.authorizeDrive();

        final headers = await driveAuthService.getAuthHeaders();

        expect(
          headers['Authorization'],
          contains('Bearer fake_mock_access_token'),
        );
        expect(headers['X-Goog-AuthUser'], '0');
      },
    );

    test(
      '8. getAuthHeaders throws StateError when not authorized or signed out',
      () async {
        // When signed out
        expect(
          () async => await driveAuthService.getAuthHeaders(),
          throwsA(isA<StateError>()),
        );

        // When signed in but not authorized
        fakeSignInDelegate.mockUser = const AuthUser(
          id: 'u123',
          email: 'user@gmail.com',
          displayName: 'Test User',
        );
        await authService.signIn();

        expect(
          () async => await driveAuthService.getAuthHeaders(),
          throwsA(isA<StateError>()),
        );
      },
    );

    test(
      '9. Signing out of Google account resets Drive authorization in memory',
      () async {
        fakeSignInDelegate.mockUser = const AuthUser(
          id: 'u123',
          email: 'user@gmail.com',
          displayName: 'Test User',
        );
        await authService.signIn();
        fakeDriveDelegate.driveScopeGranted = true;
        await driveAuthService.authorizeDrive();
        expect(driveAuthService.isAuthorized, isTrue);

        // Sign out
        await authService.signOut();

        // Memory state is cleanly reset to notAuthorized
        expect(driveAuthService.status, DriveAuthStatus.notAuthorized);
        expect(driveAuthService.isAuthorized, isFalse);
      },
    );

    test(
      '10. Local photos and store are completely preserved across authorization and sign out',
      () async {
        final storeDir = Directory('${tempDir.path}/store')..createSync();
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
          title: 'Preserved Memory',
          syncStatus: SyncStatus.localOnly,
          gradientColors: const [Color(0xFFE2D9CC), Color(0xFFD4C7B5)],
        );
        await store.savePhoto(entry: entry, sourceTempPath: dummyFile.path);
        expect(store.totalPhotos, 1);

        // Authorize Drive
        fakeSignInDelegate.mockUser = const AuthUser(
          id: 'u123',
          email: 'user@gmail.com',
          displayName: 'Test User',
        );
        await authService.signIn();
        fakeDriveDelegate.driveScopeGranted = true;
        await driveAuthService.authorizeDrive();
        expect(driveAuthService.isAuthorized, isTrue);

        // Sign out
        await authService.signOut();

        // Local store has 0 photos deleted, 0 files wiped
        expect(store.totalPhotos, 1);
        final fetched = store.getPhoto(date);
        expect(fetched?.title, 'Preserved Memory');
        expect(store.hasPhoto(date), isTrue);
      },
    );

    test(
      '11. SyncQueue durable outbox operations remain completely intact and unconsumed',
      () async {
        final storeDir = Directory('${tempDir.path}/store2')..createSync();
        final store = PersistentDailyPhotoStore(
          fileManager: PhotoFileManager(customBaseDir: storeDir),
          metadataStorage: PhotoMetadataStorage(customBaseDir: storeDir),
        );
        await store.init();

        final date = DateTime(2026, 9, 13);
        final dummyFile = File('${storeDir.path}/test_source2.jpg')
          ..writeAsStringSync('dummy_image_data2');

        final entry = PhotoEntry(
          date: date,
          title: 'Queued Memory',
          syncStatus: SyncStatus.pending,
          gradientColors: const [Color(0xFFE2D9CC), Color(0xFFD4C7B5)],
        );
        await store.savePhoto(entry: entry, sourceTempPath: dummyFile.path);
        await store.flush();

        // Queue has 1 pending upload
        expect(store.syncQueue.count, 1);
        expect(store.syncQueue.operations.first.type, SyncOperationType.upload);

        // Authorize Drive
        fakeSignInDelegate.mockUser = const AuthUser(
          id: 'u123',
          email: 'user@gmail.com',
          displayName: 'Test User',
        );
        await authService.signIn();
        fakeDriveDelegate.driveScopeGranted = true;
        await driveAuthService.authorizeDrive();

        // SyncQueue is NOT consumed, NOT modified, NOT deleted
        expect(store.syncQueue.count, 1);
        expect(store.syncQueue.operations.first.type, SyncOperationType.upload);
      },
    );

    test('12. Drive scope is strictly drive.file', () {
      expect(
        GoogleAuthService.driveFileScope,
        'https://www.googleapis.com/auth/drive.file',
      );
      expect(GoogleAuthService.driveFileScope, isNot(contains('appdata')));
      expect(
        GoogleAuthService.driveFileScope,
        isNot(equals('https://www.googleapis.com/auth/drive')),
      );
    });

    test(
      '13. Zero OAuth tokens or secrets are serialized to disk in drive_auth_state.json',
      () async {
        fakeSignInDelegate.mockUser = const AuthUser(
          id: 'u123',
          email: 'user@gmail.com',
          displayName: 'Test User',
        );
        await authService.signIn();
        fakeDriveDelegate.driveScopeGranted = true;
        await driveAuthService.authorizeDrive();

        final filePath = await driveStorage.stateFilePath;
        final fileContent = await File(filePath).readAsString();

        expect(fileContent, isNot(contains('access_token')));
        expect(fileContent, isNot(contains('refresh_token')));
        expect(fileContent, isNot(contains('Bearer')));
        expect(fileContent, isNot(contains('client_secret')));
        expect(fileContent, isNot(contains('id_token')));
      },
    );

    test(
      '14. Non-sensitive DriveAuthState survives restart across DriveAuthStorage',
      () async {
        final now = DateTime.now().toUtc();
        final state = DriveAuthState(
          hasAuthorizedDrive: true,
          authorizedEmail: 'user@gmail.com',
          lastAuthorizedAt: now,
        );
        await driveStorage.saveState(state);

        final reloaded = await driveStorage.loadState();
        expect(reloaded.hasAuthorizedDrive, isTrue);
        expect(reloaded.authorizedEmail, 'user@gmail.com');
        expect(
          reloaded.lastAuthorizedAt?.millisecondsSinceEpoch,
          now.millisecondsSinceEpoch,
        );
      },
    );

    test(
      '15. Account mismatch does not leak authorization across users',
      () async {
        // User A authorizes
        fakeSignInDelegate.mockUser = const AuthUser(
          id: 'u1',
          email: 'alice@gmail.com',
          displayName: 'Alice',
        );
        await authService.signIn();
        fakeDriveDelegate.driveScopeGranted = true;
        await driveAuthService.authorizeDrive();
        expect(driveAuthService.isAuthorized, isTrue);

        // Sign out
        await authService.signOut();

        // User B signs in
        fakeSignInDelegate.mockUser = const AuthUser(
          id: 'u2',
          email: 'bob@gmail.com',
          displayName: 'Bob',
        );
        await authService.signIn();

        // Create a fresh instance of service on restart
        final newService = GoogleDriveAuthService(
          authService: authService,
          delegate: fakeDriveDelegate,
          storage: driveStorage,
        );
        await newService.init();

        // Bob must NOT inherit Alice's authorization
        expect(newService.isAuthorized, isFalse);
        expect(newService.status, DriveAuthStatus.notAuthorized);
        newService.dispose();
      },
    );

    test(
      '16. clearAuthorization clears state and deletes state file',
      () async {
        fakeSignInDelegate.mockUser = const AuthUser(
          id: 'u1',
          email: 'alice@gmail.com',
          displayName: 'Alice',
        );
        await authService.signIn();
        fakeDriveDelegate.driveScopeGranted = true;
        await driveAuthService.authorizeDrive();
        expect(driveAuthService.isAuthorized, isTrue);

        await driveAuthService.clearAuthorization();

        expect(driveAuthService.status, DriveAuthStatus.notAuthorized);
        expect(driveAuthService.isAuthorized, isFalse);

        final stateFile = File(await driveStorage.stateFilePath);
        expect(await stateFile.exists(), isFalse);
      },
    );
  });
}
