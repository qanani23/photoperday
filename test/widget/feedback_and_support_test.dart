import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/core/theme/app_palette.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';
import 'package:photo_per_day/data/services/app_theme_storage.dart';
import 'package:photo_per_day/data/services/feedback_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/screens/settings/settings_screen.dart';
import 'package:photo_per_day/widgets/settings_group.dart';
import 'package:photo_per_day/widgets/settings_tile.dart';

class WidgetTestThemeStorage extends AppThemeStorage {
  WidgetTestThemeStorage({super.customBaseDir});

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

class TestUrlLauncherDelegate implements UrlLauncherDelegate {
  final List<Uri> launchedUris = [];
  bool shouldSucceed = true;

  @override
  Future<bool> launch(Uri uri) async {
    launchedUris.add(uri);
    return shouldSucceed;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late TestUrlLauncherDelegate mockLauncher;
  late FeedbackService feedbackService;
  late PersistentDailyPhotoStore photoStore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('daria_feedback_test_');

    final metaStorage = PhotoMetadataStorage(customBaseDir: tempDir);
    final fileManager = PhotoFileManager(customBaseDir: tempDir);
    photoStore = PersistentDailyPhotoStore(
      metadataStorage: metaStorage,
      fileManager: fileManager,
    );
    await photoStore.init();

    final themeStorage = WidgetTestThemeStorage();
    await AppThemeService.instance.init(storage: themeStorage);

    mockLauncher = TestUrlLauncherDelegate();
    feedbackService = FeedbackService(delegate: mockLauncher);
    FeedbackService.setTestInstance(feedbackService);
  });

  tearDown(() async {
    FeedbackService.resetTestInstance();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Widget buildSettingsApp() {
    return const MaterialApp(home: SettingsScreen());
  }

  group('Feedback & Support Settings Section UI Tests', () {
    testWidgets(
      'Feedback & Support section header and all 3 options are displayed',
      (tester) async {
        await tester.pumpWidget(buildSettingsApp());
        await tester.pumpAndSettle();

        // Scroll to reveal the Feedback & Support group
        final feedbackGroupFinder = find.widgetWithText(
          SettingsGroup,
          'FEEDBACK & SUPPORT',
        );
        expect(feedbackGroupFinder, findsOneWidget);

        // Verify "Report a Bug" tile with title and description
        expect(find.text('Report a Bug'), findsOneWidget);
        expect(
          find.text(
            "Found something that isn't working correctly? Let me know.",
          ),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.bug_report_outlined), findsOneWidget);

        // Verify "Suggest a Feature" tile with title and description
        expect(find.text('Suggest a Feature'), findsOneWidget);
        expect(
          find.text(
            'Have an idea that could make Daria better? Share it with me.',
          ),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.lightbulb_outlined), findsOneWidget);

        // Verify "General Feedback" tile with title and description
        expect(find.text('General Feedback'), findsOneWidget);
        expect(
          find.text(
            "Questions, thoughts, or suggestions? I'd love to hear from you.",
          ),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'Tapping Report a Bug opens Tally with bug_report category query param',
      (tester) async {
        await tester.pumpWidget(buildSettingsApp());
        await tester.pumpAndSettle();

        final bugTile = find.widgetWithText(SettingsTile, 'Report a Bug');
        await tester.ensureVisible(bugTile);
        await tester.tap(bugTile);
        await tester.pumpAndSettle();

        expect(mockLauncher.launchedUris.length, 1);
        expect(
          mockLauncher.launchedUris.first,
          Uri.parse('https://tally.so/r/perLYE?category=bug_report'),
        );
      },
    );

    testWidgets(
      'Tapping Suggest a Feature opens Tally with feature_request category query param',
      (tester) async {
        await tester.pumpWidget(buildSettingsApp());
        await tester.pumpAndSettle();

        final featureTile = find.widgetWithText(
          SettingsTile,
          'Suggest a Feature',
        );
        await tester.ensureVisible(featureTile);
        await tester.tap(featureTile);
        await tester.pumpAndSettle();

        expect(mockLauncher.launchedUris.length, 1);
        expect(
          mockLauncher.launchedUris.first,
          Uri.parse('https://tally.so/r/perLYE?category=feature_request'),
        );
      },
    );

    testWidgets(
      'Tapping General Feedback opens Tally with general_feedback category query param',
      (tester) async {
        await tester.pumpWidget(buildSettingsApp());
        await tester.pumpAndSettle();

        final generalTile = find.widgetWithText(
          SettingsTile,
          'General Feedback',
        );
        await tester.ensureVisible(generalTile);
        await tester.tap(generalTile);
        await tester.pumpAndSettle();

        expect(mockLauncher.launchedUris.length, 1);
        expect(
          mockLauncher.launchedUris.first,
          Uri.parse('https://tally.so/r/perLYE?category=general_feedback'),
        );
      },
    );

    testWidgets(
      'URL launch failure shows a friendly floating SnackBar without crashing',
      (tester) async {
        mockLauncher.shouldSucceed = false;

        await tester.pumpWidget(buildSettingsApp());
        await tester.pumpAndSettle();

        final generalTile = find.widgetWithText(
          SettingsTile,
          'General Feedback',
        );
        await tester.ensureVisible(generalTile);
        await tester.tap(generalTile);
        await tester.pump(); // Show snackbar

        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.text(
            'Could not open feedback form in browser. Please visit https://tally.so/r/perLYE',
          ),
          findsOneWidget,
        );

        // Verify user remains on Settings screen without navigation reset
        expect(find.text('Settings'), findsOneWidget);
      },
    );

    testWidgets(
      'Rapid repeated taps in UI trigger only a single launch attempt (debouncing)',
      (tester) async {
        await tester.pumpWidget(buildSettingsApp());
        await tester.pumpAndSettle();

        final bugTile = find.widgetWithText(SettingsTile, 'Report a Bug');
        await tester.ensureVisible(bugTile);

        // Rapidly tap 3 times without waiting for cooldown
        await tester.tap(bugTile);
        await tester.tap(bugTile);
        await tester.tap(bugTile);
        await tester.pumpAndSettle();

        // Only one launch attempt occurred
        expect(mockLauncher.launchedUris.length, 1);
      },
    );

    testWidgets(
      'Existing Settings groups (Preferences, Memories, Storage, About) remain intact',
      (tester) async {
        await tester.pumpWidget(buildSettingsApp());
        await tester.pumpAndSettle();

        expect(find.text('Preferences'.toUpperCase()), findsOneWidget);
        expect(find.text('Memories & Journal'.toUpperCase()), findsOneWidget);
        expect(find.text('Data & Storage'.toUpperCase()), findsOneWidget);
        expect(find.text('Feedback & Support'.toUpperCase()), findsOneWidget);
        expect(find.text('About'.toUpperCase()), findsOneWidget);
      },
    );

    testWidgets(
      'Feedback & Support renders properly across all registered themes',
      (tester) async {
        for (final palette in AppPalettes.all) {
          await AppThemeService.instance.setPalette(palette);

          await tester.pumpWidget(buildSettingsApp());
          await tester.pumpAndSettle();

          final feedbackHeader = find.widgetWithText(
            SettingsGroup,
            'FEEDBACK & SUPPORT',
          );
          expect(feedbackHeader, findsOneWidget);
          expect(find.text('Report a Bug'), findsOneWidget);
          expect(find.text('Suggest a Feature'), findsOneWidget);
          expect(find.text('General Feedback'), findsOneWidget);
        }
      },
    );
  });
}
