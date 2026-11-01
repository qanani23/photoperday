import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/app.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_palette.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';
import 'package:photo_per_day/data/services/app_theme_storage.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/screens/profile/profile_screen.dart';
import 'package:photo_per_day/widgets/bottom_nav_dock.dart';

class TestThemeStorage extends AppThemeStorage {
  String? _savedPaletteId;
  bool _savedFollowSystem = false;

  @override
  Future<ThemeSettingsData> loadSettings() async => ThemeSettingsData(
    paletteId: _savedPaletteId ?? 'daria_red_light',
    followSystem: _savedFollowSystem,
  );

  @override
  Future<void> saveSettings({
    required String paletteId,
    required bool followSystem,
  }) async {
    _savedPaletteId = paletteId;
    _savedFollowSystem = followSystem;
  }

  @override
  Future<String> loadPaletteId() async => _savedPaletteId ?? 'daria_red_light';

  @override
  Future<void> savePaletteId(String paletteId) async {
    _savedPaletteId = paletteId;
    _savedFollowSystem = false;
  }
}

void main() {
  group('Profile Screen & MainShell Dynamic Theme Integration Tests', () {
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
      'Profile Screen and MainShell dynamically adopt Daria Red and themes',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Start with default Daria Red theme
        await tester.pumpWidget(const PhotoPerDayApp());
        await tester.pumpAndSettle();

        // 1. Navigate to "Me" tab via BottomNavDock
        final meTab = find.descendant(
          of: find.byType(BottomNavDock),
          matching: find.text('Me'),
        );
        expect(meTab, findsOneWidget);
        await tester.tap(meTab);
        await tester.pumpAndSettle();

        // Verify ProfileScreen is active
        expect(find.byType(ProfileScreen), findsOneWidget);
        expect(find.text('Daily Photo Diary'), findsOneWidget);
        expect(find.text('PREFERENCES'), findsOneWidget);

        // 2. Initial state reflects Daria Red Light colors
        expect(AppColors.current.id, equals('daria_red_light'));
        expect(AppColors.surface, equals(AppPalettes.dariaRedLight.surface));
        expect(
          AppColors.background,
          equals(AppPalettes.dariaRedLight.background),
        );

        // 3. Switch active theme to Midnight
        await themeService.setPalette(AppPalettes.midnight);
        await tester.pumpAndSettle();

        // 4. Verify that AppColors and ProfileScreen reflect Midnight palette
        expect(AppColors.current.id, equals('midnight'));
        expect(AppColors.surface, equals(AppPalettes.midnight.surface));
        expect(AppColors.background, equals(AppPalettes.midnight.background));
        expect(AppColors.textPrimary, equals(AppPalettes.midnight.textPrimary));

        // Verify dock updated to Midnight dock colors
        final dockContainer = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(BottomNavDock),
                matching: find.byType(Container),
              )
              .first,
        );
        final dockBoxDeco = dockContainer.decoration as BoxDecoration;
        expect(dockBoxDeco.color, equals(AppPalettes.midnight.dockBackground));

        // 5. Navigate to Home tab and back to Me tab to confirm seamless persistence
        final homeTab = find.descendant(
          of: find.byType(BottomNavDock),
          matching: find.text('Home'),
        );
        await tester.tap(homeTab);
        await tester.pumpAndSettle();

        // Tap back to Me tab
        await tester.tap(meTab);
        await tester.pumpAndSettle();

        expect(find.text('Daily Photo Diary'), findsOneWidget);
        expect(AppColors.current.id, equals('midnight'));

        // 6. Switch to Linen and verify live restoration
        await themeService.setPalette(AppPalettes.linen);
        await tester.pumpAndSettle();

        expect(AppColors.current.id, equals('linen'));
        final restoredDockContainer = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(BottomNavDock),
                matching: find.byType(Container),
              )
              .first,
        );
        final restoredDockDeco =
            restoredDockContainer.decoration as BoxDecoration;
        expect(
          restoredDockDeco.color,
          equals(AppPalettes.linen.dockBackground),
        );
      },
    );
  });
}
