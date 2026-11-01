import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/day_entry.dart';
import 'package:photo_per_day/data/models/pdf_export_models.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/statistics_service.dart';
import 'package:photo_per_day/data/services/streak_service.dart';
import 'package:printing/printing.dart';

/// Pluggable delegate for sharing and printing PDF documents across platforms.
abstract class PdfPlatformDelegate {
  Future<bool> sharePdf({required Uint8List bytes, required String filename});
  Future<bool> layoutPdf({required Uint8List bytes, required String name});
  Future<String?> savePdfToUserDestination({
    required Uint8List bytes,
    required String suggestedFilename,
  });
}

/// Default implementation delegating to the `printing` and `file_picker` plugins.
class DefaultPdfPlatformDelegate implements PdfPlatformDelegate {
  const DefaultPdfPlatformDelegate();

  @override
  Future<bool> sharePdf({
    required Uint8List bytes,
    required String filename,
  }) async {
    return await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  @override
  Future<bool> layoutPdf({
    required Uint8List bytes,
    required String name,
  }) async {
    return await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => bytes,
      name: name,
    );
  }

  @override
  Future<String?> savePdfToUserDestination({
    required Uint8List bytes,
    required String suggestedFilename,
  }) async {
    try {
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Photo Diary PDF',
        fileName: suggestedFilename,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (outputPath != null && outputPath.isNotEmpty) {
        final file = File(outputPath);
        await file.writeAsBytes(bytes);
        return outputPath;
      }
    } catch (e) {
      debugPrint('Error saving PDF to user destination: $e');
    }
    return null;
  }
}

/// Palette tokens for PDF document design reproducing Photo a Day's warm editorial aesthetic.
abstract final class PdfThemeTokens {
  static const PdfColor linenBackground = PdfColor.fromInt(0xFFFAF8F5);
  static const PdfColor surface = PdfColor.fromInt(0xFFFFFFFF);
  static const PdfColor surfaceSubtle = PdfColor.fromInt(0xFFF5F2EB);
  static const PdfColor textPrimary = PdfColor.fromInt(0xFF1F1D1A);
  static const PdfColor textSecondary = PdfColor.fromInt(0xFF706C66);
  static const PdfColor textMuted = PdfColor.fromInt(0xFF9E9991);
  static const PdfColor accentCaramel = PdfColor.fromInt(0xFFC88A3E);
  static const PdfColor accentCaramelLight = PdfColor.fromInt(0xFFF7EEDF);
  static const PdfColor border = PdfColor.fromInt(0xFFE8E4DC);
  static const PdfColor borderLight = PdfColor.fromInt(0xFFF0ECE4);
  static const PdfColor statDaysGreen = PdfColor.fromInt(0xFF6A7F60);
}

/// Service that creates a beautiful, print-ready PDF photo diary from local photos.
///
/// Features:
/// - **Restrained Editorial Design**: Warm linen backgrounds, charcoal typography, caramel accents.
/// - **Five Core Sections**:
///   1. Cover Page with hero photo, title, date range, and key metrics.
///   2. Year Overview calendar grid showing recorded days.
///   3. Monthly Calendar pages with day cells and photo indicators.
///   4. Photo Memory pages with 2 photos per page, formatted dates, titles, and locations.
///   5. Diary Summary with streaks, counts, and closing reflection.
/// - **Memory Optimization**: Downsamples oversized images to avoid OOM crashes on large diaries.
/// - **Fault Tolerant**: Handles corrupt or missing files safely with dignified editorial fallback frames.
/// - **Zero Network Code**: Generates and persists locally; supports sharing and printing.
class PdfDiaryExportService {
  PdfDiaryExportService({
    this.store,
    this.defaultExportDir,
    this.platformDelegate = const DefaultPdfPlatformDelegate(),
  });

  final PersistentDailyPhotoStore? store;
  final Directory? defaultExportDir;
  final PdfPlatformDelegate platformDelegate;

  PersistentDailyPhotoStore get _effectiveStore =>
      store ?? PersistentDailyPhotoStore.instance;

  static PdfDiaryExportService? _instance;

  static PdfDiaryExportService get instance =>
      _instance ??= PdfDiaryExportService();

  @visibleForTesting
  static void setTestInstance(PdfDiaryExportService service) {
    _instance = service;
  }

  @visibleForTesting
  static void resetTestInstance() {
    _instance = null;
  }

  static const String exportDirectoryName = 'diary_pdf_exports';

  /// Resolves the dedicated local export directory.
  Future<Directory> getExportDirectory({Directory? customExportDir}) async {
    final effectiveDir = customExportDir ?? defaultExportDir;
    if (effectiveDir != null) {
      if (!await effectiveDir.exists()) {
        await effectiveDir.create(recursive: true);
      }
      return effectiveDir;
    }
    final base = await getTemporaryDirectory();
    final exportDir = Directory(p.join(base.path, exportDirectoryName));
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    return exportDir;
  }

  /// Returns the distinct calendar years that contain at least one photo entry.
  List<int> getAvailableYears() {
    final dates = _effectiveStore.recordedDates;
    final years = dates.map((d) => d.year).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    return years;
  }

  /// Filters day entries according to the given [range] in chronological order (oldest to newest).
  List<DayEntry> getFilteredDays(PdfExportRange range) {
    final allDays = _effectiveStore.chronologicalAscendingDayEntries;
    if (range.type == ExportRangeType.allTime) {
      return allDays;
    }
    final targetYear = range.year;
    if (targetYear == null) return allDays;
    return allDays.where((d) => d.dateKey.year == targetYear).toList();
  }

  /// Filters photo entries according to the given [range] in chronological order (oldest to newest).
  List<PhotoEntry> getFilteredEntries(PdfExportRange range) {
    return getFilteredDays(range).expand((d) => d.photos).toList();
  }

  /// Generates the complete PDF diary document.
  Future<PdfExportResult> generatePdf({
    PdfExportRange range = const PdfExportRange.allTime(),
    Directory? customExportDir,
    void Function(double progress, String status)? onProgress,
  }) async {
    final days = getFilteredDays(range);
    final filename = _generateFilename(range);

    if (days.isEmpty) {
      return PdfExportResult.empty(filename: filename);
    }

    final allPhotos = days.expand((d) => d.photos).toList();

    try {
      onProgress?.call(0.05, 'Preparing diary layout...');

      final pdf = pw.Document(
        title: 'Daria — My Photo Diary',
        author: 'Daria',
        creator: 'Daria Local PDF Generator',
      );

      final fontRegular = pw.Font.helvetica();
      final fontBold = pw.Font.helveticaBold();
      final fontItalic = pw.Font.helveticaOblique();

      final textTheme = pw.ThemeData.withFont(
        base: fontRegular,
        bold: fontBold,
        italic: fontItalic,
      );

      final startDate = days.first.dateKey.toDateTime();
      final endDate = days.last.dateKey.toDateTime();
      final dateRangeStr = _formatDateRange(startDate, endDate, range);

      // 1. Cover Page
      onProgress?.call(0.15, 'Designing cover page...');
      PhotoEntry? heroEntry;
      pw.ImageProvider? heroImageProvider;
      for (final day in days) {
        for (final photo in day.photos) {
          final img = _loadImageSafely(photo.imagePath);
          if (img != null) {
            heroEntry = photo;
            heroImageProvider = img;
            break;
          }
        }
        if (heroImageProvider != null) break;
      }
      if (heroEntry == null && allPhotos.isNotEmpty) {
        heroEntry = allPhotos.first;
      }

      pw.ImageProvider? logoImageProvider;
      final logoBytes = await _loadLogoBytes();
      if (logoBytes != null && logoBytes.isNotEmpty) {
        try {
          logoImageProvider = pw.MemoryImage(logoBytes);
        } catch (e) {
          debugPrint('Failed to decode logo for PDF: $e');
        }
      }

      pdf.addPage(
        _buildCoverPage(
          theme: textTheme,
          dateRangeStr: dateRangeStr,
          photoCount: allPhotos.length,
          dayCount: days.length,
          heroEntry: heroEntry,
          heroImage: heroImageProvider,
          logoImage: logoImageProvider,
        ),
      );

      // 2. Year Overview Page(s)
      onProgress?.call(0.25, 'Building year calendar overview...');
      final years = days.map((d) => d.dateKey.year).toSet().toList()..sort();
      for (final year in years) {
        final yearDays = days.where((d) => d.dateKey.year == year).toList();
        pdf.addPage(
          _buildYearOverviewPage(
            theme: textTheme,
            year: year,
            yearDays: yearDays,
          ),
        );
      }

      // 3. Monthly Calendar Pages
      onProgress?.call(0.40, 'Compiling monthly calendar layouts...');
      final monthGroups = _groupDaysByYearAndMonth(days);
      for (final group in monthGroups) {
        pdf.addPage(
          _buildMonthlyCalendarPage(
            theme: textTheme,
            year: group.year,
            month: group.month,
            monthDays: group.days,
          ),
        );
      }

      // 4. Memory Pages (Adaptive multi-photo and single-item days)
      onProgress?.call(0.55, 'Formatting photo memory pages...');
      int processedPhotos = 0;
      int skippedPhotos = 0;

      final loadedImages = <String, pw.ImageProvider?>{};
      for (final day in days) {
        for (final photo in day.photos) {
          pw.ImageProvider? imgProvider;
          if (photo.imagePath != null) {
            if (!loadedImages.containsKey(photo.imagePath!)) {
              imgProvider = _loadImageSafely(photo.imagePath);
              loadedImages[photo.imagePath!] = imgProvider;
            } else {
              imgProvider = loadedImages[photo.imagePath!];
            }
          }
          if (imgProvider == null && photo.hasRealImage) {
            skippedPhotos++;
          }
          processedPhotos++;
          final progress =
              0.55 +
              (0.35 *
                  (processedPhotos /
                      (allPhotos.isEmpty ? 1 : allPhotos.length)));
          onProgress?.call(
            progress,
            'Processing photo $processedPhotos of ${allPhotos.length}...',
          );
        }
      }

      final pendingSingleDays = <DayEntry>[];

      void flushSingleDays() {
        if (pendingSingleDays.isEmpty) return;
        final d1 = pendingSingleDays[0];
        final d2 = pendingSingleDays.length > 1 ? pendingSingleDays[1] : null;

        pdf.addPage(
          _buildSingleOrTwoDayPage(
            theme: textTheme,
            day1: d1,
            image1: d1.photos.isNotEmpty
                ? loadedImages[d1.photos.first.imagePath]
                : null,
            day2: d2,
            image2: (d2 != null && d2.photos.isNotEmpty)
                ? loadedImages[d2.photos.first.imagePath]
                : null,
            monthYearLabel:
                '${_monthName(d1.dateKey.month)} ${d1.dateKey.year}',
          ),
        );
        pendingSingleDays.clear();
      }

      for (final day in days) {
        if (day.photos.length >= 2) {
          // Multi-photo day! Flush buffered single days first
          flushSingleDays();

          final dayImages = day.photos
              .map((p) => loadedImages[p.imagePath])
              .toList();
          pdf.addPage(
            _buildMultiPhotoDayPage(
              theme: textTheme,
              day: day,
              images: dayImages,
              monthYearLabel:
                  '${_monthName(day.dateKey.month)} ${day.dateKey.year}',
            ),
          );
        } else {
          pendingSingleDays.add(day);
          if (pendingSingleDays.length == 2) {
            flushSingleDays();
          }
        }
      }

      flushSingleDays();

      // 5. Diary Summary Page
      onProgress?.call(0.92, 'Generating diary milestones & statistics...');
      pdf.addPage(
        _buildSummaryPage(
          theme: textTheme,
          entries: allPhotos,
          days: days,
          dateRangeStr: dateRangeStr,
        ),
      );

      // Save to document bytes
      onProgress?.call(0.97, 'Finalizing PDF document...');
      final Uint8List bytes = await pdf.save();

      // Write to export file
      final exportDir = await getExportDirectory(
        customExportDir: customExportDir,
      );
      final pdfFilePath = p.join(exportDir.path, filename);
      final pdfFile = File(pdfFilePath);
      await pdfFile.writeAsBytes(bytes, flush: true);

      onProgress?.call(1.0, 'Complete!');

      return PdfExportResult(
        pdfBytes: bytes,
        pdfFile: pdfFile,
        filename: filename,
        exportedPhotoCount: allPhotos.length - skippedPhotos,
        skippedPhotoCount: skippedPhotos,
        totalEntriesEvaluated: allPhotos.length,
        pageCount: pdf.document.pdfPageList.pages.length,
        startDate: startDate,
        endDate: endDate,
        fileSizeBytes: bytes.length,
        isSuccess: true,
        isPartial: skippedPhotos > 0,
      );
    } catch (e, stack) {
      debugPrint('PdfDiaryExportService.generatePdf error: $e\n$stack');
      return PdfExportResult.failure(
        errorMessage: 'Failed to generate PDF diary: $e',
        filename: filename,
        totalEntries: allPhotos.length,
      );
    }
  }

  /// Shares the generated PDF document using the platform share sheet.
  Future<bool> sharePdf(PdfExportResult result) async {
    if (result.pdfBytes.isEmpty) return false;
    return await platformDelegate.sharePdf(
      bytes: result.pdfBytes,
      filename: result.filename,
    );
  }

  /// Prompts the user to choose a durable file destination and saves the PDF.
  Future<String?> savePdf(PdfExportResult result) async {
    if (result.pdfBytes.isEmpty) return null;
    return await platformDelegate.savePdfToUserDestination(
      bytes: result.pdfBytes,
      suggestedFilename: result.filename,
    );
  }

  /// Opens the native platform print spooler to print the PDF document.
  Future<bool> printPdf(PdfExportResult result) async {
    if (result.pdfBytes.isEmpty) return false;
    return await platformDelegate.layoutPdf(
      bytes: result.pdfBytes,
      name: result.filename,
    );
  }

  /// Cleans temporary export PDF files generated in previous sessions.
  Future<int> cleanTemporaryExports({Directory? customExportDir}) async {
    try {
      final exportDir = await getExportDirectory(
        customExportDir: customExportDir,
      );
      if (!await exportDir.exists()) return 0;
      int deletedCount = 0;
      final files = exportDir.listSync();
      for (final file in files) {
        if (file is File && file.path.toLowerCase().endsWith('.pdf')) {
          try {
            file.deleteSync();
            deletedCount++;
          } catch (_) {}
        }
      }
      return deletedCount;
    } catch (_) {
      return 0;
    }
  }

  // ===========================================================================
  // Page Builders
  // ===========================================================================

  pw.Page _buildCoverPage({
    required pw.ThemeData theme,
    required String dateRangeStr,
    required int photoCount,
    int? dayCount,
    PhotoEntry? heroEntry,
    required pw.ImageProvider? heroImage,
    pw.ImageProvider? logoImage,
  }) {
    final effectiveDays = dayCount ?? photoCount;

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      theme: theme,
      build: (context) {
        return pw.Container(
          decoration: pw.BoxDecoration(
            color: PdfThemeTokens.linenBackground,
            border: pw.Border.all(color: PdfThemeTokens.border, width: 1.5),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          padding: const pw.EdgeInsets.all(32),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              // Top Badges & Title
              pw.Column(
                children: [
                  if (logoImage != null)
                    pw.Container(
                      width: 48,
                      height: 48,
                      margin: const pw.EdgeInsets.only(bottom: 12),
                      child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                    ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfThemeTokens.accentCaramelLight,
                      borderRadius: pw.BorderRadius.circular(12),
                    ),
                    child: pw.Text(
                      'DARIA  |  PERSONAL JOURNAL',
                      style: const pw.TextStyle(
                        color: PdfThemeTokens.accentCaramel,
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 14),
                  pw.Text(
                    'My Photo Diary',
                    style: const pw.TextStyle(
                      color: PdfThemeTokens.textPrimary,
                      fontSize: 32,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    dateRangeStr,
                    style: const pw.TextStyle(
                      color: PdfThemeTokens.accentCaramel,
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),

              // Hero Photo Frame
              pw.Container(
                width: 320,
                height: 240,
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfThemeTokens.surface,
                  border: pw.Border.all(
                    color: PdfThemeTokens.border,
                    width: 1.0,
                  ),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: heroImage != null
                    ? pw.ClipRRect(
                        horizontalRadius: 3,
                        verticalRadius: 3,
                        child: pw.Image(heroImage, fit: pw.BoxFit.cover),
                      )
                    : pw.Container(
                        color: PdfThemeTokens.surfaceSubtle,
                        child: pw.Center(
                          child: pw.Column(
                            mainAxisAlignment: pw.MainAxisAlignment.center,
                            children: [
                              pw.Text(
                                heroEntry != null
                                    ? 'Daily Photo Memory'
                                    : 'Daily Reflection Journal',
                                style: const pw.TextStyle(
                                  color: PdfThemeTokens.textSecondary,
                                  fontSize: 14,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.SizedBox(height: 4),
                              pw.Text(
                                heroEntry?.title ?? 'Daria',
                                style: const pw.TextStyle(
                                  color: PdfThemeTokens.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),

              // Bottom Metadata Row & Editorial Notice
              pw.Column(
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildCoverMetric('PHOTOS', '$photoCount'),
                      pw.Container(
                        width: 1,
                        height: 24,
                        color: PdfThemeTokens.border,
                      ),
                      _buildCoverMetric('DAYS', '$effectiveDays'),
                      pw.Container(
                        width: 1,
                        height: 24,
                        color: PdfThemeTokens.border,
                      ),
                      _buildCoverMetric('PRIVACY', 'Stored Locally'),
                    ],
                  ),
                  pw.SizedBox(height: 18),
                  pw.Divider(color: PdfThemeTokens.border, thickness: 0.8),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'Compiled locally from Daria | Completely Private & Offline',
                    style: const pw.TextStyle(
                      color: PdfThemeTokens.textMuted,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  pw.Widget _buildCoverMetric(String label, String value) {
    return pw.Column(
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(
            color: PdfThemeTokens.textMuted,
            fontSize: 8.5,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          value,
          style: const pw.TextStyle(
            color: PdfThemeTokens.textPrimary,
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  pw.Page _buildYearOverviewPage({
    required pw.ThemeData theme,
    required int year,
    List<PhotoEntry>? yearEntries,
    List<DayEntry>? yearDays,
  }) {
    final recordedDatesSet = yearDays != null
        ? yearDays.map((d) => d.dateKey).toSet()
        : (yearEntries?.map((e) => e.dateKey).toSet() ?? <DateKey>{});
    final totalRecordedDays = yearDays?.length ?? yearEntries?.length ?? 0;

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      theme: theme,
      build: (context) {
        return pw.Container(
          decoration: pw.BoxDecoration(
            color: PdfThemeTokens.linenBackground,
            border: pw.Border.all(color: PdfThemeTokens.border, width: 1.0),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          padding: const pw.EdgeInsets.all(24),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Page Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        '$year Year at a Glance',
                        style: const pw.TextStyle(
                          color: PdfThemeTokens.textPrimary,
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Recorded calendar across all twelve months',
                        style: const pw.TextStyle(
                          color: PdfThemeTokens.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfThemeTokens.surface,
                      border: pw.Border.all(
                        color: PdfThemeTokens.border,
                        width: 0.8,
                      ),
                      borderRadius: pw.BorderRadius.circular(10),
                    ),
                    child: pw.Text(
                      '$totalRecordedDays Recorded Days',
                      style: const pw.TextStyle(
                        color: PdfThemeTokens.accentCaramel,
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Divider(color: PdfThemeTokens.border, thickness: 0.8),
              pw.SizedBox(height: 12),

              // 12 Mini Month Grids (4 columns x 3 rows)
              pw.Expanded(
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                  children: [
                    for (int row = 0; row < 3; row++)
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          for (int col = 0; col < 4; col++)
                            _buildMiniMonthGrid(
                              year: year,
                              month: (row * 4) + col + 1,
                              recordedDates: recordedDatesSet,
                            ),
                        ],
                      ),
                  ],
                ),
              ),

              pw.SizedBox(height: 10),
              pw.Divider(color: PdfThemeTokens.border, thickness: 0.8),
              pw.SizedBox(height: 6),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Row(
                    children: [
                      pw.Container(
                        width: 8,
                        height: 8,
                        decoration: const pw.BoxDecoration(
                          color: PdfThemeTokens.accentCaramel,
                          shape: pw.BoxShape.circle,
                        ),
                      ),
                      pw.SizedBox(width: 4),
                      pw.Text(
                        'Entry Recorded',
                        style: const pw.TextStyle(
                          color: PdfThemeTokens.textSecondary,
                          fontSize: 9,
                        ),
                      ),
                      pw.SizedBox(width: 14),
                      pw.Container(
                        width: 8,
                        height: 8,
                        decoration: const pw.BoxDecoration(
                          color: PdfThemeTokens.border,
                          shape: pw.BoxShape.circle,
                        ),
                      ),
                      pw.SizedBox(width: 4),
                      pw.Text(
                        'No Entry',
                        style: const pw.TextStyle(
                          color: PdfThemeTokens.textSecondary,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                  pw.Text(
                    'Year $year | Daria Diary',
                    style: const pw.TextStyle(
                      color: PdfThemeTokens.textMuted,
                      fontSize: 8.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  pw.Widget _buildMiniMonthGrid({
    required int year,
    required int month,
    required Set<DateKey> recordedDates,
  }) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday;
    final leadingBlanks = firstWeekday % 7; // Sunday = 0

    return pw.Container(
      width: 116,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        color: PdfThemeTokens.surface,
        border: pw.Border.all(color: PdfThemeTokens.borderLight, width: 0.6),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            _monthName(month).toUpperCase(),
            style: const pw.TextStyle(
              color: PdfThemeTokens.accentCaramel,
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              for (final dayLabel in ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                pw.Container(
                  width: 14,
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    dayLabel,
                    style: const pw.TextStyle(
                      color: PdfThemeTokens.textMuted,
                      fontSize: 6,
                    ),
                  ),
                ),
            ],
          ),
          pw.SizedBox(height: 2),
          // Month calendar days
          pw.Wrap(
            children: [
              for (int b = 0; b < leadingBlanks; b++)
                pw.Container(width: 14, height: 12),
              for (int d = 1; d <= daysInMonth; d++)
                pw.Container(
                  width: 14,
                  height: 12,
                  alignment: pw.Alignment.center,
                  decoration: recordedDates.contains(DateKey(year, month, d))
                      ? const pw.BoxDecoration(
                          color: PdfThemeTokens.accentCaramel,
                          shape: pw.BoxShape.circle,
                        )
                      : null,
                  child: pw.Text(
                    '$d',
                    style: pw.TextStyle(
                      fontSize: 6,
                      color: recordedDates.contains(DateKey(year, month, d))
                          ? PdfColors.white
                          : PdfThemeTokens.textSecondary,
                      fontWeight:
                          recordedDates.contains(DateKey(year, month, d))
                          ? pw.FontWeight.bold
                          : pw.FontWeight.normal,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Page _buildMonthlyCalendarPage({
    required pw.ThemeData theme,
    required int year,
    required int month,
    List<PhotoEntry>? monthEntries,
    List<DayEntry>? monthDays,
  }) {
    final daysList =
        monthDays ??
        (monthEntries != null
            ? monthEntries
                  .map((e) => DayEntry(dateKey: e.dateKey, photos: [e]))
                  .toList()
            : <DayEntry>[]);
    final dayMap = {for (final d in daysList) d.dateKey.day: d};
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday;
    final leadingBlanks = firstWeekday % 7; // Sunday = 0
    final totalCells = leadingBlanks + daysInMonth;
    final rowCount = (totalCells / 7).ceil();

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      theme: theme,
      build: (context) {
        return pw.Container(
          decoration: pw.BoxDecoration(
            color: PdfThemeTokens.linenBackground,
            border: pw.Border.all(color: PdfThemeTokens.border, width: 1.0),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          padding: const pw.EdgeInsets.all(24),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        '${_monthName(month)} $year',
                        style: const pw.TextStyle(
                          color: PdfThemeTokens.textPrimary,
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        '${daysList.length} daily entries recorded | ${_monthName(month)} journal view',
                        style: const pw.TextStyle(
                          color: PdfThemeTokens.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfThemeTokens.surface,
                      border: pw.Border.all(
                        color: PdfThemeTokens.border,
                        width: 0.8,
                      ),
                      borderRadius: pw.BorderRadius.circular(10),
                    ),
                    child: pw.Text(
                      '${((daysList.length / daysInMonth) * 100).round()}% Completed',
                      style: const pw.TextStyle(
                        color: PdfThemeTokens.statDaysGreen,
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 14),
              pw.Divider(color: PdfThemeTokens.border, thickness: 0.8),
              pw.SizedBox(height: 8),

              // Weekday Table Headers
              pw.Row(
                children: [
                  for (final weekday in [
                    'Sunday',
                    'Monday',
                    'Tuesday',
                    'Wednesday',
                    'Thursday',
                    'Friday',
                    'Saturday',
                  ])
                    pw.Expanded(
                      child: pw.Container(
                        alignment: pw.Alignment.center,
                        padding: const pw.EdgeInsets.symmetric(vertical: 4),
                        child: pw.Text(
                          weekday,
                          style: const pw.TextStyle(
                            color: PdfThemeTokens.textSecondary,
                            fontSize: 8.5,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              pw.SizedBox(height: 4),

              // Calendar Grid Rows
              pw.Expanded(
                child: pw.Column(
                  children: [
                    for (int r = 0; r < rowCount; r++)
                      pw.Expanded(
                        child: pw.Row(
                          children: [
                            for (int c = 0; c < 7; c++)
                              _buildMonthCell(
                                dayNumber: (r * 7 + c) - leadingBlanks + 1,
                                daysInMonth: daysInMonth,
                                dayEntry:
                                    dayMap[(r * 7 + c) - leadingBlanks + 1],
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              pw.SizedBox(height: 8),
              pw.Divider(color: PdfThemeTokens.border, thickness: 0.8),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Daria | Monthly Calendar Overview',
                    style: const pw.TextStyle(
                      color: PdfThemeTokens.textMuted,
                      fontSize: 8.5,
                    ),
                  ),
                  pw.Text(
                    '${_monthName(month)} $year',
                    style: const pw.TextStyle(
                      color: PdfThemeTokens.textMuted,
                      fontSize: 8.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  pw.Widget _buildMonthCell({
    required int dayNumber,
    required int daysInMonth,
    DayEntry? dayEntry,
    PhotoEntry? entry,
  }) {
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.all(1.5),
          decoration: pw.BoxDecoration(
            color: PdfThemeTokens.surfaceSubtle,
            borderRadius: pw.BorderRadius.circular(3),
          ),
        ),
      );
    }

    final effectiveDay =
        dayEntry ??
        (entry != null
            ? DayEntry(dateKey: entry.dateKey, photos: [entry])
            : null);
    final hasEntry = effectiveDay != null;
    final hasPhotos = hasEntry && effectiveDay.photos.isNotEmpty;
    final hasNote = hasEntry && effectiveDay.hasNote;
    final photoCount = hasPhotos ? effectiveDay.photos.length : 0;

    return pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.all(1.5),
        padding: const pw.EdgeInsets.all(4),
        decoration: pw.BoxDecoration(
          color: hasEntry
              ? PdfThemeTokens.surface
              : PdfThemeTokens.surfaceSubtle,
          border: pw.Border.all(
            color: hasEntry
                ? PdfThemeTokens.accentCaramel
                : PdfThemeTokens.borderLight,
            width: hasEntry ? 1.0 : 0.6,
          ),
          borderRadius: pw.BorderRadius.circular(3),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '$dayNumber',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: hasEntry
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                    color: hasEntry
                        ? PdfThemeTokens.textPrimary
                        : PdfThemeTokens.textMuted,
                  ),
                ),
                if (hasEntry)
                  pw.Container(
                    width: 4.5,
                    height: 4.5,
                    decoration: const pw.BoxDecoration(
                      color: PdfThemeTokens.accentCaramel,
                      shape: pw.BoxShape.circle,
                    ),
                  ),
              ],
            ),
            if (hasPhotos)
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    photoCount == 1
                        ? effectiveDay.photos.first.title
                        : '$photoCount photos',
                    maxLines: 1,
                    style: const pw.TextStyle(
                      fontSize: 6,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfThemeTokens.textPrimary,
                    ),
                  ),
                  if (effectiveDay.photos.first.location != null &&
                      effectiveDay.photos.first.location!.isNotEmpty)
                    pw.Text(
                      effectiveDay.photos.first.location!,
                      maxLines: 1,
                      style: const pw.TextStyle(
                        fontSize: 5,
                        color: PdfThemeTokens.textMuted,
                      ),
                    ),
                ],
              )
            else if (hasNote)
              pw.Text(
                'Note',
                maxLines: 1,
                style: const pw.TextStyle(
                  fontSize: 5.5,
                  fontStyle: pw.FontStyle.italic,
                  color: PdfThemeTokens.accentCaramel,
                ),
              ),
          ],
        ),
      ),
    );
  }

  pw.Page _buildSingleOrTwoDayPage({
    required pw.ThemeData theme,
    required DayEntry day1,
    required pw.ImageProvider? image1,
    required DayEntry? day2,
    required pw.ImageProvider? image2,
    required String monthYearLabel,
  }) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      theme: theme,
      build: (context) {
        return pw.Container(
          decoration: pw.BoxDecoration(
            color: PdfThemeTokens.linenBackground,
            border: pw.Border.all(color: PdfThemeTokens.border, width: 1.0),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          padding: const pw.EdgeInsets.all(20),
          child: pw.Column(
            children: [
              // Entry 1
              pw.Expanded(
                child: _buildDaySlot(day: day1, image: image1),
              ),

              if (day2 != null) ...[
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 8),
                  child: pw.Divider(
                    color: PdfThemeTokens.border,
                    thickness: 0.8,
                  ),
                ),
                // Entry 2
                pw.Expanded(
                  child: _buildDaySlot(day: day2, image: image2),
                ),
              ],

              // Running Footer
              pw.SizedBox(height: 6),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Daria | $monthYearLabel',
                    style: const pw.TextStyle(
                      color: PdfThemeTokens.textMuted,
                      fontSize: 8.5,
                    ),
                  ),
                  pw.Text(
                    'Personal Photo Diary',
                    style: const pw.TextStyle(
                      color: PdfThemeTokens.textMuted,
                      fontSize: 8.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  pw.Widget _buildDaySlot({
    required DayEntry day,
    required pw.ImageProvider? image,
  }) {
    if (day.photos.isNotEmpty) {
      return _buildMemoryEntry(
        entry: day.photos.first,
        image: image,
        dailyNote: day.note,
      );
    } else {
      return _buildNoteOnlyDayEntry(day);
    }
  }

  pw.Widget _buildNoteOnlyDayEntry(DayEntry day) {
    final formattedDate = _formatLongDate(day.dateKey.toDateTime());

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Date & Meta Bar
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              formattedDate,
              style: const pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfThemeTokens.textPrimary,
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 2,
              ),
              decoration: pw.BoxDecoration(
                color: PdfThemeTokens.accentCaramelLight,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Text(
                'Daily Reflection',
                style: const pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfThemeTokens.accentCaramel,
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Expanded(
          child: pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfThemeTokens.surface,
              border: pw.Border.all(color: PdfThemeTokens.border, width: 0.8),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '"',
                  style: const pw.TextStyle(
                    fontSize: 26,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfThemeTokens.accentCaramel,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  day.note,
                  style: const pw.TextStyle(
                    fontSize: 10.5,
                    color: PdfThemeTokens.textPrimary,
                    lineSpacing: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  pw.Page _buildMultiPhotoDayPage({
    required pw.ThemeData theme,
    required DayEntry day,
    required List<pw.ImageProvider?> images,
    required String monthYearLabel,
  }) {
    final formattedDate = _formatLongDate(day.dateKey.toDateTime());
    final hasNote = day.hasNote;
    final photos = day.photos;

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      theme: theme,
      build: (context) {
        return pw.Container(
          decoration: pw.BoxDecoration(
            color: PdfThemeTokens.linenBackground,
            border: pw.Border.all(color: PdfThemeTokens.border, width: 1.0),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          padding: const pw.EdgeInsets.all(20),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header Row
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    formattedDate,
                    style: const pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfThemeTokens.textPrimary,
                    ),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfThemeTokens.accentCaramelLight,
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Text(
                      '${photos.length} Photos',
                      style: const pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfThemeTokens.accentCaramel,
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),

              // Photos Grid Area
              pw.Expanded(
                child: _buildAdaptivePhotoGrid(photos: photos, images: images),
              ),

              // Shared Daily Note (rendered ONCE per day)
              if (hasNote) ...[
                pw.SizedBox(height: 8),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfThemeTokens.surface,
                    borderRadius: pw.BorderRadius.circular(4),
                    border: pw.Border.all(
                      color: PdfThemeTokens.accentCaramelLight,
                      width: 1.0,
                    ),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        children: [
                          pw.Container(
                            width: 3,
                            height: 10,
                            decoration: const pw.BoxDecoration(
                              color: PdfThemeTokens.accentCaramel,
                              borderRadius: pw.BorderRadius.all(
                                pw.Radius.circular(1),
                              ),
                            ),
                          ),
                          pw.SizedBox(width: 5),
                          pw.Text(
                            'DAILY REFLECTION',
                            style: const pw.TextStyle(
                              color: PdfThemeTokens.accentCaramel,
                              fontSize: 7.5,
                              fontWeight: pw.FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        day.note,
                        style: const pw.TextStyle(
                          color: PdfThemeTokens.textPrimary,
                          fontSize: 9,
                          lineSpacing: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Running Footer
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Daria | $monthYearLabel',
                    style: const pw.TextStyle(
                      color: PdfThemeTokens.textMuted,
                      fontSize: 8.5,
                    ),
                  ),
                  pw.Text(
                    'Personal Photo Diary',
                    style: const pw.TextStyle(
                      color: PdfThemeTokens.textMuted,
                      fontSize: 8.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  pw.Widget _buildAdaptivePhotoGrid({
    required List<PhotoEntry> photos,
    required List<pw.ImageProvider?> images,
  }) {
    if (photos.length == 2) {
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Expanded(
            child: _buildPhotoTile(photo: photos[0], image: images[0]),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: _buildPhotoTile(photo: photos[1], image: images[1]),
          ),
        ],
      );
    } else if (photos.length == 3) {
      return pw.Column(
        children: [
          pw.Expanded(
            flex: 6,
            child: _buildPhotoTile(photo: photos[0], image: images[0]),
          ),
          pw.SizedBox(height: 8),
          pw.Expanded(
            flex: 5,
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Expanded(
                  child: _buildPhotoTile(photo: photos[1], image: images[1]),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: _buildPhotoTile(photo: photos[2], image: images[2]),
                ),
              ],
            ),
          ),
        ],
      );
    } else {
      // 4 or more photos: 2 rows grid
      final mid = (photos.length / 2).ceil();
      final firstRowPhotos = photos.sublist(0, mid);
      final firstRowImages = images.sublist(0, mid);
      final secondRowPhotos = photos.sublist(mid);
      final secondRowImages = images.sublist(mid);

      return pw.Column(
        children: [
          pw.Expanded(
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < firstRowPhotos.length; i++) ...[
                  if (i > 0) pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: _buildPhotoTile(
                      photo: firstRowPhotos[i],
                      image: firstRowImages[i],
                    ),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Expanded(
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < secondRowPhotos.length; i++) ...[
                  if (i > 0) pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: _buildPhotoTile(
                      photo: secondRowPhotos[i],
                      image: secondRowImages[i],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }
  }

  pw.Widget _buildPhotoTile({
    required PhotoEntry photo,
    required pw.ImageProvider? image,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Photo Frame
        pw.Expanded(
          child: pw.Container(
            width: double.infinity,
            decoration: pw.BoxDecoration(
              color: PdfThemeTokens.surface,
              border: pw.Border.all(color: PdfThemeTokens.border, width: 0.8),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            padding: const pw.EdgeInsets.all(4),
            child: image != null
                ? pw.ClipRRect(
                    horizontalRadius: 3,
                    verticalRadius: 3,
                    child: pw.Image(image, fit: pw.BoxFit.contain),
                  )
                : pw.Container(
                    color: PdfThemeTokens.surfaceSubtle,
                    child: pw.Center(
                      child: pw.Column(
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: [
                          pw.Text(
                            'Photo File Unavailable',
                            style: const pw.TextStyle(
                              color: PdfThemeTokens.textSecondary,
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Image not found or unreadable',
                            style: const pw.TextStyle(
                              color: PdfThemeTokens.textMuted,
                              fontSize: 7,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
        pw.SizedBox(height: 4),
        // Title and Time/Location Row
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(
                photo.title,
                maxLines: 1,
                style: const pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfThemeTokens.textPrimary,
                ),
              ),
            ),
            pw.SizedBox(width: 4),
            pw.Text(
              photo.timeFormatted,
              style: const pw.TextStyle(
                fontSize: 7.5,
                color: PdfThemeTokens.accentCaramel,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
        if (photo.location != null && photo.location!.isNotEmpty) ...[
          pw.SizedBox(height: 1),
          pw.Text(
            photo.location!,
            maxLines: 1,
            style: const pw.TextStyle(
              fontSize: 7.5,
              color: PdfThemeTokens.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  pw.Widget _buildMemoryEntry({
    required PhotoEntry entry,
    required pw.ImageProvider? image,
    String? dailyNote,
  }) {
    final formattedDate = _formatLongDate(entry.normalizedDate);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Date & Meta Bar
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Row(
              children: [
                pw.Text(
                  formattedDate,
                  style: const pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfThemeTokens.textPrimary,
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfThemeTokens.accentCaramelLight,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Text(
                    entry.timeFormatted,
                    style: const pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfThemeTokens.accentCaramel,
                    ),
                  ),
                ),
              ],
            ),
            pw.Text(
              entry.category,
              style: const pw.TextStyle(
                fontSize: 8.5,
                color: PdfThemeTokens.textMuted,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),

        // Photo Frame
        pw.Expanded(
          child: pw.Container(
            width: double.infinity,
            decoration: pw.BoxDecoration(
              color: PdfThemeTokens.surface,
              border: pw.Border.all(color: PdfThemeTokens.border, width: 0.8),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            padding: const pw.EdgeInsets.all(6),
            child: image != null
                ? pw.ClipRRect(
                    horizontalRadius: 3,
                    verticalRadius: 3,
                    child: pw.Image(image, fit: pw.BoxFit.contain),
                  )
                : pw.Container(
                    color: PdfThemeTokens.surfaceSubtle,
                    child: pw.Center(
                      child: pw.Column(
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: [
                          pw.Text(
                            'Photo File Unavailable',
                            style: const pw.TextStyle(
                              color: PdfThemeTokens.textSecondary,
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            'Original image was unreadable or not found on device',
                            style: const pw.TextStyle(
                              color: PdfThemeTokens.textMuted,
                              fontSize: 8.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
        pw.SizedBox(height: 6),

        // Title and Location Caption
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(
                entry.title,
                maxLines: 1,
                style: const pw.TextStyle(
                  fontSize: 10.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfThemeTokens.textPrimary,
                ),
              ),
            ),
            if (entry.location != null && entry.location!.isNotEmpty) ...[
              pw.SizedBox(width: 8),
              pw.Text(
                entry.location!,
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfThemeTokens.textSecondary,
                ),
              ),
            ],
          ],
        ),
        if (dailyNote != null && dailyNote.trim().isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: pw.BoxDecoration(
              color: PdfThemeTokens.surfaceSubtle,
              borderRadius: pw.BorderRadius.circular(3),
              border: pw.Border.all(
                color: PdfThemeTokens.borderLight,
                width: 0.6,
              ),
            ),
            child: pw.Text(
              dailyNote,
              maxLines: 2,
              style: const pw.TextStyle(
                color: PdfThemeTokens.textSecondary,
                fontSize: 8,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ),
        ],
      ],
    );
  }

  pw.Page _buildSummaryPage({
    required pw.ThemeData theme,
    required List<PhotoEntry> entries,
    List<DayEntry>? days,
    required String dateRangeStr,
  }) {
    final stats = StatisticsService.instance.calculateStatistics();
    final streaks = StreakService.instance.calculateStreak();
    final totalDaysCount = days?.length ?? entries.length;

    final activeMonthStr = stats.mostActiveMonth != null
        ? '${_monthName(stats.mostActiveMonth!)} (${stats.mostActiveMonthCount} photos)'
        : 'All Months Active';

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      theme: theme,
      build: (context) {
        return pw.Container(
          decoration: pw.BoxDecoration(
            color: PdfThemeTokens.linenBackground,
            border: pw.Border.all(color: PdfThemeTokens.border, width: 1.5),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          padding: const pw.EdgeInsets.all(32),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              // Header
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfThemeTokens.accentCaramelLight,
                      borderRadius: pw.BorderRadius.circular(10),
                    ),
                    child: pw.Text(
                      'MILESTONES & REFLECTION',
                      style: const pw.TextStyle(
                        color: PdfThemeTokens.accentCaramel,
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    'Diary Summary & Statistics',
                    style: const pw.TextStyle(
                      color: PdfThemeTokens.textPrimary,
                      fontSize: 26,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'A quiet reflection on your journey of daily observation ($dateRangeStr)',
                    style: const pw.TextStyle(
                      color: PdfThemeTokens.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),

              // Statistics Cards Grid (2x2)
              pw.Column(
                children: [
                  pw.Row(
                    children: [
                      _buildSummaryStatCard(
                        title: 'Total Memories',
                        value: '${entries.length} Photos',
                        description: '$totalDaysCount Recorded Days',
                        accent: PdfThemeTokens.accentCaramel,
                      ),
                      pw.SizedBox(width: 14),
                      _buildSummaryStatCard(
                        title: 'Longest Streak',
                        value: '${streaks.longestStreak} Days',
                        description: 'Best consecutive daily photo run',
                        accent: PdfThemeTokens.statDaysGreen,
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 14),
                  pw.Row(
                    children: [
                      _buildSummaryStatCard(
                        title: 'Current Streak',
                        value: '${streaks.currentStreak} Days',
                        description: 'Active consecutive photo streak',
                        accent: PdfThemeTokens.accentCaramel,
                      ),
                      pw.SizedBox(width: 14),
                      _buildSummaryStatCard(
                        title: 'Most Active Month',
                        value: activeMonthStr,
                        description: 'Month with highest photo frequency',
                        accent: PdfThemeTokens.statDaysGreen,
                      ),
                    ],
                  ),
                ],
              ),

              // Closing Statement / Philosophy Card
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(18),
                decoration: pw.BoxDecoration(
                  color: PdfThemeTokens.surface,
                  border: pw.Border.all(
                    color: PdfThemeTokens.border,
                    width: 0.8,
                  ),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '"We do not remember days, we remember moments."',
                      style: const pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        fontStyle: pw.FontStyle.italic,
                        color: PdfThemeTokens.textPrimary,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Daria is built on the philosophy that everyday life is worth noticing. '
                      'By capturing deliberate photographs each calendar day, ordinary routines transform into an enduring personal archive.',
                      style: const pw.TextStyle(
                        fontSize: 9.5,
                        color: PdfThemeTokens.textSecondary,
                        lineSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              // Footer Stamp
              pw.Column(
                children: [
                  pw.Divider(color: PdfThemeTokens.border, thickness: 0.8),
                  pw.SizedBox(height: 8),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Stored Privately on Device | No Cloud Transmission',
                        style: const pw.TextStyle(
                          color: PdfThemeTokens.textMuted,
                          fontSize: 9,
                        ),
                      ),
                      pw.Text(
                        'Daria v1.0',
                        style: const pw.TextStyle(
                          color: PdfThemeTokens.textMuted,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  pw.Widget _buildSummaryStatCard({
    required String title,
    required String value,
    required String description,
    required PdfColor accent,
  }) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(
          color: PdfThemeTokens.surface,
          border: pw.Border.all(color: PdfThemeTokens.border, width: 0.8),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: accent,
                letterSpacing: 0.6,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              value,
              style: const pw.TextStyle(
                fontSize: 17,
                fontWeight: pw.FontWeight.bold,
                color: PdfThemeTokens.textPrimary,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              description,
              style: const pw.TextStyle(
                fontSize: 8.5,
                color: PdfThemeTokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  /// Safely reads, validates, and downsamples an image from disk without risking OOM or parser crashes.
  Future<Uint8List?> _loadLogoBytes() async {
    try {
      final file = File('assets/images/icons/dariaicon.png');
      if (file.existsSync()) {
        return await file.readAsBytes();
      }
    } catch (_) {}
    try {
      final byteData = await rootBundle.load(
        'assets/images/icons/dariaicon.png',
      );
      return byteData.buffer.asUint8List();
    } catch (_) {}
    return null;
  }

  pw.ImageProvider? _loadImageSafely(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    final file = File(path.trim());
    if (!file.existsSync()) return null;

    try {
      final bytes = file.readAsBytesSync();
      if (bytes.isEmpty) return null;

      final isJpg =
          bytes.length > 3 &&
          bytes[0] == 0xFF &&
          bytes[1] == 0xD8 &&
          bytes[2] == 0xFF;
      final isPng =
          bytes.length > 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47;

      if (!isJpg && !isPng) {
        // If not standard JPEG/PNG, attempt to decode and transcode (supports WebP, BMP, GIF)
        try {
          final decoded = img.decodeImage(bytes);
          if (decoded == null) return null; // Corrupt or unreadable image data
          final compressed = Uint8List.fromList(
            img.encodeJpg(decoded, quality: 85),
          );
          return pw.MemoryImage(compressed);
        } catch (_) {
          return null;
        }
      }

      // If image is larger than 1.5MB, downsample it to max 1200px width/height
      if (bytes.length > 1572864) {
        try {
          final decoded = img.decodeImage(bytes);
          if (decoded != null &&
              (decoded.width > 1200 || decoded.height > 1200)) {
            final resized = img.copyResize(
              decoded,
              width: decoded.width > decoded.height ? 1200 : null,
              height: decoded.height >= decoded.width ? 1200 : null,
            );
            final compressed = Uint8List.fromList(
              img.encodeJpg(resized, quality: 85),
            );
            return pw.MemoryImage(compressed);
          }
        } catch (_) {
          // If downsampling fails, use original bytes
        }
      }

      return pw.MemoryImage(bytes);
    } catch (e) {
      debugPrint('PdfDiaryExportService: failed to read image $path: $e');
      return null;
    }
  }

  List<_YearMonthDayGroup> _groupDaysByYearAndMonth(List<DayEntry> days) {
    final map = <String, _YearMonthDayGroup>{};
    for (final day in days) {
      final key = '${day.dateKey.year}_${day.dateKey.month}';
      if (!map.containsKey(key)) {
        map[key] = _YearMonthDayGroup(
          year: day.dateKey.year,
          month: day.dateKey.month,
          days: [],
        );
      }
      map[key]!.days.add(day);
    }
    return map.values.toList();
  }

  String _generateFilename(PdfExportRange range) {
    if (range.type == ExportRangeType.year && range.year != null) {
      return 'Daria_Diary_${range.year}.pdf';
    }
    return 'Daria_Diary_all_time.pdf';
  }

  String _formatDateRange(DateTime start, DateTime end, PdfExportRange range) {
    if (range.type == ExportRangeType.year && range.year != null) {
      return 'Year ${range.year} (${_monthName(start.month)} ${start.day} - ${_monthName(end.month)} ${end.day})';
    }
    return '${_monthName(start.month)} ${start.day}, ${start.year} - ${_monthName(end.month)} ${end.day}, ${end.year}';
  }

  String _formatLongDate(DateTime date) {
    final weekday = _weekdayName(date.weekday);
    final month = _monthName(date.month);
    return '$weekday, $month ${date.day}, ${date.year}';
  }

  static String _monthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    if (month >= 1 && month <= 12) return names[month - 1];
    return 'Month $month';
  }

  static String _weekdayName(int weekday) {
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    if (weekday >= 1 && weekday <= 7) return names[weekday - 1];
    return '';
  }
}

class _YearMonthDayGroup {
  _YearMonthDayGroup({
    required this.year,
    required this.month,
    required this.days,
  });

  final int year;
  final int month;
  final List<DayEntry> days;
}
