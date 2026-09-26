import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';

/// 7-column weekday indicator row perfectly aligned with the calendar grid columns.
class WeekdayHeader extends StatelessWidget {
  const WeekdayHeader({
    super.key,
    this.weekdays = const ['S', 'M', 'T', 'W', 'T', 'F', 'S'],
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.pageHorizontal,
    ),
  });

  final List<String> weekdays;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          for (int i = 0; i < weekdays.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.gridGap),
            Expanded(
              child: Center(
                child: Text(
                  weekdays[i],
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
