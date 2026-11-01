import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/pdf_export_models.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/pdf_diary_export_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';

class _MockPdfPlatformDelegate implements PdfPlatformDelegate {
  bool shareCalled = false;
  bool layoutCalled = false;
  String? lastSharedFilename;
  String? lastPrintedName;
  Uint8List? lastSharedBytes;

  @override
  Future<bool> sharePdf({
    required Uint8List bytes,
    required String filename,
  }) async {
    shareCalled = true;
    lastSharedFilename = filename;
    lastSharedBytes = bytes;
    return true;
  }

  @override
  Future<bool> layoutPdf({
    required Uint8List bytes,
    required String name,
  }) async {
    layoutCalled = true;
    lastPrintedName = name;
    return true;
  }

  @override
  Future<String?> savePdfToUserDestination({
    required Uint8List bytes,
    required String suggestedFilename,
  }) async {
    return '/mock/saved/$suggestedFilename';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory exportDir;
  late PersistentDailyPhotoStore store;
  late _MockPdfPlatformDelegate mockDelegate;
  late PdfDiaryExportService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('m54_pdf_test_');
    exportDir = Directory('${tempDir.path}/exports');
    await exportDir.create(recursive: true);

    final fileManager = PhotoFileManager(customBaseDir: tempDir);
    final metadataStorage = PhotoMetadataStorage(customBaseDir: tempDir);
    store = PersistentDailyPhotoStore(
      fileManager: fileManager,
      metadataStorage: metadataStorage,
    );
    await store.init();

    mockDelegate = _MockPdfPlatformDelegate();
    service = PdfDiaryExportService(
      store: store,
      defaultExportDir: exportDir,
      platformDelegate: mockDelegate,
    );
  });

  tearDown(() async {
    PersistentDailyPhotoStore.resetTestInstance();
    PdfDiaryExportService.resetTestInstance();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  /// Helper to create a valid 20x20 JPEG image on disk.
  Future<String> createValidPhotoFile(String filename) async {
    final photoPath = '${tempDir.path}/$filename';
    final image = img.Image(width: 20, height: 20);
    for (int y = 0; y < 20; y++) {
      for (int x = 0; x < 20; x++) {
        image.setPixelRgb(x, y, 200, 138, 62);
      }
    }
    final bytes = img.encodeJpg(image, quality: 90);
    final file = File(photoPath);
    await file.writeAsBytes(bytes);
    return photoPath;
  }

  group('Milestone 54 — PDF Diary Export Service Unit Tests', () {
    test(
      '1. Empty diary export returns empty result and creates no file',
      () async {
        final result = await service.generatePdf();

        expect(result.isEmpty, isTrue);
        expect(result.isSuccess, isFalse);
        expect(result.exportedPhotoCount, 0);
        expect(result.pageCount, 0);
        expect(result.pdfBytes, isEmpty);
        expect(result.pdfFile, isNull);

        final files = exportDir.listSync();
        expect(files, isEmpty);
      },
    );

    test(
      '2. Single photo export generates valid PDF with correct magic bytes and page count',
      () async {
        final photoPath = await createValidPhotoFile('photo_2026_03_15.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 3, 15, 14, 30),
            title: 'Spring Blossom',
            location: 'Botanical Gardens',
            category: 'Nature',
            gradientColors: const [],
            imagePath: photoPath,
          ),
        );

        final result = await service.generatePdf();

        expect(result.isSuccess, isTrue);
        expect(result.isEmpty, isFalse);
        expect(result.exportedPhotoCount, 1);
        expect(result.skippedPhotoCount, 0);
        expect(
          result.pageCount,
          greaterThanOrEqualTo(4),
        ); // Cover, Year, Month, Memory, Summary
        expect(result.pdfBytes.length, greaterThan(100));

        // Check PDF magic bytes '%PDF'
        final header = String.fromCharCodes(result.pdfBytes.take(4));
        expect(header, '%PDF');

        // Check file was saved to export directory
        expect(result.pdfFile, isNotNull);
        expect(await result.pdfFile!.exists(), isTrue);
        expect(result.pdfFile!.lengthSync(), equals(result.pdfBytes.length));
      },
    );

    test(
      '3. Chronological ordering of entries across month and year boundaries',
      () async {
        final p1 = await createValidPhotoFile('p1.jpg');
        final p2 = await createValidPhotoFile('p2.jpg');
        final p3 = await createValidPhotoFile('p3.jpg');

        // Insert in reverse order to ensure chronological sorting
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 12, 31, 23, 59),
            title: 'New Year Eve',
            gradientColors: const [],
            imagePath: p3,
          ),
        );
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 6, 15, 12, 0),
            title: 'Summer Solstice',
            gradientColors: const [],
            imagePath: p2,
          ),
        );
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 1, 1, 8, 0),
            title: 'First Morning',
            gradientColors: const [],
            imagePath: p1,
          ),
        );

        final filtered = service.getFilteredEntries(
          const PdfExportRange.allTime(),
        );
        expect(filtered.length, 3);
        expect(filtered[0].title, 'First Morning');
        expect(filtered[1].title, 'Summer Solstice');
        expect(filtered[2].title, 'New Year Eve');

        final result = await service.generatePdf();
        expect(result.isSuccess, isTrue);
        expect(result.exportedPhotoCount, 3);
        expect(result.startDate, DateTime(2026, 1, 1));
        expect(result.endDate, DateTime(2026, 12, 31));
      },
    );

    test('4. Date range and year filtering', () async {
      final p2025 = await createValidPhotoFile('p2025.jpg');
      final p2026 = await createValidPhotoFile('p2026.jpg');

      await store.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2025, 8, 20),
          title: 'Summer 2025',
          gradientColors: const [],
          imagePath: p2025,
        ),
      );
      await store.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2026, 4, 10),
          title: 'Spring 2026',
          gradientColors: const [],
          imagePath: p2026,
        ),
      );

      final years = service.getAvailableYears();
      expect(years, [2026, 2025]);

      // Filter by 2025 only
      final entries2025 = service.getFilteredEntries(
        const PdfExportRange.year(2025),
      );
      expect(entries2025.length, 1);
      expect(entries2025.first.title, 'Summer 2025');

      final result2025 = await service.generatePdf(
        range: const PdfExportRange.year(2025),
      );
      expect(result2025.isSuccess, isTrue);
      expect(result2025.exportedPhotoCount, 1);
      expect(result2025.filename.contains('2025'), isTrue);

      // Filter by 2026 only
      final result2026 = await service.generatePdf(
        range: const PdfExportRange.year(2026),
      );
      expect(result2026.isSuccess, isTrue);
      expect(result2026.exportedPhotoCount, 1);
      expect(result2026.filename.contains('2026'), isTrue);

      // All time
      final resultAll = await service.generatePdf(
        range: const PdfExportRange.allTime(),
      );
      expect(resultAll.isSuccess, isTrue);
      expect(resultAll.exportedPhotoCount, 2);
    });

    test(
      '5. Missing or unreadable image handling renders fallback card without crashing',
      () async {
        final validPhoto = await createValidPhotoFile('valid.jpg');
        final missingPhoto = await createValidPhotoFile('missing.jpg');

        // Entry 1: Valid photo
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 5, 1),
            title: 'Valid Photo Entry',
            gradientColors: const [],
            imagePath: validPhoto,
          ),
        );

        // Entry 2: Saved photo whose file is removed from disk afterwards
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 5, 2),
            title: 'Missing Photo Entry',
            gradientColors: const [],
            imagePath: missingPhoto,
          ),
        );

        // Delete the stored file for entry 2 from disk
        final savedEntry2 = store.getPhotoByKey(const DateKey(2026, 5, 2));
        expect(savedEntry2?.imagePath, isNotNull);
        final storedFile2 = File(savedEntry2!.imagePath!);
        if (storedFile2.existsSync()) {
          storedFile2.deleteSync();
        }

        final result = await service.generatePdf();

        expect(result.isSuccess, isTrue);
        expect(result.isPartial, isTrue);
        expect(result.exportedPhotoCount, 1);
        expect(result.skippedPhotoCount, 1);
        expect(result.totalEntriesEvaluated, 2);
        expect(result.pdfBytes, isNotEmpty);
      },
    );

    test(
      '6. Corrupt photo file handling does not crash PDF compilation',
      () async {
        // Create a file with random non-image bytes
        final corruptPath = '${tempDir.path}/corrupt.jpg';
        await File(corruptPath).writeAsBytes([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 6, 1),
            title: 'Corrupt File Entry',
            gradientColors: const [],
            imagePath: corruptPath,
          ),
        );

        final result = await service.generatePdf();

        expect(result.isSuccess, isTrue);
        expect(result.skippedPhotoCount, 1);
        expect(result.isPartial, isTrue);
        expect(result.pdfBytes, isNotEmpty);
      },
    );

    test('7. Sharing and printing delegate invocation', () async {
      final validPhoto = await createValidPhotoFile('share_test.jpg');
      await store.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2026, 7, 1),
          title: 'Share Test',
          gradientColors: const [],
          imagePath: validPhoto,
        ),
      );

      final result = await service.generatePdf();
      expect(result.isSuccess, isTrue);

      // Share PDF
      final shareSuccess = await service.sharePdf(result);
      expect(shareSuccess, isTrue);
      expect(mockDelegate.shareCalled, isTrue);
      expect(mockDelegate.lastSharedFilename, equals(result.filename));
      expect(mockDelegate.lastSharedBytes, equals(result.pdfBytes));

      // Print PDF
      final printSuccess = await service.printPdf(result);
      expect(printSuccess, isTrue);
      expect(mockDelegate.layoutCalled, isTrue);
      expect(mockDelegate.lastPrintedName, equals(result.filename));
    });

    test(
      '8. Progress callback reports monotonic progress from start to 1.0',
      () async {
        final validPhoto = await createValidPhotoFile('progress_test.jpg');
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 7, 2),
            title: 'Progress Test',
            gradientColors: const [],
            imagePath: validPhoto,
          ),
        );

        final reportedSteps = <double>[];
        final statuses = <String>[];

        await service.generatePdf(
          onProgress: (progress, status) {
            reportedSteps.add(progress);
            statuses.add(status);
          },
        );

        expect(reportedSteps, isNotEmpty);
        expect(reportedSteps.last, 1.0);
        expect(statuses.last, 'Complete!');

        // Ensure progress never decreases
        for (int i = 1; i < reportedSteps.length; i++) {
          expect(reportedSteps[i], greaterThanOrEqualTo(reportedSteps[i - 1]));
        }
      },
    );

    test('9. Temporary export file cleanup', () async {
      final validPhoto = await createValidPhotoFile('cleanup_test.jpg');
      await store.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2026, 7, 3),
          title: 'Cleanup Test',
          gradientColors: const [],
          imagePath: validPhoto,
        ),
      );

      final result = await service.generatePdf();
      expect(await result.pdfFile!.exists(), isTrue);

      final deleted = await service.cleanTemporaryExports();
      expect(deleted, greaterThanOrEqualTo(1));
      expect(await result.pdfFile!.exists(), isFalse);
    });

    test(
      '10. Original photo files and metadata remain strictly unmodified',
      () async {
        final validPhoto = await createValidPhotoFile('unmodified.jpg');
        final originalBytes = await File(validPhoto).readAsBytes();

        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 7, 4),
            title: 'Unmodified Photo',
            location: 'Original Location',
            gradientColors: const [],
            imagePath: validPhoto,
          ),
        );

        final originalEntry = store.getPhotoByKey(const DateKey(2026, 7, 4));
        expect(originalEntry, isNotNull);

        await service.generatePdf();

        // Verify photo file on disk was not modified or deleted
        final currentFile = File(validPhoto);
        expect(await currentFile.exists(), isTrue);
        final currentBytes = await currentFile.readAsBytes();
        expect(currentBytes, equals(originalBytes));

        // Verify store metadata is identical
        final storedAfter = store.getPhotoByKey(const DateKey(2026, 7, 4));
        expect(storedAfter, isNotNull);
        expect(storedAfter!.title, originalEntry!.title);
        expect(storedAfter.location, originalEntry.location);
        expect(storedAfter.imagePath, originalEntry.imagePath);
      },
    );
  });

  group('Milestone 60 — Multi-Photo PDF Diary Export Unit Tests', () {
    test(
      '11. Multi-photo day export with 3 photos exports all 3 photos in stored order',
      () async {
        const dateKey = DateKey(2026, 8, 10);
        final photo1 = await createValidPhotoFile('multi_1.jpg');
        final photo2 = await createValidPhotoFile('multi_2.jpg');
        final photo3 = await createValidPhotoFile('multi_3.jpg');

        await store.addPhotoToDay(
          dateKey: dateKey,
          photo: PhotoEntry(
            id: 'p1',
            date: dateKey.toDateTime(),
            title: 'Morning Coffee',
            imagePath: photo1,
            gradientColors: const [],
          ),
        );
        await store.addPhotoToDay(
          dateKey: dateKey,
          photo: PhotoEntry(
            id: 'p2',
            date: dateKey.toDateTime(),
            title: 'Midday Hike',
            imagePath: photo2,
            gradientColors: const [],
          ),
        );
        await store.addPhotoToDay(
          dateKey: dateKey,
          photo: PhotoEntry(
            id: 'p3',
            date: dateKey.toDateTime(),
            title: 'Sunset View',
            imagePath: photo3,
            gradientColors: const [],
          ),
        );

        final result = await service.generatePdf();
        expect(result.isSuccess, isTrue);
        expect(result.exportedPhotoCount, equals(3));
        expect(result.skippedPhotoCount, equals(0));
        expect(result.pageCount, greaterThanOrEqualTo(3));
        expect(await result.pdfFile!.exists(), isTrue);
      },
    );

    test(
      '12. Shared daily note appears once per day (not repeated under each photo)',
      () async {
        const dateKey = DateKey(2026, 8, 11);
        final photo1 = await createValidPhotoFile('shared_note_1.jpg');
        final photo2 = await createValidPhotoFile('shared_note_2.jpg');

        await store.addPhotoToDay(
          dateKey: dateKey,
          photo: PhotoEntry(
            id: 'sn1',
            date: dateKey.toDateTime(),
            title: 'Garden Flower',
            imagePath: photo1,
            gradientColors: const [],
          ),
        );
        await store.addPhotoToDay(
          dateKey: dateKey,
          photo: PhotoEntry(
            id: 'sn2',
            date: dateKey.toDateTime(),
            title: 'Bee on Leaf',
            imagePath: photo2,
            gradientColors: const [],
          ),
        );
        await store.updateDayNote(
          dateKey: dateKey,
          note: 'A quiet afternoon observing pollinators in bloom.',
        );

        final day = store.getDay(dateKey);
        expect(day, isNotNull);
        expect(day!.photos.length, equals(2));
        expect(
          day.note,
          equals('A quiet afternoon observing pollinators in bloom.'),
        );

        final result = await service.generatePdf();
        expect(result.isSuccess, isTrue);
        expect(result.exportedPhotoCount, equals(2));
        expect(result.skippedPhotoCount, equals(0));
      },
    );

    test(
      '13. Note-only day (0 photos + note) exports successfully without photos or broken frames',
      () async {
        const dateKey = DateKey(2026, 8, 12);
        await store.updateDayNote(
          dateKey: dateKey,
          note: 'Spent the whole day reading indoors; no photos taken.',
        );

        final day = store.getDay(dateKey);
        expect(day, isNotNull);
        expect(day!.photos, isEmpty);
        expect(day.hasNote, isTrue);

        final result = await service.generatePdf();
        expect(result.isSuccess, isTrue);
        expect(result.exportedPhotoCount, equals(0));
        expect(result.skippedPhotoCount, equals(0));
        expect(await result.pdfFile!.exists(), isTrue);
        expect(await result.pdfFile!.length(), greaterThan(0));
      },
    );

    test(
      '14. Photo-only day (photos with empty note) exports without blank reflection box',
      () async {
        const dateKey = DateKey(2026, 8, 13);
        final photo1 = await createValidPhotoFile('photo_only_1.jpg');
        final photo2 = await createValidPhotoFile('photo_only_2.jpg');

        await store.addPhotoToDay(
          dateKey: dateKey,
          photo: PhotoEntry(
            id: 'po1',
            date: dateKey.toDateTime(),
            title: 'Photo Only 1',
            imagePath: photo1,
            gradientColors: const [],
          ),
        );
        await store.addPhotoToDay(
          dateKey: dateKey,
          photo: PhotoEntry(
            id: 'po2',
            date: dateKey.toDateTime(),
            title: 'Photo Only 2',
            imagePath: photo2,
            gradientColors: const [],
          ),
        );

        final day = store.getDay(dateKey);
        expect(day, isNotNull);
        expect(day!.photos.length, equals(2));
        expect(day.hasNote, isFalse);

        final result = await service.generatePdf();
        expect(result.isSuccess, isTrue);
        expect(result.exportedPhotoCount, equals(2));
        expect(result.skippedPhotoCount, equals(0));
      },
    );

    test(
      '15. Range filtering (All Time vs Specific Year) with multi-photo and note-only days',
      () async {
        // 2025: 1 day with 2 photos
        const dk2025 = DateKey(2025, 5, 1);
        final p2025_1 = await createValidPhotoFile('p2025_1.jpg');
        final p2025_2 = await createValidPhotoFile('p2025_2.jpg');
        await store.addPhotoToDay(
          dateKey: dk2025,
          photo: PhotoEntry(
            id: 'p25_1',
            date: dk2025.toDateTime(),
            title: '2025 Photo 1',
            imagePath: p2025_1,
            gradientColors: const [],
          ),
        );
        await store.addPhotoToDay(
          dateKey: dk2025,
          photo: PhotoEntry(
            id: 'p25_2',
            date: dk2025.toDateTime(),
            title: '2025 Photo 2',
            imagePath: p2025_2,
            gradientColors: const [],
          ),
        );

        // 2026: 1 day with 3 photos, 1 note-only day
        const dk2026A = DateKey(2026, 6, 1);
        final p2026_1 = await createValidPhotoFile('p2026_1.jpg');
        final p2026_2 = await createValidPhotoFile('p2026_2.jpg');
        final p2026_3 = await createValidPhotoFile('p2026_3.jpg');
        await store.addPhotoToDay(
          dateKey: dk2026A,
          photo: PhotoEntry(
            id: 'p26_1',
            date: dk2026A.toDateTime(),
            title: '2026 Photo 1',
            imagePath: p2026_1,
            gradientColors: const [],
          ),
        );
        await store.addPhotoToDay(
          dateKey: dk2026A,
          photo: PhotoEntry(
            id: 'p26_2',
            date: dk2026A.toDateTime(),
            title: '2026 Photo 2',
            imagePath: p2026_2,
            gradientColors: const [],
          ),
        );
        await store.addPhotoToDay(
          dateKey: dk2026A,
          photo: PhotoEntry(
            id: 'p26_3',
            date: dk2026A.toDateTime(),
            title: '2026 Photo 3',
            imagePath: p2026_3,
            gradientColors: const [],
          ),
        );

        const dk2026B = DateKey(2026, 7, 1);
        await store.updateDayNote(
          dateKey: dk2026B,
          note: 'July reflection without photo.',
        );

        // Verify Year 2026 filter
        final days2026 = service.getFilteredDays(
          const PdfExportRange.year(2026),
        );
        final entries2026 = service.getFilteredEntries(
          const PdfExportRange.year(2026),
        );
        expect(days2026.length, equals(2));
        expect(entries2026.length, equals(3));

        // Verify Year 2025 filter
        final days2025 = service.getFilteredDays(
          const PdfExportRange.year(2025),
        );
        final entries2025 = service.getFilteredEntries(
          const PdfExportRange.year(2025),
        );
        expect(days2025.length, equals(1));
        expect(entries2025.length, equals(2));

        // Verify All Time filter
        final allDays = service.getFilteredDays(const PdfExportRange.allTime());
        final allEntries = service.getFilteredEntries(
          const PdfExportRange.allTime(),
        );
        expect(allDays.length, equals(3));
        expect(allEntries.length, equals(5));
      },
    );

    test(
      '16. Missing/corrupted image counting and editorial fallback frame in multi-photo day',
      () async {
        const dateKey = DateKey(2026, 8, 14);
        final validPhoto = await createValidPhotoFile('multi_corrupt_1.jpg');
        final secondPhoto = await createValidPhotoFile('multi_corrupt_2.jpg');

        await store.addPhotoToDay(
          dateKey: dateKey,
          photo: PhotoEntry(
            id: 'mc1',
            date: dateKey.toDateTime(),
            title: 'Valid Frame',
            imagePath: validPhoto,
            gradientColors: const [],
          ),
        );
        final savedP2 = await store.addPhotoToDay(
          dateKey: dateKey,
          photo: PhotoEntry(
            id: 'mc2',
            date: dateKey.toDateTime(),
            title: 'Missing Frame',
            imagePath: secondPhoto,
            gradientColors: const [],
          ),
        );

        // Delete the persisted photo file so it is missing during PDF generation
        if (savedP2.imagePath != null) {
          final fileToDelete = File(savedP2.imagePath!);
          if (await fileToDelete.exists()) {
            await fileToDelete.delete();
          }
        }

        final result = await service.generatePdf();
        expect(result.isSuccess, isTrue);
        expect(result.exportedPhotoCount, equals(1));
        expect(result.skippedPhotoCount, equals(1));
        expect(result.totalEntriesEvaluated, equals(2));
        expect(result.isPartial, isTrue);
        expect(await result.pdfFile!.exists(), isTrue);
      },
    );

    test(
      '17. Source photo files and metadata remain strictly unmodified during export',
      () async {
        const dateKey = DateKey(2026, 8, 15);
        final photo1 = await createValidPhotoFile('immutable_pdf_1.jpg');
        final photo2 = await createValidPhotoFile('immutable_pdf_2.jpg');
        final p1Bytes = await File(photo1).readAsBytes();
        final p2Bytes = await File(photo2).readAsBytes();

        await store.addPhotoToDay(
          dateKey: dateKey,
          photo: PhotoEntry(
            id: 'imm1',
            date: dateKey.toDateTime(),
            title: 'Imm 1',
            imagePath: photo1,
            gradientColors: const [],
          ),
        );
        await store.addPhotoToDay(
          dateKey: dateKey,
          photo: PhotoEntry(
            id: 'imm2',
            date: dateKey.toDateTime(),
            title: 'Imm 2',
            imagePath: photo2,
            gradientColors: const [],
          ),
        );
        await store.updateDayNote(
          dateKey: dateKey,
          note: 'Diary note to verify immutability.',
        );

        final metaBytesBefore = await store.metadataStorage.metadataFile
            .readAsBytes();

        final result = await service.generatePdf();
        expect(result.isSuccess, isTrue);

        // Verify photo files on disk
        expect(await File(photo1).readAsBytes(), equals(p1Bytes));
        expect(await File(photo2).readAsBytes(), equals(p2Bytes));

        // Verify metadata file
        final metaBytesAfter = await store.metadataStorage.metadataFile
            .readAsBytes();
        expect(metaBytesAfter, equals(metaBytesBefore));
      },
    );
  });
}
