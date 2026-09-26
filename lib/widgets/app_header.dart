import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_shadows.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';
import 'package:photo_per_day/widgets/app_icon_button.dart';

/// Reusable application header reproducing the reference design.
///
/// Contains the app squircle logo badge, "Photo a Day" title, uppercase tagline,
/// and the "Explore >" and "Me" circular action buttons.
class AppHeader extends StatelessWidget {
  const AppHeader({super.key, this.onExploreTap, this.onMeTap});

  final VoidCallback? onExploreTap;
  final VoidCallback? onMeTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageHorizontal,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // App Logo Badge
          Container(
            width: 44.0,
            height: 44.0,
            decoration: const BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: AppRadii.iconBadge,
              boxShadow: AppShadows.logoBadge,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(
                  Icons.photo_camera_rounded,
                  color: Colors.white,
                  size: 22.0,
                ),
                Positioned(
                  right: 4.0,
                  bottom: 4.0,
                  child: Container(
                    padding: const EdgeInsets.all(2.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(3.0),
                    ),
                    child: const Icon(
                      Icons.calendar_month_rounded,
                      size: 10.0,
                      color: AppColors.surfaceDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),

          // Title & Tagline
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Photo a Day', style: AppTypography.appTitle),
                SizedBox(height: 2.0),
                Text(
                  'CAPTURE YOUR LIFE,\nONE PHOTO AT A TIME',
                  style: AppTypography.appTagline,
                ),
              ],
            ),
          ),

          // Action Buttons (Explore & Me)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppHeaderAction(
                icon: Icons.search_rounded,
                label: 'Explore >',
                onTap: onExploreTap,
              ),
              const SizedBox(width: AppSpacing.xs),
              AppHeaderAction(
                icon: Icons.more_horiz_rounded,
                label: 'Me',
                onTap: onMeTap,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
