import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/pdf_export_models.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/pdf_diary_export_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/widgets/pdf_export_dialog.dart';

class _WidgetTestPhotoMetadataStorage extends PhotoMetadataStorage {
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

class _WidgetTestPhotoFileManager extends PhotoFileManager {
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
  Future<bool> deletePhotoFile(String? path) async => true;

  @override
  Future<void> clearAll() async {}
}

class _FakePlatformDelegate implements PdfPlatformDelegate {
  bool shareCalled = false;
  bool printCalled = false;

  @override
  Future<bool> sharePdf({
    required Uint8List bytes,
    required String filename,
  }) async {
    shareCalled = true;
    return true;
  }

  @override
  Future<bool> layoutPdf({
    required Uint8List bytes,
    required String name,
  }) async {
    printCalled = true;
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

class _TestPdfDiaryExportService extends PdfDiaryExportService {
  _TestPdfDiaryExportService({super.store, super.platformDelegate});

  bool generateCalled = false;
  PdfExportRange? lastRequestedRange;
  PdfExportResult? stubbedResult;
  bool shouldThrow = false;

  @override
  Future<PdfExportResult> generatePdf({
    PdfExportRange range = const PdfExportRange.allTime(),
    Directory? customExportDir,
    void Function(double progress, String status)? onProgress,
  }) async {
    generateCalled = true;
    lastRequestedRange = range;

    if (shouldThrow) {
      throw Exception('Simulated disk full failure');
    }

    onProgress?.call(0.5, 'Formatting pages...');

    return stubbedResult ??
        PdfExportResult(
          pdfBytes: Uint8List.fromList([37, 80, 68, 70]), // %PDF
          filename: 'photo_a_day_diary_test.pdf',
          exportedPhotoCount: 1,
          skippedPhotoCount: 0,
          totalEntriesEvaluated: 1,
          pageCount: 5,
          startDate: DateTime(2026, 3, 16),
          endDate: DateTime(2026, 3, 16),
          fileSizeBytes: 2048,
          isSuccess: true,
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PersistentDailyPhotoStore store;
  late _FakePlatformDelegate mockDelegate;
  late _TestPdfDiaryExportService service;

  setUp(() async {
    final fileManager = _WidgetTestPhotoFileManager();
    final metadataStorage = _WidgetTestPhotoMetadataStorage();
    store = PersistentDailyPhotoStore(
      fileManager: fileManager,
      metadataStorage: metadataStorage,
    );
    await store.init();

    mockDelegate = _FakePlatformDelegate();
    service = _TestPdfDiaryExportService(
      store: store,
      platformDelegate: mockDelegate,
    );

    PersistentDailyPhotoStore.setTestInstance(store);
    PdfDiaryExportService.setTestInstance(service);
  });

  tearDown(() {
    PersistentDailyPhotoStore.resetTestInstance();
    PdfDiaryExportService.resetTestInstance();
  });

  Widget buildTestApp({required Widget child}) {
    return MaterialApp(home: Scaffold(body: child));
  }

  group('Milestone 54 — PdfExportDialog Widget Tests', () {
    testWidgets('1. Empty diary shows friendly empty state with close action', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => PdfExportDialog.show(
                context,
                exportService: service,
                store: store,
              ),
              child: const Text('Open Export'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Export'));
      await tester.pumpAndSettle();

      expect(find.text('Photo Diary Book'), findsOneWidget);
      expect(
        find.text('Your diary does not contain any captured photos yet.'),
        findsOneWidget,
      );
      expect(find.text('Close'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Photo Diary Book'), findsNothing);
    });

    testWidgets(
      '2. Populated diary renders configuration options, editorial preview, and create button',
      (tester) async {
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 3, 15),
            title: 'Spring Day',
            gradientColors: const [],
          ),
        );

        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => PdfExportDialog.show(
                  context,
                  exportService: service,
                  store: store,
                ),
                child: const Text('Open Export'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Export'));
        await tester.pumpAndSettle();

        expect(find.text('Export as PDF Diary'), findsOneWidget);
        expect(find.text('Editorial print-ready photo book'), findsOneWidget);
        expect(find.text('Entire Diary (All Time)'), findsOneWidget);
        expect(find.text('1 memories'), findsOneWidget);
        expect(find.text('Specific Year'), findsOneWidget);
        expect(
          find.text('Warm linen cover page with hero photo'),
          findsOneWidget,
        );
        expect(
          find.text('Full-year overview & monthly calendars'),
          findsOneWidget,
        );
        expect(find.text('Create PDF (1)'), findsOneWidget);
      },
    );

    testWidgets(
      '3. Full export flow: Generation to Completion and Share/Print actions',
      (tester) async {
        await store.savePhoto(
          entry: PhotoEntry(
            date: DateTime(2026, 3, 16),
            title: 'Spring Blooms',
            location: 'Central Park',
            gradientColors: const [],
          ),
        );

        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => PdfExportDialog.show(
                  context,
                  exportService: service,
                  store: store,
                ),
                child: const Text('Open Export'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Export'));
        await tester.pumpAndSettle();

        // Tap Create PDF (1)
        await tester.tap(find.text('Create PDF (1)'));
        await tester.pump();
        await tester.pump(); // Advance microtask to complete generation

        // Verify completion state
        expect(find.text('Photo Diary Ready!'), findsOneWidget);
        expect(find.text('photo_a_day_diary_test.pdf'), findsOneWidget);
        expect(find.text('MEMORIES'), findsOneWidget);
        expect(find.text('PAGES'), findsOneWidget);
        expect(find.text('SIZE'), findsOneWidget);
        expect(find.text('Share / Save to Files'), findsOneWidget);
        expect(find.text('Print'), findsOneWidget);
        expect(find.text('Done'), findsOneWidget);

        // Tap Share
        await tester.tap(find.text('Share / Save to Files'));
        await tester.pump();
        expect(mockDelegate.shareCalled, isTrue);

        // Tap Print
        await tester.tap(find.text('Print'));
        await tester.pump();
        expect(mockDelegate.printCalled, isTrue);

        // Tap Done
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.text('Photo Diary Ready!'), findsNothing);
      },
    );

    testWidgets('4. Specific year selection filters scope correctly', (
      tester,
    ) async {
      await store.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2025, 10, 1),
          title: 'Autumn 2025',
          gradientColors: const [],
        ),
      );
      await store.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2026, 5, 20),
          title: 'Spring 2026',
          gradientColors: const [],
        ),
      );

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => PdfExportDialog.show(
                context,
                exportService: service,
                store: store,
              ),
              child: const Text('Open Export'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Export'));
      await tester.pumpAndSettle();

      // Initially All Time (2 memories)
      expect(find.text('Create PDF (2)'), findsOneWidget);

      // Tap Specific Year
      await tester.tap(find.text('Specific Year'));
      await tester.pumpAndSettle();

      // Should now show 1 for the selected year (2026)
      expect(find.text('Create PDF (1)'), findsOneWidget);

      // Tap Create PDF (1)
      await tester.tap(find.text('Create PDF (1)'));
      await tester.pump();
      await tester.pump();

      expect(service.generateCalled, isTrue);
      expect(service.lastRequestedRange?.type, ExportRangeType.year);
      expect(service.lastRequestedRange?.year, 2026);
    });

    testWidgets('5. Export error displays failure message and allows retry', (
      tester,
    ) async {
      await store.savePhoto(
        entry: PhotoEntry(
          date: DateTime(2026, 5, 20),
          title: 'Spring 2026',
          gradientColors: const [],
        ),
      );
      service.shouldThrow = true;

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => PdfExportDialog.show(
                context,
                exportService: service,
                store: store,
              ),
              child: const Text('Open Export'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Export'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create PDF (1)'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Export Failed'), findsOneWidget);
      expect(
        find.textContaining('Simulated disk full failure'),
        findsOneWidget,
      );
      expect(find.text('Try Again'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);

      // Tap Try Again
      service.shouldThrow = false;
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();

      // Back to configure phase
      expect(find.text('Create PDF (1)'), findsOneWidget);
    });
  });
}
