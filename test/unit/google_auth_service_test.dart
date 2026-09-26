import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/auth_status.dart';
import 'package:photo_per_day/data/models/auth_user.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/google_auth_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/data/services/sync_queue.dart';
import 'package:photo_per_day/data/services/sync_queue_storage.dart';

/// Test double implementing [GoogleSignInDelegate] with zero native or platform channel dependencies.
class FakeGoogleSignInDelegate implements GoogleSignInDelegate {
  AuthUser? mockUser;
  bool shouldThrowOnSignIn = false;
  bool shouldCancelOnSignIn = false;
  bool driveScopeGranted = true;

  @override
  Future<AuthUser?> signInSilently() async {
    return mockUser;
  }

  @override
  Future<AuthUser?> signIn() async {
    if (shouldThrowOnSignIn) {
      throw Exception('network_error: Simulated authentication network error');
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
  Future<bool> canAccessDriveScope() async {
    return driveScopeGranted;
  }

  @override
  Future<bool> requestDriveScope() async {
    return driveScopeGranted;
  }

  @override
  Future<Map<String, String>> getAuthHeaders() async {
    if (mockUser == null) {
      throw StateError('No Google account is currently signed in.');
    }
    return {
      'Authorization': 'Bearer fake_mock_access_token_for_tests',
      'X-Goog-AuthUser': '0',
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeGoogleSignInDelegate fakeDelegate;
  late GoogleAuthService authService;

  setUp(() {
    fakeDelegate = FakeGoogleSignInDelegate();
    authService = GoogleAuthService(delegate: fakeDelegate);
  });

  group('Milestone 18 — Google Sign-In Foundation Tests', () {
    group('1. Auth Domain Models', () {
      test('AuthStatus enum has expected values and helpers', () {
        expect(AuthStatus.signedOut.isSignedIn, isFalse);
        expect(AuthStatus.signedOut.isSigningIn, isFalse);

        expect(AuthStatus.signingIn.isSignedIn, isFalse);
        expect(AuthStatus.signingIn.isSigningIn, isTrue);

        expect(AuthStatus.signedIn.isSignedIn, isTrue);
        expect(AuthStatus.signedIn.isSigningIn, isFalse);

        expect(AuthStatus.error.isSignedIn, isFalse);
        expect(AuthStatus.error.isSigningIn, isFalse);
      });

      test(
        'AuthUser model stores public profile info and excludes sensitive tokens',
        () {
          const user = AuthUser(
            id: 'google_user_123',
            email: 'sarah.jenkins@example.com',
            displayName: 'Sarah Jenkins',
            photoUrl: 'https://example.com/avatar.jpg',
          );

          expect(user.id, 'google_user_123');
          expect(user.email, 'sarah.jenkins@example.com');
          expect(user.displayName, 'Sarah Jenkins');
          expect(user.photoUrl, 'https://example.com/avatar.jpg');
          expect(user.initials, 'SJ');

          // Verify equality and copyWith
          final copy = user.copyWith(displayName: 'Sarah J.');
          expect(copy.displayName, 'Sarah J.');
          expect(copy.email, 'sarah.jenkins@example.com');
          expect(copy == user, isFalse);
          expect(user == user.copyWith(), isTrue);
        },
      );

      test('AuthUser computes fallback initials correctly', () {
        const singleName = AuthUser(
          id: '1',
          email: 'single@example.com',
          displayName: 'Cher',
        );
        expect(singleName.initials, 'C');

        const noName = AuthUser(id: '2', email: 'anonymous@example.com');
        expect(noName.initials, 'A');
      });
    });

    group('2. GoogleAuthService State & Lifecycle', () {
      test('Initial state is signedOut before initialization', () {
        expect(authService.status, AuthStatus.signedOut);
        expect(authService.currentUser, isNull);
        expect(authService.isSignedIn, isFalse);
        expect(authService.errorMessage, isNull);
      });

      test(
        'Silent init restores existing signed-in session when available',
        () async {
          fakeDelegate.mockUser = const AuthUser(
            email: 'restored.user@gmail.com',
            id: 'restored_123',
            displayName: 'Restored User',
            photoUrl: 'https://example.com/photo.png',
          );

          await authService.init();

          expect(authService.status, AuthStatus.signedIn);
          expect(authService.isSignedIn, isTrue);
          expect(authService.currentUser!.email, 'restored.user@gmail.com');
          expect(authService.currentUser!.displayName, 'Restored User');
          expect(authService.errorMessage, isNull);
        },
      );

      test('Silent init remains signedOut when no session exists', () async {
        fakeDelegate.mockUser = null;

        await authService.init();

        expect(authService.status, AuthStatus.signedOut);
        expect(authService.isSignedIn, isFalse);
        expect(authService.currentUser, isNull);
      });

      test(
        'Successful interactive sign-in transitions from signedOut to signedIn',
        () async {
          fakeDelegate.mockUser = const AuthUser(
            email: 'active.user@gmail.com',
            id: 'active_456',
            displayName: 'Active User',
          );

          final user = await authService.signIn();

          expect(user, isNotNull);
          expect(user!.email, 'active.user@gmail.com');
          expect(authService.status, AuthStatus.signedIn);
          expect(authService.isSignedIn, isTrue);
          expect(authService.errorMessage, isNull);
        },
      );

      test(
        'User cancelling sign-in cleanly returns to signedOut without error',
        () async {
          fakeDelegate.shouldCancelOnSignIn = true;

          final user = await authService.signIn();

          expect(user, isNull);
          expect(authService.status, AuthStatus.signedOut);
          expect(authService.isSignedIn, isFalse);
          expect(authService.errorMessage, isNull);
        },
      );

      test(
        'Sign-in failure sets error state with user-safe message and no token leak',
        () async {
          fakeDelegate.shouldThrowOnSignIn = true;

          final user = await authService.signIn();

          expect(user, isNull);
          expect(authService.status, AuthStatus.error);
          expect(authService.isSignedIn, isFalse);
          expect(authService.errorMessage, isNotNull);
          expect(
            authService.errorMessage,
            contains('Network connection unavailable'),
          );
          // Guarantee no raw tokens or stack traces in error message
          expect(authService.errorMessage!.contains('access_token'), isFalse);
          expect(authService.errorMessage!.contains('id_token'), isFalse);
        },
      );

      test('Sign-out clears user and transitions state to signedOut', () async {
        fakeDelegate.mockUser = const AuthUser(
          email: 'to_sign_out@gmail.com',
          id: 'sign_out_789',
        );
        await authService.signIn();
        expect(authService.isSignedIn, isTrue);

        await authService.signOut();

        expect(authService.status, AuthStatus.signedOut);
        expect(authService.isSignedIn, isFalse);
        expect(authService.currentUser, isNull);
        expect(authService.errorMessage, isNull);
      });

      test('Disconnect revokes session and sets signedOut', () async {
        fakeDelegate.mockUser = const AuthUser(
          email: 'to_disconnect@gmail.com',
          id: 'disc_999',
        );
        await authService.signIn();
        expect(authService.isSignedIn, isTrue);

        await authService.disconnect();

        expect(authService.status, AuthStatus.signedOut);
        expect(authService.currentUser, isNull);
      });

      test(
        'Milestone 19 seam: requestDriveScope requests driveFileScope',
        () async {
          fakeDelegate.mockUser = const AuthUser(
            email: 'seam.user@gmail.com',
            id: 'seam_111',
          );
          await authService.signIn();

          final granted = await authService.requestDriveScope();
          expect(granted, isTrue);

          // Drive file scope is the exact required user-visible scope (not appdata)
          expect(
            GoogleAuthService.driveFileScope,
            'https://www.googleapis.com/auth/drive.file',
          );
        },
      );
    });

    group('3. Offline & Local Data Independence', () {
      late Directory tempDir;
      late PhotoFileManager fileManager;
      late PhotoMetadataStorage metadataStorage;
      late SyncQueue queue;
      late PersistentDailyPhotoStore store;

      setUp(() async {
        tempDir = Directory.systemTemp.createTempSync('m18_auth_local_');
        fileManager = PhotoFileManager(customBaseDir: tempDir);
        metadataStorage = PhotoMetadataStorage(customBaseDir: tempDir);
        queue = SyncQueue(storage: SyncQueueStorage(customBaseDir: tempDir));
        await queue.init();
        store = PersistentDailyPhotoStore(
          fileManager: fileManager,
          metadataStorage: metadataStorage,
          syncQueue: queue,
        );
        await store.init(customBaseDir: tempDir);
      });

      tearDown(() {
        try {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        } catch (_) {}
      });

      test(
        'Local photos remain completely accessible when signed out',
        () async {
          final date = DateTime(2026, 8, 1);
          final dummyFile = File('${tempDir.path}/test_source.jpg')
            ..writeAsStringSync('dummy_image_data');

          final entry = PhotoEntry(
            date: date,
            title: 'Offline Sunrise',
            syncStatus: SyncStatus.localOnly,
            gradientColors: const [Colors.amber, Colors.orange],
          );
          await store.savePhoto(entry: entry, sourceTempPath: dummyFile.path);

          // User is signed out
          expect(authService.isSignedIn, isFalse);

          // Photo diary operations work 100% locally
          expect(store.hasPhoto(date), isTrue);
          final photo = store.getPhoto(date);
          expect(photo!.title, 'Offline Sunrise');

          // Edits work while signed out
          await store.updatePhotoMetadata(
            dateKey: const DateKey(2026, 8, 1),
            title: 'Updated Offline Title',
          );
          expect(store.getPhoto(date)!.title, 'Updated Offline Title');
        },
      );

      test(
        'Signing in and signing out never modifies or deletes local photos or SyncQueue',
        () async {
          final date = DateTime(2026, 8, 2);
          final dummyFile = File('${tempDir.path}/test_source_2.jpg')
            ..writeAsStringSync('dummy_image_data_2');

          final entry = PhotoEntry(
            date: date,
            title: 'Preserved Photo',
            syncStatus: SyncStatus.pending,
            gradientColors: const [Colors.blue, Colors.indigo],
          );
          await store.savePhoto(entry: entry, sourceTempPath: dummyFile.path);
          await store.flush();

          expect(store.totalPhotos, 1);
          expect(store.syncQueue.count, 1);

          // Sign in
          fakeDelegate.mockUser = const AuthUser(
            email: 'login.test@gmail.com',
            id: 'login_123',
          );
          await authService.signIn();
          expect(authService.isSignedIn, isTrue);

          // Local photo and queue remain intact
          expect(store.totalPhotos, 1);
          expect(store.syncQueue.count, 1);

          // Sign out
          await authService.signOut();
          expect(authService.isSignedIn, isFalse);

          // Local photo and queue STILL remain intact
          expect(store.totalPhotos, 1);
          expect(store.getPhoto(date)!.title, 'Preserved Photo');
          expect(store.syncQueue.count, 1);
        },
      );

      test(
        'PhotoEntry and SyncQueue serialization contain zero OAuth tokens',
        () async {
          final entry = PhotoEntry(
            date: DateTime(2026, 8, 3),
            title: 'Security Verification',
            gradientColors: const [Colors.green, Colors.teal],
          );
          final json = entry.toJson();

          expect(json.containsKey('accessToken'), isFalse);
          expect(json.containsKey('refreshToken'), isFalse);
          expect(json.containsKey('idToken'), isFalse);
          expect(json.containsKey('oauthToken'), isFalse);
          expect(json.containsKey('serverAuthCode'), isFalse);

          final op = await queue.enqueueUpload(const DateKey(2026, 8, 3));
          final opJson = op.toJson();

          expect(opJson.containsKey('accessToken'), isFalse);
          expect(opJson.containsKey('refreshToken'), isFalse);
          expect(opJson.containsKey('idToken'), isFalse);
        },
      );
    });
  });
}
