import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_shadows.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/statistics_service.dart';
import 'package:photo_per_day/screens/camera/camera_screen.dart';
import 'package:photo_per_day/services/gallery_photo_service.dart';
import 'package:photo_per_day/widgets/photo_source_sheet.dart';

/// Dedicated Statistics screen that summarizes the user's real Photo a Day history.
///
/// Principles:
/// - Authoritative source: [PersistentDailyPhotoStore].
/// - Pure/read-only, derived data with zero disk/network queries on build.
/// - Calm personal diary tone, avoiding gamification, leaderboards, or points.
/// - Live updates when photos are added, replaced, or deleted.
/// - Clean empty state without fake/mock statistics.
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({
    super.key,
    this.store,
    this.todayKey,
    this.onCaptureTap,
  });

  /// Injected photo store (defaults to [PersistentDailyPhotoStore.instance]).
  final PersistentDailyPhotoStore? store;

  /// Optional injected reference date for deterministic testing.
  final DateKey? todayKey;

  /// Optional capture tap handler for testing.
  final VoidCallback? onCaptureTap;

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  final GalleryPhotoService _galleryPhotoService = GalleryPhotoService();

  PersistentDailyPhotoStore get _store =>
      widget.store ?? PersistentDailyPhotoStore.instance;

  DateKey get _effectiveTodayKey => widget.todayKey ?? DateKey.today();

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
    return ListenableBuilder(
      listenable: Listenable.merge([_store, AppThemeService.instance]),
      builder: (context, _) {
        final summary = StatisticsService.instance.calculateStatistics(
          store: _store,
          todayKey: _effectiveTodayKey,
        );
        final isDark = AppColors.current.isDark;

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isDark
                ? Brightness.light
                : Brightness.dark,
            statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          ),
          child: Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pageHorizontal,
                  AppSpacing.sm,
                  AppSpacing.pageHorizontal,
                  AppSpacing.dockClearanceExtended,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: AppSpacing.md),

                    if (!summary.hasPhotos) ...[
                      _buildEmptyStateCta(),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    _buildOverviewCard(summary),
                    const SizedBox(height: AppSpacing.md),

                    _buildStreakInsightsCard(summary),
                    const SizedBox(height: AppSpacing.md),

                    _buildMilestonesCard(summary),
                    const SizedBox(height: AppSpacing.md),

                    _buildTimeBreakdownCard(summary),
                    const SizedBox(height: AppSpacing.md),

                    _buildMonthlyActivityCard(summary),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// App bar header matching the design system
  Widget _buildHeader() {
    return Row(
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
              Text('Statistics', style: AppTypography.appTitle),
              const SizedBox(height: 2.0),
              Text('YOUR PHOTO JOURNEY', style: AppTypography.appTagline),
            ],
          ),
        ),
      ],
    );
  }

  /// Calm CTA banner shown when no photos are recorded yet
  Widget _buildEmptyStateCta() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          Container(
            width: 44.0,
            height: 44.0,
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border, width: 0.8),
            ),
            child: Icon(
              Icons.auto_stories_outlined,
              color: AppColors.accent,
              size: 22.0,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Begin your Daria journey',
            style: TextStyle(
              fontSize: 15.0,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4.0),
          Text(
            'Capture your first daily photo to start tracking streaks and memories.',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w400,
              color: AppColors.textMuted,
              height: 1.35,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          ElevatedButton.icon(
            onPressed: _promptPhotoCapture,
            icon: const Icon(Icons.camera_alt_outlined, size: 16.0),
            label: const Text("Capture Today's Photo"),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryButtonBackground,
              foregroundColor: AppColors.primaryButtonForeground,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 10.0,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              textStyle: const TextStyle(
                fontSize: 13.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 4-metric core summary card (Total Photos, Recorded Days, Current Streak, Longest Streak)
  Widget _buildOverviewCard(StatisticsSummary summary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('OVERVIEW', style: AppTypography.appTagline),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  key: const Key('stat_total_photos'),
                  value: '${summary.totalPhotos}',
                  label: 'Total Photos',
                  icon: Icons.photo_library_outlined,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _buildMetricTile(
                  key: const Key('stat_recorded_days'),
                  value: '${summary.totalRecordedDays}',
                  label: 'Recorded Days',
                  icon: Icons.calendar_today_outlined,
                  color: AppColors.statDaysGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  key: const Key('stat_current_streak'),
                  value: summary.currentStreak == 1
                      ? '1 day'
                      : '${summary.currentStreak} days',
                  label: 'Current Streak',
                  icon: Icons.local_fire_department_rounded,
                  color: summary.currentStreak > 0
                      ? AppColors.statStreakOrange
                      : AppColors.textMuted,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _buildMetricTile(
                  key: const Key('stat_longest_streak'),
                  value: summary.longestStreak == 1
                      ? '1 day'
                      : '${summary.longestStreak} days',
                  label: 'Longest Streak',
                  icon: Icons.trending_up_rounded,
                  color: summary.longestStreak > 0
                      ? AppColors.accent
                      : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Single metric tile container
  Widget _buildMetricTile({
    Key? key,
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 10.0),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16.0, color: color),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 6.0),
          Text(
            value,
            style: TextStyle(
              fontSize: 18.0,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2.0),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  /// Streak insights card (Completed Streaks, Average Streak, Longest Gap, Most Active Month)
  Widget _buildStreakInsightsCard(StatisticsSummary summary) {
    const monthNames = [
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
    final activeMonthText = summary.mostActiveMonth != null
        ? '${monthNames[summary.mostActiveMonth! - 1]} (${summary.mostActiveMonthCount})'
        : 'None';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('STREAK INSIGHTS', style: AppTypography.appTagline),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  key: const Key('stat_ended_streaks'),
                  value: '${summary.endedStreakCount}',
                  label: 'Ended Streaks',
                  icon: Icons.check_circle_outline_rounded,
                  color: AppColors.statDaysGreen,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _buildMetricTile(
                  key: const Key('stat_avg_streak'),
                  value: summary.averageStreakLength > 0
                      ? '${summary.averageStreakLength} d'
                      : '0 d',
                  label: 'Average Run',
                  icon: Icons.timeline_rounded,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  key: const Key('stat_longest_gap'),
                  value: summary.longestGapDays == 1
                      ? '1 day'
                      : '${summary.longestGapDays} days',
                  label: 'Longest Gap',
                  icon: Icons.space_bar_rounded,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _buildMetricTile(
                  key: const Key('stat_active_month'),
                  value: activeMonthText,
                  label: 'Peak Month',
                  icon: Icons.star_border_rounded,
                  color: AppColors.statStreakOrange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// First Photo and Latest Photo milestone card
  Widget _buildMilestonesCard(StatisticsSummary summary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('JOURNEY MILESTONES', style: AppTypography.appTagline),
          const SizedBox(height: AppSpacing.sm),
          _buildMilestoneRow(
            label: 'First Photo',
            dateText: StatisticsSummary.formatDate(summary.firstPhotoDate),
            icon: Icons.flight_takeoff_rounded,
            iconColor: AppColors.statIconBrown,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Divider(color: AppColors.borderSubtle, height: 1.0),
          ),
          _buildMilestoneRow(
            label: 'Latest Photo',
            dateText: StatisticsSummary.formatDate(summary.latestPhotoDate),
            icon: Icons.bookmark_added_outlined,
            iconColor: AppColors.statDaysGreen,
          ),
        ],
      ),
    );
  }

  Widget _buildMilestoneRow({
    required String label,
    required String dateText,
    required IconData icon,
    required Color iconColor,
  }) {
    return Row(
      children: [
        Container(
          width: 36.0,
          height: 36.0,
          decoration: BoxDecoration(
            color: AppColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(color: AppColors.border, width: 0.6),
          ),
          child: Icon(icon, size: 18.0, color: iconColor),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 2.0),
              Text(
                dateText,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Time breakdown (This Month and This Year) card
  Widget _buildTimeBreakdownCard(StatisticsSummary summary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TIME BREAKDOWN', style: AppTypography.appTagline),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    border: Border.all(color: AppColors.border, width: 0.6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'THIS MONTH',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 4.0),
                      Text(
                        summary.currentMonthCount == 1
                            ? '1 photo'
                            : '${summary.currentMonthCount} photos',
                        style: TextStyle(
                          fontSize: 16.0,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    border: Border.all(color: AppColors.border, width: 0.6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'THIS YEAR',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 4.0),
                      Text(
                        summary.currentYearCount == 1
                            ? '1 photo'
                            : '${summary.currentYearCount} photos',
                        style: TextStyle(
                          fontSize: 16.0,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Lightweight monthly activity breakdown for the current year
  Widget _buildMonthlyActivityCard(StatisticsSummary summary) {
    const monthNames = [
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

    final year = _effectiveTodayKey.year;

    // Find maximum days in any month to scale the bars (max 31)
    const maxDays = 31;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('MONTHLY ACTIVITY ($year)', style: AppTypography.appTagline),
              Text(
                '${summary.currentYearCount} total',
                style: TextStyle(
                  fontSize: 11.0,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (int m = 1; m <= 12; m++) ...[
            _buildMonthActivityRow(
              monthName: monthNames[m - 1],
              count: summary.monthlyCountsForCurrentYear[m] ?? 0,
              maxDays: maxDays,
              isCurrentMonth: m == _effectiveTodayKey.month,
              isFutureMonth: m > _effectiveTodayKey.month,
            ),
            if (m < 12) const SizedBox(height: 6.0),
          ],
        ],
      ),
    );
  }

  Widget _buildMonthActivityRow({
    required String monthName,
    required int count,
    required int maxDays,
    required bool isCurrentMonth,
    required bool isFutureMonth,
  }) {
    final fillRatio = (count / maxDays).clamp(0.0, 1.0);

    return Row(
      children: [
        SizedBox(
          width: 32.0,
          child: Text(
            monthName,
            style: TextStyle(
              fontSize: 12.0,
              fontWeight: isCurrentMonth ? FontWeight.w700 : FontWeight.w500,
              color: isFutureMonth
                  ? AppColors.textMuted.withValues(alpha: 0.6)
                  : (isCurrentMonth
                        ? AppColors.accent
                        : AppColors.textSecondary),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Container(
            height: 10.0,
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(5.0),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fillRatio > 0 ? fillRatio : 0.0,
              child: Container(
                decoration: BoxDecoration(
                  color: isCurrentMonth
                      ? AppColors.accent
                      : (count > 0
                            ? AppColors.statDaysGreen
                            : Colors.transparent),
                  borderRadius: BorderRadius.circular(5.0),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 24.0,
          child: Text(
            '$count',
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: count > 0 ? FontWeight.w700 : FontWeight.w500,
              color: count > 0 ? AppColors.textPrimary : AppColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}
