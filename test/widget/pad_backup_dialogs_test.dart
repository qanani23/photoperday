@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/pad_backup_models.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/pad_backup_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/widgets/pad_backup_export_dialog.dart';
import 'package:photo_per_day/widgets/pad_backup_restore_dialog.dart';

class _WidgetTestMetadataStorage extends PhotoMetadataStorage {
  final Map<DateKey, PhotoEntry> memory = {};

  @override
  Future<void> init() async {}

  @override
  Future<Map<DateKey, PhotoEntry>> loadAll() async => Map.from(memory);

  @override
  Future<void> saveAll(Map<DateKey, PhotoEntry> entries) async {
    memory.clear();
    memory.addAll(entries);
  }

  @override
  Future<void> clear() async {
    memory.clear();
  }
}

class _WidgetTestFileManager extends PhotoFileManager {
  @override
  Future<void> init() async {}

  @override
  Directory get photosDir => Directory.systemTemp;

  @override
  Future<String> persistPhotoFile({
    required String sourcePath,
    required DateKey dateKey,
  }) async => sourcePath;

  @override
  bool isManagedPath(String path) => true;

  @override
  Future<bool> deletePhotoFile(String? path) async => true;

  @override
  Future<void> clearAll() async {}
}

class _MockWidgetBackupDelegate implements PadBackupPlatformDelegate {
  bool shareCalled = false;
  bool saveCalled = false;
  String? fileToPick;

  @override
  Future<bool> shareBackupFile({
    required String filePath,
    required String filename,
  }) async {
    shareCalled = true;
    return true;
  }

  @override
  Future<String?> saveBackupToUserDestination({
    required String sourceFilePath,
    required String suggestedFilename,
  }) async {
    saveCalled = true;
    return '/mock/destination/$suggestedFilename';
  }

  @override
  Future<String?> pickBackupFile() async {
    return fileToPick;
  }
}

class _TestPadBackupService extends PadBackupService {
  _TestPadBackupService({
    required super.store,
    required super.platformDelegate,
    this.customInspectionResult,
  });

  PadBackupExportResult? customExportResult;
  PadBackupInspectionResult? customInspectionResult;
  PadRestoreResult? customRestoreResult;
  PadBackupEstimate? customEstimate;

  @override
  Future<PadBackupEstimate> calculateEstimatedExportSize() async {
    return customEstimate ??
        const PadBackupEstimate(
          totalBytes: 2500000,
          availablePhotos: 5,
          missingPhotos: 0,
        );
  }

  @override
  Future<PadBackupExportResult> exportBackup({
    bool allowPartial = false,
    void Function(double progress, String status)? onProgress,
  }) async {
    onProgress?.call(0.5, 'Backing up...');
    return customExportResult ??
        PadBackupExportResult(
          backupFile: File('/fake/photoperday_backup_123.padbackup'),
          photoCount: 5,
          skippedCount: 0,
          totalSizeBytes: 2500000,
          isSuccess: true,
        );
  }

  @override
  Future<PadBackupInspectionResult> inspectBackupFile(
    File backupFile, {
    void Function(double progress, String status)? onProgress,
  }) async {
    onProgress?.call(0.5, 'Inspecting...');
    return customInspectionResult ??
        PadBackupInspectionResult(
          isValid: true,
          totalPhotosInBackup: 5,
          currentPhotosInDiary: store?.count ?? 0,
          nonConflictingCount: 3,
          conflictingCount: 2,
          manifest: PadBackupManifest(
            formatVersion: 1,
            appVersion: '1.0.0',
            appName: 'Photo a Day',
            createdAt: DateTime(2026, 3, 1),
            isPartial: false,
            photoCount: 5,
            totalSizeBytes: 2500000,
            startDate: '2026-03-01',
            endDate: '2026-03-05',
            photos: const [],
            skippedPhotos: const [],
            metadataChecksum: 'abc',
          ),
          stagingDir: Directory.systemTemp,
        );
  }

  @override
  Future<PadRestoreResult> restoreFromInspection(
    PadBackupInspectionResult inspection, {
    required PadRestoreMode mode,
    PadConflictResolution conflictResolution =
        PadConflictResolution.keepExisting,
    void Function(double progress, String status)? onProgress,
  }) async {
    onProgress?.call(0.5, 'Restoring...');
    return customRestoreResult ??
        PadRestoreResult.success(
          mode: mode,
          importedCount: 3,
          preservedCount: 2,
        );
  }

  @override
  Future<void> cleanStagingDirectory(Directory? stagingDir) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PersistentDailyPhotoStore testStore;
  late _WidgetTestMetadataStorage testMetadata;
  late _WidgetTestFileManager testFileManager;
  late _MockWidgetBackupDelegate mockDelegate;

  setUp(() async {
    testMetadata = _WidgetTestMetadataStorage();
    testFileManager = _WidgetTestFileManager();
    testStore = PersistentDailyPhotoStore(
      fileManager: testFileManager,
      metadataStorage: testMetadata,
    );
    await testStore.init();
    PersistentDailyPhotoStore.setTestInstance(testStore);
    mockDelegate = _MockWidgetBackupDelegate();
  });

  tearDown(() {
    PersistentDailyPhotoStore.resetTestInstance();
  });

  Widget buildTestApp(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('M55 — PadBackup Dialog Widget Tests', () {
    testWidgets('1. Export Dialog: shows empty state when diary has 0 photos', (
      tester,
    ) async {
      final service = _TestPadBackupService(
        store: testStore,
        platformDelegate: mockDelegate,
      );

      await tester.pumpWidget(
        buildTestApp(PadBackupExportDialog(service: service)),
      );
      await tester.pump();

      expect(find.text('Your Diary is Empty'), findsOneWidget);
      expect(
        find.text(
          'Capture daily memories first to generate a portable backup archive.',
        ),
        findsOneWidget,
      );
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets(
      '2. Export Dialog: shows estimated size and initiates backup creation',
      (tester) async {
        // Add a test photo so diary is not empty
        testStore.setPhoto(
          PhotoEntry(
            date: DateTime(2026, 3, 1),
            title: 'Memory 1',
            gradientColors: const [],
            imagePath: '/fake/img1.jpg',
          ),
        );

        final service = _TestPadBackupService(
          store: testStore,
          platformDelegate: mockDelegate,
        );

        await tester.pumpWidget(
          buildTestApp(PadBackupExportDialog(service: service)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Create Portable Backup'), findsOneWidget);
        expect(find.text('Available Memories'), findsOneWidget);
        expect(find.text('5 photos'), findsOneWidget);
        expect(find.text('Estimated Backup Size'), findsOneWidget);
        expect(find.text('Create Backup'), findsOneWidget);

        // Tap Create Backup
        final createBtn = find.text('Create Backup');
        await tester.ensureVisible(createBtn);
        await tester.tap(createBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Should transition to completed state
        expect(find.text('Backup Created Successfully!'), findsOneWidget);
        expect(find.text('Save to Files'), findsOneWidget);
        expect(find.text('Share Backup'), findsOneWidget);

        // Tap Share
        final shareBtn = find.text('Share Backup');
        await tester.ensureVisible(shareBtn);
        await tester.tap(shareBtn);
        await tester.pump();
        expect(mockDelegate.shareCalled, isTrue);

        // Tap Save to Files
        final saveBtn = find.text('Save to Files');
        await tester.ensureVisible(saveBtn);
        await tester.tap(saveBtn);
        await tester.pump();
        expect(mockDelegate.saveCalled, isTrue);
      },
    );

    testWidgets(
      '3. Restore Dialog: cancels cleanly when user cancels file picker',
      (tester) async {
        mockDelegate.fileToPick = null; // User cancelled file picker

        final service = _TestPadBackupService(
          store: testStore,
          platformDelegate: mockDelegate,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () =>
                      PadBackupRestoreDialog.show(context, service: service),
                  child: const Text('Open Restore'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Restore'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // After user cancellation, dialog was popped and is no longer present
        expect(find.byType(PadBackupRestoreDialog), findsNothing);
      },
    );

    testWidgets(
      '4. Restore Dialog: displays error when backup inspection fails',
      (tester) async {
        final service = _TestPadBackupService(
          store: testStore,
          platformDelegate: mockDelegate,
          customInspectionResult: PadBackupInspectionResult.invalid(
            'Unsupported format version (99).',
          ),
        );

        await tester.pumpWidget(
          buildTestApp(
            PadBackupRestoreDialog(
              service: service,
              initialFile: File('/fake/backup.padbackup'),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Backup Verification Failed'), findsOneWidget);
        expect(find.text('Unsupported format version (99).'), findsOneWidget);
        expect(find.text('Close'), findsOneWidget);
      },
    );

    testWidgets(
      '5. Restore Dialog: populated preview displays options and restores successfully',
      (tester) async {
        // Live diary has 2 memories
        testStore.setPhoto(
          PhotoEntry(
            date: DateTime(2026, 3, 1),
            title: 'Live 1',
            gradientColors: const [],
            imagePath: '/fake/img1.jpg',
          ),
        );
        testStore.setPhoto(
          PhotoEntry(
            date: DateTime(2026, 3, 2),
            title: 'Live 2',
            gradientColors: const [],
            imagePath: '/fake/img2.jpg',
          ),
        );

        final service = _TestPadBackupService(
          store: testStore,
          platformDelegate: mockDelegate,
        );

        await tester.pumpWidget(
          buildTestApp(
            PadBackupRestoreDialog(
              service: service,
              initialFile: File('/fake/backup.padbackup'),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Restore Diary Backup'), findsOneWidget);
        expect(find.text('Photos in Backup'), findsOneWidget);
        expect(find.text('5 photos'), findsOneWidget);
        expect(find.text('Current Diary Photos'), findsOneWidget);
        expect(find.text('2 photos recorded'), findsOneWidget);

        expect(
          find.text('Merge with Existing Diary (Recommended)'),
          findsOneWidget,
        );
        expect(find.text('Replace Entire Diary (Caution)'), findsOneWidget);

        // Perform Merge Restore
        final restoreBtnFinder = find.text('Restore Memories');
        await tester.ensureVisible(restoreBtnFinder);
        await tester.tap(restoreBtnFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Diary Restored Successfully!'), findsOneWidget);
        expect(find.text('Done'), findsOneWidget);
      },
    );

    testWidgets(
      '6. Restore Dialog: Replace mode requires confirmation checkbox',
      (tester) async {
        testStore.setPhoto(
          PhotoEntry(
            date: DateTime(2026, 3, 1),
            title: 'Live 1',
            gradientColors: const [],
            imagePath: '/fake/img1.jpg',
          ),
        );

        final service = _TestPadBackupService(
          store: testStore,
          platformDelegate: mockDelegate,
        );

        await tester.pumpWidget(
          buildTestApp(
            PadBackupRestoreDialog(
              service: service,
              initialFile: File('/fake/backup.padbackup'),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Tap Replace Entire Diary option card
        final replaceCard = find.text('Replace Entire Diary (Caution)');
        await tester.ensureVisible(replaceCard);
        await tester.tap(replaceCard);
        await tester.pump();

        // Check that button says "Replace Diary"
        final buttonFinder = find.widgetWithText(
          ElevatedButton,
          'Replace Diary',
        );
        expect(buttonFinder, findsOneWidget);

        // Confirm button is initially disabled until checkbox is checked
        ElevatedButton button = tester.widget(buttonFinder);
        expect(button.onPressed, isNull);

        // Tap confirmation checkbox
        final checkboxFinder = find.byType(Checkbox);
        await tester.ensureVisible(checkboxFinder);
        await tester.tap(checkboxFinder);
        await tester.pump();

        // Button is now enabled
        button = tester.widget(buttonFinder);
        expect(button.onPressed, isNotNull);

        // Execute Replace
        await tester.ensureVisible(buttonFinder);
        await tester.tap(buttonFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Diary Restored Successfully!'), findsOneWidget);
      },
    );
  });
}
