import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/core/theme/app_palette.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';
import 'package:photo_per_day/data/services/app_theme_storage.dart';
import 'package:photo_per_day/screens/settings/theme_selection_screen.dart';

class WidgetFakeThemeStorage extends AppThemeStorage {
  WidgetFakeThemeStorage({super.customBaseDir});

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
  group('Milestone 66 — ThemeSelectionScreen Widget Tests', () {
    late WidgetFakeThemeStorage fakeStorage;
    late AppThemeService themeService;

    setUp(() async {
      fakeStorage = WidgetFakeThemeStorage();
      themeService = AppThemeService(storage: fakeStorage);
      await themeService.init();
      AppThemeService.setTestInstance(themeService);
    });

    tearDown(() {
      AppThemeService.resetTestInstance();
    });

    Widget createTestWidget() {
      return const MaterialApp(home: ThemeSelectionScreen());
    }

    testWidgets(
      '1. Displays all 7 curated palettes in list with names and descriptions',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Theme & Palettes'), findsOneWidget);
        expect(
          find.text('Curated palettes for your daily photo journal'),
          findsOneWidget,
        );

        // Verify all 7 palette names appear
        for (final palette in AppPalettes.all) {
          expect(find.text(palette.name), findsWidgets);
        }
      },
    );

    testWidgets(
      '2. Shows Default tag for Daria Red Light and Active badge for current selection',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Default'), findsOneWidget);
        expect(find.text('Active'), findsOneWidget);
      },
    );

    testWidgets('3. Tapping another palette changes selection immediately', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(themeService.currentPalette.id, equals('daria_red_light'));

      // Tap Evergreen palette
      final evergreenFinder = find.text('Evergreen');
      expect(evergreenFinder, findsWidgets);
      await tester.tap(evergreenFinder.first);
      await tester.pumpAndSettle();

      expect(themeService.currentPalette.id, equals('evergreen'));
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('4. Palette items provide accessible Semantics labels', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Check semantics for back button
      expect(
        find.bySemanticsLabel('Navigate back to Settings'),
        findsOneWidget,
      );

      // Check semantics for active palette
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.label?.contains('Daria Red Light palette') ??
                  false) &&
              (w.properties.selected ?? false),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      '5. Quick appearance toggle buttons and Match System switch work',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Quick Appearance Toggle'), findsOneWidget);
        expect(find.text('Daria Light'), findsWidgets);
        expect(find.text('Daria Red'), findsWidgets);
        expect(find.text('Midnight'), findsWidgets);
        expect(find.text('Match System Theme'), findsOneWidget);

        // Tap Midnight
        await tester.tap(find.text('Midnight').first);
        await tester.pumpAndSettle();

        expect(themeService.currentPalette.id, equals('midnight'));
        expect(themeService.isDark, isTrue);

        // Tap Daria Light
        await tester.tap(find.text('Daria Light').first);
        await tester.pumpAndSettle();

        expect(themeService.currentPalette.id, equals('daria_red_light'));
        expect(themeService.isDark, isFalse);

        // Toggle Match System switch
        final switchFinder = find.byType(Switch);
        expect(switchFinder, findsOneWidget);
        await tester.tap(switchFinder);
        await tester.pumpAndSettle();

        expect(themeService.followSystem, isTrue);
      },
    );
  });
}
