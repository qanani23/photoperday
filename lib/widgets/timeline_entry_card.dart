import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_shadows.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';
import 'package:photo_per_day/data/models/day_entry.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';

/// Reusable timeline entry card displaying a day's memories in the Home timeline.
///
/// Groups all photos from the same day into one cohesive, photography-first entry
/// with date header, multi-photo count, thumbnail previews, note snippets, and
/// graceful fallback for missing image files or note-only entries.
class TimelineEntryCard extends StatelessWidget {
  const TimelineEntryCard({
    super.key,
    required this.dayEntry,
    this.onTap,
    this.onPhotoTap,
    this.onBrowseTap,
  });

  final DayEntry dayEntry;
  final VoidCallback? onTap;
  final ValueChanged<PhotoEntry>? onPhotoTap;
  final VoidCallback? onBrowseTap;

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
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    // DateTime.weekday: 1 = Monday, 7 = Sunday
    final weekdayName = weekdays[date.weekday % 7];
    final monthName = months[date.month - 1];
    return '$weekdayName, $monthName ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final date = dayEntry.dateKey.toDateTime();
    final formattedDate = formatDate(date);
    final hasPhotos = dayEntry.photos.isNotEmpty;
    final primaryPhoto = dayEntry.primaryPhoto;

    if (!hasPhotos && dayEntry.hasNote) {
      return _buildNoteOnlyCard(context, formattedDate);
    }

    if (primaryPhoto == null) {
      return const SizedBox.shrink();
    }

    final photoCount = dayEntry.photos.length;
    final hasMultiplePhotos = photoCount > 1;
    final hasTitle = primaryPhoto.title.trim().isNotEmpty;
    final hasLocation =
        primaryPhoto.location != null &&
        primaryPhoto.location!.trim().isNotEmpty;
    final hasNote = dayEntry.hasNote;

    return Semantics(
      container: true,
      button: true,
      label:
          'Memory for $formattedDate with $photoCount photo${photoCount == 1 ? "" : "s"}. Tap to open details.',
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
            onTap: onTap,
            hoverColor: AppColors.accent.withValues(alpha: 0.05),
            borderRadius: AppRadii.card,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header Row: Date & Photo Count Badge
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 13.0,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 6.0),
                      Expanded(
                        child: Text(
                          formattedDate,
                          style: TextStyle(
                            fontSize: 13.0,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasMultiplePhotos) ...[
                        const SizedBox(width: AppSpacing.xs),
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
                                '$photoCount photos',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (onBrowseTap != null) ...[
                        const SizedBox(width: 6.0),
                        Tooltip(
                          message: 'Browse Days',
                          child: InkWell(
                            onTap: onBrowseTap,
                            borderRadius: BorderRadius.circular(12.0),
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Icon(
                                Icons.view_carousel_rounded,
                                size: 17.0,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: AppSpacing.sm),

                  // Representative Photo (Dominant Display with Responsive Desktop Aspect Ratio)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 768;
                      final targetAspectRatio = isWide ? (16 / 9) : (4 / 3);
                      final cacheW = isWide ? 1200 : 600;
                      final cacheH = isWide ? 800 : 600;

                      Widget photoWidget =
                          (primaryPhoto.hasRealImage &&
                              primaryPhoto.isImageFileAvailable)
                          ? Image.file(
                              File(primaryPhoto.imagePath!),
                              cacheWidth: cacheW,
                              cacheHeight: cacheH,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  _buildFallbackPhoto(primaryPhoto),
                            )
                          : _buildFallbackPhoto(primaryPhoto);

                      Widget boundedPhoto = AspectRatio(
                        aspectRatio: targetAspectRatio,
                        child: photoWidget,
                      );

                      if (isWide) {
                        boundedPhoto = ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 380.0),
                          child: boundedPhoto,
                        );
                      }

                      return ClipRRect(
                        borderRadius: BorderRadius.circular(10.0),
                        child: boundedPhoto,
                      );
                    },
                  ),

                  // Multi-Photo Thumbnail Strip
                  if (hasMultiplePhotos) ...[
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      height: 44.0,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: dayEntry.photos.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: AppSpacing.xs),
                        itemBuilder: (context, index) {
                          final p = dayEntry.photos[index];
                          final isPrimary = index == 0;
                          return GestureDetector(
                            onTap: () {
                              if (onPhotoTap != null) {
                                onPhotoTap!(p);
                              } else {
                                onTap?.call();
                              }
                            },
                            child: Container(
                              width: 44.0,
                              height: 44.0,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(7.0),
                                border: Border.all(
                                  color: isPrimary
                                      ? AppColors.accent
                                      : AppColors.border,
                                  width: isPrimary ? 2.0 : 0.8,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(5.5),
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
                                      bottom: 1.5,
                                      right: 1.5,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 3.0,
                                          vertical: 0.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.65,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            3.0,
                                          ),
                                        ),
                                        child: Text(
                                          '${index + 1}',
                                          style: const TextStyle(
                                            fontSize: 7.5,
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

                  // Optional Photo Title & Location
                  if (hasTitle || hasLocation) ...[
                    const SizedBox(height: AppSpacing.sm),
                    if (hasTitle)
                      Text(
                        primaryPhoto.title.trim(),
                        style: TextStyle(
                          fontSize: 15.0,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (hasLocation) ...[
                      const SizedBox(height: 4.0),
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
                              primaryPhoto.location!.trim(),
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

                  // Shared Daily Note Preview Snippet
                  if (hasNote) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 8.0,
                      ),
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
                            size: 14.0,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 6.0),
                          Expanded(
                            child: Text(
                              dayEntry.note.trim(),
                              style: AppTypography.caption.copyWith(
                                fontSize: 12.0,
                                color: AppColors.textPrimary,
                                height: 1.35,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
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

  /// Note-only day presentation
  Widget _buildNoteOnlyCard(BuildContext context, String formattedDate) {
    return Semantics(
      container: true,
      button: true,
      label: 'Daily reflection for $formattedDate. Tap to open details.',
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
            onTap: onTap,
            hoverColor: AppColors.accent.withValues(alpha: 0.05),
            borderRadius: AppRadii.card,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 13.0,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 6.0),
                      Expanded(
                        child: Text(
                          formattedDate,
                          style: TextStyle(
                            fontSize: 13.0,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7.0,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accentLight,
                          borderRadius: BorderRadius.circular(10.0),
                        ),
                        child: Text(
                          'Daily Reflection',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(color: AppColors.border, width: 0.6),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.edit_note_rounded,
                          size: 20.0,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 8.0),
                        Expanded(
                          child: Text(
                            dayEntry.note.trim(),
                            style: AppTypography.body.copyWith(
                              fontSize: 13.0,
                              color: AppColors.textPrimary,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackPhoto(PhotoEntry entry) {
    if (entry.gradientColors.length >= 2) {
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
            size: 36.0,
            color: Colors.white.withValues(alpha: 0.75),
          ),
        ),
      );
    }

    return Container(
      color: AppColors.surfaceSubtle,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.broken_image_rounded,
              size: 32.0,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 4.0),
            Text(
              'Photo unavailable',
              style: TextStyle(fontSize: 11.0, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
