import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/data/models/pad_backup_models.dart';
import 'package:photo_per_day/data/services/pad_backup_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';

/// Modal dialog orchestrating the safe, transactional restore of a `.padbackup` file.
class PadBackupRestoreDialog extends StatefulWidget {
  const PadBackupRestoreDialog({super.key, this.service, this.initialFile});

  final PadBackupService? service;
  final File? initialFile;

  static Future<void> show(
    BuildContext context, {
    PadBackupService? service,
    File? initialFile,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          PadBackupRestoreDialog(service: service, initialFile: initialFile),
    );
  }

  @override
  State<PadBackupRestoreDialog> createState() => _PadBackupRestoreDialogState();
}

enum _RestoreStep {
  picking,
  inspecting,
  inspectionFailed,
  preview,
  restoring,
  success,
  error,
}

class _PadBackupRestoreDialogState extends State<PadBackupRestoreDialog> {
  late final PadBackupService _service;

  _RestoreStep _step = _RestoreStep.picking;
  PadBackupInspectionResult? _inspection;
  PadRestoreResult? _restoreResult;
  String? _errorMessage;

  double _progress = 0.0;
  String _statusMessage = 'Validating backup...';

  // Restore options
  PadRestoreMode _mode = PadRestoreMode.merge;
  PadConflictResolution _conflictResolution =
      PadConflictResolution.keepExisting;
  bool _replaceConfirmed = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PadBackupService();

    if (widget.initialFile != null) {
      _inspectFile(widget.initialFile!);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pickFile();
      });
    }
  }

  @override
  void dispose() {
    // Clean staging directory if dialog is dismissed without restore
    if (_inspection != null && _step != _RestoreStep.success) {
      _service.cleanStagingDirectory(_inspection!.stagingDir);
    }
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() {
      _step = _RestoreStep.picking;
    });

    final pickedPath = await _service.platformDelegate.pickBackupFile();
    if (pickedPath == null || pickedPath.isEmpty) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    final file = File(pickedPath);
    await _inspectFile(file);
  }

  Future<void> _inspectFile(File file) async {
    setState(() {
      _step = _RestoreStep.inspecting;
      _progress = 0.1;
      _statusMessage = 'Staging and validating backup archive...';
    });

    try {
      final inspection = await _service.inspectBackupFile(
        file,
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
        if (inspection.isValid) {
          setState(() {
            _inspection = inspection;
            _step = _RestoreStep.preview;
          });
        } else {
          setState(() {
            _inspection = inspection;
            _step = _RestoreStep.inspectionFailed;
            _errorMessage = inspection.validationError ?? 'Validation failed.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _step = _RestoreStep.inspectionFailed;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _executeRestore() async {
    final inspection = _inspection;
    if (inspection == null || !inspection.isValid) return;

    setState(() {
      _step = _RestoreStep.restoring;
      _progress = 0.05;
      _statusMessage = 'Preparing transactional restore...';
    });

    try {
      final result = await _service.restoreFromInspection(
        inspection,
        mode: _mode,
        conflictResolution: _conflictResolution,
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
            _restoreResult = result;
            _step = _RestoreStep.success;
          });
        } else {
          setState(() {
            _restoreResult = result;
            _step = _RestoreStep.error;
            _errorMessage = result.errorMessage ?? 'Restore failed.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _step = _RestoreStep.error;
          _errorMessage = e.toString();
        });
      }
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
          if (_step != _RestoreStep.restoring) {
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
          constraints: const BoxConstraints(maxWidth: 500),
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
            Icons.unarchive_outlined,
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
                'Restore Diary Backup',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Import photos and memories from .padbackup',
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
      case _RestoreStep.picking:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
              ),
              const SizedBox(height: 16),
              Text(
                'Opening file picker...',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
            ],
          ),
        );

      case _RestoreStep.inspecting:
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
                'Verifying cryptographic SHA-256 signatures and archive security',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        );

      case _RestoreStep.inspectionFailed:
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.shade300),
          ),
          child: Column(
            children: [
              const Icon(Icons.gpp_bad_rounded, color: Colors.red, size: 40),
              const SizedBox(height: 10),
              Text(
                'Backup Verification Failed',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _errorMessage ??
                    'The selected file is not a valid or authorized .padbackup archive.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
            ],
          ),
        );

      case _RestoreStep.preview:
        final insp = _inspection!;
        final manifest = insp.manifest!;
        final liveCount = insp.currentPhotosInDiary;

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
                    'Photos in Backup',
                    '${insp.totalPhotosInBackup} photos',
                    Icons.photo_library_rounded,
                  ),
                  const Divider(height: 14),
                  _buildStatRow(
                    'Backup Date Range',
                    manifest.startDate != null
                        ? '${manifest.startDate} to ${manifest.endDate}'
                        : 'Single Day',
                    Icons.calendar_month_rounded,
                  ),
                  const Divider(height: 14),
                  _buildStatRow(
                    'Current Diary Photos',
                    '$liveCount photos recorded',
                    Icons.access_time_rounded,
                  ),
                  const Divider(height: 14),
                  _buildStatRow(
                    'Archive Size',
                    _formatBytes(manifest.totalSizeBytes),
                    Icons.data_usage_rounded,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (liveCount > 0) ...[
              Text(
                'Choose Restore Mode',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),

              // Mode: Merge option card
              InkWell(
                onTap: () {
                  setState(() {
                    _mode = PadRestoreMode.merge;
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _mode == PadRestoreMode.merge
                        ? AppColors.accent.withValues(alpha: 0.08)
                        : AppColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _mode == PadRestoreMode.merge
                          ? AppColors.accent
                          : AppColors.border,
                      width: _mode == PadRestoreMode.merge ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _mode == PadRestoreMode.merge
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: _mode == PadRestoreMode.merge
                            ? AppColors.accent
                            : AppColors.textSecondary,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Merge with Existing Diary (Recommended)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              insp.conflictingCount > 0
                                  ? 'Adds ${insp.nonConflictingCount} new days. ${insp.conflictingCount} overlapping days detected.'
                                  : 'Adds all ${insp.nonConflictingCount} new days seamlessly.',
                              style: TextStyle(
                                fontSize: 12,
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

              if (_mode == PadRestoreMode.merge &&
                  insp.conflictingCount > 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(left: 16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Same-Day Conflict Resolution:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _conflictResolution =
                                PadConflictResolution.keepExisting;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(
                                _conflictResolution ==
                                        PadConflictResolution.keepExisting
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                size: 16,
                                color: AppColors.accent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Keep Current Photo (Preserve existing)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _conflictResolution =
                                PadConflictResolution.overwriteWithBackup;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(
                                _conflictResolution ==
                                        PadConflictResolution
                                            .overwriteWithBackup
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                size: 16,
                                color: AppColors.accent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Overwrite with Backup Photo',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 10),

              // Mode: Replace option card
              InkWell(
                onTap: () {
                  setState(() {
                    _mode = PadRestoreMode.replace;
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _mode == PadRestoreMode.replace
                        ? Colors.red.withValues(alpha: 0.05)
                        : AppColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _mode == PadRestoreMode.replace
                          ? Colors.red.shade400
                          : AppColors.border,
                      width: _mode == PadRestoreMode.replace ? 1.5 : 1.0,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            _mode == PadRestoreMode.replace
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: _mode == PadRestoreMode.replace
                                ? Colors.red
                                : AppColors.textSecondary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Replace Entire Diary (Caution)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _mode == PadRestoreMode.replace
                                        ? Colors.red
                                        : AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Replaces all current diary memories with the backup content.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (_mode == PadRestoreMode.replace) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Checkbox(
                              value: _replaceConfirmed,
                              activeColor: Colors.red,
                              onChanged: (val) {
                                setState(() {
                                  _replaceConfirmed = val ?? false;
                                });
                              },
                            ),
                            const Expanded(
                              child: Text(
                                'I understand my current diary photos will be replaced.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.red,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: Colors.green,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Diary is empty. All backup memories will be cleanly restored.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );

      case _RestoreStep.restoring:
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
                'Transactional restore with automatic rollback protection',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        );

      case _RestoreStep.success:
        final res = _restoreResult!;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade300),
          ),
          child: Column(
            children: [
              const Icon(Icons.task_alt_rounded, color: Colors.green, size: 44),
              const SizedBox(height: 10),
              Text(
                'Diary Restored Successfully!',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                res.mode == PadRestoreMode.replace
                    ? 'Replaced diary with ${res.importedCount} photos from backup.'
                    : 'Imported ${res.importedCount} photos, preserved ${res.preservedCount} existing memories.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildSummaryBadge(
                      '${res.importedCount}',
                      'Imported',
                    ),
                  ),
                  Expanded(
                    child: _buildSummaryBadge(
                      '${PersistentDailyPhotoStore.instance.count}',
                      'Total Memories',
                    ),
                  ),
                  Expanded(
                    child: _buildSummaryBadge('Ready', 'Streaks Synced'),
                  ),
                ],
              ),
            ],
          ),
        );

      case _RestoreStep.error:
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
                Icons.warning_amber_rounded,
                color: Colors.red,
                size: 40,
              ),
              const SizedBox(height: 10),
              Text(
                'Restore Failed (Rolled Back)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _errorMessage ??
                    'Restore failed. Rollback succeeded: your existing diary was not altered.',
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
      case _RestoreStep.picking:
      case _RestoreStep.inspecting:
      case _RestoreStep.restoring:
        return const SizedBox.shrink();

      case _RestoreStep.inspectionFailed:
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
                onPressed: _pickFile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Pick Another File'),
              ),
            ),
          ],
        );

      case _RestoreStep.preview:
        final isReplace = _mode == PadRestoreMode.replace;
        final canRestore = !isReplace || _replaceConfirmed;

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
                onPressed: canRestore ? _executeRestore : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isReplace ? Colors.red : AppColors.accent,
                  foregroundColor: Colors.white,
                ),
                child: Text(isReplace ? 'Replace Diary' : 'Restore Memories'),
              ),
            ),
          ],
        );

      case _RestoreStep.success:
        return ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
          ),
          child: const Text('Done'),
        );

      case _RestoreStep.error:
        return OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        );
    }
  }
}
