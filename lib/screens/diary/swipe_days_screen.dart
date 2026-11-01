import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/core/layout/app_breakpoints.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_shadows.dart';
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

/// Route arguments for configuring [SwipeDaysScreen].
class SwipeDaysArguments {
  const SwipeDaysArguments({
    this.initialDateKey,
    this.initialPhotoId,
    this.filterDateKeys,
    this.customTitle,
    this.customSubtitle,
  });

  final DateKey? initialDateKey;
  final String? initialPhotoId;
  final List<DateKey>? filterDateKeys;
  final String? customTitle;
  final String? customSubtitle;
}

/// Immersive "Swipe Through Days" screen that lets the user browse their recorded
/// daily photos chronologically via horizontal swipes.
///
/// Principles:
/// - Browsing experience over EXISTING recorded photos only (no blank dates).
/// - Chronological ordering: Oldest at index 0, Newest at index N-1.
/// - Swiping left moves forward to newer days; swiping right moves back to older days.
/// - Finite boundaries: No wrapping, disabled navigation affordances at edges.
/// - Live reactivity: Responds to edits, replacements, deletions, and sync changes.
/// - Seamless connection with [PhotoDetailScreen].
class SwipeDaysScreen extends StatefulWidget {
  const SwipeDaysScreen({
    super.key,
    this.initialDateKey,
    this.initialPhotoId,
    this.store,
    this.onCaptureTap,
    this.filterDateKeys,
    this.customTitle,
    this.customSubtitle,
  });

  /// Optional specific date to open the viewer onto.
  final DateKey? initialDateKey;

  /// Optional specific photo ID to open the viewer onto.
  final String? initialPhotoId;

  /// Injected store instance (defaults to [PersistentDailyPhotoStore.instance]).
  final PersistentDailyPhotoStore? store;

  /// Optional photo capture hook for testing.
  final VoidCallback? onCaptureTap;

  /// Optional subset of [DateKey]s to restrict browsing to (e.g. for "On This Day" memories).
  final List<DateKey>? filterDateKeys;

  /// Optional custom title for the viewer (defaults to "Daily Journal").
  final String? customTitle;

  /// Optional custom subtitle descriptor (defaults to "recorded days").
  final String? customSubtitle;

  @override
  State<SwipeDaysScreen> createState() => _SwipeDaysScreenState();
}

class _SwipeDaysScreenState extends State<SwipeDaysScreen> {
  final GalleryPhotoService _galleryPhotoService = GalleryPhotoService();

  PersistentDailyPhotoStore get _store =>
      widget.store ?? PersistentDailyPhotoStore.instance;

  late PageController _pageController;
  int _currentIndex = 0;
  DateKey? _currentDateKey;
  List<PhotoEntry> _entries = const [];
  Set<DateKey>? _filterDateKeySet;

  @override
  void initState() {
    super.initState();
    if (widget.filterDateKeys != null) {
      _filterDateKeySet = widget.filterDateKeys!.toSet();
    }
    _updateEntries();

    if (widget.initialPhotoId != null) {
      final foundIndex = _entries.indexWhere(
        (e) =>
            e.effectiveId == widget.initialPhotoId ||
            e.id == widget.initialPhotoId,
      );
      if (foundIndex >= 0) {
        _currentIndex = foundIndex;
      } else if (widget.initialDateKey != null) {
        final dateIndex = _entries.indexWhere(
          (e) => e.dateKey == widget.initialDateKey,
        );
        _currentIndex = dateIndex >= 0
            ? dateIndex
            : (_entries.isNotEmpty ? _entries.length - 1 : 0);
      } else {
        _currentIndex = _entries.isNotEmpty ? _entries.length - 1 : 0;
      }
    } else if (widget.initialDateKey != null) {
      final foundIndex = _entries.indexWhere(
        (e) => e.dateKey == widget.initialDateKey,
      );
      if (foundIndex >= 0) {
        _currentIndex = foundIndex;
      } else {
        // Default to newest recorded day if specific key not present
        _currentIndex = _entries.isNotEmpty ? _entries.length - 1 : 0;
      }
    } else {
      // Default to newest recorded day
      _currentIndex = _entries.isNotEmpty ? _entries.length - 1 : 0;
    }

    if (_entries.isNotEmpty && _currentIndex < _entries.length) {
      _currentDateKey = _entries[_currentIndex].dateKey;
    }

    _pageController = PageController(initialPage: _currentIndex);

    _store.addListener(_onStoreUpdated);
    AppThemeService.instance.addListener(_onStoreUpdated);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreUpdated);
    AppThemeService.instance.removeListener(_onStoreUpdated);
    _pageController.dispose();
    super.dispose();
  }

  void _updateEntries() {
    final todayKey = DateKey.today();
    final ascending = _store.chronologicalAscendingEntries;
    if (_filterDateKeySet != null) {
      _entries = ascending
          .where(
            (e) =>
                e.dateKey.compareTo(todayKey) <= 0 &&
                _filterDateKeySet!.contains(e.dateKey),
          )
          .toList(growable: false);
    } else {
      _entries = ascending
          .where((e) => e.dateKey.compareTo(todayKey) <= 0)
          .toList(growable: false);
    }
  }

  void _onStoreUpdated() {
    if (!mounted) return;
    _updateEntries();
    if (_entries.isEmpty) {
      setState(() {
        _currentIndex = 0;
        _currentDateKey = null;
      });
      return;
    }

    int newIndex = -1;
    if (_currentDateKey != null) {
      newIndex = _entries.indexWhere((e) => e.dateKey == _currentDateKey);
    }

    if (newIndex >= 0) {
      _currentIndex = newIndex;
      if (_pageController.hasClients &&
          _pageController.page?.round() != newIndex) {
        _pageController.jumpToPage(newIndex);
      }
    } else {
      // The current photo was deleted! Move to closest remaining entry
      final clamped = _currentIndex.clamp(0, _entries.length - 1);
      _currentIndex = clamped;
      _currentDateKey = _entries[clamped].dateKey;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(clamped);
      }
    }

    setState(() {});
  }

  void _onPageChanged(int index, List<PhotoEntry> entries) {
    if (index >= 0 && index < entries.length) {
      setState(() {
        _currentIndex = index;
        _currentDateKey = entries[index].dateKey;
      });
    }
  }

  void _goToPrevious() {
    if (_currentIndex > 0 && _pageController.hasClients) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToNext(int total) {
    if (_currentIndex < total - 1 && _pageController.hasClients) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  void _openDetail(PhotoEntry entry) {
    Navigator.of(
      context,
    ).pushNamed(AppConstants.photoDetailRoute, arguments: entry);
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

    if (capturedPath != null && capturedPath.isNotEmpty && mounted) {
      final now = DateTime.now();
      final newEntry = PhotoEntry(
        date: now,
        title: '',
        location: null,
        timeFormatted: TimeOfDay.fromDateTime(now).format(context),
        imagePath: capturedPath,
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
          child: _entries.isEmpty
              ? _buildEmptyState()
              : _buildSwipeViewer(_entries),
        ),
      ),
    );
  }

  Widget _buildSwipeViewer(List<PhotoEntry> entries) {
    // Ensure index bounds are safe
    final safeIndex = _currentIndex.clamp(0, entries.length - 1);
    final currentEntry = entries[safeIndex];

    return Column(
      children: [
        // Top Navigation Header
        _buildHeader(currentEntry, safeIndex, entries.length),

        // Main Swipeable Viewport
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            physics: const BouncingScrollPhysics(),
            itemCount: entries.length,
            onPageChanged: (index) => _onPageChanged(index, entries),
            itemBuilder: (context, index) {
              return _buildPageItem(entries[index]);
            },
          ),
        ),

        // Bottom Navigation Bar with Accessible Controls
        _buildBottomBar(safeIndex, entries.length, currentEntry),
      ],
    );
  }

  Widget _buildHeader(PhotoEntry currentEntry, int index, int total) {
    final day = _store.getDay(currentEntry.dateKey);
    final isMultiPhotoDay = day != null && day.photos.length > 1;
    final dayPhotoIndex = day != null
        ? day.photos.indexWhere(
            (p) => p.effectiveId == currentEntry.effectiveId,
          )
        : -1;
    final currentDayPosition = isMultiPhotoDay && dayPhotoIndex >= 0
        ? dayPhotoIndex + 1
        : 1;
    final dayTotal = isMultiPhotoDay ? day.photos.length : 1;

    final pillText = isMultiPhotoDay
        ? '$currentDayPosition of $dayTotal'
        : '${index + 1} of $total';

    final subtitleText = isMultiPhotoDay
        ? 'Photo $currentDayPosition of $dayTotal • ${index + 1} of $total'
        : '${index + 1} of $total ${widget.customSubtitle ?? "recorded days"}';

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
                Text(
                  widget.customTitle ?? 'Daily Journal',
                  style: AppTypography.appTitle,
                ),
                const SizedBox(height: 2.0),
                Text(
                  subtitleText,
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Position Pill Badge (e.g. "2 of 5" for multi-photo days)
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
              pillText,
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          // Photo Details Action
          IconButton(
            icon: Icon(
              Icons.info_outline_rounded,
              color: AppColors.textPrimary,
              size: 22.0,
            ),
            tooltip: 'Photo Details',
            onPressed: () => _openDetail(currentEntry),
          ),
        ],
      ),
    );
  }

  Widget _buildPageItem(PhotoEntry entry) {
    final hasTitle = entry.title.trim().isNotEmpty;
    final hasLocation =
        entry.location != null && entry.location!.trim().isNotEmpty;
    final hasTime = entry.timeFormatted.trim().isNotEmpty;
    final formattedDate = VisualDiaryEntryCard.formatDate(entry.date);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageHorizontal,
        vertical: AppSpacing.sm,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppBreakpoints.maxDiaryWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Hero Photo Container
              Semantics(
                button: true,
                label:
                    'View photo details for ${entry.title.trim().isNotEmpty ? entry.title.trim() : formattedDate}',
                child: GestureDetector(
                  onTap: () => _openDetail(entry),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: AppRadii.card,
                      border: Border.all(color: AppColors.border, width: 1.0),
                      boxShadow: AppShadows.card,
                    ),
                    child: ClipRRect(
                      borderRadius: AppRadii.card,
                      child: AspectRatio(
                        aspectRatio: 4 / 3,
                        child: Semantics(
                          image: true,
                          label: 'Photo captured on $formattedDate',
                          child:
                              (entry.hasRealImage && entry.isImageFileAvailable)
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
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              // Date, Time & Sync Status Row
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 13.5,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 5.0),
                  Expanded(
                    child: Text(
                      formattedDate,
                      style: TextStyle(
                        fontSize: 13.5,
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
                        fontSize: 12.0,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                  const SizedBox(width: AppSpacing.xs),
                  _buildSyncChip(entry),
                ],
              ),

              // Optional Diary Metadata
              if (hasTitle || hasLocation) ...[
                const SizedBox(height: AppSpacing.sm),
                if (hasTitle)
                  Text(
                    entry.title.trim(),
                    style: TextStyle(
                      fontSize: 18.0,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (hasLocation) ...[
                  const SizedBox(height: 7.0),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 14.0,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 4.0),
                      Expanded(
                        child: Text(
                          entry.location!.trim(),
                          style: AppTypography.caption.copyWith(
                            fontSize: 12.0,
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

              // Intra-day multi-photo thumbnail strip
              if (_store.getDay(entry.dateKey) != null &&
                  _store.getDay(entry.dateKey)!.photos.length > 1) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10.0,
                    vertical: 8.0,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10.0),
                    border: Border.all(color: AppColors.border, width: 0.8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Photos on this date (${_store.getDay(entry.dateKey)!.photos.indexWhere((p) => p.effectiveId == entry.effectiveId) + 1} of ${_store.getDay(entry.dateKey)!.photos.length})',
                            style: TextStyle(
                              fontSize: 11.5,
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
                              '${_store.getDay(entry.dateKey)!.photos.length} photos',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6.0),
                      SizedBox(
                        height: 48.0,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: _store
                              .getDay(entry.dateKey)!
                              .photos
                              .length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(width: AppSpacing.xs),
                          itemBuilder: (context, pIndex) {
                            final p = _store
                                .getDay(entry.dateKey)!
                                .photos[pIndex];
                            final isSelected =
                                p.effectiveId == entry.effectiveId;
                            return GestureDetector(
                              onTap: () {
                                final globalIdx = _entries.indexWhere(
                                  (e) => e.effectiveId == p.effectiveId,
                                );
                                if (globalIdx >= 0 &&
                                    _pageController.hasClients) {
                                  _pageController.animateToPage(
                                    globalIdx,
                                    duration: const Duration(milliseconds: 250),
                                    curve: Curves.easeInOut,
                                  );
                                }
                              },
                              child: Container(
                                width: 48.0,
                                height: 48.0,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6.0),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.accent
                                        : AppColors.border,
                                    width: isSelected ? 2.0 : 0.8,
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
                                              cacheWidth: 120,
                                              cacheHeight: 120,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (
                                                    context,
                                                    error,
                                                    stackTrace,
                                                  ) => _buildFallbackPhoto(p),
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
                                              2.5,
                                            ),
                                          ),
                                          child: Text(
                                            '${pIndex + 1}',
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
                  ),
                ),
              ],

              // Daily Note card if present
              if (_store.getDay(entry.dateKey) != null &&
                  _store.getDay(entry.dateKey)!.note.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(10.0),
                    border: Border.all(color: AppColors.border, width: 0.6),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.notes_rounded,
                        size: 15.0,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 8.0),
                      Expanded(
                        child: Text(
                          _store.getDay(entry.dateKey)!.note,
                          style: AppTypography.caption.copyWith(
                            fontSize: 12.0,
                            color: AppColors.textPrimary,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(int index, int total, PhotoEntry currentEntry) {
    final canGoPrevious = index > 0;
    final canGoNext = index < total - 1;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageHorizontal,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.8)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppBreakpoints.maxDiaryWidth,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Older / Previous Day Button
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Semantics(
                    label: 'Previous Day (Older)',
                    button: true,
                    enabled: canGoPrevious,
                    child: TextButton.icon(
                      onPressed: canGoPrevious ? _goToPrevious : null,
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 14.0,
                      ),
                      label: const Text('Older'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        disabledForegroundColor: AppColors.textMuted.withValues(
                          alpha: 0.4,
                        ),
                        minimumSize: const Size(48.0, 48.0),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 4.0),

              // Center Action: View Details
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: OutlinedButton.icon(
                    onPressed: () => _openDetail(currentEntry),
                    icon: const Icon(Icons.open_in_new_rounded, size: 14.0),
                    label: const Text('View Details'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14.0,
                        vertical: 8.0,
                      ),
                      minimumSize: const Size(48.0, 48.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.0),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 4.0),

              // Newer / Next Day Button
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Semantics(
                    label: 'Next Day (Newer)',
                    button: true,
                    enabled: canGoNext,
                    child: TextButton.icon(
                      onPressed: canGoNext ? () => _goToNext(total) : null,
                      label: const Text('Newer'),
                      icon: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14.0,
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        disabledForegroundColor: AppColors.textMuted.withValues(
                          alpha: 0.4,
                        ),
                        minimumSize: const Size(48.0, 48.0),
                      ),
                    ),
                  ),
                ),
              ),
            ],
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80.0,
              height: 80.0,
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.view_carousel_rounded,
                size: 40.0,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No Photos to Browse',
              style: TextStyle(
                fontSize: 20.0,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Once you capture your daily photos, you can swipe chronologically through your memories here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.0,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            ElevatedButton.icon(
              onPressed: _promptPhotoCapture,
              icon: const Icon(Icons.camera_alt_rounded, size: 18.0),
              label: const Text("Capture Today's Photo"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22.0,
                  vertical: 13.0,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
