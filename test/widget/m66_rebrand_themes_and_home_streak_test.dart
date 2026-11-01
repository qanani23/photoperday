import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/core/theme/app_palette.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/pdf_export_models.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';
import 'package:photo_per_day/data/services/app_theme_storage.dart';
import 'package:photo_per_day/data/services/pad_backup_service.dart';
import 'package:photo_per_day/data/services/pdf_diary_export_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/data/services/streak_service.dart';
import 'package:photo_per_day/screens/home/home_screen.dart';
import 'package:photo_per_day/widgets/app_header.dart';
import 'package:photo_per_day/widgets/home_streak_card.dart';

class M66FakeMetadataStorage extends PhotoMetadataStorage {
  M66FakeMetadataStorage({super.customBaseDir});
  final Map<DateKey, PhotoEntry> _memory = {};

  @override
  Future<void> init() async {}

  @override
  Future<Map<DateKey, PhotoEntry>> loadAll() async => Map.from(_memory);

  @override
  Future<void> saveAll(Map<DateKey, PhotoEntry> entries) async {
    _memory.clear();
    _memory.addAll(entries);
  }

  @override
  Future<void> clear() async => _memory.clear();
}

class M66FakeFileManager extends PhotoFileManager {
  M66FakeFileManager({super.customBaseDir});

  @override
  Future<void> init() async {}

  @override
  Future<String> persistPhotoFile({
    required String sourcePath,
    required DateKey dateKey,
  }) async => sourcePath;

  @override
  bool isManagedPath(String path) => true;

  @override
  Future<bool> deletePhotoFile(String? path) async => true;
}

class M66FakeThemeStorage extends AppThemeStorage {
  M66FakeThemeStorage({super.customBaseDir});
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
}

void main() {
  group('M66 — Daria Rebrand Tests', () {
    test('1. AppConstants.appName is Daria', () {
      expect(AppConstants.appName, equals('Daria'));
    });

    test('2. AppHeader defaults to Daria title', () {
      const header = AppHeader();
      expect(header.title, equals('Daria'));
    });

    test(
      '3. PDF export service generates Daria_Diary_ filenames and branding',
      () {
        final exportService = PdfDiaryExportService();
        final filteredDays = exportService.getFilteredDays(
          const PdfExportRange.allTime(),
        );
        expect(filteredDays, isNotNull);
      },
    );

    test('4. PadBackupService uses Daria branding in filenames', () {
      final service = PadBackupService();
      expect(PadBackupService.backupExtension, equals('.padbackup'));
      expect(service, isNotNull);
    });
  });

  group('M66 — Theme System Redesign & Curated Themes Tests', () {
    late M66FakeThemeStorage themeStorage;
    late AppThemeService themeService;

    setUp(() async {
      themeStorage = M66FakeThemeStorage();
      themeService = AppThemeService(storage: themeStorage);
      await themeService.init();
      AppThemeService.setTestInstance(themeService);
    });

    tearDown(() {
      AppThemeService.resetTestInstance();
    });

    test('1. Exactly 7 curated presets exist', () {
      expect(AppPalettes.all.length, equals(7));
      final ids = AppPalettes.all.map((p) => p.id).toList();
      expect(
        ids,
        equals([
          'daria_red_light',
          'daria_red',
          'midnight',
          'linen',
          'evergreen',
          'ocean',
          'lavender',
        ]),
      );
    });

    test('2. Daria Red Light is the default palette with signature colors', () {
      expect(themeService.currentPalette.id, equals('daria_red_light'));
      expect(themeService.currentPalette.name, equals('Daria Red Light'));
      expect(themeService.currentPalette.isDark, isFalse);
      expect(
        themeService.currentPalette.background,
        equals(const Color(0xFFFFF9F9)),
      );
      expect(
        themeService.currentPalette.accent,
        equals(const Color(0xFFE50914)),
      );
      expect(
        themeService.currentPalette.textPrimary,
        equals(const Color(0xFF1B1416)),
      );
      expect(
        themeService.currentPalette.accentForeground,
        equals(Colors.white),
      );
    });

    test('3. Backward compatibility cleanly maps legacy IDs', () {
      expect(AppPalettes.byId('sage'), equals(AppPalettes.evergreen));
      expect(AppPalettes.byId('forest'), equals(AppPalettes.evergreen));
      expect(AppPalettes.byId('dusk'), equals(AppPalettes.lavender));
      expect(AppPalettes.byId('rose'), equals(AppPalettes.lavender));
      expect(AppPalettes.byId('sand'), equals(AppPalettes.linen));
      expect(
        AppPalettes.byId('unknown_theme'),
        equals(AppPalettes.dariaRedLight),
      );
    });

    test(
      '4. Quick toggle switches between light (Daria Red Light) and dark (Daria Red)',
      () async {
        expect(themeService.currentPalette.id, equals('daria_red_light'));
        expect(themeService.isDark, isFalse);

        await themeService.toggleDarkLight();
        expect(themeService.currentPalette.id, equals('daria_red'));
        expect(themeService.isDark, isTrue);

        await themeService.toggleDarkLight();
        expect(themeService.currentPalette.id, equals('daria_red_light'));
        expect(themeService.isDark, isFalse);
      },
    );
  });

  group('M66 — Home Streak Status Card Tests', () {
    late Directory tempDir;
    late PersistentDailyPhotoStore photoStore;
    late M66FakeMetadataStorage metaStorage;
    late M66FakeFileManager fileManager;
    final DateTime fixedToday = DateTime(2026, 10, 31);

    setUp(() async {
      StreakService.instance.clearCache();
      tempDir = await Directory.systemTemp.createTemp('m66_streak_test_');
      metaStorage = M66FakeMetadataStorage();
      fileManager = M66FakeFileManager();

      photoStore = PersistentDailyPhotoStore(
        metadataStorage: metaStorage,
        fileManager: fileManager,
      );
      await photoStore.init();
      PersistentDailyPhotoStore.setTestInstance(photoStore);
    });

    tearDown(() async {
      PersistentDailyPhotoStore.resetTestInstance();
      photoStore.dispose();
      StreakService.instance.clearCache();
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    Widget createHome({Size size = const Size(400, 800)}) {
      return MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: HomeScreen(
            store: photoStore,
            initialDate: fixedToday,
            wrapWithScaffold: false,
          ),
        ),
      );
    }

    testWidgets('1. Home screen renders HomeStreakCard with initial 0 streak', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createHome());
      await tester.pumpAndSettle();

      // Card is present
      expect(find.byType(HomeStreakCard), findsOneWidget);
      expect(find.byKey(const ValueKey('home_streak_card')), findsOneWidget);

      // Current streak count is 0
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('streak_display_number')))
            .data,
        equals('0'),
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('streak_display_label')))
            .data,
        equals('CURRENT STREAK'),
      );

      // Best streak count is 0d
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('home_streak_best_count')))
            .data,
        equals('0d'),
      );

      // Motivational message when no active streak
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('home_streak_message')))
            .data,
        equals('Start a new streak today with a single photo.'),
      );

      // Flame icon is present
      expect(
        find.byKey(const ValueKey('home_streak_flame_icon')),
        findsOneWidget,
      );
    });

    testWidgets(
      '2. Saving consecutive photos reactively updates streak and motivational message',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createHome());
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('streak_display_number')))
              .data,
          equals('0'),
        );

        // Add photo for yesterday (Oct 30)
        final yesterday = fixedToday.subtract(const Duration(days: 1));
        await photoStore.savePhoto(
          entry: PhotoEntry(
            date: yesterday,
            title: 'Yesterday Memory',
            gradientColors: const [Colors.red, Colors.black],
          ),
        );
        await tester.pumpAndSettle();

        // Streak is 1 day (ended yesterday, so active waiting for today's photo)
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('streak_display_number')))
              .data,
          equals('1'),
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('home_streak_message')))
              .data,
          equals("Take today's photo to keep your streak going!"),
        );

        // Add photo for today (Oct 31)
        await photoStore.savePhoto(
          entry: PhotoEntry(
            date: fixedToday,
            title: 'Today Memory',
            gradientColors: const [Colors.red, Colors.black],
          ),
        );
        await tester.pumpAndSettle();

        // Streak is 2 days and completed for today!
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('streak_display_number')))
              .data,
          equals('2'),
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('home_streak_message')))
              .data,
          equals('Streak active! Great job capturing today.'),
        );

        // Best streak reflects 2 days
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('home_streak_best_count')),
              )
              .data,
          equals('2d'),
        );
      },
    );

    testWidgets(
      '3. Responsive layout adapts cleanly on wide desktop screens (1366px)',
      (tester) async {
        tester.view.physicalSize = const Size(1366, 768);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createHome(size: const Size(1366, 768)));
        await tester.pumpAndSettle();

        expect(find.byType(HomeStreakCard), findsOneWidget);
        expect(find.byKey(const ValueKey('home_streak_card')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('home_streak_progress_bar')),
          findsOneWidget,
        );

        // Zero overflow errors
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '4. Responsive layout adapts cleanly on narrow mobile screens (360px)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createHome(size: const Size(360, 640)));
        await tester.pumpAndSettle();

        expect(find.byType(HomeStreakCard), findsOneWidget);
        expect(find.byKey(const ValueKey('home_streak_card')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('home_streak_message')),
          findsOneWidget,
        );

        // Zero overflow errors
        expect(tester.takeException(), isNull);
      },
    );
  });
}
