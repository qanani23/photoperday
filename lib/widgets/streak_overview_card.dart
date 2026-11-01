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
        borderRadius: BorderRadius.circular(24.0),
        child: Semantics(
          button: true,
          label: _buildSemanticLabel(),
          child: InkWell(
            borderRadius: BorderRadius.circular(24.0),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 20.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24.0),
                border: Border.all(
                  color: AppColors.border.withValues(alpha: 0.6),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 16.0,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 500;
                  return Column(
                    children: [
                      _buildStreakHeader(isWide: isWide),
                      const SizedBox(height: 20.0),
                      _buildRecentWeekHistory(isWide: isWide),
                      const SizedBox(height: 16.0),
                      _buildSupportingStats(),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the main streak display with top accent handle, vibrant burning flame,
  /// thick prominent number, uppercase label, and centered motivational tagline.
  Widget _buildStreakHeader({required bool isWide}) {
    final isActive = streakSummary.isCurrentStreakActive;
    final int displayNumber = streakSummary.currentStreak;
    final String displayLabel = isActive ? 'CURRENT STREAK' : 'LAST STREAK';

    final String statusText;
    if (isActive) {
      if (streakSummary.currentStreakEndDate == todayKey) {
        statusText = 'Keep your daily photo going.';
      } else {
        statusText = 'Take a photo today to stay consistent.';
      }
    } else {
      statusText = 'Start a new streak by taking a photo today.';
    }

    return Column(
      children: [
        // Top accent grab handle / indicator from reference design
        Container(
          key: const ValueKey('streak_card_handle'),
          width: 44.0,
          height: 4.5,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(2.5),
          ),
        ),

        const SizedBox(height: 14.0),

        // Prominent, radiant burning flame logo
        _buildBurningFlame(isActive: isActive),

        const SizedBox(height: 6.0),

        // Thick, prominent streak number
        Text(
          displayNumber.toString(),
          key: const ValueKey('streak_display_number'),
          style: TextStyle(
            fontSize: isWide ? 68.0 : 60.0,
            fontWeight: FontWeight.w900,
            color: isActive ? AppColors.textPrimary : AppColors.textMuted,
            height: 1.05,
            letterSpacing: -1.5,
          ),
        ),

        const SizedBox(height: 6.0),

        // Uppercase, letter-spaced label
        Text(
          displayLabel,
          key: const ValueKey('streak_display_label'),
          style: TextStyle(
            fontSize: 12.0,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary.withValues(alpha: 0.8),
            letterSpacing: 1.4,
          ),
        ),

        const SizedBox(height: 12.0),

        // Centered sparkle + status text
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('✨', style: TextStyle(fontSize: 15.0)),
            const SizedBox(width: 6.0),
            Flexible(
              child: Text(
                statusText,
                key: const ValueKey('streak_status_text'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Builds a prominent, radiant burning flame logo with ambient warmth
  /// and rich multi-stop gradient fire colors.
  Widget _buildBurningFlame({required bool isActive}) {
    if (!isActive) {
      return Container(
        key: const ValueKey('streak_burning_flame'),
        width: 48.0,
        height: 48.0,
        alignment: Alignment.center,
        child: Icon(
          Icons.local_fire_department_rounded,
          size: 44.0,
          color: AppColors.textMuted.withValues(alpha: 0.5),
        ),
      );
    }

    return Container(
      key: const ValueKey('streak_burning_flame'),
      width: 54.0,
      height: 54.0,
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft ambient warm glow behind the burning flame
          Container(
            width: 38.0,
            height: 38.0,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF5722).withValues(alpha: 0.35),
                  blurRadius: 22.0,
                  spreadRadius: 4.0,
                ),
              ],
            ),
          ),

          // Radiant multi-stop gradient fire icon with bright white-yellow inner core and deep red flame tips
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Color(0xFFFFFDE7), // Luminous warm white-yellow core
                Color(0xFFFFEE58), // Radiant core yellow
                Color(0xFFFF9800), // Vibrant orange flame
                Color(0xFFFF3D00), // Intense fiery red-orange
                Color(0xFFD50000), // Deep burning red tips
              ],
              stops: [0.0, 0.22, 0.52, 0.78, 1.0],
            ).createShader(bounds),
            child: const Icon(
              Icons.local_fire_department_rounded,
              size: 48.0,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Displays the recent week's history: which days have synced photos.
  /// Only shows SyncStatus.synced photos—local-only and pending do not appear.
  Widget _buildRecentWeekHistory({required bool isWide}) {
    final weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Text(
          'This Week',
          style: TextStyle(
            fontSize: 13.0,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 10.0),
        // Day capsules
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(7, (index) {
            // Calculate which date this represents (from 6 days ago up to today)
            final daysFromToday = 6 - index;
            final date = todayKey;

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
            final weekdayInitial = weekDays[dateTime.weekday - 1].substring(
              0,
              1,
            );

            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: index < 6 ? (isWide ? 8.0 : 6.0) : 0.0,
                ),
                child: Semantics(
                  label:
                      '${weekDays[dateTime.weekday - 1]} ${adjustedKey.format()}: ${hasSyncedPhoto ? 'Photo synced' : 'No photo'}',
                  child: Container(
                    height: isWide ? 48.0 : 44.0,
                    decoration: BoxDecoration(
                      color: hasSyncedPhoto
                          ? AppColors.accent.withValues(alpha: 0.16)
                          : AppColors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(12.0),
                      border: Border.all(
                        color: hasSyncedPhoto
                            ? AppColors.accent.withValues(alpha: 0.42)
                            : AppColors.border.withValues(alpha: 0.25),
                        width: hasSyncedPhoto ? 1.2 : 0.8,
                      ),
                    ),
                    child: Center(
                      child: hasSyncedPhoto
                          ? Icon(
                              Icons.check_rounded,
                              size: 22.0,
                              color: AppColors.accent,
                            )
                          : Text(
                              weekdayInitial,
                              style: TextStyle(
                                fontSize: 13.0,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textMuted,
                              ),
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
      children: [
        // Best streak stat
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14.0,
              vertical: 12.0,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(14.0),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.4),
                width: 0.8,
              ),
            ),
            child: Column(
              children: [
                Text(
                  'Best',
                  style: TextStyle(
                    fontSize: 11.0,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2.0),
                Text(
                  '${streakSummary.longestStreak}',
                  style: TextStyle(
                    fontSize: 18.0,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'days',
                  style: TextStyle(
                    fontSize: 10.0,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 12.0),

        // Total photo days stat
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10.0,
              vertical: 10.0,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(14.0),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.4),
                width: 0.8,
              ),
            ),
            child: Column(
              children: [
                Text(
                  'Photo Days',
                  style: TextStyle(
                    fontSize: 11.0,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2.0),
                Text(
                  '${statisticsSummary.totalRecordedDays}',
                  style: TextStyle(
                    fontSize: 17.0,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'days',
                  style: TextStyle(
                    fontSize: 10.0,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 8.0),

        // Streak count stat (number of separate streaks)
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10.0,
              vertical: 10.0,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(14.0),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.4),
                width: 0.8,
              ),
            ),
            child: Column(
              children: [
                Text(
                  'Streaks',
                  style: TextStyle(
                    fontSize: 11.0,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2.0),
                Text(
                  '${streakSummary.streakCount}',
                  style: TextStyle(
                    fontSize: 17.0,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'total',
                  style: TextStyle(
                    fontSize: 10.0,
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
