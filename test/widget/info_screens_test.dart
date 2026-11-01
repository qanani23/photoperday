import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/app.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_palette.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';
import 'package:photo_per_day/data/services/app_theme_storage.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/screens/info/about_app_screen.dart';
import 'package:photo_per_day/screens/info/privacy_policy_screen.dart';
import 'package:photo_per_day/screens/info/terms_of_service_screen.dart';

class TestThemeStorage extends AppThemeStorage {
  String? _savedPaletteId;
  bool _followSystem = false;

  @override
  Future<ThemeSettingsData> loadSettings() async => ThemeSettingsData(
    paletteId: _savedPaletteId ?? 'daria_red_light',
    followSystem: _followSystem,
  );

  @override
  Future<void> saveSettings({
    required String paletteId,
    required bool followSystem,
  }) async {
    _savedPaletteId = paletteId;
    _followSystem = followSystem;
  }
}

void main() {
  group('Dedicated Info Screens Test Suite', () {
    late TestThemeStorage themeStorage;
    late AppThemeService themeService;

    setUp(() async {
      themeStorage = TestThemeStorage();
      themeService = AppThemeService(storage: themeStorage);
      await themeService.init();
      AppThemeService.setTestInstance(themeService);
    });

    tearDown(() {
      AppThemeService.resetTestInstance();
      PersistentDailyPhotoStore.resetTestInstance();
    });

    testWidgets(
      'AboutAppScreen renders branding, philosophy, pillars, and responds to theme switch',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(430, 932));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(const MaterialApp(home: AboutAppScreen()));
        await tester.pumpAndSettle();

        // Verify hero branding
        expect(find.text('About'), findsOneWidget);
        expect(find.text('The Story Behind Daria'), findsOneWidget);
        expect(find.text('The Philosophy'), findsOneWidget);
        expect(find.text('One Frame Per Day'), findsOneWidget);
        expect(find.text('100% Local-First'), findsOneWidget);
        expect(find.text('CRAFT & INTEGRITY'), findsOneWidget);

        // Verify initial theme (Daria Red Light)
        expect(
          AppColors.background,
          equals(AppPalettes.dariaRedLight.background),
        );

        // Switch to Midnight dark theme
        await themeService.setPalette(AppPalettes.midnight);
        await tester.pumpAndSettle();

        // Verify dynamic dark theme adaptation
        expect(AppColors.background, equals(AppPalettes.midnight.background));
        expect(AppColors.surface, equals(AppPalettes.midnight.surface));
      },
    );

    testWidgets(
      'PrivacyPolicyScreen renders manifesto, trust badges, permissions, and rights',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(430, 932));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(const MaterialApp(home: PrivacyPolicyScreen()));
        await tester.pumpAndSettle();

        expect(find.text('Privacy Policy'), findsOneWidget);
        expect(find.text('The Privacy Manifesto'), findsOneWidget);
        expect(find.text('Local-First'), findsOneWidget);
        expect(find.text('No Trackers'), findsOneWidget);
        expect(find.text('Direct Drive'), findsOneWidget);
        expect(find.text('PERMISSIONS TRANSPARENCY'), findsOneWidget);
        expect(find.text('Camera'), findsOneWidget);
        expect(find.text('Notifications'), findsOneWidget);
        expect(find.text('Complete Data Control & Erasure'), findsOneWidget);
      },
    );

    testWidgets(
      'TermsOfServiceScreen renders highlights, ownership article, and fair use pledge',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(430, 932));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          const MaterialApp(home: TermsOfServiceScreen()),
        );
        await tester.pumpAndSettle();

        expect(find.text('Terms of Service'), findsOneWidget);
        expect(find.text('Terms at a Glance'), findsOneWidget);
        expect(find.text('100% You Own It'), findsOneWidget);
        expect(find.text('No Subscriptions'), findsOneWidget);
        expect(find.text('1. Content Ownership & Copyright'), findsOneWidget);
        expect(find.text('Our Commitment to You'), findsOneWidget);
      },
    );

    testWidgets(
      'App navigation opens About, Privacy, and Terms via named routes',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(430, 932));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(const PhotoPerDayApp());
        await tester.pumpAndSettle();

        // Navigate to Settings
        final navigatorState = tester.state<NavigatorState>(
          find.byType(Navigator).first,
        );
        navigatorState.pushNamed(AppConstants.aboutRoute);
        await tester.pumpAndSettle();

        expect(find.byType(AboutAppScreen), findsOneWidget);

        // Pop back
        navigatorState.pop();
        await tester.pumpAndSettle();

        // Navigate to Privacy Policy
        navigatorState.pushNamed(AppConstants.privacyRoute);
        await tester.pumpAndSettle();

        expect(find.byType(PrivacyPolicyScreen), findsOneWidget);

        // Pop back
        navigatorState.pop();
        await tester.pumpAndSettle();

        // Navigate to Terms
        navigatorState.pushNamed(AppConstants.termsRoute);
        await tester.pumpAndSettle();

        expect(find.byType(TermsOfServiceScreen), findsOneWidget);
      },
    );
  });
}
