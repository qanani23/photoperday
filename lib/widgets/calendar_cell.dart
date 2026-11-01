import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';

import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/widgets/today_pulse_ring.dart';

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
    this.isToday = false,
    this.showTodayPulse = false,
    this.photoIcon,
    this.syncStatus,
    this.isSyncing = false,
    this.photoCount = 0,
    this.hasNote = false,
    this.onTap,
  });

  /// The calendar day number (1..31)
  final int day;

  /// The visual style of this cell
  final CalendarCellStyle style;

  /// Whether to render the subtle current-day pulse ring
  final bool showTodayPulse;

  /// Optional image to display when style is [CalendarCellStyle.photo]
  final ImageProvider? imageProvider;

  /// Optional fallback color tint if imageProvider is not supplied
  final Color? colorTint;

  /// Optional multi-color gradient simulating realistic photographic scenes
  final List<Color>? gradientColors;

  /// Total count of photos for this day (defaults to 0, or 1 when style is photo)
  final int photoCount;

  /// Whether this day has a daily note recorded
  final bool hasNote;

  /// Whether this date is currently selected by the user
  final bool isSelected;

  /// Whether this date belongs to the displayed month
  final bool isCurrentMonth;

  /// Whether this date represents the current calendar day ("today")
  final bool isToday;

  /// Optional scene icon
  final IconData? photoIcon;

  /// Synchronization status for days with photos
  final SyncStatus? syncStatus;

  /// Whether synchronization is currently in progress for this photo
  final bool isSyncing;

  /// Tap callback
  final VoidCallback? onTap;

  /// Whether this date effectively represents the current calendar day ("today")
  bool get effectiveIsToday => isToday || style == CalendarCellStyle.today;

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

    final todayPart = effectiveIsToday ? 'Today, ' : '';
    final countPart = photoCount > 1 ? ', $photoCount photos' : '';
    final notePart = hasNote ? ', Daily note recorded' : '';

    final semanticLabel = switch (style) {
      CalendarCellStyle.photo =>
        'Day $day, ${todayPart}Photo memory captured$countPart$notePart$syncDescription',
      CalendarCellStyle.today =>
        'Day $day, Today${hasNote ? ", Daily note" : ", No photo"}',
      CalendarCellStyle.empty =>
        'Day $day, $todayPart${hasNote ? "Daily note recorded" : "No photo"}',
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
            hoverColor: AppColors.accent.withValues(alpha: 0.12),
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
                    width: 320,
                    height: 320,
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
              Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('$day', style: AppTypography.cellNumberPhoto),
                ),
              ),

              // Subtle sync status indicator in top-right
              if (isSyncing)
                Positioned(
                  top: 4.5,
                  right: 4.5,
                  child: Container(
                    width: 5.5,
                    height: 5.5,
                    decoration: BoxDecoration(
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
                    decoration: BoxDecoration(
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

              // Subtle multi-photo indicator
              if (photoCount > 1)
                Positioned(
                  bottom: 3.5,
                  right: 3.5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3.0,
                      vertical: 1.0,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.photo_library_rounded,
                          size: 7.5,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 1.5),
                        Text(
                          '$photoCount',
                          style: const TextStyle(
                            fontSize: 7.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Subtle note indicator for days with photo and note
              if (hasNote)
                Positioned(
                  bottom: 4.0,
                  left: 4.0,
                  child: Container(
                    width: 4.5,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),

              // Subtle today pulse animation for photo cell
              if (showTodayPulse)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: Center(child: TodayPulseRing(radius: 40.0)),
                  ),
                ),
            ],
          ),
        );

      case CalendarCellStyle.today:
      case CalendarCellStyle.empty:
      default:
        if (effectiveIsToday) {
          return Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: AppRadii.cell,
            ),
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  if (showTodayPulse) const TodayPulseRing(),
                  Container(
                    width: 33.0,
                    height: 33.0,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.accent, width: 1.6),
                    ),
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('$day', style: AppTypography.cellNumberToday),
                    ),
                  ),
                  if (hasNote)
                    Positioned(
                      top: 3.5,
                      right: 3.5,
                      child: Container(
                        width: 4.5,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceSubtle,
            borderRadius: AppRadii.cell,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$day',
                    style: isCurrentMonth
                        ? AppTypography.cellNumberEmpty
                        : AppTypography.cellNumberEmpty.copyWith(
                            color: AppColors.textMutedSubtle,
                          ),
                  ),
                ),
              ),
              if (hasNote)
                Positioned(
                  top: 3.5,
                  right: 3.5,
                  child: Container(
                    width: 4.5,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        );
    }
  }
}
