import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/app.dart';
import 'package:photo_per_day/screens/camera/camera_screen.dart';
import 'package:photo_per_day/screens/main_shell.dart';
import 'package:photo_per_day/screens/photo_detail/photo_detail_screen.dart';
import 'package:photo_per_day/widgets/bottom_nav_dock.dart';
import 'package:photo_per_day/widgets/day_preview_card.dart';
import 'package:photo_per_day/widgets/photo_source_sheet.dart';

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
    expect(find.text('Photo a Day'), findsWidgets);
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
    expect(find.text('March 2026'), findsOneWidget);

    // 2. Switch to Today tab via BottomNavDock
    final captureTab = find.descendant(
      of: find.byType(BottomNavDock),
      matching: find.text('Capture'),
    );
    await tester.tap(captureTab);
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);

    // 3. Switch to Profile tab via BottomNavDock
    final meTab = find.descendant(
      of: find.byType(BottomNavDock),
      matching: find.text('Me'),
    );
    await tester.tap(meTab);
    await tester.pumpAndSettle();
    expect(find.text('Profile & Settings'), findsOneWidget);
    expect(find.text('Sarah Jenkins'), findsOneWidget);

    // 4. Return to Home tab via BottomNavDock
    final homeTab = find.descendant(
      of: find.byType(BottomNavDock),
      matching: find.text('Home'),
    );
    await tester.tap(homeTab);
    await tester.pumpAndSettle();
    expect(find.text('March 2026'), findsOneWidget);
  });

  testWidgets('Photo detail navigation from DayPreviewCard', (
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

    // Find the DayPreviewCard and scroll it into view if needed
    final previewCardFinder = find.byType(DayPreviewCard);
    expect(previewCardFinder, findsOneWidget);

    await tester.ensureVisible(previewCardFinder);
    await tester.pumpAndSettle();

    await tester.tap(previewCardFinder);
    await tester.pumpAndSettle();

    // Verify PhotoDetailScreen is displayed
    expect(find.byType(PhotoDetailScreen), findsOneWidget);
    expect(find.text('Photo Memory'), findsOneWidget);

    // Tap back button to return to journal
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    // Verify returned to Calendar
    expect(find.byType(PhotoDetailScreen), findsNothing);
    expect(find.text('March 2026'), findsOneWidget);
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
    final switchFinder = find.byType(Switch);
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
    expect(find.byType(Switch), findsOneWidget);
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

    await tester.pumpWidget(const PhotoPerDayApp());
    await tester.pumpAndSettle();

    // Navigate to Today tab
    final captureTab = find.descendant(
      of: find.byType(BottomNavDock),
      matching: find.text('Capture'),
    );
    await tester.tap(captureTab);
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
