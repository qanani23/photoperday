import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_shadows.dart';

/// Reusable surface card matching the design system's subtle elevation and rounded corners.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16.0),
    this.backgroundColor = AppColors.surface,
    this.borderRadius = AppRadii.card,
    this.hasBorder = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;
  final BorderRadius borderRadius;
  final bool hasBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: borderRadius,
        border: hasBorder
            ? Border.all(color: AppColors.border, width: 1.0)
            : null,
        boxShadow: AppShadows.card,
      ),
      child: child,
    );
  }
}
