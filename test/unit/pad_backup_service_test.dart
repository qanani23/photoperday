@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/daily_reminder_settings.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/pad_backup_models.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/app_theme_storage.dart';
import 'package:photo_per_day/data/services/daily_reminder_storage.dart';
import 'package:photo_per_day/data/services/pad_backup_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';

class _MockPadBackupPlatformDelegate implements PadBackupPlatformDelegate {
  bool shareCalled = false;
  String? lastSharedPath;
  String? lastSharedFilename;

  bool saveCalled = false;
  String? lastSavedSourcePath;
  String? lastSavedFilename;
  String? saveDestinationPath;

  String? fileToPick;

  @override
  Future<bool> shareBackupFile({
    required String filePath,
    required String filename,
  }) async {
    shareCalled = true;
    lastSharedPath = filePath;
    lastSharedFilename = filename;
    return true;
  }

  @override
  Future<String?> saveBackupToUserDestination({
    required String sourceFilePath,
    required String suggestedFilename,
  }) async {
    saveCalled = true;
    lastSavedSourcePath = sourceFilePath;
    lastSavedFilename = suggestedFilename;
    if (saveDestinationPath != null) {
      final source = File(sourceFilePath);
      final dest = File(saveDestinationPath!);
      await source.copy(dest.path);
      return dest.path;
    }
    return null;
  }

  @override
  Future<String?> pickBackupFile() async {
    return fileToPick;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory storeDir;
  late Directory workDir;
  late PersistentDailyPhotoStore store;
  late PhotoFileManager fileManager;
  late PhotoMetadataStorage metadataStorage;
  late AppThemeStorage themeStorage;
  late DailyReminderStorage reminderStorage;
  late _MockPadBackupPlatformDelegate mockDelegate;
  late PadBackupService service;

  // 1x1 valid sample image bytes
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
    0x7F,
    0x00,
    0xFF,
    0xD9,
  ]);

  Future<File> createTestImageFile(
    String name, {
    Uint8List? customBytes,
  }) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(customBytes ?? sampleJpgBytes, flush: true);
    return file;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('m55_unit_test_');
    storeDir = Directory('${tempDir.path}/store');
    workDir = Directory('${tempDir.path}/work');
    await storeDir.create(recursive: true);
    await workDir.create(recursive: true);

    fileManager = PhotoFileManager(customBaseDir: storeDir);
    metadataStorage = PhotoMetadataStorage(customBaseDir: storeDir);
    themeStorage = AppThemeStorage(customBaseDir: storeDir.path);
    reminderStorage = DailyReminderStorage(customBaseDir: storeDir.path);

    store = PersistentDailyPhotoStore(
      fileManager: fileManager,
      metadataStorage: metadataStorage,
    );
    await store.init();

    mockDelegate = _MockPadBackupPlatformDelegate();
    service = PadBackupService(
      store: store,
      fileManager: fileManager,
      metadataStorage: metadataStorage,
      themeStorage: themeStorage,
      reminderStorage: reminderStorage,
      platformDelegate: mockDelegate,
      customTempDir: workDir,
    );
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('M55 — Portable .padbackup Export & Restore Unit Tests', () {
    test(
      '1. Empty diary export returns empty result and creates no file',
      () async {
        final result = await service.exportBackup();

        expect(result.isEmpty, isTrue);
        expect(result.isSuccess, isFalse);
        expect(result.backupFile, isNull);
        expect(result.photoCount, equals(0));
      },
    );

    test(
      '2. Populated diary export generates valid .padbackup with manifest and SHA-256',
      () async {
        final img1 = await createTestImageFile('source1.jpg');
        final img2 = await createTestImageFile('source2.jpg');

        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 3, 1),
            title: 'First Memory',
            location: 'Home',
            timeFormatted: '10:00 AM',
            gradientColors: const [],
            imagePath: img1.path,
          ),
        );

        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 3, 2),
            title: 'Second Memory',
            location: 'Park',
            timeFormatted: '2:30 PM',
            gradientColors: const [],
            imagePath: img2.path,
          ),
        );

        final result = await service.exportBackup();

        expect(result.isSuccess, isTrue);
        expect(result.backupFile, isNotNull);
        expect(result.photoCount, equals(2));
        expect(result.skippedCount, equals(0));
        expect(result.isPartial, isFalse);

        final file = result.backupFile!;
        expect(await file.exists(), isTrue);
        expect(file.path.endsWith('.padbackup'), isTrue);

        // Inspect ZIP container
        final archiveBytes = await file.readAsBytes();
        final archive = ZipDecoder().decodeBytes(archiveBytes);
        final names = archive.files.map((f) => f.name).toSet();

        expect(names.contains('manifest.json'), isTrue);
        expect(names.contains('photos_metadata.json'), isTrue);
        expect(names.contains('preferences.json'), isTrue);
        expect(names.contains('photos/2026-03-01.jpg'), isTrue);
        expect(names.contains('photos/2026-03-02.jpg'), isTrue);

        // Verify manifest content
        final manifestFile = archive.findFile('manifest.json')!;
        final manifestJson =
            jsonDecode(utf8.decode(manifestFile.content as List<int>)) as Map;
        expect(manifestJson['formatVersion'], equals(2));
        expect(manifestJson['appName'], equals('Daria'));
        expect(manifestJson['photoCount'], equals(2));
        expect(manifestJson['isPartial'], isFalse);

        final photosList = manifestJson['photos'] as List;
        expect(photosList.length, equals(2));
        final photo1 = photosList[0] as Map;
        expect(photo1['dateKey'], equals('2026-03-01'));
        expect(photo1['sha256'], isNotEmpty);
      },
    );

    test(
      '3. Original photo bytes are preserved without modification',
      () async {
        final customBytes = Uint8List.fromList(List.generate(256, (i) => i));
        final img = await createTestImageFile(
          'custom.jpg',
          customBytes: customBytes,
        );

        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 4, 10),
            title: 'Raw Bytes Test',
            gradientColors: const [],
            imagePath: img.path,
          ),
        );

        final result = await service.exportBackup();
        expect(result.isSuccess, isTrue);

        final archive = ZipDecoder().decodeBytes(
          await result.backupFile!.readAsBytes(),
        );
        final archivedPhoto = archive.findFile('photos/2026-04-10.jpg')!;
        final extractedBytes = Uint8List.fromList(
          archivedPhoto.content as List<int>,
        );

        expect(extractedBytes, equals(customBytes));
      },
    );

    test(
      '4. Partial backup policy handles missing photo files with user consent',
      () async {
        final img1 = await createTestImageFile('valid.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 5, 1),
            title: 'Valid Photo',
            gradientColors: const [],
            imagePath: img1.path,
          ),
        );

        final img2 = await createTestImageFile('missing.jpg');
        final saved2 = await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 5, 2),
            title: 'Missing Photo',
            gradientColors: const [],
            imagePath: img2.path,
          ),
        );

        // Delete the second file from disk to simulate missing file
        final photoFile2 = File(saved2.imagePath!);
        if (await photoFile2.exists()) {
          await photoFile2.delete();
        }

        // Check estimate
        final estimate = await service.calculateEstimatedExportSize();
        expect(estimate.availablePhotos, equals(1));
        expect(estimate.missingPhotos, equals(1));
        expect(estimate.hasMissingPhotos, isTrue);

        // Export without allowPartial should fail honestly
        final failResult = await service.exportBackup(allowPartial: false);
        expect(failResult.isSuccess, isFalse);
        expect(failResult.errorMessage, contains('missing or unreadable'));

        // Export with allowPartial should succeed with partial flag
        final partialResult = await service.exportBackup(allowPartial: true);
        expect(partialResult.isSuccess, isTrue);
        expect(partialResult.isPartial, isTrue);
        expect(partialResult.photoCount, equals(1));
        expect(partialResult.skippedCount, equals(1));
      },
    );

    test(
      '5. Pre-flight inspection validates manifest structure and checksums',
      () async {
        final img = await createTestImageFile('test.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 6, 15),
            title: 'Summer Solstice',
            gradientColors: const [],
            imagePath: img.path,
          ),
        );

        final exportRes = await service.exportBackup();
        final backupFile = exportRes.backupFile!;

        final inspection = await service.inspectBackupFile(backupFile);

        expect(inspection.isValid, isTrue);
        expect(inspection.validationError, isNull);
        expect(inspection.totalPhotosInBackup, equals(1));
        expect(inspection.manifest, isNotNull);
        expect(inspection.manifest!.formatVersion, equals(2));
        expect(inspection.stagingDir, isNotNull);
        expect(await inspection.stagingDir!.exists(), isTrue);

        // Clean staging
        await service.cleanStagingDirectory(inspection.stagingDir);
        expect(await inspection.stagingDir!.exists(), isFalse);
      },
    );

    test('6. Inspection rejects unsupported future format versions', () async {
      final img = await createTestImageFile('ver.jpg');
      await store.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2026, 7, 1),
          title: 'Future Version',
          gradientColors: const [],
          imagePath: img.path,
        ),
      );

      final exportRes = await service.exportBackup();
      final archiveBytes = await exportRes.backupFile!.readAsBytes();
      final archive = ZipDecoder().decodeBytes(archiveBytes);

      // Modify manifest to have formatVersion = 99
      final newArchive = Archive();
      for (final file in archive) {
        if (file.name == 'manifest.json') {
          final manifestMap =
              jsonDecode(utf8.decode(file.content as List<int>))
                  as Map<String, dynamic>;
          manifestMap['formatVersion'] = 99;
          final modifiedBytes = utf8.encode(jsonEncode(manifestMap));
          newArchive.addFile(
            ArchiveFile.bytes(
              'manifest.json',
              Uint8List.fromList(modifiedBytes),
            ),
          );
        } else {
          newArchive.addFile(file);
        }
      }

      final tamperedZipBytes = ZipEncoder().encode(newArchive);
      final tamperedFile = File('${workDir.path}/future_version.padbackup');
      await tamperedFile.writeAsBytes(tamperedZipBytes);

      final inspection = await service.inspectBackupFile(tamperedFile);
      expect(inspection.isValid, isFalse);
      expect(
        inspection.validationError,
        contains('Unsupported backup format version'),
      );
    });

    test('7. Inspection rejects Zip-Slip path traversal attempts', () async {
      final maliciousArchive = Archive();
      maliciousArchive.addFile(
        ArchiveFile.bytes('manifest.json', utf8.encode('{}')),
      );
      maliciousArchive.addFile(
        ArchiveFile.bytes(
          '../../../evil.txt',
          utf8.encode('malicious content'),
        ),
      );

      final zipBytes = ZipEncoder().encode(maliciousArchive);
      final maliciousFile = File('${workDir.path}/zip_slip.padbackup');
      await maliciousFile.writeAsBytes(zipBytes);

      final inspection = await service.inspectBackupFile(maliciousFile);
      expect(inspection.isValid, isFalse);
      expect(inspection.validationError, contains('Insecure path detected'));
    });

    test(
      '8. Inspection rejects archives with tampered photo bytes (SHA-256 mismatch)',
      () async {
        final img = await createTestImageFile('secure.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 8, 1),
            title: 'Checksum Integrity',
            gradientColors: const [],
            imagePath: img.path,
          ),
        );

        final exportRes = await service.exportBackup();
        final archive = ZipDecoder().decodeBytes(
          await exportRes.backupFile!.readAsBytes(),
        );

        // Replace photo bytes with different content to cause SHA mismatch
        final tamperedArchive = Archive();
        for (final file in archive) {
          if (file.name.startsWith('photos/')) {
            tamperedArchive.addFile(
              ArchiveFile.bytes(file.name, utf8.encode('corrupted bytes')),
            );
          } else {
            tamperedArchive.addFile(file);
          }
        }

        final tamperedFile = File('${workDir.path}/corrupt_photo.padbackup');
        await tamperedFile.writeAsBytes(ZipEncoder().encode(tamperedArchive));

        final inspection = await service.inspectBackupFile(tamperedFile);
        expect(inspection.isValid, isFalse);
        expect(inspection.validationError, contains('Checksum mismatch'));
      },
    );

    test('9. Full export and restore round-trip into an empty diary', () async {
      final img1 = await createTestImageFile('day1.jpg');
      final img2 = await createTestImageFile('day2.jpg');

      await store.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2026, 9, 1),
          title: 'Trip Start',
          location: 'Airport',
          gradientColors: const [],
          imagePath: img1.path,
        ),
      );

      await store.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2026, 9, 2),
          title: 'Destination',
          location: 'Paris',
          gradientColors: const [],
          imagePath: img2.path,
        ),
      );

      // Export
      final exportRes = await service.exportBackup();
      expect(exportRes.isSuccess, isTrue);

      // Clear the live diary completely
      await store.clearAsync();
      expect(store.count, equals(0));

      // Inspect
      final inspection = await service.inspectBackupFile(exportRes.backupFile!);
      expect(inspection.isValid, isTrue);
      expect(inspection.totalPhotosInBackup, equals(2));

      // Restore
      final restoreRes = await service.restoreFromInspection(
        inspection,
        mode: PadRestoreMode.replace,
      );

      expect(restoreRes.isSuccess, isTrue);
      expect(restoreRes.importedCount, equals(2));
      expect(store.count, equals(2));

      final entry1 = store.getPhotoByKey(const DateKey(2026, 9, 1));
      expect(entry1, isNotNull);
      expect(entry1!.title, equals('Trip Start'));
      expect(entry1.location, equals('Airport'));
      expect(File(entry1.imagePath!).existsSync(), isTrue);

      final entry2 = store.getPhotoByKey(const DateKey(2026, 9, 2));
      expect(entry2, isNotNull);
      expect(entry2!.title, equals('Destination'));
      expect(entry2.location, equals('Paris'));
      expect(File(entry2.imagePath!).existsSync(), isTrue);
    });

    test(
      '10. Merge restore with no conflicts adds all backup photos',
      () async {
        final img1 = await createTestImageFile('existing.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 1, 1),
            title: 'New Year',
            gradientColors: const [],
            imagePath: img1.path,
          ),
        );

        // Create a separate backup containing Day 2
        final freshDir = Directory('${tempDir.path}/fresh');
        await freshDir.create();
        final freshStore = PersistentDailyPhotoStore(
          fileManager: PhotoFileManager(customBaseDir: freshDir),
          metadataStorage: PhotoMetadataStorage(customBaseDir: freshDir),
        );
        await freshStore.init();

        final img2 = await createTestImageFile('backup_day.jpg');
        await freshStore.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 1, 2),
            title: 'Day Two Backup',
            gradientColors: const [],
            imagePath: img2.path,
          ),
        );

        final backupService = PadBackupService(
          store: freshStore,
          customTempDir: workDir,
        );
        final exportRes = await backupService.exportBackup();

        // Inspect and Merge into live store
        final inspection = await service.inspectBackupFile(
          exportRes.backupFile!,
        );
        expect(inspection.nonConflictingCount, equals(1));
        expect(inspection.conflictingCount, equals(0));

        final restoreRes = await service.restoreFromInspection(
          inspection,
          mode: PadRestoreMode.merge,
        );

        expect(restoreRes.isSuccess, isTrue);
        expect(restoreRes.importedCount, equals(1));
        expect(store.count, equals(2));
        expect(store.hasPhotoByKey(const DateKey(2026, 1, 1)), isTrue);
        expect(store.hasPhotoByKey(const DateKey(2026, 1, 2)), isTrue);
      },
    );

    test('11. Merge conflict with keepExisting preserves live entry', () async {
      final img1 = await createTestImageFile('live.jpg');
      await store.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2026, 2, 14),
          title: 'Valentine Live',
          gradientColors: const [],
          imagePath: img1.path,
        ),
      );

      // Create backup with conflicting date but different title
      final otherDir = Directory('${tempDir.path}/other');
      await otherDir.create();
      final otherStore = PersistentDailyPhotoStore(
        fileManager: PhotoFileManager(customBaseDir: otherDir),
        metadataStorage: PhotoMetadataStorage(customBaseDir: otherDir),
      );
      await otherStore.init();

      final img2 = await createTestImageFile('backup_v.jpg');
      await otherStore.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2026, 2, 14),
          title: 'Valentine Backup',
          gradientColors: const [],
          imagePath: img2.path,
        ),
      );

      final backupService = PadBackupService(
        store: otherStore,
        customTempDir: workDir,
      );
      final exportRes = await backupService.exportBackup();

      final inspection = await service.inspectBackupFile(exportRes.backupFile!);
      expect(inspection.conflictingCount, equals(1));

      final restoreRes = await service.restoreFromInspection(
        inspection,
        mode: PadRestoreMode.merge,
        conflictResolution: PadConflictResolution.keepExisting,
      );

      expect(restoreRes.isSuccess, isTrue);
      expect(restoreRes.preservedCount, equals(1));
      expect(restoreRes.replacedCount, equals(0));

      // Live photo was preserved
      final entry = store.getPhotoByKey(const DateKey(2026, 2, 14))!;
      expect(entry.title, equals('Valentine Live'));
    });

    test(
      '12. Merge conflict with overwriteWithBackup replaces conflicting entry',
      () async {
        final img1 = await createTestImageFile('live.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 2, 14),
            title: 'Valentine Live',
            gradientColors: const [],
            imagePath: img1.path,
          ),
        );

        final otherDir = Directory('${tempDir.path}/other2');
        await otherDir.create();
        final otherStore = PersistentDailyPhotoStore(
          fileManager: PhotoFileManager(customBaseDir: otherDir),
          metadataStorage: PhotoMetadataStorage(customBaseDir: otherDir),
        );
        await otherStore.init();

        final img2 = await createTestImageFile('backup_v2.jpg');
        await otherStore.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 2, 14),
            title: 'Valentine Backup',
            gradientColors: const [],
            imagePath: img2.path,
          ),
        );

        final backupService = PadBackupService(
          store: otherStore,
          customTempDir: workDir,
        );
        final exportRes = await backupService.exportBackup();

        final inspection = await service.inspectBackupFile(
          exportRes.backupFile!,
        );

        final restoreRes = await service.restoreFromInspection(
          inspection,
          mode: PadRestoreMode.merge,
          conflictResolution: PadConflictResolution.overwriteWithBackup,
        );

        expect(restoreRes.isSuccess, isTrue);
        expect(restoreRes.replacedCount, equals(1));

        // Overwritten with backup photo
        final entry = store.getPhotoByKey(const DateKey(2026, 2, 14))!;
        expect(entry.title, equals('Valentine Backup'));
      },
    );

    test(
      '13. Replace mode replaces entire diary and updates photo count',
      () async {
        final img1 = await createTestImageFile('live1.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 10, 1),
            title: 'Live 1',
            gradientColors: const [],
            imagePath: img1.path,
          ),
        );

        final otherDir = Directory('${tempDir.path}/other3');
        await otherDir.create();
        final otherStore = PersistentDailyPhotoStore(
          fileManager: PhotoFileManager(customBaseDir: otherDir),
          metadataStorage: PhotoMetadataStorage(customBaseDir: otherDir),
        );
        await otherStore.init();

        final img2 = await createTestImageFile('replace_item.jpg');
        await otherStore.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 12, 25),
            title: 'Christmas Backup',
            gradientColors: const [],
            imagePath: img2.path,
          ),
        );

        final backupService = PadBackupService(
          store: otherStore,
          customTempDir: workDir,
        );
        final exportRes = await backupService.exportBackup();

        final inspection = await service.inspectBackupFile(
          exportRes.backupFile!,
        );
        final restoreRes = await service.restoreFromInspection(
          inspection,
          mode: PadRestoreMode.replace,
        );

        expect(restoreRes.isSuccess, isTrue);
        expect(store.count, equals(1));
        expect(store.hasPhotoByKey(const DateKey(2026, 10, 1)), isFalse);
        expect(store.hasPhotoByKey(const DateKey(2026, 12, 25)), isTrue);
      },
    );

    test(
      '14. Failure during restore triggers safe rollback preserving existing diary',
      () async {
        final liveImg = await createTestImageFile('keep_me.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 11, 1),
            title: 'Must Preserve',
            gradientColors: const [],
            imagePath: liveImg.path,
          ),
        );

        // Create a corrupted staging session where metadata references a missing file
        final workDirStaging = Directory('${workDir.path}/staging_corrupt');
        await workDirStaging.create();

        final corruptedMetadata = {
          '2026-11-05': {
            'date': '2026-11-05T00:00:00.000Z',
            'title': 'Corrupt Staging',
            'imagePath': 'photos/nonexistent.jpg',
            'gradientColors': [],
          },
        };
        await File(
          '${workDirStaging.path}/photos_metadata.json',
        ).writeAsString(jsonEncode(corruptedMetadata));

        final fakeInspection = PadBackupInspectionResult(
          isValid: true,
          stagingDir: workDirStaging,
          manifest: PadBackupManifest(
            formatVersion: 1,
            appVersion: '1.0.0',
            appName: 'Photo a Day',
            createdAt: DateTime.now(),
            isPartial: false,
            photoCount: 1,
            totalSizeBytes: 100,
            photos: const [],
            skippedPhotos: const [],
            metadataChecksum: '',
          ),
        );

        final result = await service.restoreFromInspection(
          fakeInspection,
          mode: PadRestoreMode.replace,
        );

        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, contains('rolled back'));

        // Verify original live entry is completely untouched
        expect(store.count, equals(1));
        final preserved = store.getPhotoByKey(const DateKey(2026, 11, 1))!;
        expect(preserved.title, equals('Must Preserve'));
        expect(File(preserved.imagePath!).existsSync(), isTrue);
      },
    );

    test(
      '15. Preferences round-trip correctly through export and restore',
      () async {
        await themeStorage.saveSettings(
          paletteId: 'midnight',
          followSystem: false,
        );
        await reminderStorage.saveSettings(
          const DailyReminderSettings(enabled: true, hour: 21, minute: 30),
        );

        final img = await createTestImageFile('pref.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 3, 20),
            title: 'Spring',
            gradientColors: const [],
            imagePath: img.path,
          ),
        );

        final exportRes = await service.exportBackup();
        expect(exportRes.isSuccess, isTrue);

        // Change preferences locally
        await themeStorage.saveSettings(
          paletteId: 'classicCaramel',
          followSystem: true,
        );
        await reminderStorage.saveSettings(
          const DailyReminderSettings(enabled: false, hour: 20, minute: 0),
        );

        final inspection = await service.inspectBackupFile(
          exportRes.backupFile!,
        );
        expect(inspection.hasPreferences, isTrue);

        final restoreRes = await service.restoreFromInspection(
          inspection,
          mode: PadRestoreMode.merge,
        );
        expect(restoreRes.isSuccess, isTrue);

        // Verify preferences restored
        final restoredTheme = await themeStorage.loadSettings();
        expect(restoredTheme.paletteId, equals('midnight'));
        expect(restoredTheme.followSystem, isFalse);

        final restoredReminders = await reminderStorage.loadSettings();
        expect(restoredReminders.enabled, isTrue);
        expect(restoredReminders.hour, equals(21));
        expect(restoredReminders.minute, equals(30));
      },
    );

    test(
      '16. Temporary exports and staging cleanup leaves photo library untouched',
      () async {
        final img = await createTestImageFile('clean.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 7, 7),
            title: 'Lucky Day',
            gradientColors: const [],
            imagePath: img.path,
          ),
        );

        await service.exportBackup();
        expect(workDir.listSync().isNotEmpty, isTrue);

        final deleted = await service.cleanTemporaryBackups();
        expect(deleted, greaterThanOrEqualTo(1));

        // Managed photo library remains untouched
        expect(store.count, equals(1));
        expect(store.hasPhotoByKey(const DateKey(2026, 7, 7)), isTrue);
      },
    );

    test(
      '17. Archive with duplicate file entries is rejected by pre-flight inspection',
      () async {
        final archive = Archive();
        archive.addFile(ArchiveFile.bytes('manifest.json', utf8.encode('{}')));
        archive.addFile(
          ArchiveFile.bytes('photos/2026-05-01.jpg', sampleJpgBytes),
        );
        archive.addFile(
          ArchiveFile.bytes('photos/./2026-05-01.jpg', sampleJpgBytes),
        );

        final zipBytes = ZipEncoder().encode(archive);
        final file = File('${workDir.path}/dup_archive.padbackup');
        await file.writeAsBytes(zipBytes);

        final inspection = await service.inspectBackupFile(file);
        expect(inspection.isValid, isFalse);
        expect(
          inspection.validationError,
          contains('Duplicate entry in backup archive'),
        );
      },
    );

    test(
      '18. Archive with unmanifested photo file in photos/ is rejected',
      () async {
        final img = await createTestImageFile('manifested.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 5, 1),
            title: 'Manifested',
            gradientColors: const [],
            imagePath: img.path,
          ),
        );

        final exportRes = await service.exportBackup();
        final archive = ZipDecoder().decodeBytes(
          await exportRes.backupFile!.readAsBytes(),
        );

        final tamperedArchive = Archive();
        for (final file in archive) {
          tamperedArchive.addFile(file);
        }
        // Add an extra unmanifested photo file into photos/
        tamperedArchive.addFile(
          ArchiveFile.bytes('photos/2026-05-02.jpg', sampleJpgBytes),
        );

        final zipBytes = ZipEncoder().encode(tamperedArchive);
        final file = File('${workDir.path}/unmanifested_extra.padbackup');
        await file.writeAsBytes(zipBytes);

        final inspection = await service.inspectBackupFile(file);
        expect(inspection.isValid, isFalse);
        expect(
          inspection.validationError,
          contains('Archive contains unreferenced photo'),
        );
      },
    );

    test(
      '19. Manifest with duplicate dateKey or duplicate archivePath is rejected',
      () async {
        final img = await createTestImageFile('dup_manifest.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 5, 1),
            title: 'Dup DateKey',
            gradientColors: const [],
            imagePath: img.path,
          ),
        );

        final exportRes = await service.exportBackup();
        final archive = ZipDecoder().decodeBytes(
          await exportRes.backupFile!.readAsBytes(),
        );

        final tamperedArchive = Archive();
        for (final file in archive) {
          if (file.name == 'manifest.json') {
            final manifestMap =
                jsonDecode(utf8.decode(file.content as List<int>))
                    as Map<String, dynamic>;
            final photosList = List<Map<String, dynamic>>.from(
              manifestMap['photos'] as List,
            );
            // Duplicate the photo item in the manifest list
            photosList.add(Map<String, dynamic>.from(photosList.first));
            manifestMap['photos'] = photosList;
            tamperedArchive.addFile(
              ArchiveFile.bytes(
                'manifest.json',
                utf8.encode(jsonEncode(manifestMap)),
              ),
            );
          } else {
            tamperedArchive.addFile(file);
          }
        }

        final zipBytes = ZipEncoder().encode(tamperedArchive);
        final file = File('${workDir.path}/dup_date_manifest.padbackup');
        await file.writeAsBytes(zipBytes);

        final inspection = await service.inspectBackupFile(file);
        expect(inspection.isValid, isFalse);
        expect(
          inspection.validationError,
          anyOf(
            contains('Duplicate DateKey'),
            contains('Duplicate archivePath'),
          ),
        );
      },
    );

    test(
      '20. Archive with metadata/manifest photo count mismatch is rejected',
      () async {
        final img = await createTestImageFile('mismatch.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 5, 1),
            title: 'Mismatch',
            gradientColors: const [],
            imagePath: img.path,
          ),
        );

        final exportRes = await service.exportBackup();
        final archive = ZipDecoder().decodeBytes(
          await exportRes.backupFile!.readAsBytes(),
        );

        // Modify metadata to add a ghost photo, and update manifest metadataChecksum to match
        final tamperedArchive = Archive();
        late List<int> newMetaBytes;
        for (final file in archive) {
          if (file.name == 'photos_metadata.json') {
            final metadataMap =
                jsonDecode(utf8.decode(file.content as List<int>))
                    as Map<String, dynamic>;
            if (metadataMap.containsKey('days') && metadataMap['days'] is Map) {
              final daysMap = metadataMap['days'] as Map<String, dynamic>;
              daysMap['2026-05-02'] = {
                'dateKey': '2026-05-02',
                'photos': [
                  {
                    'id': 'ghost_id',
                    'date': '2026-05-02T00:00:00.000Z',
                    'title': 'Ghost',
                    'imagePath': 'photos/2026-05-02.jpg',
                    'gradientColors': [],
                  },
                ],
                'note': '',
              };
            } else {
              metadataMap['2026-05-02'] = {
                'date': '2026-05-02T00:00:00.000Z',
                'title': 'Ghost',
                'imagePath': 'photos/2026-05-02.jpg',
                'gradientColors': [],
              };
            }
            newMetaBytes = utf8.encode(jsonEncode(metadataMap));
            tamperedArchive.addFile(
              ArchiveFile.bytes('photos_metadata.json', newMetaBytes),
            );
          } else {
            tamperedArchive.addFile(file);
          }
        }

        // Now update manifest's metadataChecksum to match newMetaBytes so checksum passes
        final finalArchive = Archive();
        final newMetaChecksum = sha256.convert(newMetaBytes).toString();
        for (final file in tamperedArchive) {
          if (file.name == 'manifest.json') {
            final manifestMap =
                jsonDecode(utf8.decode(file.content as List<int>))
                    as Map<String, dynamic>;
            manifestMap['metadataChecksum'] = newMetaChecksum;
            finalArchive.addFile(
              ArchiveFile.bytes(
                'manifest.json',
                utf8.encode(jsonEncode(manifestMap)),
              ),
            );
          } else {
            finalArchive.addFile(file);
          }
        }

        final zipBytes = ZipEncoder().encode(finalArchive);
        final file = File('${workDir.path}/mismatch_metadata.padbackup');
        await file.writeAsBytes(zipBytes);

        final inspection = await service.inspectBackupFile(file);
        expect(inspection.isValid, isFalse);
        expect(
          inspection.validationError,
          anyOf(
            contains('Metadata entry count'),
            contains('Metadata references photo path'),
          ),
        );
      },
    );

    test(
      '21. Decompression bomb protection rejects archives exceeding entry limit',
      () async {
        final bombArchive = Archive();
        for (int i = 0; i <= 5001; i++) {
          bombArchive.addFile(
            ArchiveFile.noCompress('test_$i.txt', 0, <int>[]),
          );
        }

        final zipBytes = ZipEncoder().encode(bombArchive);
        final file = File('${workDir.path}/entry_bomb.padbackup');
        await file.writeAsBytes(zipBytes);

        final inspection = await service.inspectBackupFile(file);
        expect(inspection.isValid, isFalse);
        expect(inspection.validationError, contains('safety limit'));
      },
    );

    test(
      '22. Path safety rejects absolute paths, drive letters, and null bytes',
      () async {
        // Drive letter path
        final driveArchive = Archive();
        driveArchive.addFile(
          ArchiveFile.bytes('C:\\evil.jpg', utf8.encode('evil')),
        );
        var file = File('${workDir.path}/drive_path.padbackup');
        await file.writeAsBytes(ZipEncoder().encode(driveArchive));
        var inspection = await service.inspectBackupFile(file);
        expect(inspection.isValid, isFalse);
        expect(inspection.validationError, contains('Insecure path detected'));

        // Null byte in path
        final nullByteArchive = Archive();
        nullByteArchive.addFile(
          ArchiveFile.bytes('photos/2026-01-01\x00.jpg', utf8.encode('evil')),
        );
        file = File('${workDir.path}/null_byte.padbackup');
        await file.writeAsBytes(ZipEncoder().encode(nullByteArchive));
        inspection = await service.inspectBackupFile(file);
        expect(inspection.isValid, isFalse);
        expect(inspection.validationError, contains('Insecure path detected'));
      },
    );

    test(
      '23. Injected failure during photo copying rolls back newly copied files and keeps pre-existing photos intact with original bytes',
      () async {
        // Save initial diary photo
        final liveImg = await createTestImageFile(
          'live_keeper.jpg',
          customBytes: sampleJpgBytes,
        );
        final originalBytes = await liveImg.readAsBytes();
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 6, 1),
            title: 'Live Keeper',
            gradientColors: const [],
            imagePath: liveImg.path,
          ),
        );

        // Create staging dir with one valid photo and one invalid/missing photo
        final stagingDir = Directory('${workDir.path}/staging_fail_copy');
        final stagingPhotos = Directory('${stagingDir.path}/photos');
        await stagingPhotos.create(recursive: true);

        final stagedFile1 = File('${stagingPhotos.path}/2026-06-02.jpg');
        await stagedFile1.writeAsBytes([1, 2, 3, 4]);

        final metadata = {
          '2026-06-02': {
            'date': '2026-06-02T00:00:00.000Z',
            'title': 'New 1',
            'imagePath': 'photos/2026-06-02.jpg',
            'gradientColors': [],
          },
          '2026-06-03': {
            'date': '2026-06-03T00:00:00.000Z',
            'title': 'New 2 Missing',
            'imagePath': 'photos/2026-06-03.jpg',
            'gradientColors': [],
          },
        };
        await File(
          '${stagingDir.path}/photos_metadata.json',
        ).writeAsString(jsonEncode(metadata));

        final fakeInspection = PadBackupInspectionResult(
          isValid: true,
          stagingDir: stagingDir,
          manifest: PadBackupManifest(
            formatVersion: 1,
            appVersion: '1.0.0',
            appName: 'Photo a Day',
            createdAt: DateTime.now(),
            isPartial: false,
            photoCount: 2,
            totalSizeBytes: 100,
            photos: const [],
            skippedPhotos: const [],
            metadataChecksum: '',
          ),
        );

        final result = await service.restoreFromInspection(
          fakeInspection,
          mode: PadRestoreMode.replace,
        );

        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, contains('rolled back'));

        // Invariant: Live diary entry must still exist and file bytes must match exactly
        expect(store.count, equals(1));
        final preserved = store.getPhotoByKey(const DateKey(2026, 6, 1))!;
        expect(preserved.title, equals('Live Keeper'));
        final liveBytesNow = await File(preserved.imagePath!).readAsBytes();
        expect(liveBytesNow, equals(originalBytes));

        // Journal and metadata backup should be cleaned up
        final journalFile = File('${workDir.path}/restore_journal.json');
        expect(await journalFile.exists(), isFalse);
      },
    );

    test(
      '24. Process interruption recovery in staged/copying state rolls back safely',
      () async {
        // Setup initial diary
        final liveImg = await createTestImageFile('live_orig.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 6, 10),
            title: 'Live Orig',
            gradientColors: const [],
            imagePath: liveImg.path,
          ),
        );

        // Simulate crash during copy:
        // A newly copied file was written to disk
        final stagedCopiedFile = File(
          '${storeDir.path}/photos/2026-06-11_restore_123.jpg',
        );
        await stagedCopiedFile.parent.create(recursive: true);
        await stagedCopiedFile.writeAsBytes([9, 9, 9]);

        // Backup snapshot created
        final metaBak = File('${workDir.path}/photos_metadata.pre_restore.bak');
        await metadataStorage.metadataFile.copy(metaBak.path);

        // Journal written with state 'copying'
        final journal = File('${workDir.path}/restore_journal.json');
        await journal.writeAsString(
          jsonEncode({
            'state': 'copying',
            'mode': 'replace',
            'newlyCopiedFiles': [stagedCopiedFile.path],
            'oldPhotosToDeleteOnSuccess': [liveImg.path],
          }),
        );

        final recovered = await service.recoverPendingRestore();
        expect(recovered, isTrue);

        // Interrupted newly copied file is deleted
        expect(await stagedCopiedFile.exists(), isFalse);
        // Original photo remains intact
        expect(await liveImg.exists(), isTrue);
        // Live diary still has exactly 1 entry
        expect(store.count, equals(1));
        expect(
          store.getPhotoByKey(const DateKey(2026, 6, 10))!.title,
          equals('Live Orig'),
        );
        // Journal is deleted
        expect(await journal.exists(), isFalse);
      },
    );

    test(
      '25. Process interruption recovery in committed state finalizes cleanup',
      () async {
        final oldObsoleteFile = File('${storeDir.path}/photos/obsolete.jpg');
        await oldObsoleteFile.parent.create(recursive: true);
        await oldObsoleteFile.writeAsBytes([7, 7, 7]);

        final journal = File('${workDir.path}/restore_journal.json');
        await journal.writeAsString(
          jsonEncode({
            'state': 'committed',
            'mode': 'replace',
            'newlyCopiedFiles': [],
            'oldPhotosToDeleteOnSuccess': [oldObsoleteFile.path],
          }),
        );

        final recovered = await service.recoverPendingRestore();
        expect(recovered, isTrue);

        // Obsolete file successfully deleted
        expect(await oldObsoleteFile.exists(), isFalse);
        // Journal cleaned
        expect(await journal.exists(), isFalse);
      },
    );

    test(
      '26. Diary persistence across app/store restart after successful restore and after failed restore',
      () async {
        // 1. Successful restore
        final img = await createTestImageFile('restart_test.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 9, 1),
            title: 'Pre-Restore Photo',
            gradientColors: const [],
            imagePath: img.path,
          ),
        );

        final exportRes = await service.exportBackup();
        expect(exportRes.isSuccess, isTrue);

        // Inspect and restore into store
        final inspection = await service.inspectBackupFile(
          exportRes.backupFile!,
        );
        final restoreRes = await service.restoreFromInspection(
          inspection,
          mode: PadRestoreMode.replace,
        );
        expect(restoreRes.isSuccess, isTrue);

        // Simulate app restart: Create completely new instance of PersistentDailyPhotoStore
        final newStoreAfterSuccess = PersistentDailyPhotoStore(
          fileManager: fileManager,
          metadataStorage: metadataStorage,
        );
        await newStoreAfterSuccess.init();
        expect(newStoreAfterSuccess.count, equals(1));
        final entry = newStoreAfterSuccess.getPhotoByKey(
          const DateKey(2026, 9, 1),
        );
        expect(entry, isNotNull);
        expect(entry!.title, equals('Pre-Restore Photo'));
        expect(File(entry.imagePath!).existsSync(), isTrue);

        // 2. Failed restore leaves disk persistence consistent
        final fakeInspection = PadBackupInspectionResult(
          isValid: true,
          stagingDir: Directory('${workDir.path}/nonexistent_staging'),
          manifest: PadBackupManifest(
            formatVersion: 1,
            appVersion: '1.0.0',
            appName: 'Photo a Day',
            createdAt: DateTime.now(),
            isPartial: false,
            photoCount: 1,
            totalSizeBytes: 100,
            photos: const [],
            skippedPhotos: const [],
            metadataChecksum: '',
          ),
        );

        final failRestore = await service.restoreFromInspection(
          fakeInspection,
          mode: PadRestoreMode.replace,
        );
        expect(failRestore.isSuccess, isFalse);

        // Simulate app restart again
        final newStoreAfterFailure = PersistentDailyPhotoStore(
          fileManager: fileManager,
          metadataStorage: metadataStorage,
        );
        await newStoreAfterFailure.init();
        expect(newStoreAfterFailure.count, equals(1));
        expect(
          newStoreAfterFailure.hasPhotoByKey(const DateKey(2026, 9, 1)),
          isTrue,
        );
      },
    );

    test(
      '27. Source photo bytes and metadata remain strictly immutable during export',
      () async {
        final img = await createTestImageFile(
          'immutable_src.jpg',
          customBytes: sampleJpgBytes,
        );
        final originalBytes = await img.readAsBytes();
        final originalLastModified = await img.lastModified();

        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 10, 1),
            title: 'Immutable Source',
            location: 'Studio Room',
            gradientColors: const [],
            imagePath: img.path,
          ),
        );

        final originalMetaBytes = await metadataStorage.metadataFile
            .readAsBytes();

        final exportRes = await service.exportBackup();
        expect(exportRes.isSuccess, isTrue);

        // Verify source photo was not modified
        final currentPhotoBytes = await img.readAsBytes();
        expect(currentPhotoBytes, equals(originalBytes));
        expect(await img.lastModified(), equals(originalLastModified));

        // Verify live metadata file was not modified
        final currentMetaBytes = await metadataStorage.metadataFile
            .readAsBytes();
        expect(currentMetaBytes, equals(originalMetaBytes));
      },
    );

    test(
      '28. Version 2 backup export and restore round-trip preserving multi-photo days, photo order, photo IDs, and notes',
      () async {
        const dateKey = DateKey(2026, 11, 1);
        final img1 = await createTestImageFile('v2_p1.jpg');
        final img2 = await createTestImageFile('v2_p2.jpg');
        final img3 = await createTestImageFile('v2_p3.jpg');

        await store.addPhotoToDay(
          dateKey: dateKey,
          photo: PhotoEntry(
            id: 'id_alpha',
            date: dateKey.toDateTime(),
            title: 'First Photo',
            location: 'Camp',
            imagePath: img1.path,
            gradientColors: const [],
          ),
        );
        await store.addPhotoToDay(
          dateKey: dateKey,
          photo: PhotoEntry(
            id: 'id_beta',
            date: dateKey.toDateTime(),
            title: 'Second Photo',
            location: 'Trail',
            imagePath: img2.path,
            gradientColors: const [],
          ),
        );
        await store.addPhotoToDay(
          dateKey: dateKey,
          photo: PhotoEntry(
            id: 'id_gamma',
            date: dateKey.toDateTime(),
            title: 'Third Photo',
            location: 'Summit',
            imagePath: img3.path,
            gradientColors: const [],
          ),
        );
        await store.updateDayNote(
          dateKey: dateKey,
          note:
              'Autumn colors in the valley and an exhilarating mountain hike.',
        );

        final exportRes = await service.exportBackup();
        expect(exportRes.isSuccess, isTrue);
        expect(exportRes.photoCount, equals(3));
        expect(exportRes.backupFile, isNotNull);

        final inspection = await service.inspectBackupFile(
          exportRes.backupFile!,
        );
        expect(inspection.isValid, isTrue);
        expect(inspection.manifest!.formatVersion, equals(2));
        expect(inspection.manifest!.dayCount, equals(1));
        expect(inspection.manifest!.photos.length, equals(3));
        expect(inspection.manifest!.photos[0].id, equals('id_alpha'));
        expect(inspection.manifest!.photos[0].order, equals(0));
        expect(inspection.manifest!.photos[1].id, equals('id_beta'));
        expect(inspection.manifest!.photos[1].order, equals(1));
        expect(inspection.manifest!.photos[2].id, equals('id_gamma'));
        expect(inspection.manifest!.photos[2].order, equals(2));

        // Clear live store completely
        await store.clearAsync();
        expect(store.totalDays, equals(0));
        expect(store.count, equals(0));

        // Restore in replace mode
        final restoreRes = await service.restoreFromInspection(
          inspection,
          mode: PadRestoreMode.replace,
        );
        expect(restoreRes.isSuccess, isTrue);
        expect(restoreRes.importedCount, equals(3));
        expect(store.totalDays, equals(1));

        final restoredDay = store.getDay(dateKey);
        expect(restoredDay, isNotNull);
        expect(restoredDay!.photos.length, equals(3));
        expect(
          restoredDay.note,
          equals(
            'Autumn colors in the valley and an exhilarating mountain hike.',
          ),
        );
        expect(restoredDay.photos[0].id, equals('id_alpha'));
        expect(restoredDay.photos[0].title, equals('First Photo'));
        expect(restoredDay.photos[0].order, equals(0));
        expect(File(restoredDay.photos[0].imagePath!).existsSync(), isTrue);

        expect(restoredDay.photos[1].id, equals('id_beta'));
        expect(restoredDay.photos[1].title, equals('Second Photo'));
        expect(restoredDay.photos[1].order, equals(1));
        expect(File(restoredDay.photos[1].imagePath!).existsSync(), isTrue);

        expect(restoredDay.photos[2].id, equals('id_gamma'));
        expect(restoredDay.photos[2].title, equals('Third Photo'));
        expect(restoredDay.photos[2].order, equals(2));
        expect(File(restoredDay.photos[2].imagePath!).existsSync(), isTrue);
      },
    );

    test('29. Note-only day round-trip into an empty diary', () async {
      const dateKey = DateKey(2026, 11, 2);
      await store.updateDayNote(
        dateKey: dateKey,
        note: 'Quiet rainy afternoon with tea.',
      );

      expect(store.totalDays, equals(1));
      expect(store.count, equals(0));

      final exportRes = await service.exportBackup();
      expect(exportRes.isSuccess, isTrue);
      expect(exportRes.isEmpty, isFalse);
      expect(exportRes.photoCount, equals(0));
      expect(exportRes.backupFile, isNotNull);

      final inspection = await service.inspectBackupFile(exportRes.backupFile!);
      expect(inspection.isValid, isTrue);
      expect(inspection.manifest!.dayCount, equals(1));
      expect(inspection.manifest!.photoCount, equals(0));

      // Clear store
      await store.clearAsync();
      expect(store.totalDays, equals(0));

      // Restore
      final restoreRes = await service.restoreFromInspection(
        inspection,
        mode: PadRestoreMode.replace,
      );
      expect(restoreRes.isSuccess, isTrue);
      expect(store.totalDays, equals(1));
      expect(store.count, equals(0));

      final restoredDay = store.getDay(dateKey);
      expect(restoredDay, isNotNull);
      expect(restoredDay!.photos, isEmpty);
      expect(restoredDay.note, equals('Quiet rainy afternoon with tea.'));
    });

    test(
      '30. Legacy Version 1 synthetic fixture import migrating legacy caption to daily reflection note',
      () async {
        final archive = Archive();
        final photoBytes = sampleJpgBytes;
        final photoSha = sha256.convert(photoBytes).toString();

        archive.addFile(ArchiveFile.bytes('photos/2026-04-10.jpg', photoBytes));

        final metadataJson = jsonEncode({
          '2026-04-10': {
            'date': '2026-04-10T10:00:00.000Z',
            'title': 'Sunset at Venice Beach Pier',
            'caption': 'Sunset at Venice Beach Pier',
            'location': 'Venice Beach',
            'gradientColors': [],
            'imagePath': 'photos/2026-04-10.jpg',
          },
        });
        final metadataSha = sha256
            .convert(utf8.encode(metadataJson))
            .toString();
        archive.addFile(
          ArchiveFile.bytes('photos_metadata.json', utf8.encode(metadataJson)),
        );

        final manifestJson = jsonEncode({
          'formatVersion': 1,
          'appVersion': '1.0.0',
          'appName': 'Photo a Day',
          'createdAt': '2026-04-10T12:00:00.000Z',
          'isPartial': false,
          'photoCount': 1,
          'totalSizeBytes': photoBytes.length,
          'photos': [
            {
              'dateKey': '2026-04-10',
              'archivePath': 'photos/2026-04-10.jpg',
              'sha256': photoSha,
              'sizeBytes': photoBytes.length,
              'title': 'Sunset at Venice Beach Pier',
              'location': 'Venice Beach',
              'timeFormatted': '10:00 AM',
            },
          ],
          'skippedPhotos': [],
          'metadataChecksum': metadataSha,
        });
        archive.addFile(
          ArchiveFile.bytes('manifest.json', utf8.encode(manifestJson)),
        );

        final v1File = File('${workDir.path}/legacy_v1.padbackup');
        await v1File.writeAsBytes(ZipEncoder().encode(archive));

        final inspection = await service.inspectBackupFile(v1File);
        expect(inspection.isValid, isTrue);
        expect(inspection.manifest!.formatVersion, equals(1));
        expect(inspection.manifest!.photoCount, equals(1));

        // Restore into empty store
        await store.clearAsync();
        final restoreRes = await service.restoreFromInspection(
          inspection,
          mode: PadRestoreMode.replace,
        );
        expect(restoreRes.isSuccess, isTrue);
        expect(restoreRes.importedCount, equals(1));

        final restoredDay = store.getDay(const DateKey(2026, 4, 10));
        expect(restoredDay, isNotNull);
        expect(restoredDay!.photos.length, equals(1));
        // Legacy caption migrated into daily reflection note
        expect(restoredDay.note, equals('Sunset at Venice Beach Pier'));
        expect(
          restoredDay.photos.first.title,
          equals('Sunset at Venice Beach Pier'),
        );
        expect(restoredDay.photos.first.location, equals('Venice Beach'));
      },
    );

    test(
      '31. Merge mode on multi-photo days respects keepExisting and overwriteWithBackup conflict policies',
      () async {
        const dateKey = DateKey(2026, 12, 1);
        final localImg = await createTestImageFile('local_merge.jpg');

        // Setup local diary
        await store.addPhotoToDay(
          dateKey: dateKey,
          photo: PhotoEntry(
            id: 'local_p1',
            date: dateKey.toDateTime(),
            title: 'Local Photo',
            imagePath: localImg.path,
            gradientColors: const [],
          ),
        );
        await store.updateDayNote(
          dateKey: dateKey,
          note: 'Local Reflection Note',
        );

        // Create a backup on a separate store containing a conflicting entry for the same date
        final externalDir = Directory('${tempDir.path}/external_merge');
        await externalDir.create();
        final externalStore = PersistentDailyPhotoStore(
          fileManager: PhotoFileManager(customBaseDir: externalDir),
          metadataStorage: PhotoMetadataStorage(customBaseDir: externalDir),
        );
        await externalStore.init();

        final extImg1 = await createTestImageFile('ext_p1.jpg');
        final extImg2 = await createTestImageFile('ext_p2.jpg');
        await externalStore.addPhotoToDay(
          dateKey: dateKey,
          photo: PhotoEntry(
            id: 'ext_p1',
            date: dateKey.toDateTime(),
            title: 'Backup Photo 1',
            imagePath: extImg1.path,
            gradientColors: const [],
          ),
        );
        await externalStore.addPhotoToDay(
          dateKey: dateKey,
          photo: PhotoEntry(
            id: 'ext_p2',
            date: dateKey.toDateTime(),
            title: 'Backup Photo 2',
            imagePath: extImg2.path,
            gradientColors: const [],
          ),
        );
        await externalStore.updateDayNote(
          dateKey: dateKey,
          note: 'Backup Reflection Note',
        );

        final extService = PadBackupService(
          store: externalStore,
          customTempDir: workDir,
        );
        final extExport = await extService.exportBackup();
        final extInspection = await service.inspectBackupFile(
          extExport.backupFile!,
        );
        expect(extInspection.isValid, isTrue);

        // 1. Merge with keepExisting -> Local data preserved
        final mergeKeepRes = await service.restoreFromInspection(
          extInspection,
          mode: PadRestoreMode.merge,
          conflictResolution: PadConflictResolution.keepExisting,
        );
        expect(mergeKeepRes.isSuccess, isTrue);
        expect(mergeKeepRes.preservedCount, equals(1));
        var dayAfterKeep = store.getDay(dateKey)!;
        expect(dayAfterKeep.photos.length, equals(1));
        expect(dayAfterKeep.photos.first.id, equals('local_p1'));
        expect(dayAfterKeep.note, equals('Local Reflection Note'));

        // 2. Merge with overwriteWithBackup -> Local data replaced with backup data
        final extInspectionOverwrite = await service.inspectBackupFile(
          extExport.backupFile!,
        );
        expect(extInspectionOverwrite.isValid, isTrue);

        final mergeOverwriteRes = await service.restoreFromInspection(
          extInspectionOverwrite,
          mode: PadRestoreMode.merge,
          conflictResolution: PadConflictResolution.overwriteWithBackup,
        );
        expect(mergeOverwriteRes.isSuccess, isTrue);
        expect(mergeOverwriteRes.replacedCount, equals(2));
        var dayAfterOverwrite = store.getDay(dateKey)!;
        expect(dayAfterOverwrite.photos.length, equals(2));
        expect(dayAfterOverwrite.photos[0].id, equals('ext_p1'));
        expect(dayAfterOverwrite.photos[1].id, equals('ext_p2'));
        expect(dayAfterOverwrite.note, equals('Backup Reflection Note'));
      },
    );

    test(
      '32. Replace mode on multi-photo days cleanly purges previous photos from disk and store',
      () async {
        const dateKey1 = DateKey(2026, 5, 1);
        const dateKey2 = DateKey(2026, 5, 2);

        final p1 = await store.addPhotoToDay(
          dateKey: dateKey1,
          photo: PhotoEntry(
            id: 'old_1',
            date: dateKey1.toDateTime(),
            title: 'Old Photo 1',
            imagePath: (await createTestImageFile('old1.jpg')).path,
            gradientColors: const [],
          ),
        );
        final p2 = await store.addPhotoToDay(
          dateKey: dateKey1,
          photo: PhotoEntry(
            id: 'old_2',
            date: dateKey1.toDateTime(),
            title: 'Old Photo 2',
            imagePath: (await createTestImageFile('old2.jpg')).path,
            gradientColors: const [],
          ),
        );
        final p3 = await store.addPhotoToDay(
          dateKey: dateKey2,
          photo: PhotoEntry(
            id: 'old_3',
            date: dateKey2.toDateTime(),
            title: 'Old Photo 3',
            imagePath: (await createTestImageFile('old3.jpg')).path,
            gradientColors: const [],
          ),
        );

        final oldPath1 = p1.imagePath!;
        final oldPath2 = p2.imagePath!;
        final oldPath3 = p3.imagePath!;
        expect(File(oldPath1).existsSync(), isTrue);
        expect(File(oldPath2).existsSync(), isTrue);
        expect(File(oldPath3).existsSync(), isTrue);

        // Create a backup containing only Day 3
        final replaceDir = Directory('${tempDir.path}/replace_source');
        await replaceDir.create();
        final replaceStore = PersistentDailyPhotoStore(
          fileManager: PhotoFileManager(customBaseDir: replaceDir),
          metadataStorage: PhotoMetadataStorage(customBaseDir: replaceDir),
        );
        await replaceStore.init();

        const dateKey3 = DateKey(2026, 5, 3);
        await replaceStore.addPhotoToDay(
          dateKey: dateKey3,
          photo: PhotoEntry(
            id: 'new_3',
            date: dateKey3.toDateTime(),
            title: 'New Replacement Photo',
            imagePath: (await createTestImageFile('new3.jpg')).path,
            gradientColors: const [],
          ),
        );
        await replaceStore.updateDayNote(
          dateKey: dateKey3,
          note: 'Fresh diary replacement.',
        );

        final replaceService = PadBackupService(
          store: replaceStore,
          customTempDir: workDir,
        );
        final exportRes = await replaceService.exportBackup();
        final inspection = await service.inspectBackupFile(
          exportRes.backupFile!,
        );

        // Restore in replace mode
        final restoreRes = await service.restoreFromInspection(
          inspection,
          mode: PadRestoreMode.replace,
        );
        expect(restoreRes.isSuccess, isTrue);

        // Previous photos purged from disk and store
        expect(File(oldPath1).existsSync(), isFalse);
        expect(File(oldPath2).existsSync(), isFalse);
        expect(File(oldPath3).existsSync(), isFalse);
        expect(store.getDay(dateKey1), isNull);
        expect(store.getDay(dateKey2), isNull);

        // Only Day 3 remains
        final day3 = store.getDay(dateKey3);
        expect(day3, isNotNull);
        expect(day3!.photos.length, equals(1));
        expect(day3.photos.first.id, equals('new_3'));
        expect(day3.note, equals('Fresh diary replacement.'));
      },
    );
  });
}
