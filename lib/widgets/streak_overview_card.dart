import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/services/streak_service.dart';
import 'package:photo_per_day/data/services/statistics_service.dart';

/// A beautiful, meaningful streak overview card for the Home screen.
///
/// Displays:
/// - The current streak as a large, visually dominant number
/// - Streak state (active, ended, no synced photos, not connected)
/// - Recent week history (which days have synced photos)
/// - Supporting statistics (best streak, photo days)
/// - Calm, premium visual presentation consistent with Photo a Day
///
/// M45 Feature: Redesigned Home screen streak viewer using cloud-backed
/// streak data from M44's StreakService.
class StreakOverviewCard extends StatelessWidget {
  const StreakOverviewCard({
    super.key,
    required this.streakSummary,
    required this.statisticsSummary,
    required this.recentSyncedDates,
    required this.todayKey,
    required this.onTap,
  });

  /// The derived streak summary (never stored, always calculated).
  final StreakSummary streakSummary;

  /// The derived statistics summary (never stored, always calculated).
  final StatisticsSummary statisticsSummary;

  /// Recent synced dates to display as history (typically last 14 days).
  /// Only includes SyncStatus.synced photos for the authenticated account.
  final List<DateKey> recentSyncedDates;

  /// Today's date (local calendar).
  final DateKey todayKey;

  /// Callback when the card is tapped (navigate to Statistics or Profile).
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageHorizontal,
        vertical: 12.0,
      ),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20.0),
        child: Semantics(
          button: true,
          label: _buildSemanticLabel(),
          child: InkWell(
            borderRadius: BorderRadius.circular(20.0),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20.0),
                border: Border.all(
                  color: AppColors.border.withValues(alpha: 0.5),
                  width: 1.0,
                ),
              ),
              child: Column(
                spacing: 16.0,
                children: [
                  _buildStreakHeader(),
                  _buildRecentWeekHistory(),
                  _buildSupportingStats(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the main streak display with large number and status.
  Widget _buildStreakHeader() {
    return Column(
      spacing: 12.0,
      children: [
        // Visual accent streak indicator
        _buildStreakVisual(),

        // Large streak number
        _buildStreakNumber(),

        // Streak label and tagline
        _buildStreakStatus(),
      ],
    );
  }

  /// Builds a subtle visual accent for the streak (flame-inspired elegance).
  /// Uses Photo a Day's warm caramel/orange palette, not a literal fitness app flame.
  Widget _buildStreakVisual() {
    final accentColor = streakSummary.isCurrentStreakActive
        ? AppColors.statStreakOrange
        : AppColors.textMuted;

    return Container(
      height: 3.0,
      width: 40.0,
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(2.0),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          height: 3.0,
          width:
              40.0 *
              (streakSummary.currentStreak /
                      (streakSummary.longestStreak.toDouble() > 0
                          ? streakSummary.longestStreak.toDouble()
                          : 1))
                  .clamp(0.0, 1.0),
          decoration: BoxDecoration(
            color: accentColor,
            borderRadius: BorderRadius.circular(2.0),
          ),
        ),
      ),
    );
  }

  /// Renders the large, visually dominant current streak number.
  Widget _buildStreakNumber() {
    final isActive = streakSummary.isCurrentStreakActive;
    final int displayNumber = streakSummary.currentStreak;
    final String displayLabel = isActive ? 'CURRENT STREAK' : 'LAST STREAK';

    return Column(
      spacing: 6.0,
      children: [
        Text(
          displayNumber.toString(),
          key: const ValueKey('streak_display_number'),
          style: TextStyle(
            fontSize: 60.0,
            fontWeight: FontWeight.w300,
            color: isActive ? AppColors.textPrimary : AppColors.textMuted,
            height: 1.0,
            letterSpacing: -1.0,
          ),
        ),
        Text(
          displayLabel,
          key: const ValueKey('streak_display_label'),
          style: TextStyle(
            fontSize: 11.0,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  /// Builds the status text (tagline + icon based on local streak state).
  Widget _buildStreakStatus() {
    final String statusText;
    final IconData statusIcon;
    final Color statusColor;

    if (streakSummary.isCurrentStreakActive) {
      if (streakSummary.currentStreakEndDate == todayKey) {
        statusText = 'Keep your daily photo going.';
      } else {
        statusText = 'Take a photo today to stay consistent.';
      }
      statusIcon = Icons.local_fire_department_rounded;
      statusColor = AppColors.statStreakOrange;
    } else {
      statusText = 'Start a new streak by taking a photo today.';
      statusIcon = Icons.history_rounded;
      statusColor = AppColors.textMuted;
    }

    return Row(
      spacing: 8.0,
      children: [
        Icon(statusIcon, size: 16.0, color: statusColor),
        Expanded(
          child: Text(
            statusText,
            key: const ValueKey('streak_status_text'),
            style: TextStyle(
              fontSize: 12.0,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  /// Displays the recent week's history: which days have synced photos.
  /// Only shows SyncStatus.synced photos—local-only and pending do not appear.
  Widget _buildRecentWeekHistory() {
    // Build last 7 days (today going backward)
    final dayHistory = <DateKey, bool>{};
    for (int i = 0; i < 7; i++) {
      final date = todayKey.previousDay;
      final dayKey = DateKey(date.year, date.month, date.day - i);
      dayHistory[dayKey] = recentSyncedDates.contains(dayKey);
    }

    final weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Column(
      spacing: 8.0,
      children: [
        // Header
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'This Week',
            style: TextStyle(
              fontSize: 11.0,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
        ),
        // Day grid
        Row(
          spacing: 6.0,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(7, (index) {
            // Calculate which date this represents (from 7 days ago to today)
            final daysFromToday = 6 - index;
            final date = todayKey;

            // Adjust for month/year boundaries
            final dateTime = DateTime(
              date.year,
              date.month,
              date.day,
            ).subtract(Duration(days: daysFromToday));
            final adjustedKey = DateKey(
              dateTime.year,
              dateTime.month,
              dateTime.day,
            );

            final hasSyncedPhoto = recentSyncedDates.contains(adjustedKey);
            final isToday = adjustedKey == todayKey;
            final isYesterday = adjustedKey == todayKey.previousDay;

            return Expanded(
              child: Semantics(
                label:
                    '${weekDays[dateTime.weekday - 1]} ${adjustedKey.format()}: ${hasSyncedPhoto ? 'Photo synced' : 'No photo'}',
                child: Container(
                  height: 32.0,
                  decoration: BoxDecoration(
                    color: hasSyncedPhoto
                        ? AppColors.statStreakOrange.withValues(alpha: 0.15)
                        : AppColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(6.0),
                    border: Border.all(
                      color: isToday
                          ? AppColors.statStreakOrange.withValues(alpha: 0.4)
                          : isYesterday
                          ? AppColors.accent.withValues(alpha: 0.3)
                          : Colors.transparent,
                      width: isToday || isYesterday ? 1.0 : 0.0,
                    ),
                  ),
                  child: Center(
                    child: hasSyncedPhoto
                        ? Icon(
                            Icons.check_rounded,
                            size: 16.0,
                            color: AppColors.statStreakOrange,
                          )
                        : Text(
                            weekDays[dateTime.weekday - 1].substring(0, 1),
                            style: TextStyle(
                              fontSize: 10.0,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMuted,
                            ),
                          ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  /// Displays supporting statistics: best streak, total photo days.
  /// These are derived from StatisticsService (never stored).
  Widget _buildSupportingStats() {
    return Row(
      spacing: 12.0,
      children: [
        // Best streak stat
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 10.0,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(10.0),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: Column(
              spacing: 4.0,
              children: [
                Text(
                  'Best',
                  style: TextStyle(
                    fontSize: 9.0,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                    letterSpacing: 0.2,
                  ),
                ),
                Text(
                  '${streakSummary.longestStreak}',
                  style: TextStyle(
                    fontSize: 16.0,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'days',
                  style: TextStyle(
                    fontSize: 8.0,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Total photo days stat
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 10.0,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(10.0),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: Column(
              spacing: 4.0,
              children: [
                Text(
                  'Photo Days',
                  style: TextStyle(
                    fontSize: 9.0,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                    letterSpacing: 0.2,
                  ),
                ),
                Text(
                  '${statisticsSummary.totalRecordedDays}',
                  style: TextStyle(
                    fontSize: 16.0,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'days',
                  style: TextStyle(
                    fontSize: 8.0,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Streak count stat (number of separate streaks)
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 10.0,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(10.0),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: Column(
              spacing: 4.0,
              children: [
                Text(
                  'Streaks',
                  style: TextStyle(
                    fontSize: 9.0,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                    letterSpacing: 0.2,
                  ),
                ),
                Text(
                  '${streakSummary.streakCount}',
                  style: TextStyle(
                    fontSize: 16.0,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'total',
                  style: TextStyle(
                    fontSize: 8.0,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Builds the semantic label for screen readers.
  String _buildSemanticLabel() {
    final isActive = streakSummary.isCurrentStreakActive;
    final streakText = streakSummary.currentStreak == 1
        ? '1 day streak'
        : '${streakSummary.currentStreak} day streak';
    final statusText = isActive ? 'Active' : 'Ended';
    final bestText = streakSummary.longestStreak == 1
        ? '1 day best'
        : '${streakSummary.longestStreak} day best';
    final photoDaysText = streakSummary.totalSynchronizedDays == 1
        ? '1 photo day'
        : '${streakSummary.totalSynchronizedDays} photo days';

    return '$statusText $streakText. $bestText. $photoDaysText. Tap to view full statistics.';
  }
}
