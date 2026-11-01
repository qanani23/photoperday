import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_shadows.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/day_entry.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/memory_service.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/screens/camera/camera_screen.dart';
import 'package:photo_per_day/services/gallery_photo_service.dart';
import 'package:photo_per_day/widgets/app_icon_button.dart';
import 'package:photo_per_day/widgets/photo_source_sheet.dart';

/// The Today Screen focused entirely on today's daily photograph and memory.
///
/// Supports both State A (Today has a photo) and State B (Today has no photo),
/// with a state toggle for testing, progress indicator, and mock actions.
class TodayScreen extends StatefulWidget {
  const TodayScreen({
    super.key,
    this.onNavigateToCalendar,
    this.todayDate,
    this.store,
  });

  final VoidCallback? onNavigateToCalendar;
  final DateTime? todayDate;
  final PersistentDailyPhotoStore? store;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  final GalleryPhotoService _galleryPhotoService = GalleryPhotoService();

  /// Whether today currently has a photo (toggled for demo/testing)
  bool _hasPhoto = true;

  /// Photo entry for today
  late PhotoEntry _todayPhoto;

  /// Index of the currently focused photo within today's entry
  int _selectedPhotoIndex = 0;

  late PageController _todayPageController;

  DateTime get _effectiveToday {
    if (widget.todayDate != null) {
      return DateTime(
        widget.todayDate!.year,
        widget.todayDate!.month,
        widget.todayDate!.day,
      );
    }
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  PersistentDailyPhotoStore get _store =>
      widget.store ?? PersistentDailyPhotoStore.instance;

  DayEntry? get _todayDayEntry =>
      _store.getDay(DateKey.fromDateTime(_effectiveToday));

  static const List<String> _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static const List<String> _months = [
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

  String get _formattedDateSubtitle {
    final target = _effectiveToday;
    final weekday = _weekdays[target.weekday - 1];
    final month = _months[target.month - 1];
    return '$weekday, $month ${target.day}, ${target.year}';
  }

  int get _dayOfYear {
    final target = _effectiveToday;
    return target.difference(DateTime(target.year, 1, 1)).inDays + 1;
  }

  @override
  void initState() {
    super.initState();
    final today = _effectiveToday;
    final day = _store.getDay(DateKey.fromDateTime(today));
    if (day != null && day.hasPhotos) {
      _selectedPhotoIndex = 0;
      _todayPhoto = day.photos.first;
      _hasPhoto = true;
    } else {
      final sessionPhoto = _store.getPhoto(today);
      if (sessionPhoto != null) {
        _todayPhoto = sessionPhoto;
        _hasPhoto = true;
      } else {
        _todayPhoto = PhotoEntry(
          date: today,
          title: 'Daily Capture',
          timeFormatted: '',
          gradientColors: [AppColors.accent, AppColors.surfaceDark],
        );
        _hasPhoto = false;
      }
    }
    _todayPageController = PageController(initialPage: _selectedPhotoIndex);
    _store.addListener(_onPhotoStoreUpdated);
    AppThemeService.instance.addListener(_onPhotoStoreUpdated);
  }

  void _onPhotoStoreUpdated() {
    if (!mounted) return;
    final today = _effectiveToday;
    final day = _store.getDay(DateKey.fromDateTime(today));
    setState(() {
      if (day != null && day.hasPhotos) {
        if (_selectedPhotoIndex >= day.photos.length) {
          _selectedPhotoIndex = day.photos.length - 1;
        }
        _todayPhoto = day.photos[_selectedPhotoIndex];
        _hasPhoto = true;
        if (_todayPageController.hasClients &&
            _todayPageController.page?.round() != _selectedPhotoIndex) {
          _todayPageController.jumpToPage(_selectedPhotoIndex);
        }
      } else {
        final sessionPhoto = _store.getPhoto(today);
        if (sessionPhoto != null) {
          _todayPhoto = sessionPhoto;
          _hasPhoto = true;
        } else {
          if (_todayPhoto.hasRealImage) {
            _hasPhoto = false;
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _store.removeListener(_onPhotoStoreUpdated);
    AppThemeService.instance.removeListener(_onPhotoStoreUpdated);
    _todayPageController.dispose();
    super.dispose();
  }

  void _toggleState() {
    setState(() {
      _hasPhoto = !_hasPhoto;
    });
  }

  Future<void> _promptPhotoSource({bool isAddition = true}) async {
    final source = await PhotoSourceSheet.show(context);
    if (source == null || !mounted) return;

    List<String> capturedPaths = [];
    if (source == PhotoSource.camera) {
      final single = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (context) => const CameraScreen()),
      );
      if (single != null) capturedPaths.add(single);
    } else if (source == PhotoSource.gallery) {
      capturedPaths = await _galleryPhotoService.pickPhotos(
        allowMultiple: isAddition || !_hasPhoto,
      );
    }

    if (capturedPaths.isNotEmpty && mounted) {
      final dateKey = DateKey.fromDateTime(_effectiveToday);

      try {
        PhotoEntry? lastPersisted;
        for (final capturedPath in capturedPaths) {
          final now = DateTime.now();
          final period = now.hour >= 12 ? 'PM' : 'AM';
          final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
          final minuteFormatted = now.minute.toString().padLeft(2, '0');
          final formattedTime = '$hour12:$minuteFormatted $period';

          if (isAddition || !_hasPhoto || capturedPaths.length > 1) {
            final newPhoto = PhotoEntry(
              date: dateKey.toDateTime(hour: now.hour, minute: now.minute),
              title: 'Daily Capture',
              timeFormatted: formattedTime,
              imagePath: capturedPath,
              location: source == PhotoSource.camera
                  ? 'Camera Capture'
                  : (Platform.isWindows
                        ? 'Imported from Computer'
                        : 'Photo Library'),
              gradientColors: [AppColors.accent, AppColors.surfaceDark],
            );
            lastPersisted = await _store.addPhotoToDay(
              dateKey: dateKey,
              photo: newPhoto,
              sourceTempPath: capturedPath,
            );
          } else {
            final updatedPhoto = _todayPhoto.copyWith(
              date: _effectiveToday,
              title: _todayPhoto.title.isNotEmpty
                  ? _todayPhoto.title
                  : 'Daily Capture',
              timeFormatted: formattedTime,
              imagePath: capturedPath,
            );
            lastPersisted = await _store.savePhoto(
              entry: updatedPhoto,
              sourceTempPath: capturedPath,
            );
          }
        }

        if (mounted && lastPersisted != null) {
          final day = _store.getDay(dateKey);
          setState(() {
            _todayPhoto = lastPersisted!;
            _hasPhoto = true;
            if (day != null) {
              final idx = day.photos.indexWhere(
                (p) => p.id == lastPersisted!.id,
              );
              if (idx != -1) {
                _selectedPhotoIndex = idx;
                if (_todayPageController.hasClients) {
                  _todayPageController.jumpToPage(idx);
                }
              }
            }
          });
        }
      } catch (e) {
        debugPrint('Failed to save photo from today screen: $e');
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

  Future<void> _confirmAndReplacePhoto() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.dialogRadius,
          side: BorderSide(color: AppColors.border, width: 0.8),
        ),
        title: Text(
          'Replace Photo',
          style: TextStyle(
            fontSize: 18.0,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to replace this photo with a new capture? Other photos on this date will remain unchanged.',
          style: TextStyle(
            fontSize: 14.0,
            color: AppColors.textSecondary,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryButtonBackground,
              foregroundColor: AppColors.primaryButtonForeground,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
              ),
            ),
            child: const Text('Replace'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _promptPhotoSource(isAddition: false);
    }
  }

  Future<void> _showEditNoteDialog() async {
    final day = _todayDayEntry;
    final controller = TextEditingController(text: day?.note ?? '');
    final dateKey = DateKey.fromDateTime(_effectiveToday);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (bottomSheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.lg,
            bottom:
                MediaQuery.of(bottomSheetContext).viewInsets.bottom +
                AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Daily Note',
                    style: TextStyle(
                      fontSize: 18.0,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(bottomSheetContext).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: controller,
                maxLines: 4,
                autofocus: true,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14.0),
                decoration: InputDecoration(
                  hintText:
                      "Write today's thoughts, memories, or reflections...",
                  hintStyle: TextStyle(color: AppColors.textMuted),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.0),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.0),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.0),
                    borderSide: BorderSide(color: AppColors.accent, width: 1.5),
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceSubtle,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(bottomSheetContext).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ElevatedButton(
                    onPressed: () async {
                      final updatedNote = controller.text.trim();
                      await _store.updateDayNote(
                        dateKey: dateKey,
                        note: updatedNote,
                      );
                      if (bottomSheetContext.mounted) {
                        Navigator.of(bottomSheetContext).pop();
                      }
                      if (mounted) {
                        setState(() {});
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                    ),
                    child: const Text('Save Note'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
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
    final today = _effectiveToday;
    final memories = MemoryService.instance.getMemoriesForDate(
      today,
      store: _store,
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
        child: Semantics(
          button: true,
          label: 'On This Day, $text. Tap to view memories.',
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
                    child: Icon(
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
                        Text(
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
                          style: TextStyle(
                            fontSize: 12.0,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14.0,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Today', style: AppTypography.appTitle),
              const SizedBox(height: 2.0),
              Text(_formattedDateSubtitle, style: AppTypography.screenSubtitle),
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 11.0,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 4.0),
                    Text(
                      'Day $_dayOfYear of ${_effectiveToday.year}',
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
        ),
        const SizedBox(width: 8.0),

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
                          style: TextStyle(
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

  /// STATE A: Today Has a Photo (Responsive 2-column on desktop, stacked on mobile)
  Widget _buildPhotoState() {
    final dayEntry = _todayDayEntry;
    final currentPhoto =
        (dayEntry != null &&
            dayEntry.photos.isNotEmpty &&
            _selectedPhotoIndex < dayEntry.photos.length)
        ? dayEntry.photos[_selectedPhotoIndex]
        : _todayPhoto;

    return LayoutBuilder(
      key: const ValueKey('photo_state'),
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 840;

        final photoWidget = Container(
          width: double.infinity,
          height: isWide ? 420.0 : 340.0,
          decoration: const BoxDecoration(
            borderRadius: AppRadii.card,
            boxShadow: AppShadows.card,
          ),
          child: ClipRRect(
            borderRadius: AppRadii.card,
            child: (dayEntry != null && dayEntry.photos.length > 1)
                ? PageView.builder(
                    controller: _todayPageController,
                    physics: const BouncingScrollPhysics(),
                    itemCount: dayEntry.photos.length,
                    onPageChanged: (index) {
                      setState(() {
                        _selectedPhotoIndex = index;
                        _todayPhoto = dayEntry.photos[index];
                      });
                    },
                    itemBuilder: (context, index) {
                      return _buildPhotoCard(
                        dayEntry.photos[index],
                        index,
                        dayEntry.photos.length,
                      );
                    },
                  )
                : _buildPhotoCard(currentPhoto, 0, 1),
          ),
        );

        final metadataCard = Container(
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
              if (currentPhoto.title.trim().isNotEmpty)
                Text(
                  currentPhoto.title.trim(),
                  style: TextStyle(
                    fontSize: 17.0,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              if (currentPhoto.location != null &&
                  currentPhoto.location!.trim().isNotEmpty) ...[
                const SizedBox(height: 8.0),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 13.0,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 3.0),
                    Text(
                      currentPhoto.location!.trim(),
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
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    photoWidget,
                    if (dayEntry != null && dayEntry.photos.length > 1) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _buildThumbnailStrip(dayEntry),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    metadataCard,
                    const SizedBox(height: AppSpacing.md),
                    _buildDailyNoteSection(dayEntry),
                    const SizedBox(height: AppSpacing.md),
                    _buildActionButtons(),
                  ],
                ),
              ),
            ],
          );
        }

        // Mobile / narrow stacked layout
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            photoWidget,
            if (dayEntry != null && dayEntry.photos.length > 1) ...[
              const SizedBox(height: AppSpacing.sm),
              _buildThumbnailStrip(dayEntry),
            ],
            const SizedBox(height: AppSpacing.md),
            metadataCard,
            const SizedBox(height: AppSpacing.md),
            _buildDailyNoteSection(dayEntry),
            const SizedBox(height: AppSpacing.md),
            _buildActionButtons(),
          ],
        );
      },
    );
  }

  Widget _buildActionButtons() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isVeryNarrow = constraints.maxWidth < 380;
        final addLabel = isVeryNarrow ? 'Add' : 'Add Photo';
        final replaceLabel = isVeryNarrow ? 'Replace' : 'Replace Photo';

        return Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: "Add another photo to today",
                child: ElevatedButton.icon(
                  onPressed: () => _promptPhotoSource(isAddition: true),
                  icon: const Icon(Icons.add_a_photo_outlined, size: 16.0),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(addLabel),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryButtonBackground,
                    foregroundColor: AppColors.primaryButtonForeground,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 12.0,
                    ),
                    minimumSize: const Size(0, 48.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Semantics(
                button: true,
                label: "Replace today's photo",
                child: OutlinedButton.icon(
                  onPressed: _confirmAndReplacePhoto,
                  icon: const Icon(Icons.refresh_rounded, size: 16.0),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(replaceLabel),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 12.0,
                    ),
                    minimumSize: const Size(0, 48.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Semantics(
              button: true,
              label: "Share today's photo",
              child: IconButton.outlined(
                onPressed: () => _showMockActionMessage('Share'),
                tooltip: 'Share photo',
                icon: const Icon(Icons.share_outlined, size: 18.0),
                color: AppColors.textPrimary,
                style: IconButton.styleFrom(
                  side: BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.all(12.0),
                  minimumSize: const Size(48.0, 48.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPhotoCard(PhotoEntry photo, int index, int totalPhotos) {
    return Semantics(
      button: true,
      label: "Today's photo memory: ${photo.title}. Tap to view photo details.",
      child: GestureDetector(
        onTap: () {
          Navigator.pushNamed(
            context,
            AppConstants.photoDetailRoute,
            arguments: photo,
          );
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Photo Content (Real Image or Gradient Art fallback)
            if (photo.hasRealImage && photo.isImageFileAvailable)
              Image.file(
                File(photo.imagePath!),
                cacheWidth: 1080,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _buildGradientArt(photo),
              )
            else
              _buildGradientArt(photo),

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

            // Top Category Tag & Multi-Photo Badge
            Positioned(
              top: 14.0,
              left: 14.0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
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
                          photo.category,
                          style: const TextStyle(
                            fontSize: 11.0,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (totalPhotos > 1) ...[
                    const SizedBox(width: 6.0),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 4.0,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: Text(
                        '${index + 1} of $totalPhotos',
                        style: const TextStyle(
                          fontSize: 11.0,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Top-Right Backup Status Indicator
            Positioned(
              top: 14.0,
              right: 14.0,
              child: _buildSyncStatusBadge(photo),
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
                      photo.timeFormatted,
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
                            arguments: photo,
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
    );
  }

  Widget _buildThumbnailStrip(DayEntry day) {
    return SizedBox(
      height: 60.0,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: day.photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final photo = day.photos[index];
          final isSelected = index == _selectedPhotoIndex;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedPhotoIndex = index;
                _todayPhoto = photo;
              });
              if (_todayPageController.hasClients &&
                  _todayPageController.page?.round() != index) {
                _todayPageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                );
              }
            },
            child: Container(
              width: 60.0,
              height: 60.0,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.sm),
                border: Border.all(
                  color: isSelected ? AppColors.accent : AppColors.border,
                  width: isSelected ? 2.5 : 1.0,
                ),
                boxShadow: isSelected ? AppShadows.card : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.sm - 1),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (photo.hasRealImage && photo.isImageFileAvailable)
                      Image.file(File(photo.imagePath!), fit: BoxFit.cover)
                    else
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: photo.gradientColors,
                          ),
                        ),
                        child: Icon(
                          photo.icon,
                          size: 20.0,
                          color: Colors.white,
                        ),
                      ),
                    Positioned(
                      top: 2,
                      left: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4.0,
                          vertical: 1.0,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4.0),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            fontSize: 9.0,
                            fontWeight: FontWeight.bold,
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
    );
  }

  Widget _buildDailyNoteSection(DayEntry? day) {
    final hasNote = day != null && day.hasNote;
    final note = day?.note ?? '';

    return Container(
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_note_rounded,
                      size: 18.0,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 6.0),
                    Expanded(
                      child: Text(
                        'Daily Reflection',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              TextButton.icon(
                onPressed: _showEditNoteDialog,
                icon: Icon(
                  hasNote ? Icons.edit_outlined : Icons.add_rounded,
                  size: 14.0,
                ),
                label: Text(
                  hasNote ? 'Edit' : 'Add Note',
                  style: const TextStyle(fontSize: 12.0),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          if (hasNote) ...[
            const SizedBox(height: 6.0),
            Text(
              note,
              style: TextStyle(
                fontSize: 13.0,
                height: 1.4,
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ] else ...[
            const SizedBox(height: 4.0),
            Text(
              'No note for today yet. Tap Add Note to record your thoughts.',
              style: TextStyle(fontSize: 12.0, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGradientArt([PhotoEntry? photo]) {
    final p = photo ?? _todayPhoto;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: p.gradientColors,
        ),
      ),
      child: Center(
        child: Icon(
          p.icon,
          size: 64.0,
          color: Colors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }

  /// STATE B: Today Has No Photo (Minimalist, Calm Empty State - Responsive 2-column on wide screens)
  Widget _buildEmptyState() {
    final dayEntry = _todayDayEntry;
    return LayoutBuilder(
      key: const ValueKey('empty_state'),
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 840;

        final emptyCard = Container(
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
                child: Center(
                  child: Icon(
                    Icons.camera_alt_outlined,
                    size: 36.0,
                    color: AppColors.accent,
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              Text(
                dayEntry?.isNoteOnly == true
                    ? 'Note recorded for today'
                    : 'Today hasn\'t been captured yet',
                style: TextStyle(
                  fontSize: 17.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.2,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 6.0),

              Text(
                dayEntry?.isNoteOnly == true
                    ? 'Add a photo to complete your daily entry.\nMultiple photos welcome.'
                    : 'Preserve your daily memory before midnight.\nOne photo at a time.',
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
              Semantics(
                button: true,
                label: "Capture today's photo",
                child: ElevatedButton.icon(
                  onPressed: () => _promptPhotoSource(isAddition: true),
                  icon: const Icon(Icons.photo_camera_rounded, size: 18.0),
                  label: const Text('Capture Today\'s Photo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryButtonBackground,
                    foregroundColor: AppColors.primaryButtonForeground,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 14.0,
                    ),
                    minimumSize: const Size(0, 48.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24.0),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: emptyCard),
              const SizedBox(width: AppSpacing.lg),
              Expanded(flex: 4, child: _buildDailyNoteSection(dayEntry)),
            ],
          );
        }

        return Column(
          children: [
            emptyCard,
            const SizedBox(height: AppSpacing.md),
            _buildDailyNoteSection(dayEntry),
          ],
        );
      },
    );
  }

  Widget _buildSyncStatusBadge(PhotoEntry photo) {
    return Semantics(
      label: 'Photo saved locally on device',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 11.5, color: Colors.white),
            SizedBox(width: 4.0),
            Text(
              'Saved',
              style: TextStyle(
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
