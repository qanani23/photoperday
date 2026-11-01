import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_shadows.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';
import 'package:photo_per_day/data/models/day_entry.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';

/// Reusable Visual Diary entry card for chronological photo journaling.
///
/// Features the photo as the dominant visual centerpiece, an understated date &
/// time header, subtle cloud backup status indicator, and graceful typography
/// for optional title, location, daily note, and multi-photo thumbnail strip.
class VisualDiaryEntryCard extends StatelessWidget {
  const VisualDiaryEntryCard({
    super.key,
    required this.entry,
    this.dayEntry,
    this.onTap,
    this.onBrowseTap,
  });

  final PhotoEntry entry;
  final DayEntry? dayEntry;
  final ValueChanged<PhotoEntry>? onTap;
  final ValueChanged<PhotoEntry>? onBrowseTap;

  static String formatDate(DateTime date) {
    const months = [
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
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final weekdayName = weekdays[date.weekday - 1];
    final monthName = months[date.month - 1];
    return '$weekdayName, $monthName ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final hasTitle = entry.title.trim().isNotEmpty;
    final hasLocation =
        entry.location != null && entry.location!.trim().isNotEmpty;
    final hasTime = entry.timeFormatted.trim().isNotEmpty;
    final formattedDate = formatDate(entry.date);

    return Semantics(
      container: true,
      button: true,
      label:
          'Diary entry for $formattedDate${hasTitle ? ", ${entry.title.trim()}" : ""}. Double tap to view details.',
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.card,
          border: Border.all(color: AppColors.border, width: 1.0),
          boxShadow: AppShadows.card,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: AppRadii.card,
          child: InkWell(
            onTap: () => onTap?.call(entry),
            borderRadius: AppRadii.card,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header Row: Date, Time & Sync Status
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 13.0,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 5.0),
                      Expanded(
                        child: Text(
                          formattedDate,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasTime) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          entry.timeFormatted.trim(),
                          style: AppTypography.caption.copyWith(
                            fontSize: 11.0,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                      if (dayEntry != null && dayEntry!.photos.length > 1) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6.0,
                            vertical: 2.0,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accentLight,
                            borderRadius: BorderRadius.circular(6.0),
                          ),
                          child: Text(
                            'Photo ${entry.order + 1} of ${dayEntry!.photos.length}',
                            style: TextStyle(
                              fontSize: 10.0,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: AppSpacing.xs),
                      _buildSyncChip(entry),
                      if (onBrowseTap != null) ...[
                        const SizedBox(width: 4.0),
                        Semantics(
                          label: 'Browse days starting from this photo',
                          button: true,
                          child: Tooltip(
                            message: 'Browse Days',
                            child: InkWell(
                              onTap: () => onBrowseTap?.call(entry),
                              borderRadius: BorderRadius.circular(12.0),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minWidth: 44.0,
                                  minHeight: 44.0,
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.view_carousel_rounded,
                                    size: 16.0,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: AppSpacing.sm),

                  // Dominant Photo
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10.0),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Semantics(
                        label: 'Photo captured on $formattedDate',
                        image: true,
                        child:
                            (entry.hasRealImage && entry.isImageFileAvailable)
                            ? Image.file(
                                File(entry.imagePath!),
                                cacheWidth: 800,
                                cacheHeight: 800,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    _buildFallbackPhoto(entry),
                              )
                            : _buildFallbackPhoto(entry),
                      ),
                    ),
                  ),

                  // Optional Diary Metadata (gracefully omitted if absent)
                  if (hasTitle || hasLocation) ...[
                    const SizedBox(height: AppSpacing.sm),
                    if (hasTitle)
                      Text(
                        entry.title.trim(),
                        style: TextStyle(
                          fontSize: 16.0,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (hasLocation) ...[
                      const SizedBox(height: 6.0),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 13.0,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 4.0),
                          Expanded(
                            child: Text(
                              entry.location!.trim(),
                              style: AppTypography.caption.copyWith(
                                fontSize: 11.5,
                                color: AppColors.textMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],

                  // Shared Daily Note if present
                  if (dayEntry != null && dayEntry!.note.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(8.0),
                        border: Border.all(color: AppColors.border, width: 0.6),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.notes_rounded,
                            size: 13.0,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 6.0),
                          Expanded(
                            child: Text(
                              dayEntry!.note,
                              style: AppTypography.caption.copyWith(
                                fontSize: 11.5,
                                color: AppColors.textPrimary,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Multi-photo thumbnail strip
                  if (dayEntry != null && dayEntry!.photos.length > 1) ...[
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      height: 40.0,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: dayEntry!.photos.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: AppSpacing.xs),
                        itemBuilder: (context, pIdx) {
                          final p = dayEntry!.photos[pIdx];
                          final isCurrent = p.effectiveId == entry.effectiveId;
                          return GestureDetector(
                            onTap: () => onTap?.call(p),
                            child: Container(
                              width: 40.0,
                              height: 40.0,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6.0),
                                border: Border.all(
                                  color: isCurrent
                                      ? AppColors.accent
                                      : AppColors.border,
                                  width: isCurrent ? 2.0 : 0.8,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(5.0),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    (p.hasRealImage && p.isImageFileAvailable)
                                        ? Image.file(
                                            File(p.imagePath!),
                                            cacheWidth: 100,
                                            cacheHeight: 100,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    _buildFallbackPhoto(p),
                                          )
                                        : _buildFallbackPhoto(p),
                                    Positioned(
                                      bottom: 1.0,
                                      right: 1.0,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 2.5,
                                          vertical: 0.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.65,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            2.0,
                                          ),
                                        ),
                                        child: Text(
                                          '${pIdx + 1}',
                                          style: const TextStyle(
                                            fontSize: 7.0,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackPhoto(PhotoEntry entry) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: entry.gradientColors,
        ),
      ),
      child: Center(
        child: Icon(
          entry.icon,
          size: 48.0,
          color: Colors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }

  Widget _buildSyncChip(PhotoEntry entry) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.5),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(6.0),
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 10.5, color: AppColors.statDaysGreen),
          const SizedBox(width: 3.5),
          Text(
            'Local',
            style: TextStyle(
              fontSize: 10.0,
              fontWeight: FontWeight.w600,
              color: AppColors.statDaysGreen,
            ),
          ),
        ],
      ),
    );
  }
}
