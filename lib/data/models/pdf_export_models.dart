import 'dart:io';
import 'package:flutter/foundation.dart';

/// Scope of photos to include in the PDF export.
enum ExportRangeType {
  /// All recorded photos from the entire diary history.
  allTime,

  /// Photos recorded within a specific calendar year.
  year,
}

/// Defines the range selection for PDF diary generation.
@immutable
class PdfExportRange {
  const PdfExportRange.allTime() : type = ExportRangeType.allTime, year = null;

  const PdfExportRange.year(int selectedYear)
    : type = ExportRangeType.year,
      year = selectedYear;

  final ExportRangeType type;
  final int? year;

  /// User-friendly label for UI selectors.
  String get label {
    switch (type) {
      case ExportRangeType.allTime:
        return 'Entire Diary (All Time)';
      case ExportRangeType.year:
        return 'Year $year';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfExportRange &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          year == other.year;

  @override
  int get hashCode => Object.hash(type, year);

  @override
  String toString() => 'PdfExportRange($label)';
}

/// Structured result of a PDF diary export operation.
@immutable
class PdfExportResult {
  const PdfExportResult({
    required this.pdfBytes,
    this.pdfFile,
    required this.filename,
    required this.exportedPhotoCount,
    required this.skippedPhotoCount,
    required this.totalEntriesEvaluated,
    required this.pageCount,
    this.startDate,
    this.endDate,
    required this.fileSizeBytes,
    this.isSuccess = false,
    this.isEmpty = false,
    this.isPartial = false,
    this.errorMessage,
  });

  /// The raw PDF document bytes.
  final Uint8List pdfBytes;

  /// The persisted PDF file on disk, if saved to local storage.
  final File? pdfFile;

  /// Standardized filename for the export (e.g. `photo_a_day_diary_2026.pdf`).
  final String filename;

  /// Count of photo entries successfully rendered into the PDF.
  final int exportedPhotoCount;

  /// Count of photo entries skipped or rendered with fallback artwork due to missing files.
  final int skippedPhotoCount;

  /// Total count of photo entries evaluated for the selected range.
  final int totalEntriesEvaluated;

  /// Total pages generated in the PDF document.
  final int pageCount;

  /// Earliest photo date included in the document.
  final DateTime? startDate;

  /// Latest photo date included in the document.
  final DateTime? endDate;

  /// File size in bytes.
  final int fileSizeBytes;

  /// Whether the PDF was generated successfully without unhandled errors.
  final bool isSuccess;

  /// Whether the selected range contained zero photos.
  final bool isEmpty;

  /// Whether some photos had to fall back to placeholder frames.
  final bool isPartial;

  /// Error message if generation failed completely.
  final String? errorMessage;

  factory PdfExportResult.empty({required String filename}) {
    return PdfExportResult(
      pdfBytes: Uint8List(0),
      filename: filename,
      exportedPhotoCount: 0,
      skippedPhotoCount: 0,
      totalEntriesEvaluated: 0,
      pageCount: 0,
      fileSizeBytes: 0,
      isEmpty: true,
      isSuccess: false,
    );
  }

  factory PdfExportResult.failure({
    required String errorMessage,
    required String filename,
    int totalEntries = 0,
  }) {
    return PdfExportResult(
      pdfBytes: Uint8List(0),
      filename: filename,
      exportedPhotoCount: 0,
      skippedPhotoCount: totalEntries,
      totalEntriesEvaluated: totalEntries,
      pageCount: 0,
      fileSizeBytes: 0,
      errorMessage: errorMessage,
      isSuccess: false,
      isEmpty: false,
    );
  }
}
