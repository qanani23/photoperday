import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/core/layout/app_breakpoints.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/screens/camera/camera_screen.dart';
import 'package:photo_per_day/services/gallery_photo_service.dart';
import 'package:photo_per_day/widgets/photo_source_sheet.dart';
import 'package:photo_per_day/widgets/visual_diary_entry.dart';

/// Dedicated Visual Diary screen presenting the user's daily photos as an
/// immersive, chronological personal photo journal.
///
/// Distinct from the calendar grid, the Visual Diary organizes memories linearly
/// (newest first), highlighting the photo and surfacing diary notes.
class VisualDiaryScreen extends StatefulWidget {
  const VisualDiaryScreen({super.key, this.store, this.onCaptureTap});

  /// Injected photo store instance (defaults to [PersistentDailyPhotoStore.instance]).
  final PersistentDailyPhotoStore? store;

  /// Optional capture callback for test environments or custom interception.
  final VoidCallback? onCaptureTap;

  @override
  State<VisualDiaryScreen> createState() => _VisualDiaryScreenState();
}

class _VisualDiaryScreenState extends State<VisualDiaryScreen> {
  final GalleryPhotoService _galleryPhotoService = GalleryPhotoService();

  PersistentDailyPhotoStore get _store =>
      widget.store ?? PersistentDailyPhotoStore.instance;

  List<PhotoEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _updateEntries();
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
      setState(() {
        _updateEntries();
      });
    }
  }

  /// Updates cached entries from the store's memoized chronological collection,
  /// filtering out future dates.
  void _updateEntries() {
    final todayKey = DateKey.today();
    _entries = _store.chronologicalEntries
        .where((entry) => entry.dateKey.compareTo(todayKey) <= 0)
        .toList(growable: false);
  }

  void _openDetail(PhotoEntry entry) {
    Navigator.of(
      context,
    ).pushNamed(AppConstants.photoDetailRoute, arguments: entry);
  }

  void _openSwipeDays(PhotoEntry entry) {
    Navigator.of(
      context,
    ).pushNamed(AppConstants.swipeDaysRoute, arguments: entry);
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
        await _store.addPhotoToDay(
          dateKey: DateKey.fromDateTime(now),
          photo: newEntry,
          sourceTempPath: capturedPath,
        );
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Screen Header
              _buildHeader(_entries.length),

              // Content Area
              Expanded(
                child: _entries.isEmpty
                    ? _buildEmptyState()
                    : _buildEntriesList(_entries),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(int entryCount) {
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
                Text('Diary', style: AppTypography.appTitle),
                const SizedBox(height: 2.0),
                Text(
                  'CHRONOLOGICAL PHOTO JOURNAL',
                  style: AppTypography.appTagline,
                ),
              ],
            ),
          ),
          if (entryCount > 0) ...[
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
                '$entryCount ${entryCount == 1 ? "entry" : "entries"}',
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 11.0,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            IconButton(
              icon: Icon(
                Icons.history_rounded,
                color: AppColors.accent,
                size: 22.0,
              ),
              tooltip: 'On This Day Memories',
              onPressed: () {
                Navigator.of(context).pushNamed(AppConstants.memoriesRoute);
              },
            ),
            IconButton(
              icon: Icon(
                Icons.view_carousel_rounded,
                color: AppColors.textPrimary,
                size: 22.0,
              ),
              tooltip: 'Browse Days',
              onPressed: () {
                Navigator.of(context).pushNamed(
                  AppConstants.swipeDaysRoute,
                  arguments: _entries.isNotEmpty
                      ? _entries.first.dateKey
                      : null,
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72.0,
              height: 72.0,
              decoration: BoxDecoration(
                color: AppColors.accentLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_stories_outlined,
                size: 34.0,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Your Photo Journal',
              style: AppTypography.sectionTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300.0),
              child: Text(
                'Every daily photo you capture will appear here in chronological order, telling the visual story of your life.',
                style: AppTypography.body,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Semantics(
              button: true,
              label: "Capture today's photo to begin your diary",
              child: ElevatedButton.icon(
                onPressed: _promptPhotoCapture,
                icon: const Icon(Icons.camera_alt_rounded, size: 18.0),
                label: const Text("Capture Today's Photo"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surfaceDark,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22.0,
                    vertical: 12.0,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntriesList(List<PhotoEntry> entries) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppBreakpoints.maxDiaryWidth,
        ),
        child: ListView.builder(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageHorizontal,
            AppSpacing.xs,
            AppSpacing.pageHorizontal,
            AppSpacing.xxl,
          ),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            return VisualDiaryEntryCard(
              key: ValueKey('diary_entry_${entry.effectiveId}'),
              entry: entry,
              dayEntry: _store.getDay(entry.dateKey),
              onTap: _openDetail,
              onBrowseTap: _openSwipeDays,
            );
          },
        ),
      ),
    );
  }
}
