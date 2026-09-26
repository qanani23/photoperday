import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';

import 'package:photo_per_day/data/models/sync_status.dart';

/// Distinct visual states of a calendar date cell.
enum CalendarCellStyle {
  /// Date with an attached photo
  photo,

  /// Date without a photo (soft neutral fill with number)
  empty,

  /// Today / current date featuring the distinctive caramel ring indicator
  today,

  /// Blank spacer for offset calendar alignment
  blank,
}

/// Reusable calendar cell component strictly reproducing the reference visual language.
class CalendarCell extends StatelessWidget {
  const CalendarCell({
    super.key,
    required this.day,
    this.style = CalendarCellStyle.empty,
    this.imageProvider,
    this.colorTint,
    this.gradientColors,
    this.isSelected = false,
    this.isCurrentMonth = true,
    this.photoIcon,
    this.syncStatus,
    this.isSyncing = false,
    this.onTap,
  });

  /// The calendar day number (1..31)
  final int day;

  /// The visual style of this cell
  final CalendarCellStyle style;

  /// Optional image to display when style is [CalendarCellStyle.photo]
  final ImageProvider? imageProvider;

  /// Optional fallback color tint if imageProvider is not supplied
  final Color? colorTint;

  /// Optional multi-color gradient simulating realistic photographic scenes
  final List<Color>? gradientColors;

  /// Whether this date is currently selected by the user
  final bool isSelected;

  /// Whether this date belongs to the displayed month
  final bool isCurrentMonth;

  /// Optional scene icon
  final IconData? photoIcon;

  /// Synchronization status for days with photos
  final SyncStatus? syncStatus;

  /// Whether synchronization is currently in progress for this photo
  final bool isSyncing;

  /// Tap callback
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (style == CalendarCellStyle.blank) {
      return const SizedBox.shrink();
    }

    final syncDescription = switch (syncStatus) {
      SyncStatus.synced => ', Backed up',
      SyncStatus.pending => ', Waiting to back up',
      SyncStatus.failed => ', Backup failed',
      SyncStatus.localOnly => ', On this device',
      null => '',
    };

    final semanticLabel = switch (style) {
      CalendarCellStyle.photo =>
        'Day $day, Photo memory captured$syncDescription',
      CalendarCellStyle.today => 'Day $day, Today',
      CalendarCellStyle.empty => 'Day $day',
      CalendarCellStyle.blank => '',
    };

    return Semantics(
      label: semanticLabel,
      button: true,
      selected: isSelected,
      child: AspectRatio(
        aspectRatio: 1.0,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadii.cell,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                borderRadius: AppRadii.cell,
                border: isSelected
                    ? Border.all(color: AppColors.accent, width: 2.2)
                    : null,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.25),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: _buildCellContent(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCellContent() {
    switch (style) {
      case CalendarCellStyle.photo:
        return ClipRRect(
          borderRadius: AppRadii.cell,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              // Photo Image or Gradient Scene
              if (imageProvider != null)
                Image(
                  image: ResizeImage(
                    imageProvider!,
                    width: 140,
                    height: 140,
                    allowUpscaling: false,
                  ),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    if (gradientColors != null && gradientColors!.length >= 2) {
                      return Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: gradientColors!,
                          ),
                        ),
                      );
                    }
                    return Container(
                      color: colorTint ?? AppColors.surfaceDarkFallback,
                    );
                  },
                )
              else if (gradientColors != null && gradientColors!.length >= 2)
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradientColors!,
                    ),
                  ),
                )
              else
                Container(color: colorTint ?? AppColors.surfaceDarkFallback),

              // Subtle dark gradient for high contrast
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, AppColors.photoOverlay],
                  ),
                ),
              ),

              // Day number
              Center(child: Text('$day', style: AppTypography.cellNumberPhoto)),

              // Subtle sync status indicator in top-right
              if (isSyncing)
                Positioned(
                  top: 4.5,
                  right: 4.5,
                  child: Container(
                    width: 5.5,
                    height: 5.5,
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                )
              else if (syncStatus == SyncStatus.failed)
                Positioned(
                  top: 4.5,
                  right: 4.5,
                  child: Container(
                    width: 5.5,
                    height: 5.5,
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                )
              else if (syncStatus == SyncStatus.pending)
                Positioned(
                  top: 4.5,
                  right: 4.5,
                  child: Container(
                    width: 5.5,
                    height: 5.5,
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                )
              else if (syncStatus == SyncStatus.synced)
                Positioned(
                  top: 4.5,
                  right: 4.5,
                  child: Container(
                    width: 4.5,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: AppColors.statDaysGreen.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        );

      case CalendarCellStyle.today:
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surfaceSubtle,
            borderRadius: AppRadii.cell,
          ),
          child: Center(
            child: Container(
              width: 33.0,
              height: 33.0,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.accent, width: 1.6),
              ),
              alignment: Alignment.center,
              child: Text('$day', style: AppTypography.cellNumberToday),
            ),
          ),
        );

      case CalendarCellStyle.empty:
      default:
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surfaceSubtle,
            borderRadius: AppRadii.cell,
          ),
          alignment: Alignment.center,
          child: Text(
            '$day',
            style: isCurrentMonth
                ? AppTypography.cellNumberEmpty
                : AppTypography.cellNumberEmpty.copyWith(
                    color: AppColors.textMutedSubtle,
                  ),
          ),
        );
    }
  }
}
