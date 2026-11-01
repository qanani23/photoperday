import 'package:flutter/material.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';

/// Authentic Daria brand mark widget displaying the official application logo.
///
/// Preserves the original 1:1 aspect ratio, transparent corners, and squircle form factor.
/// Provides accessibility semantics and resilient error handling for headless test environments.
class DariaLogo extends StatelessWidget {
  const DariaLogo({
    super.key,
    this.size = 44.0,
    this.semanticLabel = 'Daria Logo',
    this.onTap,
    this.heroTag,
  });

  /// The dimension (both width and height) of the square logo in logical pixels.
  final double size;

  /// Accessibility label announced to assistive technologies.
  final String semanticLabel;

  /// Optional tap handler for interactive logo placements.
  final VoidCallback? onTap;

  /// Optional hero animation tag.
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    Widget logoWidget = Image.asset(
      AppConstants.dariaLogoAsset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: semanticLabel,
      errorBuilder: (context, error, stackTrace) {
        // Fallback for isolated headless unit tests without full asset bundles
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(size * 0.28),
          ),
          child: Center(
            child: Icon(
              Icons.camera_alt_rounded,
              color: AppColors.accent,
              size: size * 0.52,
            ),
          ),
        );
      },
    );

    if (heroTag != null) {
      logoWidget = Hero(tag: heroTag!, child: logoWidget);
    }

    if (onTap != null) {
      return Semantics(
        button: true,
        label: semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: logoWidget,
        ),
      );
    }

    return Semantics(image: true, label: semanticLabel, child: logoWidget);
  }
}
