import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_shadows.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_presentation_model.dart';
import 'package:photo_per_day/data/services/memory_service.dart';
import 'package:photo_per_day/data/services/mock_photo_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/sync_coordinator.dart';
import 'package:photo_per_day/data/services/sync_worker.dart';
import 'package:photo_per_day/screens/camera/camera_screen.dart';
import 'package:photo_per_day/services/gallery_photo_service.dart';
import 'package:photo_per_day/widgets/app_icon_button.dart';
import 'package:photo_per_day/widgets/photo_source_sheet.dart';

/// The Today Screen focused entirely on today's daily photograph and memory.
///
/// Supports both State A (Today has a photo) and State B (Today has no photo),
/// with a state toggle for testing, progress indicator, and mock actions.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, this.onNavigateToCalendar});

  final VoidCallback? onNavigateToCalendar;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  final GalleryPhotoService _galleryPhotoService = GalleryPhotoService();

  /// Whether today currently has a photo (toggled for demo/testing)
  bool _hasPhoto = true;

  /// Photo entry for today (Sunday, March 15, 2026)
  late PhotoEntry _todayPhoto;

  @override
  void initState() {
    super.initState();
    final today = DateTime(2026, 3, 15);
    final sessionPhoto = PersistentDailyPhotoStore.instance.getPhoto(today);
    if (sessionPhoto != null) {
      _todayPhoto = sessionPhoto;
      _hasPhoto = true;
    } else {
      _todayPhoto = MockPhotoService.defaultTodayPhoto;
      _hasPhoto = true;
    }
    PersistentDailyPhotoStore.instance.addListener(_onPhotoStoreUpdated);
    SyncWorker.instance.addListener(_onPhotoStoreUpdated);
    SyncCoordinator.instance.addListener(_onPhotoStoreUpdated);
  }

  void _onPhotoStoreUpdated() {
    if (!mounted) return;
    final today = DateTime(2026, 3, 15);
    final sessionPhoto = PersistentDailyPhotoStore.instance.getPhoto(today);
    setState(() {
      if (sessionPhoto != null) {
        _todayPhoto = sessionPhoto;
        _hasPhoto = true;
      } else {
        if (_todayPhoto.hasRealImage) {
          _hasPhoto = false;
        }
      }
    });
  }

  @override
  void dispose() {
    PersistentDailyPhotoStore.instance.removeListener(_onPhotoStoreUpdated);
    SyncWorker.instance.removeListener(_onPhotoStoreUpdated);
    SyncCoordinator.instance.removeListener(_onPhotoStoreUpdated);
    super.dispose();
  }

  void _toggleState() {
    setState(() {
      _hasPhoto = !_hasPhoto;
    });
  }

  Future<void> _promptPhotoSource() async {
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

      final newPhoto = _todayPhoto.copyWith(
        title: 'Daily Capture',
        timeFormatted: formattedTime,
      );

      try {
        final persistedPhoto = await PersistentDailyPhotoStore.instance
            .savePhoto(entry: newPhoto, sourceTempPath: capturedPath);

        if (mounted) {
          setState(() {
            _todayPhoto = persistedPhoto;
            _hasPhoto = true;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Today's photo added successfully!"),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        debugPrint('Failed to save today photo: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to save photo: $e'),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  void _showMockActionMessage(String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$action action triggered (Mock UI)'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(
        left: AppSpacing.pageHorizontal,
        right: AppSpacing.pageHorizontal,
        top: AppSpacing.sm,
        bottom: AppSpacing.dockClearance,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Section
          _buildHeader(),

          const SizedBox(height: AppSpacing.lg),

          // Main Content: State A (Photo) or State B (Empty)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _hasPhoto ? _buildPhotoState() : _buildEmptyState(),
          ),

          // On This Day Memories Banner (subtle, secondary, only when memories exist)
          _buildMemoriesBanner(),
        ],
      ),
    );
  }

  Widget _buildMemoriesBanner() {
    final today = DateTime(2026, 3, 15);
    final memories = MemoryService.instance.getMemoriesForDate(
      today,
      store: PersistentDailyPhotoStore.instance,
    );
    if (memories.isEmpty) {
      return const SizedBox.shrink();
    }

    final count = memories.length;
    final text = count == 1
        ? '1 memory from years past'
        : '$count memories from years past';

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.md),
          onTap: () {
            Navigator.of(
              context,
            ).pushNamed(AppConstants.memoriesRoute, arguments: today);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: AppColors.border, width: 0.8),
            ),
            child: Row(
              children: [
                Container(
                  width: 36.0,
                  height: 36.0,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.history_rounded,
                    color: AppColors.accent,
                    size: 20.0,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'On This Day',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 1.5),
                      Text(
                        text,
                        style: const TextStyle(
                          fontSize: 12.0,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14.0,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Screen Header with "Today", date subtitle, daily progress pill, and demo toggle
  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Today', style: AppTypography.appTitle),
            const SizedBox(height: 2.0),
            const Text(
              'Sunday, March 15, 2026',
              style: AppTypography.screenSubtitle,
            ),
            const SizedBox(height: 6.0),
            // Daily Progress Badge
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 3.0,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: AppColors.border, width: 0.8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 11.0,
                    color: AppColors.accent,
                  ),
                  SizedBox(width: 4.0),
                  Text(
                    'Day 74 of 2026',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // Header action controls
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Quick state toggle pill for testing State A and State B
            Semantics(
              label:
                  'Toggle mock photo state. Currently ${_hasPhoto ? "Photo" : "Empty"}',
              button: true,
              child: Tooltip(
                message: 'Toggle demo state',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleState,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9.0,
                      vertical: 5.0,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(16.0),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _hasPhoto
                              ? Icons.check_circle_outline_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 13.0,
                          color: _hasPhoto
                              ? AppColors.accent
                              : AppColors.textMuted,
                        ),
                        const SizedBox(width: 4.0),
                        Text(
                          _hasPhoto ? 'Photo' : 'Empty',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (widget.onNavigateToCalendar != null) ...[
              const SizedBox(width: 6.0),
              AppHeaderAction(
                icon: Icons.calendar_month_rounded,
                label: 'Calendar',
                size: 36.0,
                onTap: widget.onNavigateToCalendar,
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// STATE A: Today Has a Photo
  Widget _buildPhotoState() {
    return Column(
      key: const ValueKey('photo_state'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hero Photo Container
        GestureDetector(
          onTap: () {
            Navigator.pushNamed(
              context,
              AppConstants.photoDetailRoute,
              arguments:
                  PersistentDailyPhotoStore.instance.getPhoto(
                    DateTime(2026, 3, 15),
                  ) ??
                  _todayPhoto,
            );
          },
          child: Container(
            width: double.infinity,
            height: 340.0,
            decoration: const BoxDecoration(
              borderRadius: AppRadii.card,
              boxShadow: AppShadows.card,
            ),
            child: ClipRRect(
              borderRadius: AppRadii.card,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Photo Content (Real Image or Gradient Art fallback)
                  if (_todayPhoto.hasRealImage &&
                      _todayPhoto.isImageFileAvailable)
                    Image.file(
                      File(_todayPhoto.imagePath!),
                      cacheWidth: 1080,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _buildGradientArt(),
                    )
                  else
                    _buildGradientArt(),

                  // Vignette & Contrast Gradients
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x33000000),
                          Colors.transparent,
                          Color(0x66000000),
                        ],
                        stops: [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),

                  // Top Category Tag & Time Badge
                  Positioned(
                    top: 14.0,
                    left: 14.0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10.0,
                        vertical: 4.0,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.wb_sunny_rounded,
                            size: 12.0,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4.0),
                          Text(
                            _todayPhoto.category,
                            style: const TextStyle(
                              fontSize: 11.0,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Top-Right Backup Status Indicator
                  Positioned(
                    top: 14.0,
                    right: 14.0,
                    child: _buildSyncStatusBadge(_todayPhoto),
                  ),

                  // Bottom Overlay Day & Timestamp
                  Positioned(
                    bottom: 14.0,
                    left: 14.0,
                    right: 14.0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9.0,
                            vertical: 3.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          child: Text(
                            _todayPhoto.timeFormatted,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Semantics(
                          label: 'View photo in full screen',
                          button: true,
                          child: Tooltip(
                            message: 'Full screen',
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                Navigator.pushNamed(
                                  context,
                                  AppConstants.photoDetailRoute,
                                  arguments:
                                      PersistentDailyPhotoStore.instance
                                          .getPhoto(DateTime(2026, 3, 15)) ??
                                      _todayPhoto,
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(6.0),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.fullscreen_rounded,
                                  size: 16.0,
                                  color: Colors.white,
                                ),
                              ),
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

        const SizedBox(height: AppSpacing.md),

        // Metadata Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.card,
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_todayPhoto.title.trim().isNotEmpty)
                Text(
                  _todayPhoto.title.trim(),
                  style: const TextStyle(
                    fontSize: 17.0,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              if (_todayPhoto.caption != null &&
                  _todayPhoto.caption!.trim().isNotEmpty) ...[
                const SizedBox(height: 4.0),
                Text(
                  _todayPhoto.caption!.trim(),
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
              if (_todayPhoto.location != null &&
                  _todayPhoto.location!.trim().isNotEmpty) ...[
                const SizedBox(height: 8.0),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 13.0,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 3.0),
                    Text(
                      _todayPhoto.location!.trim(),
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // Action Buttons Row
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _promptPhotoSource,
                icon: const Icon(Icons.refresh_rounded, size: 16.0),
                label: const Text('Replace Photo'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.outlined(
              onPressed: () => _showMockActionMessage('Share'),
              tooltip: 'Share photo',
              icon: const Icon(Icons.share_outlined, size: 18.0),
              color: AppColors.textPrimary,
              style: IconButton.styleFrom(
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.all(12.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.0),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGradientArt() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _todayPhoto.gradientColors,
        ),
      ),
      child: Center(
        child: Icon(
          _todayPhoto.icon,
          size: 64.0,
          color: Colors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }

  /// STATE B: Today Has No Photo (Minimalist, Calm Empty State)
  Widget _buildEmptyState() {
    return Container(
      key: const ValueKey('empty_state'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xxxl,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Elegant circular camera badge with accent ring
          Container(
            width: 80.0,
            height: 80.0,
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.3),
                width: 2.0,
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.camera_alt_outlined,
                size: 36.0,
                color: AppColors.accent,
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          const Text(
            'Today hasn\'t been captured yet',
            style: TextStyle(
              fontSize: 17.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 6.0),

          const Text(
            'Preserve your daily memory before midnight.\nOne photo at a time.',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w400,
              color: AppColors.textMuted,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: AppSpacing.xl),

          // Primary Capture Button
          ElevatedButton.icon(
            onPressed: _promptPhotoSource,
            icon: const Icon(Icons.photo_camera_rounded, size: 18.0),
            label: const Text('Capture Today\'s Photo'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.textPrimary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 14.0,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24.0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncStatusBadge(PhotoEntry photo) {
    final presentation = PhotoSyncPresentation.forEntry(photo);
    return Semantics(
      label: presentation.semanticLabel,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (presentation.isBackingUp)
              const SizedBox(
                width: 10.0,
                height: 10.0,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Colors.white,
                ),
              )
            else
              Icon(
                presentation.icon,
                size: 11.5,
                color: presentation.color == AppColors.error
                    ? AppColors.error
                    : (presentation.color == AppColors.statDaysGreen
                          ? AppColors.statDaysGreen
                          : Colors.white),
              ),
            const SizedBox(width: 4.0),
            Text(
              presentation.label,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
