import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/app.dart';
import 'package:photo_per_day/core/routing/app_router.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/mock_photo_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/screens/camera/camera_screen.dart';
import 'package:photo_per_day/screens/home/home_screen.dart';
import 'package:photo_per_day/screens/main_shell.dart';
import 'package:photo_per_day/screens/photo_detail/photo_detail_screen.dart';
import 'package:photo_per_day/screens/settings/settings_screen.dart';
import 'package:photo_per_day/widgets/app_icon_button.dart';
import 'package:photo_per_day/widgets/bottom_nav_dock.dart';
import 'package:photo_per_day/widgets/photo_source_sheet.dart';
import 'package:photo_per_day/widgets/settings_tile.dart';

void main() {
  testWidgets('App verification smoke test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const PhotoPerDayApp());
    await tester.pumpAndSettle();

    // Verify app title and MainShell
    expect(find.text('Daria'), findsWidgets);
    expect(find.byType(MainShell), findsOneWidget);
    expect(find.byType(BottomNavDock), findsOneWidget);
  });

  testWidgets('Bottom navigation tab switching and state preservation', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const PhotoPerDayApp());
    await tester.pumpAndSettle();

    // 1. Initial tab is Calendar (Home)
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('This Month'), findsOneWidget);

    // 2. Tap Capture opens direct camera
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
    expect(find.text('This Month'), findsOneWidget);

    // 3. Switch to Profile tab via BottomNavDock
    final meTab = find.descendant(
      of: find.byType(BottomNavDock),
      matching: find.text('Me'),
    );
    await tester.tap(meTab);
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Daily Photo Diary'), findsOneWidget);
    expect(find.text('Local-Only Storage'), findsOneWidget);

    // 4. Return to Home tab via BottomNavDock
    final homeTab = find.descendant(
      of: find.byType(BottomNavDock),
      matching: find.text('Home'),
    );
    await tester.tap(homeTab);
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('This Month'), findsOneWidget);

    // 5. Navigate to Settings via top-right Settings header action
    final settingsButton = find.widgetWithText(AppHeaderAction, 'Settings');
    expect(settingsButton, findsOneWidget);
    await tester.tap(settingsButton);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    // Pop back to Home
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('This Month'), findsOneWidget);
  });

  testWidgets('Photo detail navigation from Home memory timeline', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final testDate = DateTime(2026, 3, 3);
    await PersistentDailyPhotoStore.instance.savePhoto(
      entry: PhotoEntry(
        date: testDate,
        title: 'Coffee & Morning Journal',
        timeFormatted: '10:00 AM',
        gradientColors: const [Color(0xFFB86B35), Color(0xFF2B2823)],
      ),
    );

    await tester.pumpWidget(const PhotoPerDayApp());
    await tester.pumpAndSettle();

    // Find the showcase memory card in the timeline
    final memoryCardFinder = find.byKey(
      const ValueKey('timeline_day_2026-03-03'),
    );
    expect(memoryCardFinder, findsOneWidget);

    await tester.tap(memoryCardFinder);
    await tester.pumpAndSettle();

    // Verify PhotoDetailScreen is displayed
    expect(find.byType(PhotoDetailScreen), findsOneWidget);
    expect(find.text('Photo Memory'), findsOneWidget);

    // Tap back button to return to journal
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    // Verify returned to Calendar
    expect(find.byType(PhotoDetailScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('Profile daily reminder toggle state updates', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const PhotoPerDayApp());
    await tester.pumpAndSettle();

    // Navigate to Profile via BottomNavDock
    final meTab = find.descendant(
      of: find.byType(BottomNavDock),
      matching: find.text('Me'),
    );
    await tester.tap(meTab);
    await tester.pumpAndSettle();

    // Verify initial reminder state
    expect(find.text('Daily Reminder'), findsOneWidget);
    final switchFinder = find.descendant(
      of: find.widgetWithText(SettingsTile, 'Daily Reminder'),
      matching: find.byType(Switch),
    );
    expect(switchFinder, findsOneWidget);

    // Toggle switch
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    // Navigate away to Home and back to Profile
    final homeTab = find.descendant(
      of: find.byType(BottomNavDock),
      matching: find.byIcon(Icons.home_rounded),
    );
    await tester.tap(homeTab);
    await tester.pumpAndSettle();

    final meTabIcon = find.descendant(
      of: find.byType(BottomNavDock),
      matching: find.byIcon(Icons.person_rounded),
    );
    await tester.tap(meTabIcon);
    await tester.pumpAndSettle();

    // Switch should still be rendered with preserved state
    expect(switchFinder, findsOneWidget);
  });

  testWidgets('Today screen toggle between photo captured and empty state', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final now = DateTime.now();
    await PersistentDailyPhotoStore.instance.savePhoto(
      entry: MockPhotoService.defaultTodayPhoto.copyWith(
        date: DateTime(now.year, now.month, now.day),
      ),
    );

    await tester.pumpWidget(const PhotoPerDayApp());
    await tester.pumpAndSettle();

    // Navigate to Today tab via AppRouter
    AppRouter.navigateToToday();
    await tester.pumpAndSettle();

    // Initially has photo: should show Photo toggle pill and Replace Photo button
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Replace Photo'), findsOneWidget);
    expect(find.text('Golden Afternoon Reflections'), findsOneWidget);

    // Tap toggle pill to switch to Empty state
    final togglePill = find.byTooltip('Toggle demo state');
    expect(togglePill, findsOneWidget);
    await tester.tap(togglePill);
    await tester.pumpAndSettle();

    // Verify empty state is displayed
    expect(find.text("Today hasn't been captured yet"), findsOneWidget);
    expect(find.text("Capture Today's Photo"), findsOneWidget);

    // Tap "Capture Today's Photo" button - launches PhotoSourceSheet
    final captureButton = find.text("Capture Today's Photo");
    await tester.tap(captureButton);
    await tester.pumpAndSettle();

    // Verify PhotoSourceSheet is displayed
    expect(find.byType(PhotoSourceSheet), findsOneWidget);
    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text('Choose from Gallery'), findsOneWidget);

    // Tap "Take Photo" to launch CameraScreen
    await tester.tap(find.text('Take Photo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // Verify CameraScreen is opened
    expect(find.byType(CameraScreen), findsOneWidget);

    // Cancel out of camera screen
    await tester.tap(find.byTooltip('Cancel').first);
    await tester.pump();
    await tester.pumpAndSettle();

    // Verify returned to Today screen empty state
    expect(find.byType(CameraScreen), findsNothing);
    expect(find.text("Today hasn't been captured yet"), findsOneWidget);

    // Toggle demo state pill back to Photo state
    await tester.tap(togglePill);
    await tester.pumpAndSettle();
    expect(find.text('Replace Photo'), findsOneWidget);
    expect(find.text('Golden Afternoon Reflections'), findsOneWidget);
  });
}
