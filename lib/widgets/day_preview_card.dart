import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_shadows.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';

import 'package:photo_per_day/data/models/sync_presentation_model.dart';

/// Interactive card displayed below the calendar showing details for the selected date.
class DayPreviewCard extends StatelessWidget {
  const DayPreviewCard({
    super.key,
    required this.selectedDate,
    this.photoEntry,
    this.isToday = false,
    this.isFuture = false,
    this.onActionTap,
    this.onPhotoTap,
  });

  final DateTime selectedDate;
  final PhotoEntry? photoEntry;
  final bool isToday;
  final bool isFuture;
  final VoidCallback? onActionTap;
  final ValueChanged<PhotoEntry>? onPhotoTap;

  @override
  Widget build(BuildContext context) {
    final dateFormatted = _formatDate(selectedDate);

    final cardSemanticLabel = photoEntry != null
        ? 'Selected day details, $dateFormatted, ${photoEntry!.title}. Tap to open photo detail.'
        : 'Selected day details, $dateFormatted. No photo recorded.';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageHorizontal,
        vertical: AppSpacing.md,
      ),
      child: Semantics(
        button: photoEntry != null,
        label: cardSemanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: photoEntry != null
              ? () => onPhotoTap?.call(photoEntry!)
              : null,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.card,
              border: Border.all(color: AppColors.border, width: 1.0),
              boxShadow: AppShadows.card,
            ),
            child: photoEntry != null
                ? _buildPhotoContent(dateFormatted)
                : _buildEmptyContent(dateFormatted),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoContent(String dateFormatted) {
    final entry = photoEntry!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header Row: Date & Time
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7.0,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentLight,
                      borderRadius: BorderRadius.circular(6.0),
                    ),
                    child: Text(
                      entry.category,
                      style: const TextStyle(
                        fontSize: 10.0,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      dateFormatted,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 12.0,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              entry.timeFormatted,
              style: AppTypography.caption.copyWith(fontSize: 11.0),
            ),
          ],
        ),

        const SizedBox(height: AppSpacing.sm),

        // Photo thumbnail + details row
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail container
            ClipRRect(
              borderRadius: AppRadii.cell,
              child: SizedBox(
                width: 60.0,
                height: 60.0,
                child: (entry.hasRealImage && entry.isImageFileAvailable)
                    ? Image.file(
                        File(entry.imagePath!),
                        cacheWidth: 200,
                        cacheHeight: 200,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildFallbackThumbnail(entry),
                      )
                    : _buildFallbackThumbnail(entry),
              ),
            ),

            const SizedBox(width: AppSpacing.md),

            // Title, Caption, Location
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (entry.title.trim().isNotEmpty)
                    Text(
                      entry.title.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  if (entry.caption != null &&
                      entry.caption!.trim().isNotEmpty) ...[
                    const SizedBox(height: 2.0),
                    Text(
                      entry.caption!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                  if (entry.location != null &&
                      entry.location!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4.0),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 11.0,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 2.0),
                        Flexible(
                          child: Text(
                            entry.location!.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption.copyWith(
                              fontSize: 10.5,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 5.0),
                  _buildSyncChip(entry),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20.0,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyContent(String dateFormatted) {
    return Row(
      children: [
        Container(
          width: 44.0,
          height: 44.0,
          decoration: const BoxDecoration(
            color: AppColors.surfaceSubtle,
            shape: BoxShape.circle,
          ),
          child: Icon(
            isFuture
                ? Icons.schedule_rounded
                : (isToday
                      ? Icons.add_a_photo_rounded
                      : Icons.camera_alt_outlined),
            size: 20.0,
            color: isToday ? AppColors.accent : AppColors.textMuted,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                dateFormatted,
                style: const TextStyle(
                  fontSize: 13.0,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2.0),
              Text(
                isFuture
                    ? 'Upcoming day in the future'
                    : (isToday
                          ? 'No photo captured yet for today'
                          : 'No photo recorded on this date'),
                style: AppTypography.caption.copyWith(
                  fontSize: 11.5,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        if (isToday)
          Semantics(
            button: true,
            label: 'Capture photo for today',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onActionTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 48.0,
                  minHeight: 48.0,
                ),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14.0,
                      vertical: 8.0,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    child: const Text(
                      'Capture',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _formatDate(DateTime date) {
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

  Widget _buildFallbackThumbnail(PhotoEntry entry) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: entry.gradientColors,
        ),
      ),
      child: Center(child: Icon(entry.icon, size: 24.0, color: Colors.white)),
    );
  }

  Widget _buildSyncChip(PhotoEntry entry) {
    final presentation = PhotoSyncPresentation.forEntry(entry);
    return Semantics(
      label: presentation.semanticLabel,
      child: Tooltip(
        message: presentation.detailLabel,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 2.0),
          decoration: BoxDecoration(
            color: presentation.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4.0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(presentation.icon, size: 10.0, color: presentation.color),
              const SizedBox(width: 3.0),
              Text(
                presentation.label,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  color: presentation.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
