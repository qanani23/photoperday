import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';

/// Reusable photo placeholder thumbnail with subtle gradient and icon.
class PhotoPlaceholder extends StatelessWidget {
  const PhotoPlaceholder({
    super.key,
    this.borderRadius = AppRadii.cell,
    this.aspectRatio = 1.0,
    this.icon = Icons.photo_outlined,
    this.colorTint,
  });

  final BorderRadius borderRadius;
  final double aspectRatio;
  final IconData icon;
  final Color? colorTint;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Container(
          decoration: BoxDecoration(
            color: colorTint ?? AppColors.surfaceSubtle,
            gradient: colorTint != null
                ? null
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.placeholderGradientStart,
                      AppColors.placeholderGradientEnd,
                    ],
                  ),
          ),
          child: Center(
            child: Icon(icon, size: 20.0, color: AppColors.textMuted),
          ),
        ),
      ),
    );
  }
}
