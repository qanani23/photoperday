import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/core/layout/app_breakpoints.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_shadows.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/day_entry.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/daily_photo_rule.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/streak_service.dart';
import 'package:photo_per_day/screens/calendar/full_calendar_screen.dart';
import 'package:photo_per_day/screens/camera/camera_screen.dart';
import 'package:photo_per_day/screens/diary/swipe_days_screen.dart';
import 'package:photo_per_day/services/gallery_photo_service.dart';
import 'package:photo_per_day/widgets/app_header.dart';
import 'package:photo_per_day/widgets/app_scaffold.dart';
import 'package:photo_per_day/widgets/calendar_cell.dart';
import 'package:photo_per_day/widgets/calendar_grid.dart';
import 'package:photo_per_day/widgets/home_streak_card.dart';
import 'package:photo_per_day/widgets/photo_source_sheet.dart';
import 'package:photo_per_day/widgets/timeline_entry_card.dart';
import 'package:photo_per_day/widgets/weekday_header.dart';

/// Redesigned Home Screen combining:
/// 1. A compact calendar showing strictly the current local month.
/// 2. A scrollable memories timeline underneath it.
///
/// Follows a premium, warm, minimal photo diary visual language:
/// off-white/linen background, charcoal typography, muted secondary text,
/// restrained caramel accents, subtle photo indicators, and photography-first cards.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.wrapWithScaffold = true,
    this.onNavigateToToday,
    this.onNavigateToSettings,
    this.onNavigateToProfile,
    this.initialDate,
    this.initialSelectedDate,
    this.store,
    this.showFullCalendar = false,
  });

  final bool wrapWithScaffold;
  final VoidCallback? onNavigateToToday;
  final VoidCallback? onNavigateToSettings;
  final VoidCallback? onNavigateToProfile;
  final DateTime? initialDate;
  final DateTime? initialSelectedDate;
  final PersistentDailyPhotoStore? store;

  /// Backwards-compatibility toggle allowing access to the 12-month calendar.
  final bool showFullCalendar;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GalleryPhotoService _galleryPhotoService = GalleryPhotoService();
  final ScrollController _scrollController = ScrollController();

  PersistentDailyPhotoStore get _store =>
      widget.store ?? PersistentDailyPhotoStore.instance;

  late DateTime _currentDate;
  late DateTime _selectedDate;

  static const List<String> _monthNames = [
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

  @override
  void initState() {
    super.initState();
    final now = widget.initialDate ?? DateTime.now();
    _currentDate = DateTime(now.year, now.month, now.day);

    if (widget.initialSelectedDate != null) {
      _selectedDate = widget.initialSelectedDate!;
    } else {
      _selectedDate = _currentDate;
    }

    _store.addListener(_onPhotoStoreUpdated);
    AppThemeService.instance.addListener(_onPhotoStoreUpdated);
  }

  void _onPhotoStoreUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.store != oldWidget.store) {
      (oldWidget.store ?? PersistentDailyPhotoStore.instance).removeListener(
        _onPhotoStoreUpdated,
      );
      _store.addListener(_onPhotoStoreUpdated);
    }
    if (widget.initialDate != oldWidget.initialDate) {
      final now = widget.initialDate ?? DateTime.now();
      _currentDate = DateTime(now.year, now.month, now.day);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _store.removeListener(_onPhotoStoreUpdated);
    AppThemeService.instance.removeListener(_onPhotoStoreUpdated);
    super.dispose();
  }

  PhotoEntry? _getPhotoForDate(DateKey dateKey) {
    return _store.getPhotoByKey(dateKey);
  }

  Future<void> _promptPhotoSource([DateTime? targetDate]) async {
    final effectiveDate = targetDate ?? _selectedDate;
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
        allowMultiple: true,
      );
    }

    if (capturedPaths.isNotEmpty && mounted) {
      final dateKey = DateKey.fromDateTime(effectiveDate);
      int successCount = 0;

      for (final capturedPath in capturedPaths) {
        final now = DateTime.now();
        final period = now.hour >= 12 ? 'PM' : 'AM';
        final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
        final minuteFormatted = now.minute.toString().padLeft(2, '0');
        final formattedTime = '$hour12:$minuteFormatted $period';

        final isTargetToday = DailyPhotoRule.isSameDay(
          effectiveDate,
          _currentDate,
        );
        final newEntry = PhotoEntry(
          date: effectiveDate,
          title: isTargetToday ? 'Daily Capture' : 'Photo Memory',
          location: source == PhotoSource.camera
              ? 'Camera Capture'
              : (Platform.isWindows
                    ? 'Imported from Computer'
                    : 'Photo Library'),
          timeFormatted: formattedTime,
          imagePath: capturedPath,
          gradientColors: [AppColors.accent, AppColors.surfaceDark],
        );

        try {
          await _store.addPhotoToDay(
            dateKey: dateKey,
            photo: newEntry,
            sourceTempPath: capturedPath,
          );
          successCount++;
        } catch (e) {
          debugPrint('Failed to save photo from home screen: $e');
        }
      }

      if (mounted && successCount > 0) {
        setState(() {
          _selectedDate = effectiveDate;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              successCount == 1
                  ? "Photo added successfully!"
                  : "$successCount photos added successfully!",
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _openDayDetail(DayEntry dayEntry) {
    if (dayEntry.photos.isNotEmpty) {
      _openPhotoDetail(dayEntry.primaryPhoto!);
    } else if (dayEntry.dateKey == DateKey.fromDateTime(_currentDate) &&
        widget.onNavigateToToday != null) {
      widget.onNavigateToToday!();
    } else {
      final entry = PhotoEntry(
        date: dayEntry.dateKey.toDateTime(),
        title: 'Daily Reflection',
        timeFormatted: '',
        gradientColors: [AppColors.accent, AppColors.surfaceDark],
      );
      _openPhotoDetail(entry);
    }
  }

  void _openPhotoDetail(PhotoEntry photo) {
    Navigator.pushNamed(
      context,
      AppConstants.photoDetailRoute,
      arguments: photo,
    );
  }

  void _openSwipeDays(DayEntry dayEntry) {
    Navigator.pushNamed(
      context,
      AppConstants.swipeDaysRoute,
      arguments: SwipeDaysArguments(initialDateKey: dayEntry.dateKey),
    );
  }

  void _navigateToFullCalendar() {
    Navigator.pushNamed(context, AppConstants.fullCalendarRoute);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.showFullCalendar) {
      return FullCalendarScreen(
        wrapWithScaffold: widget.wrapWithScaffold,
        onNavigateToToday: widget.onNavigateToToday,
        onNavigateToSettings: widget.onNavigateToSettings,
        onNavigateToProfile: widget.onNavigateToProfile,
        initialDate: widget.initialDate,
        initialSelectedDate: widget.initialSelectedDate,
        store: widget.store,
      );
    }

    final todayKey = DateKey.fromDateTime(_currentDate);
    final streakSummary = StreakService.instance.calculateStreak(
      store: _store,
      todayDate: _currentDate,
    );

    // Retrieve recorded days in reverse-chronological order (newest first)
    final timelineDays = _store.chronologicalDayEntries
        .where(
          (d) =>
              d.dateKey.compareTo(todayKey) <= 0 && (d.isNotEmpty || d.hasNote),
        )
        .toList();

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top App Header
        AppHeader(
          onDiaryTap: () =>
              Navigator.pushNamed(context, AppConstants.diaryRoute),
          onSettingsTap:
              widget.onNavigateToSettings ??
              () => Navigator.pushNamed(context, AppConstants.settingsRoute),
        ),

        // Scrollable Home Content: Compact Calendar + Memories Timeline
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(
              left: AppSpacing.pageHorizontal,
              right: AppSpacing.pageHorizontal,
              top: AppSpacing.xs,
              bottom: AppSpacing.dockClearance,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Compact Current-Month Calendar Card
                _buildCompactCalendarCard(),

                const SizedBox(height: AppSpacing.md),

                // 2. Home Streak Status Card
                HomeStreakCard(
                  streakSummary: streakSummary,
                  todayKey: todayKey,
                  onTap: _navigateToFullCalendar,
                ),

                const SizedBox(height: AppSpacing.lg),

                // 3. Memories Timeline Header
                _buildTimelineHeader(timelineDays.length),

                const SizedBox(height: AppSpacing.sm),

                // 3. Memories Timeline Content
                if (timelineDays.isEmpty)
                  _buildEmptyTimelineState()
                else
                  ...timelineDays.map(
                    (dayEntry) => TimelineEntryCard(
                      key: ValueKey(
                        'timeline_day_${dayEntry.dateKey.format()}',
                      ),
                      dayEntry: dayEntry,
                      onTap: () => _openDayDetail(dayEntry),
                      onPhotoTap: (photo) => _openPhotoDetail(photo),
                      onBrowseTap: () => _openSwipeDays(dayEntry),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );

    if (widget.wrapWithScaffold) {
      return AppScaffold(
        currentNavIndex: 0,
        maxContentWidth: AppBreakpoints.maxContentWidth,
        onCaptureTap: widget.onNavigateToToday,
        body: content,
      );
    }

    return Material(color: AppColors.background, child: content);
  }

  /// Compact Current-Month Calendar Card:
  /// Displays the current local month and year, 7-column grid with photo indicators,
  /// and a clear "Full calendar" action. Contains NO month-navigation arrows.
  Widget _buildCompactCalendarCard() {
    final monthName = _monthNames[_currentDate.month - 1];
    final monthYearTitle = '$monthName ${_currentDate.year}';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.border, width: 1.0),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Month Header Row with clear "Full calendar" action (No month chevrons)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6.0,
                  runSpacing: 2.0,
                  children: [
                    Semantics(
                      header: true,
                      label: '$monthYearTitle calendar',
                      child: Text(
                        monthYearTitle,
                        style: AppTypography.appTitle.copyWith(
                          fontSize: 18.0,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7.0,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: Text(
                        'This Month',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Full calendar action button
              Semantics(
                button: true,
                label: 'Open full calendar',
                child: TextButton.icon(
                  key: const ValueKey('home_full_calendar_button'),
                  onPressed: _navigateToFullCalendar,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 4.0,
                    ),
                    minimumSize: const Size(48.0, 36.0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Icon(
                    Icons.calendar_month_outlined,
                    size: 16.0,
                    color: AppColors.accent,
                  ),
                  label: Text(
                    'Full calendar',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),

          // Weekday Indicators (S M T W T F S)
          const WeekdayHeader(padding: EdgeInsets.zero),

          const SizedBox(height: AppSpacing.xs),

          // Compact 7-column calendar grid for the current month
          _buildCurrentMonthGrid(),
        ],
      ),
    );
  }

  /// Builds the compact 7-column calendar grid for the current local month
  Widget _buildCurrentMonthGrid() {
    final year = _currentDate.year;
    final month = _currentDate.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstDayWeekday = DateTime(year, month, 1).weekday;

    // Sunday-first alignment: Sunday = 0, Monday = 1, ..., Saturday = 6
    final leadingOffset = firstDayWeekday % 7;
    final cells = <Widget>[];

    // Leading empty spacers
    for (int i = 0; i < leadingOffset; i++) {
      cells.add(const CalendarCell(day: 0, style: CalendarCellStyle.blank));
    }

    // Days in current month
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(year, month, day);
      final dateKey = DateKey(year, month, day);
      final dayEntry = _store.getDay(dateKey);
      final photo = dayEntry?.primaryPhoto ?? _getPhotoForDate(dateKey);
      final photoCount = dayEntry?.photoCount ?? (photo != null ? 1 : 0);
      final hasNote = dayEntry?.hasNote ?? false;

      final isToday = DailyPhotoRule.isSameDay(date, _currentDate);
      final isSelected = DailyPhotoRule.isSameDay(date, _selectedDate);

      final CalendarCellStyle cellStyle;
      if (photo != null) {
        cellStyle = CalendarCellStyle.photo;
      } else {
        cellStyle = CalendarCellStyle.empty;
      }

      cells.add(
        CalendarCell(
          key: ValueKey(dateKey),
          day: day,
          style: cellStyle,
          isToday: isToday,
          showTodayPulse: isToday,
          photoCount: photoCount,
          hasNote: hasNote,
          imageProvider:
              (photo?.hasRealImage == true &&
                  photo?.isImageFileAvailable == true)
              ? FileImage(File(photo!.imagePath!))
              : null,
          gradientColors: photo?.gradientColors,
          photoIcon: photo?.icon,
          isSelected: isSelected,
          syncStatus: photo?.syncStatus,
          isSyncing: false,
          onTap: () async {
            setState(() {
              _selectedDate = date;
            });

            if (photo != null) {
              await Navigator.pushNamed(
                context,
                AppConstants.photoDetailRoute,
                arguments: photo,
              );
              if (mounted) setState(() {});
            } else if (hasNote) {
              if (isToday && widget.onNavigateToToday != null) {
                widget.onNavigateToToday!();
              } else {
                final entry = PhotoEntry(
                  date: date,
                  title: 'Daily Reflection',
                  timeFormatted: '',
                  gradientColors: [AppColors.accent, AppColors.surfaceDark],
                );
                await Navigator.pushNamed(
                  context,
                  AppConstants.photoDetailRoute,
                  arguments: entry,
                );
                if (mounted) setState(() {});
              }
            } else if (isToday) {
              await _promptPhotoSource(date);
            }
          },
        ),
      );
    }

    // Trailing blank spacers
    final totalPlaced = leadingOffset + daysInMonth;
    final trailingOffset = (7 - (totalPlaced % 7)) % 7;
    for (int i = 0; i < trailingOffset; i++) {
      cells.add(const CalendarCell(day: 0, style: CalendarCellStyle.blank));
    }

    final isDesktop = MediaQuery.sizeOf(context).width >= 800;
    return CalendarGrid(
      key: ValueKey('compact-grid-$year-$month'),
      padding: EdgeInsets.zero,
      childAspectRatio: isDesktop ? 1.15 : 1.0,
      children: cells,
    );
  }

  /// Memories Timeline Section Header
  Widget _buildTimelineHeader(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_stories_rounded,
              size: 19.0,
              color: AppColors.accent,
            ),
            const SizedBox(width: 8.0),
            Text(
              'Memories',
              style: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        if (count > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(color: AppColors.border, width: 0.8),
            ),
            child: Text(
              '$count ${count == 1 ? "day" : "days"}',
              style: TextStyle(
                fontSize: 11.0,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }

  /// Helpful empty state when no memories exist yet
  Widget _buildEmptyTimelineState() {
    return Container(
      key: const ValueKey('home_memories_empty_state'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.border, width: 1.0),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56.0,
            height: 56.0,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.photo_library_outlined,
              size: 28.0,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No Memories Yet',
            style: TextStyle(
              fontSize: 16.0,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6.0),
          Text(
            'Your daily photo journal starts here. Capture or choose today\'s photo to begin your story.',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(
              fontSize: 12.5,
              color: AppColors.textMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ElevatedButton.icon(
            key: const ValueKey('home_empty_add_photo_button'),
            onPressed: () => _promptPhotoSource(_currentDate),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 10.0,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.0),
              ),
              elevation: 0,
            ),
            icon: const Icon(Icons.add_a_photo_outlined, size: 16.0),
            label: const Text(
              'Add Your First Photo',
              style: TextStyle(fontSize: 13.0, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
