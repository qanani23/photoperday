import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/auth_user.dart';
import 'package:photo_per_day/data/services/drive_auth_storage.dart';
import 'package:photo_per_day/data/services/google_auth_service.dart';
import 'package:photo_per_day/data/services/google_drive_auth_service.dart';
import 'package:photo_per_day/screens/profile/profile_screen.dart';

class WidgetTestFakeGoogleSignInDelegate implements GoogleSignInDelegate {
  AuthUser? mockUser;
  bool shouldThrowOnSignIn = false;
  bool shouldCancelOnSignIn = false;

  @override
  Future<AuthUser?> signInSilently() async => mockUser;

  @override
  Future<AuthUser?> signIn() async {
    if (shouldThrowOnSignIn) throw Exception('network_error');
    if (shouldCancelOnSignIn) return null;
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
  Future<bool> canAccessDriveScope() async => false;

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
  bool shouldThrow = false;
  int requestScopeCalls = 0;

  @override
  Future<bool> canAccessDriveScope() async => false;

  @override
  Future<bool> requestDriveScope() async {
    requestScopeCalls++;
    if (shouldThrow) {
      throw Exception('network_error: connection reset');
    }
    return driveScopeGranted;
  }

  @override
  Future<Map<String, String>> getAuthHeaders() async => {
    'Authorization': 'Bearer fake_token',
    'X-Goog-AuthUser': '0',
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late WidgetTestFakeGoogleSignInDelegate fakeSignInDelegate;
  late WidgetTestFakeDriveAuthDelegate fakeDriveDelegate;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('widget_drive_auth_');
    fakeSignInDelegate = WidgetTestFakeGoogleSignInDelegate();
    GoogleAuthService.instance.delegate = fakeSignInDelegate;
    await GoogleAuthService.instance.signOut();

    fakeDriveDelegate = WidgetTestFakeDriveAuthDelegate();
    GoogleDriveAuthService.instance.delegate = fakeDriveDelegate;
    GoogleDriveAuthService.instance.storage = DriveAuthStorage(
      customBaseDir: tempDir.path,
    );
    await GoogleDriveAuthService.instance.clearAuthorization();
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  Widget createTestWidget() {
    return const MaterialApp(home: Scaffold(body: ProfileScreen()));
  }

  group('ProfileScreen Google Drive Authorization UI Tests', () {
    testWidgets(
      '1. Signed-out state displays Not connected and Connect button',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Google Drive Backup'), findsOneWidget);
        expect(find.text('Not connected • Cloud storage'), findsOneWidget);
        expect(find.text('Connect'), findsOneWidget);
      },
    );

    testWidgets(
      '2. Signed-in but not authorized displays Not authorized and Enable Drive Backup button',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        fakeSignInDelegate.mockUser = const AuthUser(
          id: 'user_1',
          email: 'photodiary@example.com',
          displayName: 'Diary Author',
        );
        await GoogleAuthService.instance.signIn();

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Google Drive Backup'), findsOneWidget);
        expect(find.text('Not authorized • Cloud storage'), findsOneWidget);
        expect(find.text('Enable Drive Backup'), findsOneWidget);
      },
    );

    testWidgets(
      '3. Tapping Enable Drive Backup grants access and updates UI to Authorized',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        fakeSignInDelegate.mockUser = const AuthUser(
          id: 'user_1',
          email: 'photodiary@example.com',
          displayName: 'Diary Author',
        );
        await GoogleAuthService.instance.signIn();
        fakeDriveDelegate.driveScopeGranted = true;

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Tap Enable Drive Backup
        final enableButton = find.text('Enable Drive Backup');
        expect(enableButton, findsOneWidget);
        await tester.tap(enableButton);
        await tester.pumpAndSettle();

        // UI updates to Authorized state with setup required
        expect(find.text('Drive authorized • Setup required'), findsOneWidget);
        expect(find.text('Set Up'), findsOneWidget);
        // Explicitly verifies we do NOT claim photos are backed up
        expect(find.text('Backed up'), findsNothing);
      },
    );

    testWidgets(
      '4. Denial of Drive permission displays Permission denied and Authorize action',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        fakeSignInDelegate.mockUser = const AuthUser(
          id: 'user_1',
          email: 'photodiary@example.com',
          displayName: 'Diary Author',
        );
        await GoogleAuthService.instance.signIn();
        fakeDriveDelegate.driveScopeGranted = false;

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Enable Drive Backup'));
        await tester.pumpAndSettle();

        expect(
          find.text('Permission denied • Tap to authorize'),
          findsOneWidget,
        );
        expect(find.text('Authorize'), findsOneWidget);
      },
    );

    testWidgets(
      '5. Network error during Drive authorization displays error subtitle and Retry',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        fakeSignInDelegate.mockUser = const AuthUser(
          id: 'user_1',
          email: 'photodiary@example.com',
          displayName: 'Diary Author',
        );
        await GoogleAuthService.instance.signIn();
        fakeDriveDelegate.shouldThrow = true;

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Enable Drive Backup'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Network connection unavailable. Please check your internet connection.',
          ),
          findsAtLeastNWidgets(1),
        );
        expect(find.text('Retry'), findsOneWidget);
      },
    );

    testWidgets(
      '6. Signing out returns Drive Backup card to signed-out state',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        fakeSignInDelegate.mockUser = const AuthUser(
          id: 'user_1',
          email: 'photodiary@example.com',
          displayName: 'Diary Author',
        );
        await GoogleAuthService.instance.signIn();
        fakeDriveDelegate.driveScopeGranted = true;
        await GoogleDriveAuthService.instance.authorizeDrive();

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Drive authorized • Setup required'), findsOneWidget);

        final signOutFinder = find.text('Sign Out');
        expect(signOutFinder, findsOneWidget);
        await tester.tap(signOutFinder);
        await tester.pumpAndSettle();

        // Both Google Account and Drive Backup are back to signed-out state
        expect(find.text('Not connected • Cloud storage'), findsOneWidget);
        expect(find.text('Connect'), findsOneWidget);
        expect(find.text('Google Account'), findsOneWidget);
        expect(find.text('Sign In'), findsOneWidget);
      },
    );
  });
}
