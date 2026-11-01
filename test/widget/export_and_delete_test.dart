import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/diary_export_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/screens/profile/profile_screen.dart';

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
    tempDir = await Directory.systemTemp.createTemp('widget_export_delete_');
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

  Widget buildTestWidget() {
    return const MaterialApp(home: Scaffold(body: ProfileScreen()));
  }

  Future<void> addSamplePhoto(DateKey key) async {
    final photoFile = File(
      '${tempDir.path}${Platform.pathSeparator}photo_${key.year}_${key.month}_${key.day}.jpg',
    );
    photoFile.writeAsBytesSync(List.filled(512, 7));

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

  group('ProfileScreen Local Export & Delete Tests', () {
    testWidgets(
      'renders Data & Storage section with local photo storage, export, and delete tiles',
      (tester) async {
        setLargeScreen(tester);
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('DATA & STORAGE'), findsOneWidget);
        expect(find.text('Local Photo Storage'), findsOneWidget);
        expect(find.text('Export Diary'), findsOneWidget);
        expect(find.text('Delete Local Diary'), findsOneWidget);
        // Cloud tiles no longer exist
        expect(find.text('Delete Google Drive Backup'), findsNothing);
        expect(find.text('Delete Local & Cloud Data'), findsNothing);
      },
    );

    testWidgets('Export Diary with empty store shows empty notice dialog', (
      tester,
    ) async {
      setLargeScreen(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final exportTile = find.text('Export Diary');
      await tester.ensureVisible(exportTile);
      await tester.tap(exportTile);
      await tester.pumpAndSettle();

      expect(find.text('Export Diary'), findsWidgets);
      expect(
        find.text('Your diary does not contain any photos to export yet.'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await tester.pumpAndSettle();
      expect(
        find.text('Your diary does not contain any photos to export yet.'),
        findsNothing,
      );
    });

    testWidgets(
      'Export Diary with photos prompts confirmation and runs export',
      (tester) async {
        setLargeScreen(tester);
        await addSamplePhoto(const DateKey(2026, 5, 1));
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        final exportTile = find.text('Export Diary');
        await tester.ensureVisible(exportTile);
        await tester.tap(exportTile);
        await tester.pumpAndSettle();

        expect(find.text('Export Your Diary'), findsOneWidget);
        expect(
          find.textContaining('into a standard ZIP archive'),
          findsOneWidget,
        );

        // Tap Export button
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
        expect(
          find.textContaining('1 photo exported successfully'),
          findsOneWidget,
        );

        // Dismiss dialog
        await tester.tap(find.widgetWithText(TextButton, 'Done'));
        await tester.pumpAndSettle();
        expect(find.text('Export Complete'), findsNothing);
      },
    );

    testWidgets('Delete Local Diary shows confirmation and deletes local diary', (
      tester,
    ) async {
      setLargeScreen(tester);
      await addSamplePhoto(const DateKey(2026, 5, 2));
      expect(photoStore.totalPhotos, 1);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final deleteLocalTile = find.text('Delete Local Diary');
      await tester.ensureVisible(deleteLocalTile);
      await tester.tap(deleteLocalTile);
      await tester.pumpAndSettle();

      // Verify destructive confirmation dialog
      expect(find.text('Delete Local Diary?'), findsOneWidget);
      expect(
        find.textContaining(
          'Because Daria operates entirely offline, this action cannot be undone.',
        ),
        findsOneWidget,
      );

      // Tap Delete Local Diary
      await tester.tap(
        find.widgetWithText(TextButton, 'Delete Local Diary').last,
      );
      await tester.pumpAndSettle();

      // Local diary is now empty
      expect(photoStore.totalPhotos, 0);
      expect(
        find.textContaining(
          'Local diary photos and metadata have been deleted.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Delete Local Diary cancel preserves photos', (tester) async {
      setLargeScreen(tester);
      await addSamplePhoto(const DateKey(2026, 5, 3));
      expect(photoStore.totalPhotos, 1);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final deleteLocalTile = find.text('Delete Local Diary');
      await tester.ensureVisible(deleteLocalTile);
      await tester.tap(deleteLocalTile);
      await tester.pumpAndSettle();

      // Tap Cancel
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      // Photo preserved
      expect(photoStore.totalPhotos, 1);
    });
  });
}
