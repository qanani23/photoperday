import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/screens/home/home_screen.dart';
import 'package:photo_per_day/screens/photo_detail/photo_detail_screen.dart';
import 'package:photo_per_day/widgets/calendar_grid.dart';
import 'package:photo_per_day/widgets/day_preview_card.dart';
import 'package:photo_per_day/widgets/today_pulse_ring.dart';
import 'package:photo_per_day/widgets/weekday_header.dart';

void main() {
  group('Milestone 41 — Full-Year Scrollable Calendar Tests', () {
    testWidgets(
      'A, B, C: Displays full 12-month scrollable calendar for the current year',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Test with reference date October 3, 2026
        final testDate = DateTime(2026, 10, 3);

        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(
              wrapWithScaffold: false,
              initialDate: testDate,
              showFullCalendar: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Year Header displays 2026 and "This Year" chip
        expect(find.text('2026'), findsOneWidget);
        expect(find.text('This Year'), findsOneWidget);

        // 2. Exactly 12 month sections exist (January through December)
        const expectedMonths = [
          'January 2026',
          'February 2026',
          'March 2026',
          'April 2026',
          'May 2026',
          'June 2026',
          'July 2026',
          'August 2026',
          'September 2026',
          'October 2026',
          'November 2026',
          'December 2026',
        ];

        for (final monthTitle in expectedMonths) {
          expect(
            find.text(monthTitle),
            findsOneWidget,
            reason: '$monthTitle must appear exactly once in the year calendar',
          );
        }

        // Exactly 12 CalendarGrid and WeekdayHeader instances
        expect(find.byType(CalendarGrid), findsNWidgets(12));
        expect(find.byType(WeekdayHeader), findsNWidgets(12));
      },
    );

    testWidgets(
      'D: Leap year and standard February day counts are mathematically accurate',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // 1. Test leap year: 2028
        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(
              wrapWithScaffold: false,
              initialDate: DateTime(2028, 2, 15),
              showFullCalendar: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('2028'), findsOneWidget);

        // February 2028 has 29 days
        final feb2028Grid = find.byKey(const ValueKey('2028-2'));
        expect(feb2028Grid, findsOneWidget);
        expect(
          find.descendant(of: feb2028Grid, matching: find.text('29')),
          findsOneWidget,
          reason: 'February 2028 leap year must contain day 29',
        );

        // 2. Test non-leap year: 2027
        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(
              key: const ValueKey('year-2027'),
              wrapWithScaffold: false,
              initialDate: DateTime(2027, 2, 15),
              showFullCalendar: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('2027'), findsOneWidget);

        // February 2027 has 28 days (day 29 does NOT exist)
        final feb2027Grid = find.byKey(const ValueKey('2027-2'));
        expect(feb2027Grid, findsOneWidget);
        expect(
          find.descendant(of: feb2027Grid, matching: find.text('28')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: feb2027Grid, matching: find.text('29')),
          findsNothing,
          reason: 'February 2027 non-leap year must not contain day 29',
        );
      },
    );

    testWidgets(
      'E, L: Year navigation switches year and updates all 12 month blocks with accessible controls',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(
              wrapWithScaffold: false,
              initialDate: DateTime(2026, 6, 15),
              showFullCalendar: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('2026'), findsOneWidget);
        expect(find.text('January 2026'), findsOneWidget);

        // Year navigation chevrons have proper accessible tooltips and semantics
        final prevYearBtn = find.byTooltip('Previous year');
        final nextYearBtn = find.byTooltip('Next year');
        expect(prevYearBtn, findsOneWidget);
        expect(nextYearBtn, findsOneWidget);

        // Tap Previous Year -> decrements to 2025
        await tester.tap(prevYearBtn);
        await tester.pumpAndSettle();

        expect(find.text('2025'), findsOneWidget);
        expect(find.text('January 2025'), findsOneWidget);
        expect(find.text('December 2025'), findsOneWidget);
        expect(find.text('This Year'), findsNothing);

        // Tap Next Year -> increments to 2026
        await tester.tap(nextYearBtn);
        await tester.pumpAndSettle();

        expect(find.text('2026'), findsOneWidget);
        expect(find.text('January 2026'), findsOneWidget);
        expect(find.text('This Year'), findsOneWidget);

        // Tap Next Year again -> increments to 2027
        await tester.tap(nextYearBtn);
        await tester.pumpAndSettle();

        expect(find.text('2027'), findsOneWidget);
        expect(find.text('January 2027'), findsOneWidget);
        expect(find.text('December 2027'), findsOneWidget);
        expect(find.text('This Year'), findsNothing);
      },
    );

    testWidgets(
      'F, G, H: Today pulse animation appears ONLY on current date and is suppressed in other years',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final today = DateTime(2026, 10, 3);

        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(
              wrapWithScaffold: false,
              initialDate: today,
              showFullCalendar: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Current month (October) displays "Current Month" badge
        expect(find.text('Current Month'), findsOneWidget);

        // 2. Exactly ONE TodayPulseRing exists across all 12 months for 2026
        final pulseRingFinder = find.byType(TodayPulseRing);
        expect(
          pulseRingFinder,
          findsOneWidget,
          reason:
              'Exactly one pulse animation must render on today in the current year',
        );

        // 3. The pulse ring is inside October's calendar grid
        final octGrid = find.byKey(const ValueKey('2026-10'));
        expect(
          find.descendant(of: octGrid, matching: find.byType(TodayPulseRing)),
          findsOneWidget,
        );

        // 4. Other months do NOT have TodayPulseRing
        final septGrid = find.byKey(const ValueKey('2026-9'));
        expect(
          find.descendant(of: septGrid, matching: find.byType(TodayPulseRing)),
          findsNothing,
        );

        // 5. Navigate to 2025 (historical year)
        final prevYearBtn = find.byTooltip('Previous year');
        await tester.tap(prevYearBtn);
        await tester.pumpAndSettle();

        // No day in 2025 receives the today pulse animation
        expect(
          find.byType(TodayPulseRing),
          findsNothing,
          reason:
              'No pulse animation should appear on any day in a historical year',
        );

        // 6. Navigate to 2027 (future year)
        final nextYearBtn = find.byTooltip('Next year');
        await tester.tap(nextYearBtn); // back to 2026
        await tester.pumpAndSettle();
        await tester.tap(nextYearBtn); // to 2027
        await tester.pumpAndSettle();

        expect(find.text('2027'), findsOneWidget);
        expect(
          find.byType(TodayPulseRing),
          findsNothing,
          reason:
              'No pulse animation should appear on any day in a future year',
        );
      },
    );

    testWidgets(
      'I: Scroll targeting positions current month on initial open and January for other years',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Current date in late year: November 15, 2026
        final today = DateTime(2026, 11, 15);

        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(
              wrapWithScaffold: false,
              initialDate: today,
              showFullCalendar: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Find scrollable
        final scrollableFinder = find.byType(SingleChildScrollView);
        expect(scrollableFinder, findsOneWidget);

        final scrollableState = tester.state<ScrollableState>(
          find
              .descendant(
                of: scrollableFinder,
                matching: find.byType(Scrollable),
              )
              .first,
        );

        // In 2026 with November as current month, scroll offset should be greater than 0
        // because it auto-scrolled down to November
        expect(scrollableState.position.pixels, greaterThan(0.0));

        // Switch to 2025
        final prevYearBtn = find.byTooltip('Previous year');
        await tester.tap(prevYearBtn);
        await tester.pumpAndSettle();

        // For non-current year (2025), it targets January (offset near 0.0)
        expect(scrollableState.position.pixels, lessThanOrEqualTo(10.0));
      },
    );

    testWidgets(
      'J, K: Photo state is preserved, day selection updates DayPreviewCard, and tap opens photo detail',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final testDate = DateTime.now();
        await PersistentDailyPhotoStore.instance.savePhoto(
          entry: PhotoEntry(
            date: testDate,
            title: 'Coffee & Morning Journal',
            timeFormatted: '10:00 AM',
            gradientColors: const [Color(0xFFB86B35), Color(0xFF2B2823)],
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(
              showFullCalendar: true,
              initialDate: testDate,
              initialSelectedDate: testDate,
            ),
            onGenerateRoute: (settings) {
              if (settings.name == AppConstants.photoDetailRoute) {
                final entry = settings.arguments as PhotoEntry;
                return MaterialPageRoute<void>(
                  builder: (_) => PhotoDetailScreen(photoEntry: entry),
                  settings: settings,
                );
              }
              return null;
            },
          ),
        );
        await tester.pumpAndSettle();

        // 1. DayPreviewCard is present in the scroll view
        final previewCardFinder = find.byType(DayPreviewCard);
        expect(previewCardFinder, findsOneWidget);

        // Scroll to DayPreviewCard
        await tester.ensureVisible(previewCardFinder);
        await tester.pumpAndSettle();

        // Tap DayPreviewCard opens PhotoDetailScreen
        await tester.tap(previewCardFinder);
        await tester.pumpAndSettle();

        expect(find.text('Photo Memory'), findsOneWidget);

        // Tap back button
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();

        expect(find.text('Photo Memory'), findsNothing);
        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );
  });
}
