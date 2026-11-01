import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/core/layout/app_breakpoints.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/daily_photo_rule.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/streak_service.dart';
import 'package:photo_per_day/data/services/statistics_service.dart';
import 'package:photo_per_day/screens/camera/camera_screen.dart';
import 'package:photo_per_day/services/gallery_photo_service.dart';
import 'package:photo_per_day/widgets/app_header.dart';
import 'package:photo_per_day/widgets/app_scaffold.dart';
import 'package:photo_per_day/widgets/calendar_cell.dart';
import 'package:photo_per_day/widgets/calendar_grid.dart';
import 'package:photo_per_day/widgets/day_preview_card.dart';
import 'package:photo_per_day/widgets/photo_source_sheet.dart';
import 'package:photo_per_day/widgets/section_header.dart';
import 'package:photo_per_day/widgets/streak_overview_card.dart';
import 'package:photo_per_day/widgets/weekday_header.dart';

/// Full-Year Calendar Screen displaying all 12 months with year navigation,
/// current-month auto-positioning, streak status, and preserved day preview card integration.
class FullCalendarScreen extends StatefulWidget {
  const FullCalendarScreen({
    super.key,
    this.wrapWithScaffold = true,
    this.onNavigateToToday,
    this.onNavigateToSettings,
    this.onNavigateToProfile,
    this.initialDate,
    this.initialSelectedDate,
    this.store,
  });

  final bool wrapWithScaffold;
  final VoidCallback? onNavigateToToday;
  final VoidCallback? onNavigateToSettings;
  final VoidCallback? onNavigateToProfile;
  final DateTime? initialDate;
  final DateTime? initialSelectedDate;
  final PersistentDailyPhotoStore? store;

  @override
  State<FullCalendarScreen> createState() => _FullCalendarScreenState();
}

class _FullCalendarScreenState extends State<FullCalendarScreen> {
  final GalleryPhotoService _galleryPhotoService = GalleryPhotoService();
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _monthKeys = List.generate(12, (_) => GlobalKey());

  PersistentDailyPhotoStore get _store =>
      widget.store ?? PersistentDailyPhotoStore.instance;

  late DateTime _currentDate;
  late int _selectedYear;
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
    _selectedYear = _currentDate.year;

    if (widget.initialSelectedDate != null) {
      _selectedDate = widget.initialSelectedDate!;
    } else {
      _selectedDate = _currentDate;
    }

    _store.addListener(_onPhotoStoreUpdated);
    AppThemeService.instance.addListener(_onPhotoStoreUpdated);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToTargetMonth(isInitial: true);
    });
  }

  void _onPhotoStoreUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(FullCalendarScreen oldWidget) {
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
      _selectedYear = _currentDate.year;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToTargetMonth(isInitial: true);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _store.removeListener(_onPhotoStoreUpdated);
    AppThemeService.instance.removeListener(_onPhotoStoreUpdated);
    super.dispose();
  }

  void _scrollToTargetMonth({bool isInitial = false}) {
    if (!mounted) return;
    final isCurrentYear = _selectedYear == _currentDate.year;
    final targetIndex = isCurrentYear ? _currentDate.month - 1 : 0;

    if (targetIndex == 0) {
      if (_scrollController.hasClients) {
        if (isInitial) {
          _scrollController.jumpTo(0.0);
        } else {
          _scrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
          );
        }
      }
      return;
    }

    void tryScroll() {
      if (!mounted) return;
      final targetKey = _monthKeys[targetIndex];
      final targetContext = targetKey.currentContext;
      if (targetContext != null) {
        final renderObject = targetContext.findRenderObject();
        if (renderObject is RenderBox &&
            renderObject.hasSize &&
            renderObject.attached) {
          Scrollable.ensureVisible(
            targetContext,
            alignment: 0.0,
            duration: isInitial
                ? Duration.zero
                : const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
          );
        } else if (isInitial) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final ro = targetKey.currentContext?.findRenderObject();
            if (ro is RenderBox && ro.hasSize && ro.attached) {
              Scrollable.ensureVisible(
                targetKey.currentContext!,
                alignment: 0.0,
                duration: Duration.zero,
              );
            }
          });
        }
      }
    }

    final targetKey = _monthKeys[targetIndex];
    if (targetKey.currentContext != null) {
      tryScroll();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => tryScroll());
    }
  }

  void _changeYear(int delta) {
    setState(() {
      _selectedYear += delta;
      if (_selectedYear == _currentDate.year) {
        _selectedDate = _currentDate;
      } else {
        _selectedDate = DateTime(_selectedYear, 1, 1);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToTargetMonth(isInitial: false);
    });
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
          debugPrint('Failed to save photo from full calendar: $e');
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

  PhotoEntry? _getPhotoForDate(DateKey dateKey) {
    return _store.getPhotoByKey(dateKey);
  }

  @override
  Widget build(BuildContext context) {
    final selectedKey = DateKey.fromDateTime(_selectedDate);
    final selectedPhoto = _getPhotoForDate(selectedKey);
    final isSelectedToday = DailyPhotoRule.isSameDay(
      _selectedDate,
      _currentDate,
    );
    final isSelectedFuture = _selectedDate.isAfter(_currentDate);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // App Header with Back action when pushed, plus Diary and Settings
        AppHeader(
          title: 'Full Calendar',
          tagline: 'ALL MONTHS & MEMORIES',
          showBackButton: true,
          onBackTap: () => Navigator.maybePop(context),
          onDiaryTap: () =>
              Navigator.pushNamed(context, AppConstants.diaryRoute),
          onSettingsTap:
              widget.onNavigateToSettings ??
              () => Navigator.pushNamed(context, AppConstants.settingsRoute),
        ),

        // Pinned Year Navigation Header (< 2025 | 2026 | 2027 >)
        _buildYearNavigationHeader(),

        // Scrollable content: Streak Card + 12-Month Calendar
        Expanded(
          child: GestureDetector(
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity != null) {
                if (details.primaryVelocity! < -200) {
                  _changeYear(1);
                } else if (details.primaryVelocity! > 200) {
                  _changeYear(-1);
                }
              }
            },
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: AppSpacing.dockClearance),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.xs),

                  // Scrollable Photo Streak Status Card
                  _buildHomeStreakStatus(),

                  const SizedBox(height: AppSpacing.sm),

                  // All 12 Months of the Selected Year (Multi-column responsive layout)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final int columns = width >= 1150
                          ? 3
                          : (width >= 700 ? 2 : 1);

                      if (columns == 1) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (int m = 1; m <= 12; m++) ...[
                              _buildMonthSection(m),
                              if (m < 12)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.pageHorizontal,
                                    vertical: AppSpacing.md,
                                  ),
                                  child: Divider(
                                    height: 1.0,
                                    thickness: 0.8,
                                    color: AppColors.border.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        );
                      }

                      final rows = <Widget>[];
                      for (int i = 0; i < 12; i += columns) {
                        final rowChildren = <Widget>[];
                        for (int c = 0; c < columns; c++) {
                          final month = i + c + 1;
                          if (month <= 12) {
                            rowChildren.add(
                              Expanded(child: _buildMonthSection(month)),
                            );
                          } else {
                            rowChildren.add(
                              const Expanded(child: SizedBox.shrink()),
                            );
                          }
                        }
                        rows.add(
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.lg,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: rowChildren,
                            ),
                          ),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: rows,
                      );
                    },
                  ),

                  const SizedBox(height: AppSpacing.md),

                  // Interactive Day Detail Preview Card
                  DayPreviewCard(
                    selectedDate: _selectedDate,
                    dayEntry: _store.getDay(
                      DateKey.fromDateTime(_selectedDate),
                    ),
                    photoEntry: selectedPhoto,
                    isToday: isSelectedToday,
                    isFuture: isSelectedFuture,
                    onActionTap: !isSelectedFuture
                        ? (selectedPhoto == null
                              ? () => _promptPhotoSource(_selectedDate)
                              : (isSelectedToday
                                    ? widget.onNavigateToToday
                                    : null))
                        : null,
                    onAddPhotoTap: !isSelectedFuture
                        ? () => _promptPhotoSource(_selectedDate)
                        : null,
                    onPhotoTap: (entry) async {
                      await Navigator.pushNamed(
                        context,
                        AppConstants.photoDetailRoute,
                        arguments: entry,
                      );
                      if (mounted) {
                        setState(() {});
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );

    if (widget.wrapWithScaffold) {
      return AppScaffold(
        currentNavIndex: 0,
        maxContentWidth: AppBreakpoints.maxContentWidth,
        onHomeTap: () => Navigator.maybePop(context),
        onCaptureTap: widget.onNavigateToToday,
        onMeTap: widget.onNavigateToProfile,
        body: content,
      );
    }

    return Material(color: AppColors.background, child: content);
  }

  Widget _buildHomeStreakStatus() {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final todayKey = DateKey.fromDateTime(_currentDate);

        final streakSummary = StreakService.instance.calculateStreak(
          store: _store,
          todayDate: _currentDate,
        );

        final statsSummary = StatisticsService.instance.calculateStatistics(
          store: _store,
          todayDate: _currentDate,
        );

        final recentPhotoDates = <DateKey>[];
        for (int i = 0; i < 14; i++) {
          final date = _currentDate.subtract(Duration(days: i));
          final dateKey = DateKey.fromDateTime(date);
          final entry = _store.getPhotoByKey(dateKey);
          if (entry != null) {
            recentPhotoDates.add(dateKey);
          }
        }

        return StreakOverviewCard(
          key: const ValueKey('home_streak_status_banner'),
          streakSummary: streakSummary,
          statisticsSummary: statsSummary,
          recentSyncedDates: recentPhotoDates,
          todayKey: todayKey,
          onTap: () {
            Navigator.pushNamed(context, AppConstants.statisticsRoute);
          },
        );
      },
    );
  }

  Widget _buildYearNavigationHeader() {
    final isCurrentYear = _selectedYear == _currentDate.year;

    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.pageHorizontal,
        right: AppSpacing.pageHorizontal,
        top: AppSpacing.sm,
        bottom: AppSpacing.xs,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                label: 'Year $_selectedYear',
                child: Text(
                  '$_selectedYear',
                  style: AppTypography.appTitle.copyWith(
                    fontSize: 22.0,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              if (isCurrentYear) ...[
                const SizedBox(width: 8.0),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 3.0,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: Text(
                    'This Year',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildChevronButton(
                icon: Icons.chevron_left_rounded,
                tooltip: 'Previous year',
                onTap: () => _changeYear(-1),
              ),
              const SizedBox(width: 4.0),
              _buildChevronButton(
                icon: Icons.chevron_right_rounded,
                tooltip: 'Next year',
                onTap: () => _changeYear(1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChevronButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: tooltip,
      button: true,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48.0, minHeight: 48.0),
            child: Center(
              child: Container(
                width: 38.0,
                height: 38.0,
                decoration: BoxDecoration(
                  color: AppColors.surfaceSubtle,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 22.0, color: AppColors.textPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMonthSection(int month) {
    final monthDate = DateTime(_selectedYear, month, 1);
    final isCurrentYear = _selectedYear == _currentDate.year;
    final isCurrentMonth = isCurrentYear && month == _currentDate.month;
    final monthTitle = _formatMonthYear(monthDate);

    return Container(
      key: _monthKeys[month - 1],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: monthTitle,
            trailing: isCurrentMonth
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 3.0,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    child: Text(
                      'Current Month',
                      style: TextStyle(
                        fontSize: 11.0,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                        letterSpacing: 0.2,
                      ),
                    ),
                  )
                : null,
          ),
          const WeekdayHeader(),
          const SizedBox(height: AppSpacing.xs),
          _buildMonthCalendarGrid(monthDate),
        ],
      ),
    );
  }

  Widget _buildMonthCalendarGrid(DateTime monthDate) {
    final daysInMonth = DateTime(monthDate.year, monthDate.month + 1, 0).day;
    final firstDayWeekday = DateTime(
      monthDate.year,
      monthDate.month,
      1,
    ).weekday;

    final leadingOffset = firstDayWeekday % 7;
    final cells = <Widget>[];

    for (int i = 0; i < leadingOffset; i++) {
      cells.add(const CalendarCell(day: 0, style: CalendarCellStyle.blank));
    }

    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(monthDate.year, monthDate.month, day);
      final dateKey = DateKey(monthDate.year, monthDate.month, day);
      final dayEntry = _store.getDay(dateKey);
      final photo = dayEntry?.primaryPhoto ?? _getPhotoForDate(dateKey);
      final photoCount = dayEntry?.photoCount ?? (photo != null ? 1 : 0);
      final hasNote = dayEntry?.hasNote ?? false;

      final isToday = DailyPhotoRule.isSameDay(date, _currentDate);
      final isSelected = DailyPhotoRule.isSameDay(date, _selectedDate);
      final showTodayPulse = isToday && (_selectedYear == _currentDate.year);

      final CalendarCellStyle cellStyle;
      if (photo != null) {
        cellStyle = CalendarCellStyle.photo;
      } else {
        cellStyle = CalendarCellStyle.empty;
      }

      const isSyncing = false;

      cells.add(
        CalendarCell(
          key: ValueKey(dateKey),
          day: day,
          style: cellStyle,
          isToday: isToday && _selectedYear == _currentDate.year,
          showTodayPulse: showTodayPulse,
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
          isSyncing: isSyncing,
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
              if (mounted) {
                setState(() {});
              }
            }
          },
        ),
      );
    }

    final totalPlaced = leadingOffset + daysInMonth;
    final trailingOffset = (7 - (totalPlaced % 7)) % 7;
    for (int i = 0; i < trailingOffset; i++) {
      cells.add(const CalendarCell(day: 0, style: CalendarCellStyle.blank));
    }

    return CalendarGrid(
      key: ValueKey('${monthDate.year}-${monthDate.month}'),
      children: cells,
    );
  }

  String _formatMonthYear(DateTime date) {
    return '${_monthNames[date.month - 1]} ${date.year}';
  }
}
