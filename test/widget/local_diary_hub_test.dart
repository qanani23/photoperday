import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/app.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/diary_export_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/screens/home/home_screen.dart';
import 'package:photo_per_day/screens/profile/profile_screen.dart';
import 'package:photo_per_day/screens/settings/settings_screen.dart';
import 'package:photo_per_day/widgets/app_icon_button.dart';
import 'package:photo_per_day/widgets/bottom_nav_dock.dart';

class WidgetTestPhotoMetadataStorage extends PhotoMetadataStorage {
  WidgetTestPhotoMetadataStorage({super.customBaseDir});

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
  Future<void> clear() async {
    _memory.clear();
  }
}

class WidgetTestPhotoFileManager extends PhotoFileManager {
  WidgetTestPhotoFileManager({super.customBaseDir});

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
  Future<bool> deletePhotoFile(String? path) async {
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
    return true;
  }

  @override
  Future<void> clearAll() async {}

  @override
  Future<List<String>> pruneUnreferencedPhotos(
    Set<String> referencedPaths,
  ) async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory exportDir;
  late PersistentDailyPhotoStore photoStore;
  late DiaryExportService exportService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('local_diary_hub_test_');
    exportDir = Directory('${tempDir.path}${Platform.pathSeparator}exports');
    await exportDir.create(recursive: true);

    final fileManager = WidgetTestPhotoFileManager(customBaseDir: tempDir);
    final metadataStorage = WidgetTestPhotoMetadataStorage(
      customBaseDir: tempDir,
    );

    photoStore = PersistentDailyPhotoStore(
      fileManager: fileManager,
      metadataStorage: metadataStorage,
    );
    await photoStore.init();
    PersistentDailyPhotoStore.setTestInstance(photoStore);

    exportService = DiaryExportService(
      store: photoStore,
      defaultExportDir: exportDir,
    );
    DiaryExportService.setTestInstance(exportService);
  });

  tearDown(() async {
    DiaryExportService.resetTestInstance();
    PersistentDailyPhotoStore.resetTestInstance();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Future<void> addSamplePhoto(DateKey key) async {
    final photoFile = File(
      '${tempDir.path}${Platform.pathSeparator}photo_${key.year}_${key.month}_${key.day}.jpg',
    );
    photoFile.writeAsBytesSync(List.filled(256, 1));

    await photoStore.savePhoto(
      entry: PhotoEntry(
        date: key.toDateTime(),
        title: 'Memory ${key.format()}',
        location: 'Garden',
        gradientColors: const [Color(0xFF111111), Color(0xFF222222)],
        imagePath: photoFile.path,
        syncStatus: SyncStatus.localOnly,
      ),
    );
  }

  void setLargeScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Widget buildTestProfileWidget() {
    return const MaterialApp(home: Scaffold(body: ProfileScreen()));
  }

  Widget buildTestSettingsWidget() {
    return const MaterialApp(home: SettingsScreen());
  }

  group('Milestone 52 — Local Diary Hub ProfileScreen Tests', () {
    testWidgets(
      '1. Profile renders local identity without placeholder account names',
      (tester) async {
        setLargeScreen(tester);
        await tester.pumpWidget(buildTestProfileWidget());
        await tester.pumpAndSettle();

        // Screen Header
        expect(find.text('Profile'), findsOneWidget);
        expect(find.text('Personal Diary & Preferences'), findsOneWidget);
        expect(find.text('Account & Google Drive Sync'), findsNothing);

        // Profile Identity Card
        expect(find.text('Daily Photo Diary'), findsOneWidget);
        expect(
          find.text('Stored on device • Private & offline'),
          findsOneWidget,
        );
        expect(find.text('Active Local Diary'), findsOneWidget);
        expect(find.text('Sarah Jenkins'), findsNothing);
        expect(find.text('SJ'), findsNothing);
        expect(find.text('Member since January 2026'), findsNothing);

        // Prominent Local Storage Transparency Card
        expect(find.text('Local-Only Storage'), findsOneWidget);
        expect(find.text('On Device Only'), findsOneWidget);
        expect(find.text('Sign in with Google'), findsNothing);
        expect(
          find.textContaining(
            'No cloud account or internet connection is required.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '2. Profile screen completely excludes cloud-dependent UI controls',
      (tester) async {
        setLargeScreen(tester);
        await tester.pumpWidget(buildTestProfileWidget());
        await tester.pumpAndSettle();

        // No Google Account section or tiles
        expect(find.text('Google Account'), findsNothing);
        expect(find.text('Sign in to enable future cloud sync'), findsNothing);
        expect(find.text('Sign In'), findsNothing);
        expect(find.text('Sign Out'), findsNothing);
        expect(find.text('Disconnect Account'), findsNothing);

        // No Google Drive Backup section or tiles
        expect(find.text('Google Drive Backup'), findsNothing);
        expect(find.text('Storage & Backup'), findsNothing);
        expect(find.text('Manual Cloud Sync'), findsNothing);
        expect(find.text('Sync Now'), findsNothing);
        expect(find.text('Upload Test Photo'), findsNothing);
        expect(find.text('Delete Google Drive Backup'), findsNothing);
        expect(find.text('Delete Local & Cloud Data'), findsNothing);
      },
    );

    testWidgets(
      '3. Local streak and statistics section displays local-only footnote',
      (tester) async {
        setLargeScreen(tester);
        await tester.pumpWidget(buildTestProfileWidget());
        await tester.pumpAndSettle();

        expect(find.text('PHOTO STREAK'), findsOneWidget);
        expect(find.text('Current Streak'), findsOneWidget);
        expect(find.text('Longest Streak'), findsOneWidget);
        expect(find.text('Recorded Days'), findsOneWidget);
        expect(
          find.text('Local diary streak derived from your daily photos.'),
          findsOneWidget,
        );
        expect(find.textContaining('Google Drive'), findsNothing);
      },
    );

    testWidgets(
      '4. Data & Storage group renders with local photo storage, export, and delete tiles',
      (tester) async {
        setLargeScreen(tester);
        await addSamplePhoto(const DateKey(2026, 3, 1));
        await tester.pumpWidget(buildTestProfileWidget());
        await tester.pumpAndSettle();

        expect(find.text('DATA & STORAGE'), findsOneWidget);
        expect(find.text('Local Photo Storage'), findsOneWidget);
        expect(find.text('Export Diary'), findsOneWidget);
        expect(find.text('Delete Local Diary'), findsOneWidget);
        expect(
          find.text('Permanently remove all local photos and metadata'),
          findsOneWidget,
        );

        // Tap Local Photo Storage opens information dialog
        await tester.tap(find.text('Local Photo Storage'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('stored locally on this device.'),
          findsOneWidget,
        );
        expect(find.textContaining('App photo storage:'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Close'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      '5. Export Diary action prompts confirmation and exports locally',
      (tester) async {
        setLargeScreen(tester);
        await addSamplePhoto(const DateKey(2026, 3, 10));
        await tester.pumpWidget(buildTestProfileWidget());
        await tester.pumpAndSettle();

        final exportTile = find.text('Export Diary');
        await tester.tap(exportTile);
        await tester.pumpAndSettle();

        expect(find.text('Export Your Diary'), findsOneWidget);
        expect(
          find.textContaining(
            'The archive is created locally on your device without transmitting data over the internet.',
          ),
          findsOneWidget,
        );

        // Confirm export
        await tester.tap(find.widgetWithText(TextButton, 'Export'));
        await tester.pump();

        // Step pump to advance frames while background export completes
        for (int i = 0; i < 30; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 25));
          });
          await tester.pump(const Duration(milliseconds: 100));
          if (find.text('Export Complete').evaluate().isNotEmpty) {
            break;
          }
        }

        expect(find.text('Export Complete'), findsOneWidget);
        expect(find.textContaining('exported successfully.'), findsOneWidget);

        await tester.tap(find.widgetWithText(TextButton, 'Done'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      '6. Delete Local Diary prompts local-only confirmation without Drive references',
      (tester) async {
        setLargeScreen(tester);
        await addSamplePhoto(const DateKey(2026, 3, 15));
        await tester.pumpWidget(buildTestProfileWidget());
        await tester.pumpAndSettle();

        final deleteTile = find.text('Delete Local Diary');
        await tester.tap(deleteTile);
        await tester.pumpAndSettle();

        expect(find.text('Delete Local Diary?'), findsOneWidget);
        expect(
          find.textContaining(
            'Because Daria operates entirely offline, this action cannot be undone.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Google Drive'), findsNothing);

        // Confirm deletion
        await tester.tap(find.widgetWithText(TextButton, 'Delete Local Diary'));
        await tester.pumpAndSettle();

        expect(photoStore.totalPhotos, equals(0));
        expect(
          find.text('Local diary photos and metadata have been deleted.'),
          findsOneWidget,
        );
      },
    );
  });

  group('Milestone 52 — Local SettingsScreen Tests', () {
    testWidgets(
      '7. SettingsScreen excludes Google Account and Drive controls, renders Data & Storage',
      (tester) async {
        setLargeScreen(tester);
        await tester.pumpWidget(buildTestSettingsWidget());
        await tester.pumpAndSettle();

        // No account or drive backup
        expect(find.text('Account & Identity'), findsNothing);
        expect(find.text('Google Account & Cloud Backup'), findsNothing);
        expect(find.text('Delete Drive Backup'), findsNothing);

        // Preferences preserved
        expect(find.text('PREFERENCES'), findsOneWidget);
        expect(find.text('Daily Reminder'), findsOneWidget);
        expect(find.text('Start of Week'), findsOneWidget);
        expect(find.text('Dark Mode'), findsOneWidget);
        expect(find.text('Match System Theme'), findsOneWidget);

        // Data & Storage group
        expect(find.text('DATA & STORAGE'), findsOneWidget);
        expect(find.text('Local Photo Storage'), findsOneWidget);
        expect(find.text('Export Diary'), findsOneWidget);
        expect(find.text('Delete Local Diary'), findsOneWidget);
      },
    );

    testWidgets(
      '8. SettingsScreen Delete Local Diary uses honest local confirmation',
      (tester) async {
        setLargeScreen(tester);
        await addSamplePhoto(const DateKey(2026, 3, 20));
        await tester.pumpWidget(buildTestSettingsWidget());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Delete Local Diary'));
        await tester.pumpAndSettle();

        expect(find.text('Delete Local Diary?'), findsOneWidget);
        expect(
          find.textContaining(
            'Because Daria operates entirely offline, this action cannot be undone.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Google Drive'), findsNothing);

        // Cancel preserves photos
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();

        expect(photoStore.totalPhotos, equals(1));
      },
    );
  });

  group('Milestone 52 — Navigation & Shell Integration Tests', () {
    testWidgets(
      '9. Home to Settings navigation, Me tab navigation, and back flow works cleanly',
      (tester) async {
        setLargeScreen(tester);
        await tester.pumpWidget(const PhotoPerDayApp());
        await tester.pumpAndSettle();

        // Starts on Home
        expect(find.byType(HomeScreen), findsOneWidget);

        // Tap gear Settings icon in header
        final settingsButton = find.widgetWithText(AppHeaderAction, 'Settings');
        expect(settingsButton, findsOneWidget);
        await tester.tap(settingsButton);
        await tester.pumpAndSettle();

        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(find.text('Account & Identity'), findsNothing);

        // Back to Home
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);

        // Switch to Me tab via dock
        final meTab = find.descendant(
          of: find.byType(BottomNavDock),
          matching: find.text('Me'),
        );
        await tester.tap(meTab);
        await tester.pumpAndSettle();

        expect(find.byType(ProfileScreen), findsOneWidget);
        expect(find.text('Daily Photo Diary'), findsOneWidget);
        expect(find.text('Personal Diary & Preferences'), findsOneWidget);

        // Switch back to Home tab via dock
        final homeTab = find.descendant(
          of: find.byType(BottomNavDock),
          matching: find.text('Home'),
        );
        await tester.tap(homeTab);
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );
  });
}
