import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_shadows.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';
import 'package:photo_per_day/data/models/day_entry.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';

/// Interactive card displayed below the calendar showing details for the selected date.
///
/// Supports multi-photo daily entries with a horizontal thumbnail strip, clear photo
/// count badges, and daily note previews.
class DayPreviewCard extends StatelessWidget {
  const DayPreviewCard({
    super.key,
    required this.selectedDate,
    this.photoEntry,
    this.dayEntry,
    this.isToday = false,
    this.isFuture = false,
    this.onActionTap,
    this.onPhotoTap,
    this.onAddPhotoTap,
    this.onEditNoteTap,
  });

  final DateTime selectedDate;
  final PhotoEntry? photoEntry;
  final DayEntry? dayEntry;
  final bool isToday;
  final bool isFuture;
  final VoidCallback? onActionTap;
  final ValueChanged<PhotoEntry>? onPhotoTap;
  final VoidCallback? onAddPhotoTap;
  final VoidCallback? onEditNoteTap;

  @override
  Widget build(BuildContext context) {
    final dateFormatted = _formatDate(selectedDate);

    final effectiveDay = dayEntry;
    final primary = effectiveDay?.primaryPhoto ?? photoEntry;
    final photos =
        effectiveDay?.photos ??
        (photoEntry != null ? [photoEntry!] : const <PhotoEntry>[]);
    final note = effectiveDay?.note.trim() ?? '';
    final hasPhotos = photos.isNotEmpty;
    final isNoteOnly = !hasPhotos && note.isNotEmpty;

    final String cardSemanticLabel;
    if (hasPhotos) {
      final countText = photos.length > 1 ? ', ${photos.length} photos' : '';
      cardSemanticLabel =
          'Selected day details, $dateFormatted$countText, ${primary!.title}. Tap to open photo detail.';
    } else if (isNoteOnly) {
      cardSemanticLabel =
          'Selected day details, $dateFormatted, Daily note: $note';
    } else {
      cardSemanticLabel =
          'Selected day details, $dateFormatted. No photo recorded.';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageHorizontal,
        vertical: AppSpacing.md,
      ),
      child: Semantics(
        button: hasPhotos,
        label: cardSemanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: hasPhotos && primary != null
              ? () => onPhotoTap?.call(primary)
              : null,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.card,
              border: Border.all(color: AppColors.border, width: 1.0),
              boxShadow: AppShadows.card,
            ),
            child: hasPhotos
                ? _buildPhotoContent(dateFormatted, primary!, photos, note)
                : (isNoteOnly
                      ? _buildNoteOnlyContent(dateFormatted, note)
                      : _buildEmptyContent(dateFormatted)),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoContent(
    String dateFormatted,
    PhotoEntry entry,
    List<PhotoEntry> photos,
    String note,
  ) {
    final hasMultiple = photos.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header Row: Category, Date, Photo Count or Time
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
                      style: TextStyle(
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
                      style: TextStyle(
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasMultiple)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7.0,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentLight,
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.photo_library_rounded,
                          size: 11.0,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 3.5),
                        Text(
                          '${photos.length} photos',
                          style: TextStyle(
                            fontSize: 11.0,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Text(
                    entry.timeFormatted,
                    style: AppTypography.caption.copyWith(fontSize: 11.0),
                  ),
                if (onAddPhotoTap != null) ...[
                  const SizedBox(width: 6.0),
                  Semantics(
                    button: true,
                    label: 'Add photo to this date',
                    child: Tooltip(
                      message: 'Add Photo',
                      child: InkWell(
                        onTap: onAddPhotoTap,
                        borderRadius: BorderRadius.circular(12.0),
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Icon(
                            Icons.add_a_photo_outlined,
                            size: 16.0,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),

        const SizedBox(height: AppSpacing.sm),

        // Photo thumbnail + details row
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dominant / Primary thumbnail
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

            // Title, Location
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
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  if (entry.location != null &&
                      entry.location!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4.0),
                    Row(
                      children: [
                        Icon(
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
            Icon(
              Icons.chevron_right_rounded,
              size: 20.0,
              color: AppColors.textMuted,
            ),
          ],
        ),

        // Horizontal thumbnail carousel for multiple photos
        if (hasMultiple) ...[
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 48.0,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
              itemBuilder: (context, index) {
                final photo = photos[index];
                final isPrimary = index == 0;
                return Semantics(
                  button: true,
                  label:
                      'Photo ${index + 1} of ${photos.length}${photo.title.isNotEmpty ? ", ${photo.title}" : ""}',
                  child: GestureDetector(
                    onTap: () => onPhotoTap?.call(photo),
                    child: Container(
                      width: 48.0,
                      height: 48.0,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8.0),
                        border: Border.all(
                          color: isPrimary
                              ? AppColors.accent
                              : AppColors.border,
                          width: isPrimary ? 1.6 : 0.8,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7.0),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            (photo.hasRealImage && photo.isImageFileAvailable)
                                ? Image.file(
                                    File(photo.imagePath!),
                                    cacheWidth: 120,
                                    cacheHeight: 120,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            _buildFallbackThumbnail(photo),
                                  )
                                : _buildFallbackThumbnail(photo),
                            Positioned(
                              bottom: 2.0,
                              right: 2.0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3.5,
                                  vertical: 0.5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(3.0),
                                ),
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    fontSize: 8.0,
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
                  ),
                );
              },
            ),
          ),
        ],

        // Daily Note Snippet if present
        if (note.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 10.0,
              vertical: 7.0,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: AppColors.border, width: 0.6),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notes_rounded, size: 14.0, color: AppColors.accent),
                const SizedBox(width: 6.0),
                Expanded(
                  child: Text(
                    note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
      ],
    );
  }

  Widget _buildNoteOnlyContent(String dateFormatted, String note) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44.0,
          height: 44.0,
          decoration: BoxDecoration(
            color: AppColors.accentLight,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.notes_rounded, size: 20.0, color: AppColors.accent),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    dateFormatted,
                    style: TextStyle(
                      fontSize: 13.0,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
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
                      'Daily Note',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4.0),
              Text(
                note,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body.copyWith(
                  fontSize: 12.0,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (onActionTap != null) ...[
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            icon: const Icon(Icons.add_a_photo_outlined, size: 20.0),
            tooltip: 'Add Photo',
            onPressed: onActionTap,
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyContent(String dateFormatted) {
    return Row(
      children: [
        Container(
          width: 44.0,
          height: 44.0,
          decoration: BoxDecoration(
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
                style: TextStyle(
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
            label: 'Capture a photo for today',
            child: ElevatedButton.icon(
              onPressed: onActionTap,
              icon: const Icon(Icons.camera_alt_rounded, size: 14.0),
              label: const Text('Capture'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14.0,
                  vertical: 8.0,
                ),
                textStyle: const TextStyle(
                  fontSize: 12.0,
                  fontWeight: FontWeight.w700,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _formatDate(DateTime date) {
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 2.0),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(4.0),
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 10.0, color: AppColors.statDaysGreen),
          const SizedBox(width: 3.0),
          Text(
            'Local',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: AppColors.statDaysGreen,
            ),
          ),
        ],
      ),
    );
  }
}
