import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_shadows.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/memory_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/screens/camera/camera_screen.dart';
import 'package:photo_per_day/screens/diary/swipe_days_screen.dart';
import 'package:photo_per_day/screens/photo_detail/photo_detail_screen.dart';
import 'package:photo_per_day/services/gallery_photo_service.dart';
import 'package:photo_per_day/widgets/photo_source_sheet.dart';

/// Dedicated "On This Day" / "Memories" screen.
///
/// Surfaces real photos from previous years that were captured on the same month
/// and day as the target date (defaulting to today).
///
/// Principles:
/// - Real persisted data only: Uses [PersistentDailyPhotoStore].
/// - Strictly excludes current-year and future entries.
/// - Leap-year safe: February 29 entries only surface on February 29 from past leap years.
/// - Deterministic descending order: Newest memory year first.
/// - Live reactivity: Responds to edits, deletions, and replacements.
/// - Seamless connection with [PhotoDetailScreen] and [SwipeDaysScreen].
class MemoriesScreen extends StatefulWidget {
  const MemoriesScreen({
    super.key,
    this.targetDate,
    this.store,
    this.onCaptureTap,
  });

  /// Target date to find memories for (defaults to today).
  final DateTime? targetDate;

  /// Injected photo store (defaults to [PersistentDailyPhotoStore.instance]).
  final PersistentDailyPhotoStore? store;

  /// Optional capture tap handler for testing.
  final VoidCallback? onCaptureTap;

  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen> {
  final GalleryPhotoService _galleryPhotoService = GalleryPhotoService();

  PersistentDailyPhotoStore get _store =>
      widget.store ?? PersistentDailyPhotoStore.instance;

  DateTime get _effectiveTargetDate => widget.targetDate ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreUpdated);
    AppThemeService.instance.addListener(_onStoreUpdated);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreUpdated);
    AppThemeService.instance.removeListener(_onStoreUpdated);
    super.dispose();
  }

  void _onStoreUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  List<PhotoEntry> _getMemories() {
    return MemoryService.instance.getMemoriesForDate(
      _effectiveTargetDate,
      store: _store,
    );
  }

  void _openDetail(PhotoEntry entry) {
    Navigator.of(context).pushNamed(
      AppConstants.photoDetailRoute,
      arguments: _store.getPhotoByKey(entry.dateKey) ?? entry,
    );
  }

  void _openSwipeMemories({DateKey? startingDateKey}) {
    final memories = _getMemories();
    if (memories.isEmpty) return;

    final filterKeys = memories.map((e) => e.dateKey).toList();

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SwipeDaysScreen(
          initialDateKey: startingDateKey ?? memories.first.dateKey,
          filterDateKeys: filterKeys,
          customTitle: 'On This Day',
          customSubtitle: 'memories',
          store: _store,
        ),
      ),
    );
  }

  Future<void> _promptPhotoCapture() async {
    if (widget.onCaptureTap != null) {
      widget.onCaptureTap!();
      return;
    }

    final source = await PhotoSourceSheet.show(context);
    if (source == null || !mounted) return;

    String? capturedPath;
    if (source == PhotoSource.camera) {
      capturedPath = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (context) => const CameraScreen()),
      );
    } else if (source == PhotoSource.gallery) {
      capturedPath = await _galleryPhotoService.pickPhoto();
    }

    if (capturedPath != null && mounted) {
      final now = DateTime.now();
      final period = now.hour >= 12 ? 'PM' : 'AM';
      final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
      final minuteFormatted = now.minute.toString().padLeft(2, '0');
      final formattedTime = '$hour12:$minuteFormatted $period';

      final newEntry = PhotoEntry(
        date: now,
        title: 'Daily Capture',
        location: source == PhotoSource.camera
            ? 'Camera Capture'
            : 'Photo Library',
        timeFormatted: formattedTime,
        imagePath: capturedPath,
        icon: Icons.camera_alt_rounded,
        gradientColors: [AppColors.accent, AppColors.surfaceDark],
      );

      try {
        await _store.savePhoto(entry: newEntry, sourceTempPath: capturedPath);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to save photo: $e'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final memories = _getMemories();
    final isDark = AppColors.current.isDark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(memories.length),
              Expanded(
                child: memories.isEmpty
                    ? _buildEmptyState()
                    : _buildMemoriesList(memories),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(int memoryCount) {
    final date = _effectiveTargetDate;
    final months = [
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
    final formattedMonthDay = '${months[date.month - 1]} ${date.day}';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageHorizontal,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.arrow_back_rounded,
              color: AppColors.textPrimary,
              size: 22.0,
            ),
            tooltip: 'Back',
            onPressed: () => Navigator.maybePop(context),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('On This Day', style: AppTypography.appTitle),
                const SizedBox(height: 2.0),
                Text(
                  formattedMonthDay.toUpperCase(),
                  style: AppTypography.appTagline,
                ),
              ],
            ),
          ),
          if (memoryCount > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10.0,
                vertical: 4.5,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(color: AppColors.border, width: 0.8),
              ),
              child: Text(
                '$memoryCount ${memoryCount == 1 ? "memory" : "memories"}',
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            IconButton(
              icon: Icon(
                Icons.view_carousel_rounded,
                color: AppColors.accent,
                size: 22.0,
              ),
              tooltip: 'Browse Memories as Carousel',
              onPressed: () => _openSwipeMemories(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMemoriesList(List<PhotoEntry> memories) {
    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageHorizontal,
        vertical: AppSpacing.md,
      ),
      itemCount: memories.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.lg),
      itemBuilder: (context, index) {
        final entry = memories[index];
        return _buildMemoryCard(entry);
      },
    );
  }

  Widget _buildMemoryCard(PhotoEntry entry) {
    final yearsAgo = MemoryService.instance.getYearsAgo(
      entry.date,
      _effectiveTargetDate,
    );
    final relativeYearLabel = yearsAgo == 1
        ? '1 year ago'
        : '$yearsAgo years ago';

    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final formattedFullDate =
        '${months[entry.date.month - 1]} ${entry.date.day}, ${entry.date.year}';

    final hasMetadata =
        entry.title.isNotEmpty ||
        (entry.location != null && entry.location!.trim().isNotEmpty);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Header: Year Badge + Full Date + Sync Chip
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                // Year Badge Pill
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 3.5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 13.0,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 4.0),
                      Text(
                        relativeYearLabel,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // Full Date
                Expanded(
                  child: Text(
                    formattedFullDate,
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Sync Chip
                _buildSyncChip(entry),
              ],
            ),
          ),

          // Hero Photo Viewport (Tapping opens PhotoDetailScreen)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openDetail(entry),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Semantics(
                label:
                    'Memory photo from $relativeYearLabel on $formattedFullDate',
                child: (entry.hasRealImage && entry.isImageFileAvailable)
                    ? Image.file(
                        File(entry.imagePath!),
                        cacheWidth: 1080,
                        cacheHeight: 1080,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildFallbackPhoto(entry),
                      )
                    : _buildFallbackPhoto(entry),
              ),
            ),
          ),

          // Metadata Section (collapses cleanly if empty)
          if (hasMetadata)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (entry.title.isNotEmpty) ...[
                    Text(
                      entry.title,
                      style: TextStyle(
                        fontSize: 16.0,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  if (entry.location != null &&
                      entry.location!.trim().isNotEmpty) ...[
                    const SizedBox(height: 2.0),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 13.0,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 3.0),
                        Flexible(
                          child: Text(
                            entry.location!,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

          // Bottom Action Bar for this Memory
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              border: Border(
                top: BorderSide(color: AppColors.border, width: 0.8),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () => _openDetail(entry),
                  icon: const Icon(Icons.info_outline_rounded, size: 15.0),
                  label: const Text('View Details'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    textStyle: const TextStyle(
                      fontSize: 12.0,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () =>
                      _openSwipeMemories(startingDateKey: entry.dateKey),
                  icon: const Icon(Icons.view_carousel_rounded, size: 15.0),
                  label: const Text('Browse in Carousel'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    textStyle: const TextStyle(
                      fontSize: 12.0,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackPhoto(PhotoEntry entry) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: entry.gradientColors.isNotEmpty
              ? entry.gradientColors
              : [AppColors.surfaceDark, AppColors.surfaceSubtle],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          entry.icon,
          size: 56.0,
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

  Widget _buildEmptyState() {
    final date = _effectiveTargetDate;
    final months = [
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
    final formattedMonthDay = '${months[date.month - 1]} ${date.day}';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72.0,
              height: 72.0,
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(
                Icons.history_toggle_off_rounded,
                size: 36.0,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No memories from this day yet',
              style: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Memories from $formattedMonthDay will appear here when you have captured photos on this date in previous years.',
              style: TextStyle(
                fontSize: 14.0,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            ElevatedButton.icon(
              onPressed: _promptPhotoCapture,
              icon: const Icon(Icons.camera_alt_rounded, size: 18.0),
              label: const Text("Capture Today's Photo"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.accentForeground,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
