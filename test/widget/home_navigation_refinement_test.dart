import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/app.dart';
import 'package:photo_per_day/screens/camera/camera_screen.dart';
import 'package:photo_per_day/screens/diary/visual_diary_screen.dart';
import 'package:photo_per_day/screens/home/home_screen.dart';
import 'package:photo_per_day/screens/profile/profile_screen.dart';
import 'package:photo_per_day/screens/settings/settings_screen.dart';
import 'package:photo_per_day/widgets/app_header.dart';
import 'package:photo_per_day/widgets/app_icon_button.dart';
import 'package:photo_per_day/widgets/bottom_nav_dock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {});

  group('Milestone 40 — Navigation & Profile/Settings UI Refinement Tests', () {
    testWidgets(
      '1. Top-right button is Settings with gear icon and label, navigating to SettingsScreen',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(const PhotoPerDayApp());
        await tester.pumpAndSettle();

        // Check top-right header action
        final settingsAction = find.widgetWithText(AppHeaderAction, 'Settings');
        expect(settingsAction, findsOneWidget);

        // Verify gear/settings icon inside the action
        final settingsIcon = find.descendant(
          of: settingsAction,
          matching: find.byIcon(Icons.settings_rounded),
        );
        expect(settingsIcon, findsOneWidget);

        // Verify "Me" is NO LONGER in the top-right AppHeader
        final headerFinder = find.byType(AppHeader);
        expect(headerFinder, findsOneWidget);
        final meInHeader = find.descendant(
          of: headerFinder,
          matching: find.text('Me'),
        );
        expect(meInHeader, findsNothing);

        // Tap Settings button -> Navigates to SettingsScreen
        await tester.tap(settingsAction);
        await tester.pumpAndSettle();

        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(find.text('APP PREFERENCES & CONFIGURATION'), findsOneWidget);

        // Tap Back -> returns to Home
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsScreen), findsNothing);
        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );

    testWidgets('2. Bottom "Me" button navigates to dedicated ProfileScreen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const PhotoPerDayApp());
      await tester.pumpAndSettle();

      // Bottom dock contains Me tab
      final bottomDock = find.byType(BottomNavDock);
      final meTab = find.descendant(of: bottomDock, matching: find.text('Me'));
      expect(meTab, findsOneWidget);

      // Tap Me tab
      await tester.tap(meTab);
      await tester.pumpAndSettle();

      // Verifies destination is dedicated Profile screen
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Personal Diary & Preferences'), findsOneWidget);

      // Verifies Settings screen is NOT opened
      expect(find.byType(SettingsScreen), findsNothing);
    });

    testWidgets(
      '3. Bottom Center Capture button has ONLY ONE camera icon and label Capture',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(const PhotoPerDayApp());
        await tester.pumpAndSettle();

        final bottomDock = find.byType(BottomNavDock);
        expect(bottomDock, findsOneWidget);

        // Find the center Capture button
        final captureButton = find.descendant(
          of: bottomDock,
          matching: find.text('Capture'),
        );
        expect(captureButton, findsOneWidget);

        // Check that extra gallery and flare/sun icons do NOT exist in the bottom dock
        expect(
          find.descendant(
            of: bottomDock,
            matching: find.byIcon(Icons.photo_library_outlined),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: bottomDock,
            matching: find.byIcon(Icons.flare_rounded),
          ),
          findsNothing,
        );

        // The center button contains camera_alt_rounded
        expect(
          find.descendant(
            of: bottomDock,
            matching: find.byIcon(Icons.camera_alt_rounded),
          ),
          findsOneWidget,
        );

        // Exactly ONE icon per destination:
        // Tab 0: Home -> Icons.home_rounded
        expect(
          find.descendant(
            of: bottomDock,
            matching: find.byIcon(Icons.home_rounded),
          ),
          findsOneWidget,
        );
        // Tab 1: Capture -> Icons.camera_alt_rounded
        expect(
          find.descendant(
            of: bottomDock,
            matching: find.byIcon(Icons.camera_alt_rounded),
          ),
          findsOneWidget,
        );
        // Tab 2: Me -> Icons.person_rounded
        expect(
          find.descendant(
            of: bottomDock,
            matching: find.byIcon(Icons.person_rounded),
          ),
          findsOneWidget,
        );

        // Tapping Capture launches direct camera capture flow
        await tester.tap(captureButton);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(CameraScreen), findsOneWidget);

        // Pop back to Home
        await tester.tap(find.byTooltip('Cancel').first);
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );

    testWidgets(
      '4. Profile screen renders local diary hub with private local storage indication',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: ProfileScreen())),
        );
        await tester.pumpAndSettle();

        // Title & subtitle
        expect(find.text('Profile'), findsOneWidget);
        expect(find.text('Personal Diary & Preferences'), findsOneWidget);

        // Profile identity card
        expect(find.text('Daily Photo Diary'), findsOneWidget);
        expect(
          find.text('Stored on device • Private & offline'),
          findsOneWidget,
        );
        expect(find.text('Active Local Diary'), findsOneWidget);

        // Local storage card
        expect(find.text('Local-Only Storage'), findsOneWidget);
        expect(find.text('On Device Only'), findsOneWidget);
      },
    );

    testWidgets(
      '6. Navigation consistency: Home -> Diary, Home -> Settings, Home -> Capture, Bottom -> Profile',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(const PhotoPerDayApp());
        await tester.pumpAndSettle();

        // Diary button opens VisualDiaryScreen
        final diaryButton = find.widgetWithText(AppHeaderAction, 'Diary >');
        expect(diaryButton, findsOneWidget);
        await tester.tap(diaryButton);
        await tester.pumpAndSettle();
        expect(find.byType(VisualDiaryScreen), findsOneWidget);

        // Pop back to Home
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);

        // Settings button opens SettingsScreen
        final settingsButton = find.widgetWithText(AppHeaderAction, 'Settings');
        expect(settingsButton, findsOneWidget);
        await tester.tap(settingsButton);
        await tester.pumpAndSettle();
        expect(find.byType(SettingsScreen), findsOneWidget);

        // Pop back to Home
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);

        // Bottom Capture opens direct camera screen
        final captureTab = find.descendant(
          of: find.byType(BottomNavDock),
          matching: find.text('Capture'),
        );
        await tester.tap(captureTab);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(CameraScreen), findsOneWidget);

        // Pop back to Home from camera
        await tester.tap(find.byTooltip('Cancel').first);
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);

        // Bottom Me opens Profile tab
        final meTab = find.descendant(
          of: find.byType(BottomNavDock),
          matching: find.text('Me'),
        );
        await tester.tap(meTab);
        await tester.pumpAndSettle();
        expect(find.byType(ProfileScreen), findsOneWidget);

        // Bottom Home returns to Home
        final homeTab = find.descendant(
          of: find.byType(BottomNavDock),
          matching: find.text('Home'),
        );
        await tester.tap(homeTab);
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );
  });
}
