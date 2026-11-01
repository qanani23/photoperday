import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/day_entry.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/services/photo_import_service.dart';

class _FakePhotoImportPlatformDelegate implements PhotoImportPlatformDelegate {
  _FakePhotoImportPlatformDelegate({this.pathsToReturn = const []});

  List<String> pathsToReturn;
  bool pickCalled = false;
  bool lastAllowMultiple = true;

  @override
  Future<List<String>> pickPhotoFiles({bool allowMultiple = true}) async {
    pickCalled = true;
    lastAllowMultiple = allowMultiple;
    return pathsToReturn;
  }
}

class _TestMetadataStorage extends PhotoMetadataStorage {
  _TestMetadataStorage({super.customBaseDir});

  final Map<DateKey, DayEntry> inMemoryDays = {};

  @override
  Future<void> init() async {}

  @override
  Future<Map<DateKey, DayEntry>> loadDays() async => Map.from(inMemoryDays);

  @override
  Future<void> saveDays(Map<DateKey, DayEntry> days) async {
    inMemoryDays
      ..clear()
      ..addAll(days);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory sourcePhotosDir;
  late PhotoFileManager fileManager;
  late _TestMetadataStorage metadataStorage;
  late PersistentDailyPhotoStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pad_m64_import_test_');
    sourcePhotosDir = Directory('${tempDir.path}/external_source')
      ..createSync(recursive: true);

    fileManager = PhotoFileManager(customBaseDir: tempDir);
    await fileManager.init();

    metadataStorage = _TestMetadataStorage(customBaseDir: tempDir);
    await metadataStorage.init();

    store = PersistentDailyPhotoStore(
      fileManager: fileManager,
      metadataStorage: metadataStorage,
    );
    await store.init();
  });

  tearDown(() async {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  File createSampleImage(
    String filename, {
    List<int>? headerBytes,
    int size = 1024,
  }) {
    final file = File('${sourcePhotosDir.path}/$filename');
    final bytes = BytesBuilder();

    // Default to JPEG magic bytes if none specified: 0xFF, 0xD8, 0xFF, 0xE0
    if (headerBytes != null) {
      bytes.add(headerBytes);
      if (size > headerBytes.length) {
        bytes.add(List.filled(size - headerBytes.length, 0xAA));
      }
    } else {
      bytes.add([
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
      ]);
      if (size > 12) {
        bytes.add(List.filled(size - 12, 0xEE));
      }
    }

    file.writeAsBytesSync(bytes.toBytes());
    return file;
  }

  group('M64 — PhotoImportService Unit Tests', () {
    test(
      '1. Validates supported formats (JPEG, PNG, BMP, WEBP) via magic header bytes',
      () {
        final delegate = _FakePhotoImportPlatformDelegate();
        final service = PhotoImportService(
          platformDelegate: delegate,
          store: store,
        );

        // JPEG
        final jpeg = createSampleImage(
          'photo.jpg',
          headerBytes: [0xFF, 0xD8, 0xFF, 0xE0],
        );
        expect(service.validateImageFile(jpeg.path), isTrue);

        // PNG
        final png = createSampleImage(
          'photo.png',
          headerBytes: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
        );
        expect(service.validateImageFile(png.path), isTrue);

        // BMP
        final bmp = createSampleImage(
          'photo.bmp',
          headerBytes: [0x42, 0x4D, 0x00, 0x00],
        );
        expect(service.validateImageFile(bmp.path), isTrue);

        // WEBP
        final webp = createSampleImage(
          'photo.webp',
          headerBytes: [
            0x52, 0x49, 0x46, 0x46, // 'RIFF'
            0x00, 0x00, 0x00, 0x00,
            0x57, 0x45, 0x42, 0x50, // 'WEBP'
          ],
        );
        expect(service.validateImageFile(webp.path), isTrue);
      },
    );

    test('2. Rejects invalid, empty, or unsupported files gracefully', () {
      final delegate = _FakePhotoImportPlatformDelegate();
      final service = PhotoImportService(
        platformDelegate: delegate,
        store: store,
      );

      // Non-existent file
      expect(
        service.validateImageFile('${sourcePhotosDir.path}/missing.jpg'),
        isFalse,
      );

      // Empty file (0 bytes)
      final emptyFile = File('${sourcePhotosDir.path}/empty.jpg')
        ..writeAsBytesSync([]);
      expect(service.validateImageFile(emptyFile.path), isFalse);

      // Unsupported extension
      final txtFile = File('${sourcePhotosDir.path}/notes.txt')
        ..writeAsStringSync('not an image');
      expect(service.validateImageFile(txtFile.path), isFalse);

      // Corrupted header
      final corrupted = createSampleImage(
        'bad.jpg',
        headerBytes: [0x00, 0x00, 0x00, 0x00],
      );
      expect(service.validateImageFile(corrupted.path), isFalse);
    });

    test(
      '3. Picker cancellation returns cancelled result without creating diary entries',
      () async {
        final delegate = _FakePhotoImportPlatformDelegate(pathsToReturn: []);
        final service = PhotoImportService(
          platformDelegate: delegate,
          store: store,
        );

        const dateKey = DateKey(2026, 10, 31);
        final result = await service.importPhotosForDay(dateKey: dateKey);

        expect(result.isCancelled, isTrue);
        expect(result.importedCount, 0);
        expect(store.hasDay(dateKey), isFalse);
      },
    );

    test(
      '4. Imports single photo into an empty day and copies to persistent storage',
      () async {
        final sourceFile = createSampleImage('vacation.jpg');
        final delegate = _FakePhotoImportPlatformDelegate(
          pathsToReturn: [sourceFile.path],
        );
        final service = PhotoImportService(
          platformDelegate: delegate,
          store: store,
        );

        const dateKey = DateKey(2026, 10, 31);
        final result = await service.importPhotosForDay(dateKey: dateKey);

        expect(result.isSuccess, isTrue);
        expect(result.importedCount, 1);
        expect(store.hasDay(dateKey), isTrue);

        final day = store.getDay(dateKey)!;
        expect(day.photos.length, 1);
        final importedPhoto = day.photos.first;
        expect(importedPhoto.imagePath, isNotNull);
        expect(importedPhoto.imagePath, isNot(equals(sourceFile.path)));
        expect(File(importedPhoto.imagePath!).existsSync(), isTrue);
      },
    );

    test(
      '5. Multi-photo import appends all photos to existing day without replacing',
      () async {
        final file1 = createSampleImage('photo1.jpg');
        final file2 = createSampleImage(
          'photo2.png',
          headerBytes: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
        );
        final file3 = createSampleImage('photo3.jpg');

        final delegate = _FakePhotoImportPlatformDelegate(
          pathsToReturn: [file1.path, file2.path, file3.path],
        );
        final service = PhotoImportService(
          platformDelegate: delegate,
          store: store,
        );

        const dateKey = DateKey(2026, 10, 31);

        // Pre-seed an existing photo on this day with a note
        await store.savePhoto(
          entry: PhotoEntry(
            date: dateKey.toDateTime(),
            title: 'Initial Sunrise',
            imagePath: file1.path,
            gradientColors: const [],
          ),
          sourceTempPath: file1.path,
        );
        await store.updateDayNote(
          dateKey: dateKey,
          note: 'A memorable autumn morning.',
        );

        expect(store.getDay(dateKey)!.photos.length, 1);

        // Now import multiple files
        final result = await service.importPhotosForDay(dateKey: dateKey);

        expect(result.isSuccess, isTrue);
        expect(result.importedCount, 3);

        final updatedDay = store.getDay(dateKey)!;
        expect(updatedDay.photos.length, 4); // 1 initial + 3 imported
        expect(updatedDay.note, 'A memorable autumn morning.');
        expect(updatedDay.photos.first.title, 'Initial Sunrise');

        // Verify all IDs are unique
        final ids = updatedDay.photos.map((p) => p.id).toSet();
        expect(ids.length, 4);
      },
    );

    test(
      '6. Imported photos survive deletion or renaming of original external files',
      () async {
        final original = createSampleImage('temporary_download.jpg');
        final originalPath = original.path;

        final delegate = _FakePhotoImportPlatformDelegate(
          pathsToReturn: [originalPath],
        );
        final service = PhotoImportService(
          platformDelegate: delegate,
          store: store,
        );

        const dateKey = DateKey(2026, 10, 31);
        final result = await service.importPhotosForDay(dateKey: dateKey);

        expect(result.isSuccess, isTrue);
        final persistedPath = result.importedPhotos.first.imagePath!;
        expect(File(persistedPath).existsSync(), isTrue);

        // User deletes original file from their downloads/desktop
        original.deleteSync();
        expect(File(originalPath).existsSync(), isFalse);

        // The diary's persisted copy is completely untouched
        expect(File(persistedPath).existsSync(), isTrue);
        expect(File(persistedPath).lengthSync(), greaterThan(0));
      },
    );

    test('7. Imported photos persist across application restart', () async {
      final img = createSampleImage('persistent_photo.jpg');
      final delegate = _FakePhotoImportPlatformDelegate(
        pathsToReturn: [img.path],
      );
      final service = PhotoImportService(
        platformDelegate: delegate,
        store: store,
      );

      const dateKey = DateKey(2026, 10, 31);
      await service.importPhotosForDay(dateKey: dateKey);

      // Simulate app restart by initializing a new PersistentDailyPhotoStore
      final restartedStore = PersistentDailyPhotoStore(
        fileManager: fileManager,
        metadataStorage: metadataStorage,
      );
      await restartedStore.init();

      expect(restartedStore.hasDay(dateKey), isTrue);
      final day = restartedStore.getDay(dateKey)!;
      expect(day.photos.length, 1);
      expect(File(day.photos.first.imagePath!).existsSync(), isTrue);
    });
  });
}
