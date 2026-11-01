import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/app.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/core/routing/app_router.dart';
import 'package:photo_per_day/data/services/onboarding_service.dart';
import 'package:photo_per_day/data/services/onboarding_storage.dart';
import 'package:photo_per_day/screens/main_shell.dart';
import 'package:photo_per_day/screens/onboarding/onboarding_data.dart';
import 'package:photo_per_day/screens/onboarding/onboarding_screen.dart';
import 'package:photo_per_day/screens/onboarding/widgets/onboarding_page_widget.dart';

class FakeOnboardingStorage extends OnboardingStorage {
  bool _completed = false;

  @override
  Future<bool> loadCompleted() async => _completed;

  @override
  Future<void> saveCompleted({required bool completed}) async {
    _completed = completed;
  }

  @override
  Future<void> clear() async {
    _completed = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeOnboardingStorage storage;
  late OnboardingService service;

  setUp(() {
    storage = FakeOnboardingStorage();
    service = OnboardingService(storage: storage);
    OnboardingService.setTestInstance(service);
  });

  tearDown(() {
    OnboardingService.resetTestInstance();
  });

  group('Milestone 46 — 3-Screen Onboarding Experience Tests', () {
    testWidgets('1. onboarding opens correctly for a new user', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // New user: onboarding not completed
      service.setCompletedInMemory(false);

      await tester.pumpWidget(const PhotoPerDayApp());
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(MainShell), findsNothing);
      expect(find.text('One photo. Every day.'), findsOneWidget);
    });

    testWidgets('2. Screen 1 renders', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      service.setCompletedInMemory(false);

      await tester.pumpWidget(const PhotoPerDayApp());
      await tester.pumpAndSettle();

      // Verify title, description, and image
      expect(find.text('One photo. Every day.'), findsOneWidget);
      expect(
        find.text(
          'Turn everyday moments into a visual diary, one photo at a time.',
        ),
        findsOneWidget,
      );
      expect(find.byType(OnboardingPageWidget), findsWidgets);
    });

    testWidgets('3. Screen 2 renders', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      service.setCompletedInMemory(false);

      await tester.pumpWidget(const PhotoPerDayApp());
      await tester.pumpAndSettle();

      // Advance to page 2 via Next button
      final nextIcon = find.byIcon(Icons.arrow_forward_rounded);
      await tester.tap(nextIcon);
      await tester.pumpAndSettle();

      expect(find.text('Your life, in photos.'), findsOneWidget);
      expect(
        find.text(OnboardingPageData.pages[1].description),
        findsOneWidget,
      );
    });

    testWidgets('4. Screen 3 renders', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      service.setCompletedInMemory(false);

      await tester.pumpWidget(const PhotoPerDayApp());
      await tester.pumpAndSettle();

      // Advance to page 2 then page 3
      final nextIcon = find.byIcon(Icons.arrow_forward_rounded);
      await tester.tap(nextIcon);
      await tester.pumpAndSettle();

      await tester.tap(nextIcon);
      await tester.pumpAndSettle();

      expect(find.text('Make every day count.'), findsOneWidget);
      expect(
        find.text(
          'Build a lasting collection of memories and see your photo streak grow over time.',
        ),
        findsOneWidget,
      );
      expect(find.text('Start My Diary'), findsOneWidget);
    });

    testWidgets('5. Next moves to the next page', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      service.setCompletedInMemory(false);

      await tester.pumpWidget(const PhotoPerDayApp());
      await tester.pumpAndSettle();

      // Page 1
      expect(find.text('One photo. Every day.'), findsOneWidget);
      expect(find.text('Your life, in photos.'), findsNothing);

      // Tap Next -> moves to Page 2
      await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Your life, in photos.'), findsOneWidget);

      // Tap Next -> moves to Page 3
      await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Make every day count.'), findsOneWidget);
    });

    testWidgets('6. Skip exits onboarding', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      service.setCompletedInMemory(false);

      await tester.pumpWidget(const PhotoPerDayApp());
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsOneWidget);

      // Tap Skip on Screen 1
      final skipButton = find.text('Skip');
      expect(skipButton, findsOneWidget);
      await tester.tap(skipButton);
      await tester.pumpAndSettle();

      // Onboarding exits and MainShell is displayed
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(MainShell), findsOneWidget);
      expect(service.hasCompletedOnboarding, isTrue);
    });

    testWidgets('7. Get Started exits onboarding', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      service.setCompletedInMemory(false);

      await tester.pumpWidget(const PhotoPerDayApp());
      await tester.pumpAndSettle();

      // Navigate to Screen 3
      final nextIcon = find.byIcon(Icons.arrow_forward_rounded);
      await tester.tap(nextIcon);
      await tester.pumpAndSettle();
      await tester.tap(nextIcon);
      await tester.pumpAndSettle();

      // Tap "Start My Diary"
      final startCta = find.text('Start My Diary');
      expect(startCta, findsOneWidget);
      await tester.tap(startCta);
      await tester.pumpAndSettle();

      // Exits onboarding into MainShell
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(MainShell), findsOneWidget);
      expect(service.hasCompletedOnboarding, isTrue);
    });

    testWidgets('8. page indicator reflects the current page', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      service.setCompletedInMemory(false);

      await tester.pumpWidget(const PhotoPerDayApp());
      await tester.pumpAndSettle();

      // Page indicator is present
      final indicatorFinder = find.byKey(
        const ValueKey('onboarding_page_indicator'),
      );
      expect(indicatorFinder, findsOneWidget);

      // On page 1, active pill width is 24.0
      AnimatedContainer activeDot = tester.widget<AnimatedContainer>(
        find.descendant(
          of: indicatorFinder,
          matching: find.byWidgetPredicate(
            (w) => w is AnimatedContainer && (w.constraints?.maxWidth == 24.0),
          ),
        ),
      );
      expect(activeDot.constraints?.maxWidth, 24.0);

      // Move to page 2
      await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
      await tester.pumpAndSettle();

      // Page 2 active indicator
      expect(indicatorFinder, findsOneWidget);
    });

    testWidgets('9. onboarding completion is persisted', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Storage initially uncompleted
      await storage.saveCompleted(completed: false);
      await service.init();
      expect(service.hasCompletedOnboarding, isFalse);

      await tester.pumpWidget(const PhotoPerDayApp());
      await tester.pumpAndSettle();

      // Tap Skip
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      // Check on disk that completion is persisted
      final persisted = await storage.loadCompleted();
      expect(persisted, isTrue);
    });

    testWidgets('10. completed onboarding does not appear again', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Set storage to already completed
      await storage.saveCompleted(completed: true);
      await service.init();
      expect(service.hasCompletedOnboarding, isTrue);

      await tester.pumpWidget(const PhotoPerDayApp());
      await tester.pumpAndSettle();

      // Immediately lands on MainShell, skipping onboarding completely
      expect(find.byType(MainShell), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
    });

    testWidgets('11. onboarding can coexist with existing navigation', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Even if completed, user or dev can navigate to onboarding route
      service.setCompletedInMemory(true);

      await tester.pumpWidget(
        const PhotoPerDayApp(initialRoute: AppConstants.onboardingRoute),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('One photo. Every day.'), findsOneWidget);

      // Exiting via Skip returns user to initialRoute
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.byType(MainShell), findsOneWidget);
    });

    testWidgets('12. text scaling does not overflow', (
      WidgetTester tester,
    ) async {
      // Constrained viewport with 2.0x text scaling
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      service.setCompletedInMemory(false);

      await tester.pumpWidget(
        const MaterialApp(
          onGenerateRoute: AppRouter.onGenerateRoute,
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(400, 600),
              textScaler: TextScaler.linear(2.0),
            ),
            child: OnboardingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verifies no RenderFlex overflow on Screen 1
      expect(tester.takeException(), isNull);
      expect(find.text('One photo. Every day.'), findsOneWidget);

      // Advance to Screen 2
      await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Your life, in photos.'), findsOneWidget);

      // Advance to Screen 3
      await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Make every day count.'), findsOneWidget);
    });

    testWidgets('13. accessibility semantics exist', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      service.setCompletedInMemory(false);

      await tester.pumpWidget(const PhotoPerDayApp());
      await tester.pumpAndSettle();

      // Check header semantics for title
      final headerSemantics = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.header == true,
      );
      expect(headerSemantics, findsWidgets);

      // Check button semantics for Skip and Next
      final skipSemantics = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.button == true &&
            w.properties.label == 'Skip onboarding',
      );
      expect(skipSemantics, findsOneWidget);

      final nextSemantics = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.button == true &&
            w.properties.label == 'Next page',
      );
      expect(nextSemantics, findsOneWidget);

      // Check image semantics description on Screen 1
      final imageSemantics = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.image == true &&
            (w.properties.label?.contains('capturing a photo') ?? false),
      );
      expect(imageSemantics, findsOneWidget);
    });

    test('14. generated image assets load correctly', () async {
      // Verify assets can be retrieved via rootBundle
      final byteData1 = await rootBundle.load(AppConstants.onboardingImage1);
      final byteData2 = await rootBundle.load(AppConstants.onboardingImage2);
      final byteData3 = await rootBundle.load(AppConstants.onboardingImage3);

      expect(byteData1.lengthInBytes, greaterThan(1000));
      expect(byteData2.lengthInBytes, greaterThan(1000));
      expect(byteData3.lengthInBytes, greaterThan(1000));
    });

    test('15. all three onboarding assets are bundled correctly', () {
      final file1 = File(AppConstants.onboardingImage1);
      final file2 = File(AppConstants.onboardingImage2);
      final file3 = File(AppConstants.onboardingImage3);

      expect(file1.existsSync(), isTrue);
      expect(file2.existsSync(), isTrue);
      expect(file3.existsSync(), isTrue);

      expect(file1.lengthSync(), greaterThan(50000));
      expect(file2.lengthSync(), greaterThan(50000));
      expect(file3.lengthSync(), greaterThan(50000));
    });
  });
}
