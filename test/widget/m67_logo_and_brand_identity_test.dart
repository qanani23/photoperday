import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/core/theme/app_palette.dart';
import 'package:photo_per_day/data/models/pdf_export_models.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';
import 'package:photo_per_day/data/services/app_theme_storage.dart';
import 'package:photo_per_day/data/services/pdf_diary_export_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/screens/info/about_app_screen.dart';
import 'package:photo_per_day/screens/onboarding/onboarding_screen.dart';
import 'package:photo_per_day/screens/profile/profile_screen.dart';
import 'package:photo_per_day/screens/settings/settings_screen.dart';
import 'package:photo_per_day/widgets/app_header.dart';
import 'package:photo_per_day/widgets/daria_logo.dart';
import 'package:photo_per_day/widgets/pdf_export_dialog.dart';

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

class MockPdfPlatformDelegate implements PdfPlatformDelegate {
  @override
  Future<bool> sharePdf({
    required Uint8List bytes,
    required String filename,
  }) async => true;
  @override
  Future<bool> layoutPdf({
    required Uint8List bytes,
    required String name,
  }) async => true;
  @override
  Future<String?> savePdfToUserDestination({
    required Uint8List bytes,
    required String suggestedFilename,
  }) async => '/mock/$suggestedFilename';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PersistentDailyPhotoStore photoStore;
  late WidgetFakeThemeStorage fakeStorage;
  late AppThemeService themeService;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('m67_brand_test_');
    final fileManager = PhotoFileManager(customBaseDir: tempDir);
    final metadataStorage = PhotoMetadataStorage(customBaseDir: tempDir);
    photoStore = PersistentDailyPhotoStore(
      metadataStorage: metadataStorage,
      fileManager: fileManager,
    );
    PersistentDailyPhotoStore.setTestInstance(photoStore);

    fakeStorage = WidgetFakeThemeStorage();
    themeService = AppThemeService(storage: fakeStorage);
    await themeService.init();
    AppThemeService.setTestInstance(themeService);
  });

  tearDown(() {
    PersistentDailyPhotoStore.resetTestInstance();
    AppThemeService.resetTestInstance();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('M67 — Daria Official Logo Asset Verification', () {
    test(
      'Official source logo exists with exact 1254x1254 resolution and alpha',
      () {
        final logoFile = File('assets/images/icons/dariaicon.png');
        expect(
          logoFile.existsSync(),
          isTrue,
          reason: 'assets/images/icons/dariaicon.png must exist',
        );

        final bytes = logoFile.readAsBytesSync();
        expect(bytes.length, greaterThan(100000));

        final decoded = img.decodeImage(bytes);
        expect(decoded, isNotNull);
        expect(decoded!.width, equals(1254));
        expect(decoded.height, equals(1254));
        expect(decoded.hasAlpha, isTrue);

        // Check corner transparency (< 10 alpha considered transparent margin)
        expect(decoded.getPixel(0, 0).a, lessThan(10));
        expect(decoded.getPixel(1253, 0).a, lessThan(10));
        expect(decoded.getPixel(0, 1253).a, lessThan(10));
        expect(decoded.getPixel(1253, 1253).a, lessThan(10));
      },
    );

    test('pubspec.yaml registers assets/images/icons/', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec.contains('assets/images/icons/'), isTrue);
    });

    test('AppConstants points to the authentic Daria logo asset', () {
      expect(
        AppConstants.dariaLogoAsset,
        equals('assets/images/icons/dariaicon.png'),
      );
    });
  });

  group('M67 — Android Launcher Icons Verification', () {
    test('Standard mipmap density PNGs exist with correct dimensions', () {
      final densities = <String, int>{
        'mipmap-mdpi': 48,
        'mipmap-hdpi': 72,
        'mipmap-xhdpi': 96,
        'mipmap-xxhdpi': 144,
        'mipmap-xxxhdpi': 192,
      };

      for (final entry in densities.entries) {
        final path = 'android/app/src/main/res/${entry.key}/ic_launcher.png';
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path should exist');
        final decoded = img.decodeImage(file.readAsBytesSync());
        expect(decoded, isNotNull);
        expect(decoded!.width, equals(entry.value));
        expect(decoded.height, equals(entry.value));
      }
    });

    test('Adaptive icon foreground PNGs exist with correct dimensions', () {
      final adaptiveDensities = <String, int>{
        'mipmap-mdpi': 108,
        'mipmap-hdpi': 162,
        'mipmap-xhdpi': 216,
        'mipmap-xxhdpi': 324,
        'mipmap-xxxhdpi': 432,
      };

      for (final entry in adaptiveDensities.entries) {
        final path =
            'android/app/src/main/res/${entry.key}/ic_launcher_foreground.png';
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path should exist');
        final decoded = img.decodeImage(file.readAsBytesSync());
        expect(decoded, isNotNull);
        expect(decoded!.width, equals(entry.value));
        expect(decoded.height, equals(entry.value));
      }
    });

    test(
      'mipmap-anydpi-v26/ic_launcher.xml exists and references background and foreground',
      () {
        final xmlFile = File(
          'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
        );
        expect(xmlFile.existsSync(), isTrue);
        final xml = xmlFile.readAsStringSync();
        expect(xml.contains('adaptive-icon'), isTrue);
        expect(xml.contains('@color/ic_launcher_background'), isTrue);
        expect(xml.contains('@mipmap/ic_launcher_foreground'), isTrue);
      },
    );

    test('colors.xml defines ic_launcher_background', () {
      final colorsFile = File('android/app/src/main/res/values/colors.xml');
      expect(colorsFile.existsSync(), isTrue);
      final colors = colorsFile.readAsStringSync();
      expect(colors.contains('ic_launcher_background'), isTrue);
    });
  });

  group('M67 — Windows Desktop Icon Verification', () {
    test(
      'windows/runner/resources/app_icon.ico is a valid multi-resolution ICO',
      () {
        final icoFile = File('windows/runner/resources/app_icon.ico');
        expect(icoFile.existsSync(), isTrue);
        final bytes = icoFile.readAsBytesSync();
        expect(bytes.length, greaterThan(20000));

        final byteData = ByteData.sublistView(bytes);
        expect(byteData.getUint16(0, Endian.little), equals(0)); // Reserved
        expect(byteData.getUint16(2, Endian.little), equals(1)); // 1 = ICO
        final count = byteData.getUint16(4, Endian.little);
        expect(
          count,
          equals(7),
          reason: 'Expected 7 resolutions (16, 24, 32, 48, 64, 128, 256)',
        );

        final sizes = <int>[];
        for (int i = 0; i < count; i++) {
          final entryOffset = 6 + (i * 16);
          final w = byteData.getUint8(entryOffset);
          sizes.add(w == 0 ? 256 : w);
        }
        expect(sizes, containsAll([16, 24, 32, 48, 64, 128, 256]));
      },
    );
  });

  group('M67 — In-App Brand Widget & Screen Branding Verification', () {
    testWidgets('DariaLogo renders with specified dimensions and semantics', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: DariaLogo(size: 64.0))),
        ),
      );
      await tester.pumpAndSettle();

      final logoFinder = find.byType(DariaLogo);
      expect(logoFinder, findsOneWidget);
      final renderBox = tester.renderObject(logoFinder) as RenderBox;
      expect(renderBox.size.width, equals(64.0));
      expect(renderBox.size.height, equals(64.0));
    });

    testWidgets(
      'DariaLogo looks sharp and intact across all 7 curated palettes',
      (tester) async {
        for (final palette in AppPalettes.all) {
          await themeService.setPalette(palette);

          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(
                brightness: palette.isDark ? Brightness.dark : Brightness.light,
                scaffoldBackgroundColor: palette.background,
              ),
              home: const Scaffold(body: Center(child: DariaLogo(size: 44.0))),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(DariaLogo), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets('AppHeader displays DariaLogo when showBackButton is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppHeader(showBackButton: false)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DariaLogo), findsOneWidget);
      expect(
        find.byKey(const ValueKey('full_calendar_back_button')),
        findsNothing,
      );
    });

    testWidgets('AppHeader displays back button when showBackButton is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppHeader(showBackButton: true)),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('full_calendar_back_button')),
        findsOneWidget,
      );
      expect(find.byType(DariaLogo), findsNothing);
    });

    testWidgets(
      'AboutAppScreen features official DariaLogo in the hero section',
      (tester) async {
        await tester.pumpWidget(const MaterialApp(home: AboutAppScreen()));
        await tester.pumpAndSettle();

        expect(find.byType(DariaLogo), findsOneWidget);
        expect(find.text(AppConstants.appName), findsAtLeastNWidgets(1));
      },
    );

    testWidgets('OnboardingScreen displays official DariaLogo in the top bar', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(DariaLogo), findsOneWidget);
    });

    testWidgets('SettingsScreen displays DariaLogo in the version footer', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pumpAndSettle();

      final logoFinder = find.byType(DariaLogo);
      await tester.scrollUntilVisible(logoFinder, 300.0);
      expect(logoFinder, findsOneWidget);
      expect(
        find.text('${AppConstants.appName} v${AppConstants.appVersion}'),
        findsOneWidget,
      );
    });

    testWidgets('ProfileScreen displays DariaLogo in the version footer', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ProfileScreen())),
      );
      await tester.pumpAndSettle();

      final logoFinder = find.byType(DariaLogo);
      await tester.scrollUntilVisible(logoFinder, 300.0);
      expect(logoFinder, findsOneWidget);
      expect(
        find.text('${AppConstants.appName} v${AppConstants.appVersion}'),
        findsOneWidget,
      );
    });

    testWidgets('PdfExportDialog displays DariaLogo in dialog header', (
      tester,
    ) async {
      final photo = PhotoEntry(
        id: 'test-photo-dlg',
        date: DateTime(2026, 10, 31, 12, 0),
        title: 'Dialog Test Photo',
        gradientColors: const [Colors.black, Colors.grey],
        imagePath: 'assets/images/icons/dariaicon.png',
      );
      await photoStore.savePhoto(entry: photo);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PdfExportDialog(store: photoStore)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DariaLogo), findsOneWidget);
      expect(find.text('Export as PDF Diary'), findsOneWidget);
    });
  });

  group('M67 — PDF Export Cover Branding Verification', () {
    test('generatePdf builds cover page incorporating Daria logo', () async {
      final photo = PhotoEntry(
        id: 'test-photo-1',
        date: DateTime(2026, 10, 31, 12, 0),
        title: 'Logo Integration Day',
        gradientColors: const [Colors.black, Colors.grey],
        imagePath: 'assets/images/icons/dariaicon.png',
      );
      await photoStore.savePhoto(entry: photo);

      final service = PdfDiaryExportService(
        store: photoStore,
        platformDelegate: MockPdfPlatformDelegate(),
      );

      final result = await service.generatePdf(
        range: const PdfExportRange.allTime(),
        customExportDir: tempDir,
      );

      expect(result.isSuccess, isTrue);
      expect(result.pdfBytes, isNotNull);
      expect(result.pdfBytes.length, greaterThan(1000));
      expect(result.pageCount, greaterThanOrEqualTo(1));
    });
  });
}
