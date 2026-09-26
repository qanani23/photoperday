import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';

/// Reusable 7-column calendar grid matching the reference design layout.
class CalendarGrid extends StatelessWidget {
  const CalendarGrid({
    super.key,
    required this.children,
    this.crossAxisCount = 7,
    this.spacing = AppSpacing.gridGap,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.pageHorizontal,
    ),
  });

  final List<Widget> children;
  final int crossAxisCount;
  final double spacing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        children: children,
      ),
    );
  }
}
