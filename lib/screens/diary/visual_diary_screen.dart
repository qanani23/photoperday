import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/sync_coordinator.dart';
import 'package:photo_per_day/data/services/sync_worker.dart';
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

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreUpdated);
    SyncWorker.instance.addListener(_onStoreUpdated);
    SyncCoordinator.instance.addListener(_onStoreUpdated);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreUpdated);
    SyncWorker.instance.removeListener(_onStoreUpdated);
    SyncCoordinator.instance.removeListener(_onStoreUpdated);
    super.dispose();
  }

  void _onStoreUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Retrieves all persisted photos, filters out future dates and mock entries,
  /// and sorts them chronologically with newest first.
  List<PhotoEntry> _getChronologicalEntries() {
    final todayKey = DateKey.today();
    final entries = _store.allEntries.where((entry) {
      // Exclude future dates: entry must be on or before today
      return entry.dateKey.compareTo(todayKey) <= 0;
    }).toList();

    // Newest first
    entries.sort((a, b) => b.dateKey.compareTo(a.dateKey));
    return entries;
  }

  void _openDetail(PhotoEntry entry) {
    Navigator.of(context).pushNamed(
      AppConstants.photoDetailRoute,
      arguments: _store.getPhotoByKey(entry.dateKey) ?? entry,
    );
  }

  void _openSwipeDays(PhotoEntry entry) {
    Navigator.of(
      context,
    ).pushNamed(AppConstants.swipeDaysRoute, arguments: entry.dateKey);
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
        caption: 'Captured moment from today.',
        location: source == PhotoSource.camera
            ? 'Camera Capture'
            : 'Photo Library',
        timeFormatted: formattedTime,
        imagePath: capturedPath,
        icon: Icons.camera_alt_rounded,
        gradientColors: const [AppColors.accent, AppColors.surfaceDark],
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
    final entries = _getChronologicalEntries();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Screen Header
              _buildHeader(entries.length),

              // Content Area
              Expanded(
                child: entries.isEmpty
                    ? _buildEmptyState()
                    : _buildEntriesList(entries),
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
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: AppColors.textPrimary,
              size: 22.0,
            ),
            tooltip: 'Back',
            onPressed: () => Navigator.maybePop(context),
          ),
          const SizedBox(width: AppSpacing.xs),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Diary', style: AppTypography.appTitle),
                SizedBox(height: 2.0),
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
              icon: const Icon(
                Icons.view_carousel_rounded,
                color: AppColors.textPrimary,
                size: 22.0,
              ),
              tooltip: 'Browse Days',
              onPressed: () {
                final all = _getChronologicalEntries();
                Navigator.of(context).pushNamed(
                  AppConstants.swipeDaysRoute,
                  arguments: all.isNotEmpty ? all.first.dateKey : null,
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
              decoration: const BoxDecoration(
                color: AppColors.accentLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_stories_outlined,
                size: 34.0,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Your Photo Journal',
              style: AppTypography.sectionTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300.0),
              child: const Text(
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
        constraints: const BoxConstraints(maxWidth: 640.0),
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
              key: ValueKey('diary_entry_${entry.dateKey.format()}'),
              entry: entry,
              onTap: _openDetail,
              onBrowseTap: _openSwipeDays,
            );
          },
        ),
      ),
    );
  }
}
