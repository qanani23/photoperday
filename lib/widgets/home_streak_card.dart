import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_shadows.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/services/streak_service.dart';

/// A compact, elegant streak status card designed for the Home screen.
///
/// Positioned between the compact current-month calendar card and the Memories timeline,
/// this card provides an immediate summary of the user's daily photo habit:
/// - Current streak count and all-time best streak
/// - Active vs. inactive visual status with a refined flame icon
/// - Contextual motivational copy based on today's capture status
/// - Subtle progress bar toward best streak / next habit milestone
/// - Responsive adaptation across desktop and mobile screens
class HomeStreakCard extends StatelessWidget {
  const HomeStreakCard({
    super.key,
    required this.streakSummary,
    required this.todayKey,
    this.onTap,
  });

  /// Algorithmic streak summary from [StreakService].
  final StreakSummary streakSummary;

  /// Local date key representing today.
  final DateKey todayKey;

  /// Optional tap callback to inspect statistics or calendar.
  final VoidCallback? onTap;

  /// Whether the user has recorded a photo for today.
  bool get hasPhotoToday =>
      streakSummary.isCurrentStreakActive &&
      streakSummary.currentStreakEndDate == todayKey;

  /// Contextual motivational message.
  String get motivationalMessage {
    if (streakSummary.isCurrentStreakActive) {
      if (hasPhotoToday) {
        return 'Streak active! Great job capturing today.';
      } else {
        return "Take today's photo to keep your streak going!";
      }
    }
    return 'Start a new streak today with a single photo.';
  }

  /// Calculates progress toward longest streak or next milestone.
  double get progressRatio {
    if (streakSummary.longestStreak <= 0) {
      return streakSummary.currentStreak > 0 ? 1.0 : 0.0;
    }
    return (streakSummary.currentStreak / streakSummary.longestStreak).clamp(
      0.0,
      1.0,
    );
  }

  /// Next milestone recommendation.
  String get milestoneLabel {
    final current = streakSummary.currentStreak;
    if (current < 3) return 'Goal: 3 days';
    if (current < 7) return 'Goal: 7 days';
    if (current < 14) return 'Goal: 14 days';
    if (current < 30) return 'Goal: 30 days';
    if (current < 60) return 'Goal: 60 days';
    if (current < 100) return 'Goal: 100 days';
    if (current < 365) return 'Goal: 365 days';
    return 'Milestone Achieved!';
  }

  @override
  Widget build(BuildContext context) {
    final isActive = streakSummary.isCurrentStreakActive;
    final flameColor = isActive ? AppColors.accent : AppColors.textMuted;
    final flameBgColor = isActive
        ? AppColors.accent.withValues(alpha: 0.12)
        : AppColors.surfaceSubtle;

    return Semantics(
      button: onTap != null,
      label:
          'Streak Overview. Current streak: ${streakSummary.currentStreak} days. Best streak: ${streakSummary.longestStreak} days. $motivationalMessage',
      child: Material(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        elevation: 0,
        child: InkWell(
          key: const ValueKey('home_streak_card'),
          borderRadius: AppRadii.card,
          onTap: onTap,
          child: Container(
            key: const ValueKey('home_streak_status_banner'),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2.0,
            ),
            decoration: BoxDecoration(
              borderRadius: AppRadii.card,
              border: Border.all(color: AppColors.border, width: 1.0),
              boxShadow: AppShadows.card,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 520;
                return isWide
                    ? _buildWideLayout(
                        context,
                        isActive: isActive,
                        flameColor: flameColor,
                        flameBgColor: flameBgColor,
                      )
                    : _buildCompactLayout(
                        context,
                        isActive: isActive,
                        flameColor: flameColor,
                        flameBgColor: flameBgColor,
                      );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Horizontal layout for desktop and tablet screens (> 520px).
  Widget _buildWideLayout(
    BuildContext context, {
    required bool isActive,
    required Color flameColor,
    required Color flameBgColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Flame Icon Badge
        _buildFlameIcon(flameColor: flameColor, flameBgColor: flameBgColor),

        const SizedBox(width: AppSpacing.md),

        // Current Streak Number & Label
        _buildCurrentStreakBlock(isActive: isActive),

        const SizedBox(width: AppSpacing.lg),

        // Divider
        Container(
          height: 36.0,
          width: 1.0,
          color: AppColors.border.withValues(alpha: 0.7),
        ),

        const SizedBox(width: AppSpacing.lg),

        // Motivational Message & Progress Bar
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                motivationalMessage,
                key: const ValueKey('home_streak_message'),
                style: TextStyle(
                  fontSize: 13.0,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6.0),
              _buildProgressBar(),
            ],
          ),
        ),

        const SizedBox(width: AppSpacing.lg),

        // Best Streak Stat Pill
        _buildBestStreakPill(),
      ],
    );
  }

  /// Compact 2-row layout for mobile screens (<= 520px).
  Widget _buildCompactLayout(
    BuildContext context, {
    required bool isActive,
    required Color flameColor,
    required Color flameBgColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Top Row: Flame + Current Streak + Best Streak Pill
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildFlameIcon(flameColor: flameColor, flameBgColor: flameBgColor),
            const SizedBox(width: AppSpacing.sm + 2.0),
            Expanded(child: _buildCurrentStreakBlock(isActive: isActive)),
            _buildBestStreakPill(),
          ],
        ),

        const SizedBox(height: AppSpacing.sm),

        // Motivational Message
        Text(
          motivationalMessage,
          key: const ValueKey('home_streak_message'),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
            height: 1.3,
          ),
        ),

        const SizedBox(height: AppSpacing.xs + 2.0),

        // Progress Bar
        _buildProgressBar(),
      ],
    );
  }

  /// Visual flame icon indicator.
  Widget _buildFlameIcon({
    required Color flameColor,
    required Color flameBgColor,
  }) {
    if (!streakSummary.isCurrentStreakActive) {
      return Container(
        key: const ValueKey('home_streak_flame_icon'),
        width: 44.0,
        height: 44.0,
        decoration: BoxDecoration(
          color: flameBgColor,
          borderRadius: BorderRadius.circular(14.0),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.local_fire_department_rounded,
          size: 26.0,
          color: flameColor,
        ),
      );
    }

    return Container(
      key: const ValueKey('home_streak_flame_icon'),
      width: 44.0,
      height: 44.0,
      decoration: BoxDecoration(
        color: flameBgColor,
        borderRadius: BorderRadius.circular(14.0),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF5722).withValues(alpha: 0.22),
            blurRadius: 12.0,
            spreadRadius: 1.0,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Color(0xFFFFFDE7),
            Color(0xFFFFEE58),
            Color(0xFFFF9800),
            Color(0xFFFF3D00),
            Color(0xFFD50000),
          ],
          stops: [0.0, 0.22, 0.52, 0.78, 1.0],
        ).createShader(bounds),
        child: const Icon(
          Icons.local_fire_department_rounded,
          size: 28.0,
          color: Colors.white,
        ),
      ),
    );
  }

  /// Block with the dominant streak number and uppercase label.
  Widget _buildCurrentStreakBlock({required bool isActive}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          streakSummary.currentStreak.toString(),
          key: const ValueKey('streak_display_number'),
          style: TextStyle(
            fontSize: 28.0,
            fontWeight: FontWeight.w900,
            color: isActive ? AppColors.textPrimary : AppColors.textMuted,
            letterSpacing: -1.0,
            height: 1.0,
          ),
        ),
        const SizedBox(width: 4.0),
        Text(
          streakSummary.currentStreak == 1 ? 'day' : 'days',
          style: TextStyle(
            fontSize: 13.0,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 8.0),
        Flexible(
          child: Text(
            'CURRENT STREAK',
            key: const ValueKey('streak_display_label'),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(
              fontSize: 10.0,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ],
    );
  }

  /// Subtle progress bar representing streak momentum.
  Widget _buildProgressBar() {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3.0),
            child: Container(
              height: 5.0,
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(3.0),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  key: const ValueKey('home_streak_progress_bar'),
                  widthFactor: progressRatio,
                  child: Container(
                    decoration: BoxDecoration(
                      color: streakSummary.isCurrentStreakActive
                          ? AppColors.accent
                          : AppColors.textMuted.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(3.0),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          milestoneLabel,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }

  /// Best streak badge showing all-time record.
  Widget _buildBestStreakPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.emoji_events_outlined,
            size: 14.0,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 5.0),
          Text(
            'Best: ',
            style: TextStyle(
              fontSize: 11.0,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
            ),
          ),
          Text(
            '${streakSummary.longestStreak}d',
            key: const ValueKey('home_streak_best_count'),
            style: TextStyle(
              fontSize: 12.0,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
