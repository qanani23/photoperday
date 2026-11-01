import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/data/models/pad_backup_models.dart';
import 'package:photo_per_day/data/services/pad_backup_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';

/// Modal dialog facilitating the export of a portable `.padbackup` package.
class PadBackupExportDialog extends StatefulWidget {
  const PadBackupExportDialog({super.key, this.service});

  final PadBackupService? service;

  static Future<void> show(BuildContext context, {PadBackupService? service}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PadBackupExportDialog(service: service),
    );
  }

  @override
  State<PadBackupExportDialog> createState() => _PadBackupExportDialogState();
}

enum _ExportStep { estimating, empty, ready, generating, completed, error }

class _PadBackupExportDialogState extends State<PadBackupExportDialog> {
  late final PadBackupService _service;

  _ExportStep _step = _ExportStep.estimating;
  PadBackupEstimate? _estimate;
  PadBackupExportResult? _result;
  String? _errorMessage;

  double _progress = 0.0;
  String _statusMessage = 'Preparing backup...';
  bool _allowPartial = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PadBackupService();
    _calculateEstimate();
  }

  Future<void> _calculateEstimate() async {
    setState(() {
      _step = _ExportStep.estimating;
    });

    final totalDays = PersistentDailyPhotoStore.instance.totalDays;
    if (totalDays == 0) {
      if (mounted) {
        setState(() {
          _step = _ExportStep.empty;
        });
      }
      return;
    }

    try {
      final estimate = await _service.calculateEstimatedExportSize();
      if (mounted) {
        setState(() {
          _estimate = estimate;
          _step = _ExportStep.ready;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _step = _ExportStep.error;
          _errorMessage = 'Failed to inspect diary for backup: $e';
        });
      }
    }
  }

  Future<void> _startExport() async {
    setState(() {
      _step = _ExportStep.generating;
      _progress = 0.05;
      _statusMessage = 'Initializing backup archive...';
    });

    try {
      final result = await _service.exportBackup(
        allowPartial: _allowPartial,
        onProgress: (progress, status) {
          if (mounted) {
            setState(() {
              _progress = progress;
              _statusMessage = status;
            });
          }
        },
      );

      if (mounted) {
        if (result.isSuccess) {
          setState(() {
            _result = result;
            _step = _ExportStep.completed;
          });
        } else {
          setState(() {
            _step = _ExportStep.error;
            _errorMessage = result.errorMessage ?? 'Backup failed to compile.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _step = _ExportStep.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _shareBackup() async {
    final file = _result?.backupFile;
    if (file == null) return;

    final filename = file.path.split(Platform.pathSeparator).last;
    await _service.platformDelegate.shareBackupFile(
      filePath: file.path,
      filename: filename,
    );
  }

  Future<void> _saveToDestination() async {
    final file = _result?.backupFile;
    if (file == null) return;

    final filename = file.path.split(Platform.pathSeparator).last;
    final savedPath = await _service.platformDelegate
        .saveBackupToUserDestination(
          sourceFilePath: file.path,
          suggestedFilename: filename,
        );

    if (savedPath != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup saved successfully: $savedPath'),
          backgroundColor: AppColors.accent,
        ),
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_step != _ExportStep.generating) {
            Navigator.of(context).pop();
          }
        },
      },
      child: Dialog(
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadii.dialogRadius,
        ),
        backgroundColor: AppColors.surface,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                _buildBody(),
                const SizedBox(height: 24),
                _buildActions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.archive_outlined,
            color: AppColors.accent,
            size: 24,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Create Portable Backup',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Export diary to a standalone .padbackup file',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _ExportStep.estimating:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
              ),
              const SizedBox(height: 16),
              Text(
                'Inspecting diary storage...',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
            ],
          ),
        );

      case _ExportStep.empty:
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Icon(
                Icons.photo_library_outlined,
                size: 40,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 12),
              Text(
                'Your Diary is Empty',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Capture daily memories first to generate a portable backup archive.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        );

      case _ExportStep.ready:
        final estimate = _estimate!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  _buildStatRow(
                    'Available Memories',
                    '${estimate.availablePhotos} photos',
                    Icons.photo_rounded,
                  ),
                  const Divider(height: 16),
                  _buildStatRow(
                    'Estimated Backup Size',
                    _formatBytes(estimate.totalBytes),
                    Icons.data_usage_rounded,
                  ),
                  const Divider(height: 16),
                  _buildStatRow(
                    'Archive Format',
                    'Daria (.padbackup v2)',
                    Icons.security_rounded,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (estimate.hasMissingPhotos) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade400),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.amber.shade800,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${estimate.missingPhotos} Photo(s) Missing on Disk',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.amber.shade900,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Some photo files could not be found in storage. You can create a partial backup with available photos.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(
                          value: _allowPartial,
                          activeColor: AppColors.accent,
                          onChanged: (val) {
                            setState(() {
                              _allowPartial = val ?? false;
                            });
                          },
                        ),
                        const Expanded(
                          child: Text(
                            'Allow Partial Backup (proceed with available photos)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline, size: 18, color: AppColors.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Unencrypted Archive: Contains original full-resolution photos, diary metadata, and preferences. Store this file securely.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

      case _ExportStep.generating:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 16),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${(_progress * 100).toInt()}% completed',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        );

      case _ExportStep.completed:
        final res = _result!;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade300),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: Colors.green,
                size: 44,
              ),
              const SizedBox(height: 10),
              Text(
                'Backup Created Successfully!',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                res.isPartial
                    ? 'Partial backup completed (${res.skippedCount} skipped).'
                    : 'Complete diary archive with verified SHA-256 integrity.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildSummaryBadge('${res.photoCount}', 'Photos'),
                  ),
                  Expanded(
                    child: _buildSummaryBadge(
                      _formatBytes(res.totalSizeBytes),
                      'File Size',
                    ),
                  ),
                  Expanded(child: _buildSummaryBadge('SHA-256', 'Verified')),
                ],
              ),
            ],
          ),
        );

      case _ExportStep.error:
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.shade300),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.red,
                size: 40,
              ),
              const SizedBox(height: 10),
              Text(
                'Backup Failed',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _errorMessage ?? 'An unexpected error occurred during export.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildStatRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryBadge(String title, String subtitle) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            subtitle,
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    switch (_step) {
      case _ExportStep.estimating:
      case _ExportStep.generating:
        return const SizedBox.shrink();

      case _ExportStep.empty:
        return OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        );

      case _ExportStep.ready:
        final hasMissing = _estimate?.hasMissingPhotos ?? false;
        final canExport = !hasMissing || _allowPartial;

        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: canExport ? _startExport : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Create Backup'),
              ),
            ),
          ],
        );

      case _ExportStep.completed:
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saveToDestination,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Save to Files'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _shareBackup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Share Backup'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Done',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        );

      case _ExportStep.error:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _calculateEstimate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retry'),
              ),
            ),
          ],
        );
    }
  }
}
