import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/daily_photo_rule.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/mock_photo_service.dart';
import 'package:photo_per_day/screens/camera/camera_screen.dart';
import 'package:photo_per_day/services/gallery_photo_service.dart';
import 'package:photo_per_day/widgets/app_header.dart';
import 'package:photo_per_day/widgets/app_scaffold.dart';
import 'package:photo_per_day/widgets/calendar_cell.dart';
import 'package:photo_per_day/widgets/calendar_grid.dart';
import 'package:photo_per_day/widgets/day_preview_card.dart';
import 'package:photo_per_day/widgets/photo_source_sheet.dart';
import 'package:photo_per_day/widgets/section_header.dart';
import 'package:photo_per_day/widgets/weekday_header.dart';

/// Primary Calendar Screen for Photo a Day.
///
/// Implements full 7-column calendar logic, month navigation, weekday indicators,
/// dynamic mock photos, interactive date selection, and day preview card.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.wrapWithScaffold = true,
    this.onNavigateToToday,
    this.onNavigateToProfile,
  });

  final bool wrapWithScaffold;
  final VoidCallback? onNavigateToToday;
  final VoidCallback? onNavigateToProfile;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GalleryPhotoService _galleryPhotoService = GalleryPhotoService();

  /// Reference "today" date matching the visual reference (March 15, 2026)
  final DateTime _today = DateTime(2026, 3, 15);

  /// The month currently shown in the active calendar grid
  late DateTime _displayedMonth;

  /// The date currently selected by the user
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _displayedMonth = DateTime(_today.year, _today.month);
    _selectedDate = DateTime(2026, 3, 3); // Showcase photo preview initially
    PersistentDailyPhotoStore.instance.addListener(_onPhotoStoreUpdated);
  }

  void _onPhotoStoreUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    PersistentDailyPhotoStore.instance.removeListener(_onPhotoStoreUpdated);
    super.dispose();
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

      final newEntry = PhotoEntry(
        date: _today,
        title: 'Daily Capture',
        caption: 'Captured moment from today.',
        location: source == PhotoSource.camera
            ? 'Camera Capture'
            : 'Photo Library',
        timeFormatted: formattedTime,
        gradientColors: const [AppColors.accent, AppColors.surfaceDark],
      );

      try {
        await PersistentDailyPhotoStore.instance.savePhoto(
          entry: newEntry,
          sourceTempPath: capturedPath,
        );

        if (mounted) {
          setState(() {
            _selectedDate = _today;
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
        debugPrint('Failed to save photo from home screen: $e');
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

  void _changeMonth(int delta) {
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + delta,
      );
      // If the selected date is not in the newly selected month, select the 1st of that month
      if (_selectedDate.year != _displayedMonth.year ||
          _selectedDate.month != _displayedMonth.month) {
        _selectedDate = DateTime(
          _displayedMonth.year,
          _displayedMonth.month,
          1,
        );
      }
    });
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return DailyPhotoRule.isSameDay(a, b);
  }

  @override
  Widget build(BuildContext context) {
    final photoService = MockPhotoService.instance;
    final selectedPhoto =
        PersistentDailyPhotoStore.instance.getPhoto(_selectedDate) ??
        photoService.getPhoto(_selectedDate);
    final isSelectedToday = _isSameDay(_selectedDate, _today);
    final isSelectedFuture = _selectedDate.isAfter(_today);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Pinned App Header matching the reference design
        AppHeader(onMeTap: widget.onNavigateToProfile),

        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: AppSpacing.dockClearance),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.xs),

                // Active Month Header with Month Navigation Chevrons
                SectionHeader(
                  title: _formatMonthYear(_displayedMonth),
                  onPrevious: () => _changeMonth(-1),
                  onNext: () => _changeMonth(1),
                ),

                // 7-Column Weekday Header
                const WeekdayHeader(),

                const SizedBox(height: AppSpacing.xs),

                // 7-Column Calendar Grid with Swipe Navigation
                GestureDetector(
                  onHorizontalDragEnd: (details) {
                    if (details.primaryVelocity != null) {
                      if (details.primaryVelocity! < -200) {
                        _changeMonth(1);
                      } else if (details.primaryVelocity! > 200) {
                        _changeMonth(-1);
                      }
                    }
                  },
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _buildMonthCalendarGrid(_displayedMonth),
                  ),
                ),

                // Interactive Day Detail Preview Card
                DayPreviewCard(
                  selectedDate: _selectedDate,
                  photoEntry: selectedPhoto,
                  isToday: isSelectedToday,
                  isFuture: isSelectedFuture,
                  onActionTap: isSelectedToday
                      ? (selectedPhoto == null
                            ? _promptPhotoSource
                            : widget.onNavigateToToday)
                      : null,
                  onPhotoTap: (entry) {
                    Navigator.pushNamed(
                      context,
                      AppConstants.photoDetailRoute,
                      arguments:
                          PersistentDailyPhotoStore.instance.getPhoto(
                            _selectedDate,
                          ) ??
                          entry,
                    );
                  },
                ),

                const SizedBox(height: AppSpacing.md),

                // Archived Previous Month (February 2026) as seen in reference
                if (_displayedMonth.month == 3 &&
                    _displayedMonth.year == 2026) ...[
                  const SectionHeader(title: 'February 2026'),
                  _buildArchiveFebruaryGrid(),
                ],
              ],
            ),
          ),
        ),
      ],
    );

    if (widget.wrapWithScaffold) {
      return AppScaffold(
        currentNavIndex: 0,
        onCaptureTap: widget.onNavigateToToday,
        body: content,
      );
    }

    return content;
  }

  /// Builds the dynamic 7-column calendar grid for any given month/year
  Widget _buildMonthCalendarGrid(DateTime monthDate) {
    final daysInMonth = DateTime(monthDate.year, monthDate.month + 1, 0).day;
    final firstDayWeekday = DateTime(
      monthDate.year,
      monthDate.month,
      1,
    ).weekday;

    // Sunday-first alignment: Sunday = 0, Monday = 1, ..., Saturday = 6
    final leadingOffset = firstDayWeekday % 7;

    final cells = <Widget>[];

    // Leading empty/blank spacers for alignment
    for (int i = 0; i < leadingOffset; i++) {
      cells.add(const CalendarCell(day: 0, style: CalendarCellStyle.blank));
    }

    final photoService = MockPhotoService.instance;

    // Days in current month
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(monthDate.year, monthDate.month, day);
      final photo =
          PersistentDailyPhotoStore.instance.getPhoto(date) ??
          photoService.getPhoto(date);
      final isToday = _isSameDay(date, _today);
      final isSelected = _isSameDay(date, _selectedDate);

      final CalendarCellStyle cellStyle;
      if (photo != null) {
        cellStyle = CalendarCellStyle.photo;
      } else if (isToday) {
        cellStyle = CalendarCellStyle.today;
      } else {
        cellStyle = CalendarCellStyle.empty;
      }

      cells.add(
        CalendarCell(
          day: day,
          style: cellStyle,
          imageProvider:
              (photo?.hasRealImage == true &&
                  photo?.isImageFileAvailable == true)
              ? FileImage(File(photo!.imagePath!))
              : null,
          gradientColors: photo?.gradientColors,
          photoIcon: photo?.icon,
          isSelected: isSelected,
          onTap: () {
            setState(() {
              _selectedDate = date;
            });
          },
        ),
      );
    }

    // Trailing blank spacers to complete the row
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

  /// Archived February 2026 display matching reference design
  Widget _buildArchiveFebruaryGrid() {
    final photoService = MockPhotoService.instance;
    final cells = <Widget>[];

    for (int day = 1; day <= 28; day++) {
      final date = DateTime(2026, 2, day);
      final photo = photoService.getPhoto(date);
      final isSelected = _isSameDay(date, _selectedDate);

      cells.add(
        CalendarCell(
          day: day,
          style: CalendarCellStyle.photo,
          gradientColors: photo?.gradientColors,
          isSelected: isSelected,
          onTap: () {
            setState(() {
              _selectedDate = date;
            });
          },
        ),
      );
    }

    return CalendarGrid(children: cells);
  }

  String _formatMonthYear(DateTime date) {
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
    return '${months[date.month - 1]} ${date.year}';
  }
}
