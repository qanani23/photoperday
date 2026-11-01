import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';
import 'package:photo_per_day/data/services/app_theme_storage.dart';
import 'package:photo_per_day/screens/settings/settings_screen.dart';
import 'package:photo_per_day/widgets/app_header.dart';

class ToggleFakeThemeStorage extends AppThemeStorage {
  ToggleFakeThemeStorage({super.customBaseDir});

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
  group('Milestone 66 — AppHeader Theme Toggle and Settings Tests', () {
    late ToggleFakeThemeStorage fakeStorage;
    late AppThemeService themeService;

    setUp(() async {
      fakeStorage = ToggleFakeThemeStorage();
      themeService = AppThemeService(storage: fakeStorage);
      await themeService.init();
      AppThemeService.setTestInstance(themeService);
    });

    tearDown(() {
      AppThemeService.resetTestInstance();
    });

    testWidgets(
      '1. AppHeader renders theme toggle beside settings and toggles between Daria Red Light and Daria Red',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AppHeader(onSettingsTap: () {}, onDiaryTap: () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Starts on Daria Red Light (Light) -> header shows 'Dark' action button to switch to dark mode
        expect(themeService.currentPalette.id, equals('daria_red_light'));
        expect(find.text('Dark'), findsOneWidget);
        expect(find.text('Settings'), findsOneWidget);

        // Tap the Dark button
        await tester.tap(find.text('Dark'));
        await tester.pumpAndSettle();

        // Should now be Daria Red (Dark) -> header shows 'Light' action button
        expect(themeService.currentPalette.id, equals('daria_red'));
        expect(themeService.isDark, isTrue);
        expect(find.text('Light'), findsOneWidget);

        // Tap the Light button
        await tester.tap(find.text('Light'));
        await tester.pumpAndSettle();

        // Should be back to Daria Red Light (Light)
        expect(themeService.currentPalette.id, equals('daria_red_light'));
        expect(themeService.isDark, isFalse);
        expect(find.text('Dark'), findsOneWidget);
      },
    );

    testWidgets(
      '2. SettingsScreen contains Dark Mode switch and Match System Theme switch',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
        await tester.pumpAndSettle();

        // Scroll to Preferences section
        expect(find.text('Dark Mode'), findsOneWidget);
        expect(find.text('Match System Theme'), findsOneWidget);
        expect(find.text('Theme & Palettes'), findsOneWidget);

        // Starts with Dark Mode off (Daria Red Light is light)
        expect(themeService.isDark, isFalse);
        expect(themeService.currentPalette.id, equals('daria_red_light'));

        // Toggle to dark mode
        await themeService.toggleDarkLight();
        await tester.pumpAndSettle();

        expect(themeService.currentPalette.id, equals('daria_red'));
        expect(themeService.isDark, isTrue);

        // Toggle back to light mode
        await themeService.toggleDarkLight();
        await tester.pumpAndSettle();

        expect(themeService.currentPalette.id, equals('daria_red_light'));
        expect(themeService.isDark, isFalse);

        // Test Match System Theme toggle
        await themeService.setFollowSystem(true);
        await tester.pumpAndSettle();
        expect(themeService.followSystem, isTrue);
      },
    );
  });
}
