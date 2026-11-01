import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/pdf_export_models.dart';
import 'package:photo_per_day/data/services/local_storage_calculator.dart';
import 'package:photo_per_day/data/services/pdf_diary_export_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/widgets/daria_logo.dart';

/// Interactive modal dialog allowing users to configure and export their local photo diary as a PDF.
///
/// Features:
/// - Range selection: All Time or specific Year.
/// - Live memory count for chosen scope.
/// - Progress feedback during multi-page rendering.
/// - Direct system Share / Save to Files and Print actions.
/// - Graceful handling of empty diaries or unexpected errors.
class PdfExportDialog extends StatefulWidget {
  const PdfExportDialog({super.key, this.exportService, this.store});

  final PdfDiaryExportService? exportService;
  final PersistentDailyPhotoStore? store;

  static Future<void> show(
    BuildContext context, {
    PdfDiaryExportService? exportService,
    PersistentDailyPhotoStore? store,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          PdfExportDialog(exportService: exportService, store: store),
    );
  }

  @override
  State<PdfExportDialog> createState() => _PdfExportDialogState();
}

enum _DialogPhase { configure, generating, complete, error }

class _PdfExportDialogState extends State<PdfExportDialog> {
  late final PdfDiaryExportService _service;
  late final PersistentDailyPhotoStore _store;

  _DialogPhase _phase = _DialogPhase.configure;
  late PdfExportRange _selectedRange;
  List<int> _availableYears = [];
  List<DateKey> _recordedDates = [];

  PdfExportResult? _lastResult;
  String? _errorMessage;
  bool _isSharing = false;
  bool _isPrinting = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _service = widget.exportService ?? PdfDiaryExportService.instance;
    _store = widget.store ?? PersistentDailyPhotoStore.instance;

    _recordedDates = _store.recordedDates;
    _availableYears = _service.getAvailableYears();
    _selectedRange = const PdfExportRange.allTime();
  }

  int _countForRange(PdfExportRange range) {
    if (range.type == ExportRangeType.allTime) {
      return _recordedDates.length;
    }
    return _recordedDates.where((k) => k.year == range.year).length;
  }

  int _countForYear(int year) {
    return _recordedDates.where((k) => k.year == year).length;
  }

  Future<void> _handleGenerate() async {
    setState(() {
      _phase = _DialogPhase.generating;
      _errorMessage = null;
    });

    try {
      final result = await _service.generatePdf(range: _selectedRange);
      if (!mounted) return;

      if (result.isSuccess) {
        setState(() {
          _lastResult = result;
          _phase = _DialogPhase.complete;
        });
      } else {
        setState(() {
          _errorMessage =
              result.errorMessage ?? 'Unable to generate PDF diary.';
          _phase = _DialogPhase.error;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _phase = _DialogPhase.error;
      });
    }
  }

  Future<void> _handleShare() async {
    final result = _lastResult;
    if (result == null || _isSharing) return;

    setState(() => _isSharing = true);
    try {
      await _service.sharePdf(result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to share PDF: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
  }

  Future<void> _handlePrint() async {
    final result = _lastResult;
    if (result == null || _isPrinting) return;

    setState(() => _isPrinting = true);
    try {
      await _service.printPdf(result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open print preview: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPrinting = false);
      }
    }
  }

  Future<void> _handleSavePdf() async {
    final result = _lastResult;
    if (result == null || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      final savedPath = await _service.savePdf(result);
      if (savedPath != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF saved successfully to: $savedPath'),
            backgroundColor: AppColors.accent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save PDF: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = _recordedDates.isEmpty;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_phase != _DialogPhase.generating) {
            Navigator.of(context).pop();
          }
        },
      },
      child: Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.dialogRadius,
          side: BorderSide(color: AppColors.border, width: 0.8),
        ),
        insetPadding: const EdgeInsets.symmetric(
          horizontal: 20.0,
          vertical: 24.0,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: isEmpty ? _buildEmptyView() : _buildCurrentPhaseView(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const DariaLogo(size: 38.0),
            const SizedBox(width: 14.0),
            Expanded(
              child: Text(
                'Photo Diary Book',
                style: TextStyle(
                  fontSize: 18.0,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18.0),
        Text(
          'Your diary does not contain any captured photos yet.',
          style: AppTypography.body.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8.0),
        Text(
          'Capture daily photos to generate an editorial, print-ready PDF photo book with calendars, memory spreads, and milestones.',
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 24.0),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Close',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentPhaseView() {
    switch (_phase) {
      case _DialogPhase.configure:
        return _buildConfigureView();
      case _DialogPhase.generating:
        return _buildGeneratingView();
      case _DialogPhase.complete:
        return _buildCompleteView();
      case _DialogPhase.error:
        return _buildErrorView();
    }
  }

  Widget _buildConfigureView() {
    final count = _countForRange(_selectedRange);
    final isAllTime = _selectedRange.type == ExportRangeType.allTime;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const DariaLogo(size: 38.0),
            const SizedBox(width: 14.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Export as PDF Diary',
                    style: TextStyle(
                      fontSize: 18.0,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2.0),
                  Text(
                    'Editorial print-ready photo book',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18.0),
        Text(
          'SELECT EXPORT RANGE',
          style: TextStyle(
            fontSize: 11.0,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 10.0),

        // Range selector cards
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(10.0),
            border: Border.all(color: AppColors.border, width: 0.6),
          ),
          child: Column(
            children: [
              InkWell(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(10.0),
                ),
                onTap: () {
                  setState(() {
                    _selectedRange = const PdfExportRange.allTime();
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14.0,
                    vertical: 12.0,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isAllTime
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: isAllTime
                            ? AppColors.accent
                            : AppColors.textMuted,
                        size: 20.0,
                      ),
                      const SizedBox(width: 12.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Entire Diary (All Time)',
                              style: TextStyle(
                                fontSize: 14.0,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              '${_recordedDates.length} memories',
                              style: TextStyle(
                                fontSize: 12.0,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_availableYears.isNotEmpty) ...[
                Divider(height: 1.0, color: AppColors.border),
                InkWell(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(10.0),
                  ),
                  onTap: () {
                    setState(() {
                      _selectedRange = PdfExportRange.year(
                        _availableYears.first,
                      );
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14.0,
                      vertical: 12.0,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          !isAllTime
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: !isAllTime
                              ? AppColors.accent
                              : AppColors.textMuted,
                          size: 20.0,
                        ),
                        const SizedBox(width: 12.0),
                        Expanded(
                          child: Text(
                            'Specific Year',
                            style: TextStyle(
                              fontSize: 14.0,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (!isAllTime)
                          DropdownButton<int>(
                            value: _selectedRange.year ?? _availableYears.first,
                            underline: const SizedBox(),
                            isDense: true,
                            dropdownColor: AppColors.surface,
                            style: TextStyle(
                              fontSize: 13.0,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent,
                            ),
                            items: _availableYears
                                .map(
                                  (y) => DropdownMenuItem(
                                    value: y,
                                    child: Text('$y (${_countForYear(y)})'),
                                  ),
                                )
                                .toList(),
                            onChanged: (y) {
                              if (y != null) {
                                setState(() {
                                  _selectedRange = PdfExportRange.year(y);
                                });
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16.0),

        // Features list
        Container(
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: AppColors.borderSubtle, width: 0.6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFeatureItem(
                Icons.bookmark_outline_rounded,
                'Warm linen cover page with hero photo',
              ),
              const SizedBox(height: 6.0),
              _buildFeatureItem(
                Icons.calendar_today_outlined,
                'Full-year overview & monthly calendars',
              ),
              const SizedBox(height: 6.0),
              _buildFeatureItem(
                Icons.photo_library_outlined,
                '2 photos per spread with dates & locations',
              ),
              const SizedBox(height: 6.0),
              _buildFeatureItem(
                Icons.auto_graph_rounded,
                'Streak statistics & milestones summary',
              ),
            ],
          ),
        ),

        const SizedBox(height: 20.0),

        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8.0),
            ElevatedButton.icon(
              onPressed: count == 0 ? null : _handleGenerate,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 10.0,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18.0),
              label: Text(
                'Create PDF ($count)',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFeatureItem(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 14.0, color: AppColors.accent),
        const SizedBox(width: 8.0),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 12.0, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _buildGeneratingView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16.0),
        CircularProgressIndicator(color: AppColors.accent, strokeWidth: 3.0),
        const SizedBox(height: 24.0),
        Text(
          'Crafting Your Photo Diary...',
          style: TextStyle(
            fontSize: 18.0,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8.0),
        Text(
          'Formatting calendars, optimizing memory spreads, and rendering print-ready layouts.',
          textAlign: TextAlign.center,
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16.0),
      ],
    );
  }

  Widget _buildCompleteView() {
    final result = _lastResult!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10.0),
              decoration: BoxDecoration(
                color: AppColors.statDaysGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10.0),
              ),
              child: Icon(
                Icons.check_circle_rounded,
                color: AppColors.statDaysGreen,
                size: 26.0,
              ),
            ),
            const SizedBox(width: 14.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Photo Diary Ready!',
                    style: TextStyle(
                      fontSize: 18.0,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2.0),
                  Text(
                    result.filename,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18.0),

        // Document Details Card
        Container(
          padding: const EdgeInsets.all(14.0),
          decoration: BoxDecoration(
            color: AppColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(10.0),
            border: Border.all(color: AppColors.border, width: 0.6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMetricColumn('MEMORIES', '${result.exportedPhotoCount}'),
              Container(width: 1.0, height: 32.0, color: AppColors.border),
              _buildMetricColumn('PAGES', '${result.pageCount}'),
              Container(width: 1.0, height: 32.0, color: AppColors.border),
              _buildMetricColumn(
                'SIZE',
                LocalStorageCalculator.formatBytes(result.fileSizeBytes),
              ),
            ],
          ),
        ),

        if (result.skippedPhotoCount > 0) ...[
          const SizedBox(height: 8.0),
          Text(
            'Note: ${result.skippedPhotoCount} photo(s) were missing or unreadable and displayed as editorial placeholders.',
            style: TextStyle(
              fontSize: 11.5,
              color: AppColors.textMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],

        const SizedBox(height: 20.0),

        // File Save, Share & Print Actions
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('pdf_save_to_file_button'),
                onPressed: _isSaving ? null : _handleSavePdf,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
                icon: _isSaving
                    ? const SizedBox(
                        width: 16.0,
                        height: 16.0,
                        child: CircularProgressIndicator(strokeWidth: 2.0),
                      )
                    : const Icon(Icons.download_rounded, size: 18.0),
                label: const Text(
                  'Save to File',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 8.0),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isPrinting ? null : _handlePrint,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
                icon: _isPrinting
                    ? const SizedBox(
                        width: 16.0,
                        height: 16.0,
                        child: CircularProgressIndicator(strokeWidth: 2.0),
                      )
                    : const Icon(Icons.print_outlined, size: 18.0),
                label: const Text(
                  'Print',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 8.0),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isSharing ? null : _handleShare,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  elevation: 0,
                ),
                icon: _isSharing
                    ? const SizedBox(
                        width: 16.0,
                        height: 16.0,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.0,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.share_outlined, size: 18.0),
                label: const Text(
                  'Share / Save to Files',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12.0),
        Align(
          alignment: Alignment.center,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Done',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricColumn(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16.0,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2.0),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.0,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10.0),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10.0),
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: Colors.redAccent,
                size: 26.0,
              ),
            ),
            const SizedBox(width: 14.0),
            Expanded(
              child: Text(
                'Export Failed',
                style: TextStyle(
                  fontSize: 18.0,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16.0),
        Text(
          _errorMessage ??
              'An unexpected error occurred while creating the PDF diary.',
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20.0),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Dismiss',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8.0),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _phase = _DialogPhase.configure;
                  _errorMessage = null;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
                elevation: 0,
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ],
    );
  }
}
