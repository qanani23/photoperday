import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';

/// Reusable circular header action button with an optional text caption below.
///
/// Matches the "Explore >" and "Me" header controls from the reference design.
class AppHeaderAction extends StatelessWidget {
  const AppHeaderAction({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.size = 40.0,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final semanticLabel = tooltip ?? label;

    return Semantics(
      label: semanticLabel,
      button: true,
      child: Tooltip(
        message: semanticLabel,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48.0, minHeight: 48.0),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 4.0,
                vertical: 2.0,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSubtle,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 20.0, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 3.0),
                  Text(label, style: AppTypography.actionLabel),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
