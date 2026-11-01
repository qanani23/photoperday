import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/app.dart';
import 'package:photo_per_day/data/services/onboarding_service.dart';
import 'package:photo_per_day/data/services/onboarding_storage.dart';
import 'package:photo_per_day/screens/home/home_screen.dart';
import 'package:photo_per_day/screens/main_shell.dart';
import 'package:photo_per_day/screens/onboarding/onboarding_screen.dart';
import 'package:photo_per_day/screens/profile/profile_screen.dart';

class InMemoryOnboardingStorage extends OnboardingStorage {
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

  late InMemoryOnboardingStorage storage;
  late OnboardingService onboardingService;

  setUp(() async {
    storage = InMemoryOnboardingStorage();
    onboardingService = OnboardingService(storage: storage);
    OnboardingService.setTestInstance(onboardingService);
  });

  tearDown(() {
    OnboardingService.resetTestInstance();
  });

  group('Milestone 51 — Decouple Navigation & Onboarding from Login', () {
    testWidgets(
      '1. First launch completes onboarding and enters MainShell directly without signing in',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Brand new install: onboarding not complete
        await storage.saveCompleted(completed: false);
        await onboardingService.init();
        expect(onboardingService.hasCompletedOnboarding, isFalse);

        await tester.pumpWidget(const PhotoPerDayApp());
        await tester.pumpAndSettle();

        // Starts on OnboardingScreen
        expect(find.byType(OnboardingScreen), findsOneWidget);
        expect(find.byType(MainShell), findsNothing);

        // Advance through pages 1 -> 2 -> 3
        final nextIcon = find.byIcon(Icons.arrow_forward_rounded);
        await tester.tap(nextIcon);
        await tester.pumpAndSettle();
        await tester.tap(nextIcon);
        await tester.pumpAndSettle();

        // Tap "Start My Diary" CTA
        final startButton = find.text('Start My Diary');
        expect(startButton, findsOneWidget);
        await tester.tap(startButton);
        await tester.pumpAndSettle();

        // Verifies direct transition to MainShell (local diary)
        expect(find.byType(MainShell), findsOneWidget);
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byType(OnboardingScreen), findsNothing);

        expect(onboardingService.hasCompletedOnboarding, isTrue);
      },
    );

    testWidgets(
      '2. First launch skips onboarding and enters MainShell directly without signing in',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // New install
        await storage.saveCompleted(completed: false);
        await onboardingService.init();
        expect(onboardingService.hasCompletedOnboarding, isFalse);

        await tester.pumpWidget(const PhotoPerDayApp());
        await tester.pumpAndSettle();

        expect(find.byType(OnboardingScreen), findsOneWidget);

        // Tap "Skip"
        final skipButton = find.text('Skip');
        expect(skipButton, findsOneWidget);
        await tester.tap(skipButton);
        await tester.pumpAndSettle();

        // Enters MainShell directly
        expect(find.byType(MainShell), findsOneWidget);
        expect(find.byType(OnboardingScreen), findsNothing);

        expect(onboardingService.hasCompletedOnboarding, isTrue);
      },
    );

    testWidgets(
      '3. Returning user with completed onboarding launches directly into MainShell without login',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Returning user: completed onboarding
        await storage.saveCompleted(completed: true);
        await onboardingService.init();
        expect(onboardingService.hasCompletedOnboarding, isTrue);

        await tester.pumpWidget(const PhotoPerDayApp());
        await tester.pumpAndSettle();

        // Directly on MainShell
        expect(find.byType(MainShell), findsOneWidget);
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byType(OnboardingScreen), findsNothing);
      },
    );

    testWidgets('4. Local diary navigation functions smoothly', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await storage.saveCompleted(completed: true);
      await onboardingService.init();

      await tester.pumpWidget(const PhotoPerDayApp());
      await tester.pumpAndSettle();

      expect(find.byType(MainShell), findsOneWidget);
      expect(find.byType(HomeScreen), findsOneWidget);

      // Tap "Me" to open Profile
      final meButton = find.text('Me');
      expect(meButton, findsOneWidget);
      await tester.tap(meButton);
      await tester.pumpAndSettle();

      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text('Active Local Diary'), findsOneWidget);

      // Tap "Home" to return to Calendar/Home screen
      final homeButton = find.text('Home');
      expect(homeButton, findsOneWidget);
      await tester.tap(homeButton);
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets(
      '5. Back navigation does not pop back to onboarding from MainShell',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await storage.saveCompleted(completed: false);
        await onboardingService.init();

        await tester.pumpWidget(const PhotoPerDayApp());
        await tester.pumpAndSettle();

        // Skip onboarding into MainShell
        await tester.tap(find.text('Skip'));
        await tester.pumpAndSettle();
        expect(find.byType(MainShell), findsOneWidget);

        // Attempt popping navigation
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        final canPop = navigator.canPop();
        expect(canPop, isFalse);

        expect(find.byType(OnboardingScreen), findsNothing);
      },
    );

    testWidgets('6. Onboarding completion persists across re-initialization', (
      WidgetTester tester,
    ) async {
      // Complete onboarding
      await onboardingService.completeOnboarding();
      expect(await storage.loadCompleted(), isTrue);

      // Simulate app restart by re-initializing fresh service from storage
      final newService = OnboardingService(storage: storage);
      await newService.init();
      expect(newService.hasCompletedOnboarding, isTrue);
    });
  });
}
