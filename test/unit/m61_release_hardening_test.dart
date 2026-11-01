@Timeout(Duration(seconds: 90))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/pdf_export_models.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/app_theme_storage.dart';
import 'package:photo_per_day/data/services/daily_reminder_storage.dart';
import 'package:photo_per_day/data/services/pad_backup_service.dart';
import 'package:photo_per_day/data/services/pdf_diary_export_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDir;
  late Directory storeDir;
  late Directory workDir;
  late PhotoFileManager fileManager;
  late PhotoMetadataStorage metadataStorage;
  late PersistentDailyPhotoStore store;
  late PadBackupService backupService;
  late PdfDiaryExportService pdfExportService;

  final sampleJpgBytes = Uint8List.fromList([
    0xFF,
    0xD8,
    0xFF,
    0xE0,
    0x00,
    0x10,
    0x4A,
    0x46,
    0x49,
    0x46,
    0x00,
    0x01,
    0x01,
    0x01,
    0x00,
    0x48,
    0x00,
    0x48,
    0x00,
    0x00,
    0xFF,
    0xDB,
    0x00,
    0x43,
    0x00,
    0x08,
    0x06,
    0x06,
    0x07,
    0x06,
    0x05,
    0x08,
    0x07,
    0x07,
    0x07,
    0x09,
    0x09,
    0x08,
    0x0A,
    0x0C,
    0x14,
    0x0D,
    0x0C,
    0x0B,
    0x0B,
    0x0C,
    0x19,
    0x12,
    0x13,
    0x0F,
    0x14,
    0x1D,
    0x1A,
    0x1F,
    0x1E,
    0x1D,
    0x1A,
    0x1C,
    0x1C,
    0x20,
    0x24,
    0x2E,
    0x27,
    0x20,
    0x22,
    0x2C,
    0x23,
    0x1C,
    0x1C,
    0x28,
    0x37,
    0x29,
    0x2C,
    0x30,
    0x31,
    0x34,
    0x34,
    0x34,
    0x1F,
    0x27,
    0x39,
    0x3D,
    0x38,
    0x32,
    0x3C,
    0x2E,
    0x33,
    0x34,
    0x32,
    0xFF,
    0xC0,
    0x00,
    0x0B,
    0x08,
    0x00,
    0x01,
    0x00,
    0x01,
    0x01,
    0x01,
    0x11,
    0x00,
    0xFF,
    0xC4,
    0x00,
    0x1F,
    0x00,
    0x00,
    0x01,
    0x05,
    0x01,
    0x01,
    0x01,
    0x01,
    0x01,
    0x01,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x01,
    0x02,
    0x03,
    0x04,
    0x05,
    0x06,
    0x07,
    0x08,
    0x09,
    0x0A,
    0x0B,
    0xFF,
    0xDA,
    0x00,
    0x08,
    0x01,
    0x01,
    0x00,
    0x00,
    0x3F,
    0x00,
    0xBF,
    0x00,
    0xFF,
    0xD9,
  ]);

  setUp(() async {
    testDir = Directory.systemTemp.createTempSync('m61_hardening_test_');
    storeDir = Directory('${testDir.path}/app_store');
    workDir = Directory('${testDir.path}/work_dir');
    await storeDir.create(recursive: true);
    await workDir.create(recursive: true);

    fileManager = PhotoFileManager(customBaseDir: storeDir);
    metadataStorage = PhotoMetadataStorage(customBaseDir: storeDir);
    await fileManager.init();
    await metadataStorage.init();

    store = PersistentDailyPhotoStore(
      fileManager: fileManager,
      metadataStorage: metadataStorage,
    );
    await store.init(customBaseDir: storeDir);
    PersistentDailyPhotoStore.setTestInstance(store);

    backupService = PadBackupService(
      store: store,
      fileManager: fileManager,
      metadataStorage: metadataStorage,
      themeStorage: AppThemeStorage(customBaseDir: storeDir.path),
      reminderStorage: DailyReminderStorage(customBaseDir: storeDir.path),
      customTempDir: workDir,
    );

    pdfExportService = PdfDiaryExportService(
      store: store,
      defaultExportDir: workDir,
    );
    PdfDiaryExportService.setTestInstance(pdfExportService);
  });

  tearDown(() async {
    PersistentDailyPhotoStore.resetTestInstance();
    PdfDiaryExportService.resetTestInstance();
    try {
      if (testDir.existsSync()) {
        testDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Future<File> createTestPhotoFile(String name) async {
    final file = File('${testDir.path}/$name');
    await file.writeAsBytes(sampleJpgBytes, flush: true);
    return file;
  }

  group('M61: Data Integrity & Metadata Crash Recovery', () {
    test(
      '1. Interrupted write leaves .tmp file when metadataFile is missing: loadDays recovers metadata',
      () async {
        // Simulate an interrupted write:
        // A valid temporary write file exists, but metadataFile does not exist yet (or was lost)
        final validEnvelope = {
          'schemaVersion': 2,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
          'days': {
            '2026-06-15': {
              'dateKey': '2026-06-15',
              'note': 'Recovered after sudden power loss',
              'createdAt': '2026-06-15T10:00:00.000Z',
              'updatedAt': '2026-06-15T10:00:00.000Z',
              'photos': [
                {
                  'id': 'rec_photo_1',
                  'date': '2026-06-15T10:00:00.000Z',
                  'title': 'Golden Hour',
                  'location': 'Mountain Crest',
                  'imagePath': 'photos/2026-06-15_rec.jpg',
                  'gradientColors': [4284900966, 4294198070],
                  'timeFormatted': '10:00 AM',
                  'syncStatus': 'localOnly',
                },
              ],
            },
          },
        };

        final tmpFile = File(
          '${metadataStorage.metadataFile.path}.1700000000_1.tmp',
        );
        await tmpFile.writeAsString(jsonEncode(validEnvelope), flush: true);

        // Ensure primary metadataFile does not exist
        if (await metadataStorage.metadataFile.exists()) {
          await metadataStorage.metadataFile.delete();
        }

        // Re-initialize storage and load days
        final loaded = await metadataStorage.loadDays();

        expect(loaded.length, equals(1));
        final recoveredDay = loaded[const DateKey(2026, 6, 15)];
        expect(recoveredDay, isNotNull);
        expect(recoveredDay!.note, equals('Recovered after sudden power loss'));
        expect(recoveredDay.photos.length, equals(1));
        expect(recoveredDay.photos.first.title, equals('Golden Hour'));

        // Verify that metadataFile was automatically restored on disk
        expect(await metadataStorage.metadataFile.exists(), isTrue);
      },
    );

    test(
      '2. Corrupted or truncated metadataFile recovers from valid temporary write file',
      () async {
        // Simulate disk corruption: primary metadataFile is 0-byte or truncated JSON
        await metadataStorage.metadataFile.writeAsString(
          '{ truncated json broken content',
          flush: true,
        );

        final validEnvelope = {
          'schemaVersion': 2,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
          'days': {
            '2026-07-20': {
              'dateKey': '2026-07-20',
              'note': 'Saved before corruption',
              'createdAt': '2026-07-20T12:00:00.000Z',
              'updatedAt': '2026-07-20T12:00:00.000Z',
              'photos': [],
            },
          },
        };

        final tmpFile = File(
          '${metadataStorage.metadataFile.path}.1700000050_1.tmp',
        );
        await tmpFile.writeAsString(jsonEncode(validEnvelope), flush: true);

        final loaded = await metadataStorage.loadDays();
        expect(loaded.length, equals(1));
        final day = loaded[const DateKey(2026, 7, 20)];
        expect(day, isNotNull);
        expect(day!.note, equals('Saved before corruption'));
        expect(day.isNoteOnly, isTrue);
      },
    );

    test(
      '3. Fallback recovery from pre_restore backup if metadata is corrupt and no tmp exists',
      () async {
        await metadataStorage.metadataFile.writeAsString('', flush: true);

        final backupEnvelope = {
          'schemaVersion': 2,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
          'days': {
            '2026-08-10': {
              'dateKey': '2026-08-10',
              'note': 'Pre-restore backup keeper',
              'createdAt': '2026-08-10T08:00:00.000Z',
              'updatedAt': '2026-08-10T08:00:00.000Z',
              'photos': [],
            },
          },
        };

        final preRestoreBak = File(
          '${storeDir.path}/photos_metadata.pre_restore.bak',
        );
        await preRestoreBak.writeAsString(
          jsonEncode(backupEnvelope),
          flush: true,
        );

        final loaded = await metadataStorage.loadDays();
        expect(loaded.length, equals(1));
        expect(
          loaded[const DateKey(2026, 8, 10)]?.note,
          equals('Pre-restore backup keeper'),
        );
      },
    );
  });

  group('M61: Backup Restore Safety & Replace Interruption Rollback', () {
    test(
      '4. Interrupted Replace in committing state safely rolls back to previous metadata and preserves all live photo bytes',
      () async {
        // 1. Establish live diary with a photo
        final liveImg = await createTestPhotoFile('live_diary_photo.jpg');
        final originalLiveBytes = await liveImg.readAsBytes();

        final savedLivePhoto = await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 9, 10),
            title: 'Live Precious Memory',
            gradientColors: const [Colors.blue, Colors.cyan],
            imagePath: liveImg.path,
          ),
        );

        final liveManagedPath = savedLivePhoto.imagePath!;
        expect(File(liveManagedPath).existsSync(), isTrue);

        // 2. Simulate process interruption right as committing state was entered
        final stagedNewFile = File(
          '${storeDir.path}/photos/2026-09-12_new_restore.jpg',
        );
        await stagedNewFile.writeAsBytes([1, 2, 3, 4], flush: true);

        // Backup snapshot of live metadata exists
        final metaBak = File('${workDir.path}/photos_metadata.pre_restore.bak');
        await metadataStorage.metadataFile.copy(metaBak.path);

        // Journal records state 'committing' for Replace mode
        final journalFile = File('${workDir.path}/restore_journal.json');
        await journalFile.writeAsString(
          jsonEncode({
            'state': 'committing',
            'mode': 'replace',
            'newlyCopiedFiles': [stagedNewFile.path],
            'oldPhotosToDeleteOnSuccess': [liveManagedPath],
          }),
          flush: true,
        );

        // 3. Trigger recovery (as happens on cold app startup)
        final recovered = await backupService.recoverPendingRestore();
        expect(recovered, isTrue);

        // CRITICAL VERIFICATION:
        // Live photo bytes MUST NOT be deleted!
        expect(File(liveManagedPath).existsSync(), isTrue);
        final currentLiveBytes = await File(liveManagedPath).readAsBytes();
        expect(currentLiveBytes, equals(originalLiveBytes));

        // Newly copied restore file MUST be rolled back/cleaned up
        expect(await stagedNewFile.exists(), isFalse);

        // Live diary metadata remains 100% intact
        expect(store.count, equals(1));
        final liveEntry = store.getPhotoByKey(const DateKey(2026, 9, 10))!;
        expect(liveEntry.title, equals('Live Precious Memory'));
        expect(liveEntry.imagePath, equals(liveManagedPath));

        // Journal was cleanly removed
        expect(await journalFile.exists(), isFalse);
      },
    );

    test(
      '5. Committed state finalizes deletion of obsolete photos only after verified commit',
      () async {
        final oldObsolete = File('${storeDir.path}/photos/obsolete_photo.jpg');
        await oldObsolete.writeAsBytes([9, 8, 7], flush: true);

        final journalFile = File('${workDir.path}/restore_journal.json');
        await journalFile.writeAsString(
          jsonEncode({
            'state': 'committed',
            'mode': 'replace',
            'newlyCopiedFiles': [],
            'oldPhotosToDeleteOnSuccess': [oldObsolete.path],
          }),
          flush: true,
        );

        final recovered = await backupService.recoverPendingRestore();
        expect(recovered, isTrue);

        // Old obsolete file is cleaned
        expect(await oldObsolete.exists(), isFalse);
        expect(await journalFile.exists(), isFalse);
      },
    );
  });

  group('M61: Temporary Artifact Lifecycle & Storage Cleanliness', () {
    test(
      '6. Stale temporary .padbackup files and staging folders are removed without affecting live diary',
      () async {
        // Create live photo
        final liveImg = await createTestPhotoFile('live_keeper.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 5, 20),
            title: 'Live Keeper',
            gradientColors: const [],
            imagePath: liveImg.path,
          ),
        );

        // Create stale temporary backups and staging folders in workDir
        final staleBackup = File(
          '${workDir.path}/photoperday_backup_12345.padbackup',
        );
        await staleBackup.writeAsString('stale backup bytes');

        final staleStaging = Directory('${workDir.path}/staging_99999');
        await staleStaging.create(recursive: true);
        final staleInner = File('${staleStaging.path}/staged.jpg');
        await staleInner.writeAsString('stale staged photo');

        expect(await staleBackup.exists(), isTrue);
        expect(await staleStaging.exists(), isTrue);

        // Run cleanup
        final cleanedCount = await backupService.cleanTemporaryBackups();
        expect(cleanedCount, greaterThanOrEqualTo(2));
        expect(await staleBackup.exists(), isFalse);
        expect(await staleStaging.exists(), isFalse);

        // Live diary remains untouched
        expect(store.count, equals(1));
        expect(store.hasPhotoByKey(const DateKey(2026, 5, 20)), isTrue);
      },
    );

    test(
      '7. Stale PDF exports are cleaned up without mutating diary records',
      () async {
        final stalePdf = File(
          '${workDir.path}/photo_a_day_diary_2026_1111.pdf',
        );
        await stalePdf.writeAsString('%PDF-1.4 dummy content');
        expect(await stalePdf.exists(), isTrue);

        final cleanedCount = await pdfExportService.cleanTemporaryExports(
          customExportDir: workDir,
        );
        expect(cleanedCount, greaterThanOrEqualTo(1));
        expect(await stalePdf.exists(), isFalse);
      },
    );
  });

  group('M61: PDF Export Safety & Invariance', () {
    test(
      '8. Generating PDF diary does not mutate store state or alter photo files',
      () async {
        final img = await createTestPhotoFile('pdf_test.jpg');
        final originalBytes = await img.readAsBytes();

        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 3, 15, 14, 30),
            title: 'Spring Blossom',
            location: 'Botanical Gardens',
            gradientColors: const [Colors.pink, Colors.purple],
            imagePath: img.path,
          ),
        );

        await store.updateDayNote(
          dateKey: const DateKey(2026, 3, 15),
          note: 'Cherishing early blossoms in peace.',
        );

        final preCount = store.count;
        final preDays = store.totalDays;

        final result = await pdfExportService.generatePdf(
          range: const PdfExportRange.allTime(),
          customExportDir: workDir,
        );

        expect(result.isSuccess, isTrue);
        expect(result.exportedPhotoCount, equals(1));
        expect(result.pageCount, greaterThan(0));

        // Invariant: Store state and counts completely unchanged
        expect(store.count, equals(preCount));
        expect(store.totalDays, equals(preDays));

        // Invariant: Photo file bytes completely unchanged
        final postBytes = await img.readAsBytes();
        expect(postBytes, equals(originalBytes));
      },
    );
  });
}
