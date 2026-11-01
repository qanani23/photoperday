import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/core/theme/app_palette.dart';
import 'package:photo_per_day/core/theme/app_theme.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';
import 'package:photo_per_day/data/services/app_theme_storage.dart';

class FakeThemeStorage extends AppThemeStorage {
  FakeThemeStorage({super.customBaseDir});

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

  @override
  Future<void> clear() async {
    _savedPaletteId = null;
    _savedFollowSystem = false;
  }
}

void main() {
  group('Milestone 66 — Daria Themes & Palettes Unit Tests', () {
    late FakeThemeStorage fakeStorage;
    late AppThemeService themeService;

    setUp(() async {
      fakeStorage = FakeThemeStorage();
      themeService = AppThemeService(storage: fakeStorage);
      await themeService.init();
      AppThemeService.setTestInstance(themeService);
    });

    tearDown(() {
      AppThemeService.resetTestInstance();
    });

    test(
      '1. All 7 curated presets are cataloged with distinct IDs and metadata',
      () {
        expect(AppPalettes.all.length, equals(7));

        final ids = AppPalettes.all.map((p) => p.id).toSet();
        expect(ids.length, equals(7));
        expect(
          ids,
          containsAll([
            'daria_red_light',
            'daria_red',
            'midnight',
            'linen',
            'evergreen',
            'ocean',
            'lavender',
          ]),
        );

        for (final palette in AppPalettes.all) {
          expect(palette.name.isNotEmpty, isTrue);
          expect(palette.description.isNotEmpty, isTrue);
        }
      },
    );

    test('2. Daria Red Light is the default palette on fresh install', () {
      expect(AppPalettes.dariaRedLight.id, equals('daria_red_light'));
      expect(themeService.currentPalette.id, equals('daria_red_light'));
      expect(themeService.currentPalette.isDark, isFalse);
    });

    test(
      '3. Daria Red and Midnight are marked as dark, Daria Red Light and others as light',
      () {
        expect(AppPalettes.dariaRedLight.isDark, isFalse);
        expect(AppPalettes.dariaRed.isDark, isTrue);
        expect(AppPalettes.midnight.isDark, isTrue);
        expect(AppPalettes.linen.isDark, isFalse);
        expect(AppPalettes.evergreen.isDark, isFalse);
        expect(AppPalettes.ocean.isDark, isFalse);
        expect(AppPalettes.lavender.isDark, isFalse);
      },
    );

    test(
      '4. Selecting palette applies immediately and notifies listeners',
      () async {
        int notifyCount = 0;
        themeService.addListener(() => notifyCount++);

        await themeService.setPalette(AppPalettes.evergreen);

        expect(themeService.currentPalette.id, equals('evergreen'));
        expect(notifyCount, equals(1));
        expect(themeService.followSystem, isFalse);
      },
    );

    test('5. Palette selection persists across restart via storage', () async {
      await themeService.setPalette(AppPalettes.ocean);

      // Simulate app restart with a fresh service instance using same storage
      final newService = AppThemeService(storage: fakeStorage);
      await newService.init();

      expect(newService.currentPalette.id, equals('ocean'));
      expect(newService.currentPalette.name, equals('Ocean'));
      expect(newService.followSystem, isFalse);
    });

    test(
      '6. AppTheme.themeForPalette creates valid ThemeData for all palettes',
      () {
        for (final palette in AppPalettes.all) {
          final themeData = AppTheme.themeForPalette(palette);
          expect(themeData.scaffoldBackgroundColor, equals(palette.background));
          expect(themeData.colorScheme.surface, equals(palette.surface));
          expect(themeData.colorScheme.primary, equals(palette.textPrimary));
          expect(themeData.colorScheme.secondary, equals(palette.accent));
          expect(
            themeData.brightness,
            equals(palette.isDark ? Brightness.dark : Brightness.light),
          );
        }
      },
    );

    test('7. Palettes have readable contrast and distinct accents', () {
      for (final palette in AppPalettes.all) {
        // Background and text should not be identical
        expect(palette.background, isNot(equals(palette.textPrimary)));
        // Surface and text should not be identical
        expect(palette.surface, isNot(equals(palette.textPrimary)));
        // Accent should be distinct
        expect(palette.accent, isNot(equals(palette.background)));
      }
    });

    test(
      '8. toggleDarkLight toggles between light (Daria Red Light) and dark (Daria Red)',
      () async {
        // Starts on Daria Red Light (light)
        expect(themeService.currentPalette.id, equals('daria_red_light'));
        expect(themeService.isDark, isFalse);

        // Toggle -> should switch to Daria Red (dark)
        await themeService.toggleDarkLight();
        expect(themeService.currentPalette.id, equals('daria_red'));
        expect(themeService.isDark, isTrue);
        expect(themeService.followSystem, isFalse);

        // Toggle again -> should switch back to Daria Red Light (light)
        await themeService.toggleDarkLight();
        expect(themeService.currentPalette.id, equals('daria_red_light'));
        expect(themeService.isDark, isFalse);
      },
    );

    test('9. Backward compatibility maps legacy palette IDs correctly', () {
      expect(AppPalettes.byId('sage'), equals(AppPalettes.evergreen));
      expect(AppPalettes.byId('forest'), equals(AppPalettes.evergreen));
      expect(AppPalettes.byId('dusk'), equals(AppPalettes.lavender));
      expect(AppPalettes.byId('rose'), equals(AppPalettes.lavender));
      expect(AppPalettes.byId('sand'), equals(AppPalettes.linen));
      expect(
        AppPalettes.byId('daria_red_light'),
        equals(AppPalettes.dariaRedLight),
      );
      expect(
        AppPalettes.byId('daria_light'),
        equals(AppPalettes.dariaRedLight),
      );
      expect(AppPalettes.byId('daria_red'), equals(AppPalettes.dariaRed));
      expect(
        AppPalettes.byId('unknown_random_id'),
        equals(AppPalettes.dariaRedLight),
      );
    });
  });
}
