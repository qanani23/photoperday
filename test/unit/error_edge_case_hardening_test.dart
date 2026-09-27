import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:photo_per_day/data/models/daily_reminder_settings.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/drive_folder_result.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_operation.dart';
import 'package:photo_per_day/data/models/sync_operation_status.dart';
import 'package:photo_per_day/data/models/sync_operation_type.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/models/sync_tombstone.dart';
import 'package:photo_per_day/data/services/daily_reminder_storage.dart';
import 'package:photo_per_day/data/services/diary_export_service.dart';
import 'package:photo_per_day/data/services/drive_api_adapter.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/sync_queue_storage.dart';

PhotoEntry createTestEntry({
  required DateTime date,
  required String title,
  String? imagePath,
  SyncStatus syncStatus = SyncStatus.localOnly,
  String? driveFileId,
  String? authorizedEmail,
}) {
  return PhotoEntry(
    date: date,
    title: title,
    gradientColors: const [Color(0xFFE28743), Color(0xFF873E23)],
    imagePath: imagePath,
    syncStatus: syncStatus,
    driveFileId: driveFileId,
    authorizedEmail: authorizedEmail,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('m37_error_hardening_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Milestone 37: 1. Local Metadata Corruption & Recovery', () {
    test('Empty metadata file returns empty map without throwing', () async {
      final storage = PhotoMetadataStorage(customBaseDir: tempDir);
      await storage.init();
      await storage.metadataFile.writeAsString('');

      final result = await storage.loadAll();
      expect(result, isEmpty);
    });

    test('Non-map JSON (list or string) returns empty map without crashing', () async {
      final storage = PhotoMetadataStorage(customBaseDir: tempDir);
      await storage.init();
      await storage.metadataFile.writeAsString(jsonEncode([1, 2, 3]));

      final result = await storage.loadAll();
      expect(result, isEmpty);

      await storage.metadataFile.writeAsString(jsonEncode('plain string'));
      final result2 = await storage.loadAll();
      expect(result2, isEmpty);
    });

    test('Invalid DateKeys are safely skipped while valid keys are loaded', () async {
      final storage = PhotoMetadataStorage(customBaseDir: tempDir);
      await storage.init();

      final corrupted = {
        'not-a-date': {'title': 'Bad Date', 'date': '2026-09-01T12:00:00Z'},
        '2026-09-15': {'title': 'Good Date', 'date': '2026-09-15T12:00:00Z'},
      };
      await storage.metadataFile.writeAsString(jsonEncode(corrupted));

      final result = await storage.loadAll();
      expect(result.length, 1);
      expect(result.containsKey(const DateKey(2026, 9, 15)), isTrue);
      expect(result[const DateKey(2026, 9, 15)]!.title, 'Good Date');
    });

    test('Unexpected field types and unknown future fields parse safely', () async {
      final json = <String, dynamic>{
        'date': 12345, // Not a string!
        'title': 999, // Number instead of string
        'caption': true, // Boolean instead of string
        'gradientColors': ['not-a-color', null, 4294901760], // Mixed list
        'iconCodePoint': 'string-code-point', // String instead of int
        'lastModifiedAt': false, // Boolean
        'future_unknown_field': {'nested': 'metadata'}, // Forward compatibility
      };

      final entry = PhotoEntry.fromJson(json);
      expect(entry.title, '999');
      expect(entry.caption, 'true');
      expect(entry.gradientColors, isNotEmpty);
      expect(entry.date, isNotNull);
      expect(entry.lastModifiedAt, isNotNull);
    });

    test('Enforces dateKey alignment to guarantee one-photo-per-day invariant', () async {
      final storage = PhotoMetadataStorage(customBaseDir: tempDir);
      await storage.init();

      // JSON has map key 2026-09-10, but inner date field says 2026-09-11
      final mismatched = {
        '2026-09-10': {
          'title': 'Mismatched Entry',
          'date': '2026-09-11T12:00:00Z',
        },
      };
      await storage.metadataFile.writeAsString(jsonEncode(mismatched));

      final result = await storage.loadAll();
      expect(result.length, 1);
      final loaded = result[const DateKey(2026, 9, 10)]!;
      expect(loaded.dateKey, const DateKey(2026, 9, 10));
    });
  });

  group('Milestone 37: 2. SyncQueue Corruption & Recovery', () {
    test('Empty or non-list sync queue file returns empty list without crashing', () async {
      final storage = SyncQueueStorage(customBaseDir: tempDir);
      await storage.init();
      await storage.queueFile.writeAsString('');

      final ops1 = await storage.loadQueue();
      expect(ops1, isEmpty);

      await storage.queueFile.writeAsString(jsonEncode({'not': 'a list'}));
      final ops2 = await storage.loadQueue();
      expect(ops2, isEmpty);
    });

    test('Unexpected field types in queue items parse safely with valid defaults', () async {
      final json = <String, dynamic>{
        'dateKey': 20260910, // Number instead of string
        'createdAt': false, // Boolean
        'retryCount': '5', // String instead of int
        'status': 'unknown_future_status', // Unknown status enum
        'type': 'unknown_type', // Unknown type enum
        'futureField': [1, 2, 3], // Future field
      };

      final op = SyncOperation.fromJson(json);
      expect(op.dateKey, const DateKey(1970, 1, 1));
      expect(op.retryCount, 5);
      expect(op.status, SyncOperationStatus.pending);
      expect(op.type, SyncOperationType.upload);
    });

    test('Crash Recovery: inProgress operations are automatically reset to pending', () async {
      final storage = SyncQueueStorage(customBaseDir: tempDir);
      await storage.init();

      final queueData = [
        {
          'id': 'op_1',
          'type': 'upload',
          'dateKey': '2026-09-10',
          'status': 'inProgress', // Interrupted mid-upload!
          'createdAt': '2026-09-10T12:00:00Z',
        },
        {
          'id': 'op_2',
          'type': 'update',
          'dateKey': '2026-09-11',
          'status': 'pending',
          'createdAt': '2026-09-11T12:00:00Z',
        },
      ];
      await storage.queueFile.writeAsString(jsonEncode(queueData));

      final loaded = await storage.loadQueue();
      expect(loaded.length, 2);
      expect(loaded[0].id, 'op_1');
      expect(loaded[0].status, SyncOperationStatus.pending); // Reset to pending!
      expect(loaded[1].status, SyncOperationStatus.pending);
    });

    test('Corrupted queue files with duplicate operation IDs are deduplicated', () async {
      final storage = SyncQueueStorage(customBaseDir: tempDir);
      await storage.init();

      final duplicates = [
        {
          'id': 'op_duplicate',
          'type': 'upload',
          'dateKey': '2026-09-10',
          'status': 'pending',
          'createdAt': '2026-09-10T12:00:00Z',
        },
        {
          'id': 'op_duplicate',
          'type': 'upload',
          'dateKey': '2026-09-10',
          'status': 'pending',
          'createdAt': '2026-09-10T12:00:00Z',
        },
      ];
      await storage.queueFile.writeAsString(jsonEncode(duplicates));

      final loaded = await storage.loadQueue();
      expect(loaded.length, 1);
    });
  });

  group('Milestone 37: 3. Local Photo File Failures & Recovery', () {
    test('Missing disk image file safely returns isImageFileAvailable == false', () {
      final entry = createTestEntry(
        date: DateTime(2026, 9, 10),
        title: 'Missing Photo',
        imagePath: '${tempDir.path}/does_not_exist.jpg',
      );

      expect(entry.hasRealImage, isTrue);
      expect(entry.isImageFileAvailable, isFalse);
    });

    test('0-byte source photo file is rejected by persistPhotoFile', () async {
      final manager = PhotoFileManager(customBaseDir: tempDir);
      await manager.init();

      final emptySource = File('${tempDir.path}/empty.jpg');
      await emptySource.writeAsString('');

      expect(
        () => manager.persistPhotoFile(
          sourcePath: emptySource.path,
          dateKey: const DateKey(2026, 9, 10),
        ),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('Non-existent source photo file is rejected by persistPhotoFile', () async {
      final manager = PhotoFileManager(customBaseDir: tempDir);
      await manager.init();

      expect(
        () => manager.persistPhotoFile(
          sourcePath: '${tempDir.path}/ghost.jpg',
          dateKey: const DateKey(2026, 9, 10),
        ),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('Milestone 37: 4. One-Photo-Per-Day & Replacement Edge Cases', () {
    test('Replacing photo for dateKey preserves single-entry invariant', () async {
      final store = PersistentDailyPhotoStore.instance;
      await store.init(customBaseDir: tempDir);

      final dummy1 = File('${tempDir.path}/dummy1.jpg');
      await dummy1.writeAsString('bytes-version-1');

      final dummy2 = File('${tempDir.path}/dummy2.jpg');
      await dummy2.writeAsString('bytes-version-2');

      final date = DateTime(2026, 9, 10);
      final entry1 = createTestEntry(date: date, title: 'Version 1');
      await store.savePhoto(entry: entry1, sourceTempPath: dummy1.path);

      expect(store.totalPhotos, 1);
      expect(store.getPhoto(date)!.title, 'Version 1');

      // Replace with Version 2
      final entry2 = createTestEntry(date: date, title: 'Version 2');
      await store.savePhoto(entry: entry2, sourceTempPath: dummy2.path);

      expect(store.totalPhotos, 1); // Strictly 1 entry
      expect(store.getPhoto(date)!.title, 'Version 2');
    });

    test('Replacing synced photo transitions status to pending and preserves driveFileId', () async {
      final store = PersistentDailyPhotoStore.instance;
      await store.init(customBaseDir: tempDir);

      final dummy1 = File('${tempDir.path}/dummy1.jpg');
      await dummy1.writeAsString('bytes-v1');
      final dummy2 = File('${tempDir.path}/dummy2.jpg');
      await dummy2.writeAsString('bytes-v2');

      final date = DateTime(2026, 9, 12);
      final entry1 = createTestEntry(
        date: date,
        title: 'Original',
        syncStatus: SyncStatus.synced,
        driveFileId: 'remote_file_123',
        authorizedEmail: 'user@example.com',
      );
      await store.savePhoto(entry: entry1, sourceTempPath: dummy1.path);

      // Replace
      final entry2 = createTestEntry(date: date, title: 'Replacement');
      final saved = await store.savePhoto(entry: entry2, sourceTempPath: dummy2.path);

      expect(saved.syncStatus, SyncStatus.pending);
      expect(saved.driveFileId, 'remote_file_123');
      expect(saved.authorizedEmail, 'user@example.com');
    });

    test('Capturing on date with pending deletion clears the tombstone', () async {
      final store = PersistentDailyPhotoStore.instance;
      await store.init(customBaseDir: tempDir);

      final key = const DateKey(2026, 9, 14);
      final dummyOld = File('${tempDir.path}/old_photo.jpg');
      await dummyOld.writeAsString('old-bytes');

      await store.savePhoto(
        entry: createTestEntry(
          date: key.toDateTime(),
          title: 'Old Photo',
          syncStatus: SyncStatus.synced,
          driveFileId: 'old_drive_id',
        ),
        sourceTempPath: dummyOld.path,
      );

      // Deleting a synced photo records a tombstone in pendingDeletions
      await store.removePhotoAsync(key.toDateTime());
      expect(store.pendingDeletions.any((t) => t.dateKey == key), isTrue);

      final dummyNew = File('${tempDir.path}/new_capture.jpg');
      await dummyNew.writeAsString('fresh-bytes');

      await store.savePhoto(
        entry: createTestEntry(date: key.toDateTime(), title: 'New Capture'),
        sourceTempPath: dummyNew.path,
      );

      // Pending deletion tombstone for that date must be cleared
      expect(store.pendingDeletions.any((t) => t.dateKey == key), isFalse);
    });
  });

  group('Milestone 37: 5. Date & Time Edge Cases', () {
    test('Leap day validation: Feb 29 2024 / 2028 are valid, 2025 / 2026 are invalid', () {
      expect(DateKey.isValidDate(2024, 2, 29), isTrue); // Leap year
      expect(DateKey.isValidDate(2028, 2, 29), isTrue); // Leap year
      expect(DateKey.isValidDate(2025, 2, 29), isFalse); // Non-leap year
      expect(DateKey.isValidDate(2026, 2, 29), isFalse); // Non-leap year
      expect(DateKey.isValidDate(2000, 2, 29), isTrue); // Century leap year
      expect(DateKey.isValidDate(1900, 2, 29), isFalse); // Century non-leap year
    });

    test('Midnight boundary: 23:59:59 and 00:00:01 map to exact same DateKey', () {
      final dtLate = DateTime(2026, 9, 10, 23, 59, 59, 999);
      final dtEarly = DateTime(2026, 9, 10, 0, 0, 1, 1);

      final keyLate = DateKey.fromDateTime(dtLate);
      final keyEarly = DateKey.fromDateTime(dtEarly);

      expect(keyLate, equals(keyEarly));
      expect(keyLate.format(), '2026-09-10');
    });

    test('Month and year roll boundaries format accurately', () {
      final yearEnd = DateTime(2026, 12, 31, 23, 59);
      final newYear = DateTime(2027, 1, 1, 0, 1);

      expect(DateKey.fromDateTime(yearEnd).format(), '2026-12-31');
      expect(DateKey.fromDateTime(newYear).format(), '2027-01-01');
    });
  });

  group('Milestone 37: 6. Google Drive API Error Mapping', () {
    const adapter = GoogleApisDriveAdapter();

    test('DetailedApiRequestError 401 maps to unauthorized', () {
      final error = drive.DetailedApiRequestError(401, 'Unauthorized token');
      final mapped = adapter.mapErrorForTesting(error, 'TestContext');

      expect(mapped.errorType, DriveFolderErrorType.unauthorized);
      expect(mapped.message, contains('re-authenticate'));
    });

    test('DetailedApiRequestError 403 quota exceeded maps to quota message', () {
      final error = drive.DetailedApiRequestError(
        403,
        'storageQuotaExceeded: User storage limit reached',
      );
      final mapped = adapter.mapErrorForTesting(error, 'TestContext');

      expect(mapped.errorType, DriveFolderErrorType.forbidden);
      expect(mapped.message, contains('storage quota exceeded'));
      expect(mapped.message, contains('local photo is safe'));
    });

    test('DetailedApiRequestError 403 rate limit maps to rate limit message', () {
      final error = drive.DetailedApiRequestError(
        403,
        'userRateLimitExceeded: Rate limit reached',
      );
      final mapped = adapter.mapErrorForTesting(error, 'TestContext');

      expect(mapped.errorType, DriveFolderErrorType.forbidden);
      expect(mapped.message, contains('rate limit exceeded'));
    });

    test('DetailedApiRequestError 404 maps to notFound', () {
      final error = drive.DetailedApiRequestError(404, 'File not found');
      final mapped = adapter.mapErrorForTesting(error, 'TestContext');

      expect(mapped.errorType, DriveFolderErrorType.notFound);
    });

    test('DetailedApiRequestError 409 maps to conflict', () {
      final error = drive.DetailedApiRequestError(409, 'Conflict occurred');
      final mapped = adapter.mapErrorForTesting(error, 'TestContext');

      expect(mapped.message, contains('Conflict'));
    });

    test('DetailedApiRequestError 429 maps to rate limit exceeded', () {
      final error = drive.DetailedApiRequestError(429, 'Too many requests');
      final mapped = adapter.mapErrorForTesting(error, 'TestContext');

      expect(mapped.message, contains('rate limit exceeded (HTTP 429)'));
    });

    test('DetailedApiRequestError 500/503 maps to temporary unavailable', () {
      final error500 = drive.DetailedApiRequestError(500, 'Internal Server Error');
      final mapped500 = adapter.mapErrorForTesting(error500, 'TestContext');
      expect(mapped500.message, contains('temporarily unavailable (HTTP 500)'));

      final error503 = drive.DetailedApiRequestError(503, 'Service Unavailable');
      final mapped503 = adapter.mapErrorForTesting(error503, 'TestContext');
      expect(mapped503.message, contains('temporarily unavailable (HTTP 503)'));
    });
  });

  group('Milestone 37: 7. Export Partial & Edge-Case Failures', () {
    test('Exporting empty diary returns ExportResult.empty()', () async {
      final store = PersistentDailyPhotoStore.instance;
      await store.init(customBaseDir: tempDir);
      await store.clearAsync();

      final exportService = DiaryExportService(store: store);
      final result = await exportService.exportDiary(customExportDir: tempDir);

      expect(result.isEmpty, isTrue);
      expect(result.isSuccess, isFalse);
      expect(result.exportedCount, 0);
    });

    test('Export with missing disk photos is reported as partial with reasons in manifest', () async {
      final store = PersistentDailyPhotoStore.instance;
      await store.init(customBaseDir: tempDir);

      // Create 1 valid photo and 1 missing photo
      final validFile = File('${tempDir.path}/valid_photo.jpg');
      await validFile.writeAsString('actual-photo-data');

      final date1 = DateTime(2026, 9, 1);
      final date2 = DateTime(2026, 9, 2);

      await store.savePhoto(
        entry: createTestEntry(date: date1, title: 'Valid Photo'),
        sourceTempPath: validFile.path,
      );

      // Directly insert entry with non-existent path
      final missingEntry = createTestEntry(
        date: date2,
        title: 'Missing Photo',
        imagePath: '${tempDir.path}/ghost_nonexistent.jpg',
      );
      store.setPhoto(missingEntry);

      final exportService = DiaryExportService(store: store);
      final result = await exportService.exportDiary(customExportDir: tempDir);

      expect(result.isPartial, isTrue);
      expect(result.isSuccess, isFalse);
      expect(result.exportedCount, 1);
      expect(result.skippedCount, 1);
      expect(result.zipFile, isNotNull);
      expect(await result.zipFile!.exists(), isTrue);
    });
  });

  group('Milestone 37: 8. Daily Reminder Edge Cases & Sanitization', () {
    test('DailyReminderSettings.fromJson clamps invalid out-of-range hours and minutes', () {
      final corrupt1 = {'hour': 99, 'minute': 120, 'enabled': true};
      final settings1 = DailyReminderSettings.fromJson(corrupt1);
      expect(settings1.hour, 20); // Clamped fallback
      expect(settings1.minute, 0); // Clamped fallback
      expect(settings1.enabled, isTrue);

      final corrupt2 = {'hour': -5, 'minute': -1, 'enabled': 'not-a-bool'};
      final settings2 = DailyReminderSettings.fromJson(corrupt2);
      expect(settings2.hour, 20);
      expect(settings2.minute, 0);
      expect(settings2.enabled, isFalse); // Non-bool defaults to false
    });

    test('DailyReminderStorage loads defaults if file is corrupt JSON', () async {
      final storage = DailyReminderStorage(customBaseDir: tempDir.path);
      final filePath = await storage.settingsFilePath;
      await File(filePath).writeAsString('{ malformed json }');

      final loaded = await storage.loadSettings();
      expect(loaded, equals(DailyReminderSettings.defaultSettings));
    });
  });
}
