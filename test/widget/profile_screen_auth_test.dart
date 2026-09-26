import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/auth_user.dart';
import 'package:photo_per_day/data/services/google_auth_service.dart';
import 'package:photo_per_day/screens/profile/profile_screen.dart';

class WidgetTestFakeGoogleSignInDelegate implements GoogleSignInDelegate {
  AuthUser? mockUser;
  bool shouldThrowOnSignIn = false;
  bool shouldCancelOnSignIn = false;

  @override
  Future<AuthUser?> signInSilently() async {
    return mockUser;
  }

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
  Future<bool> canAccessDriveScope() async {
    return false;
  }

  @override
  Future<bool> requestDriveScope() async {
    return true;
  }

  @override
  Future<Map<String, String>> getAuthHeaders() async {
    return {'Authorization': 'Bearer fake_token', 'X-Goog-AuthUser': '0'};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WidgetTestFakeGoogleSignInDelegate fakeDelegate;

  setUp(() async {
    fakeDelegate = WidgetTestFakeGoogleSignInDelegate();
    GoogleAuthService.instance.delegate = fakeDelegate;
    await GoogleAuthService.instance.signOut();
  });

  Widget createTestWidget() {
    return const MaterialApp(home: Scaffold(body: ProfileScreen()));
  }

  group('ProfileScreen Authentication UI Tests', () {
    testWidgets(
      'Renders signed-out state with Sign In action and unconnected status',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Account section in signed-out state
        expect(find.text('Google Account'), findsOneWidget);
        expect(
          find.text('Sign in to enable future cloud sync'),
          findsOneWidget,
        );
        expect(find.text('Sign In'), findsOneWidget);

        // Storage & Backup section does NOT claim photos are backed up
        expect(find.text('Not connected • Cloud storage'), findsOneWidget);
        expect(find.text('Connect'), findsOneWidget);
      },
    );

    testWidgets(
      'Tapping Sign In authenticates and updates UI to signed-in state',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        fakeDelegate.mockUser = const AuthUser(
          email: 'photodiary.user@gmail.com',
          id: 'user_456',
          displayName: 'Diary Creator',
        );

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Tap Sign In button
        final signInButton = find.text('Sign In');
        expect(signInButton, findsOneWidget);
        await tester.tap(signInButton);
        await tester.pumpAndSettle();

        // UI updates to signed-in user profile
        expect(find.text('Diary Creator'), findsOneWidget);
        expect(find.text('photodiary.user@gmail.com'), findsOneWidget);
        expect(find.text('Sign Out'), findsOneWidget);

        // Storage & Backup displays Drive Backup is not authorized yet without claiming backup is done
        expect(find.text('Not authorized • Cloud storage'), findsOneWidget);
        expect(find.text('Enable Drive Backup'), findsOneWidget);
      },
    );

    testWidgets('Tapping Sign Out cleanly returns UI to signed-out state', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      fakeDelegate.mockUser = const AuthUser(
        email: 'alice@gmail.com',
        id: 'user_alice',
        displayName: 'Alice M.',
      );

      // Sign in first
      await GoogleAuthService.instance.signIn();

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Verify signed-in
      expect(find.text('Alice M.'), findsOneWidget);
      final signOutButton = find.text('Sign Out');
      expect(signOutButton, findsOneWidget);

      // Tap Sign Out
      await tester.tap(signOutButton);
      await tester.pumpAndSettle();

      // Returns to signed-out state
      expect(find.text('Google Account'), findsOneWidget);
      expect(find.text('Sign in to enable future cloud sync'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('Displays Retry when sign-in encounters an error', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      fakeDelegate.shouldThrowOnSignIn = true;

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Tap Sign In which throws network error
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      // Error subtitle and Retry button appear
      expect(find.text('Retry'), findsOneWidget);
      expect(
        find.text(
          'Network connection unavailable. Please check your internet connection.',
        ),
        findsOneWidget,
      );
    });
  });
}
