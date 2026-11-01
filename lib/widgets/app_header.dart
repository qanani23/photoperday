import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';
import 'package:photo_per_day/widgets/app_icon_button.dart';
import 'package:photo_per_day/widgets/daria_logo.dart';

/// Reusable application header reproducing the reference design.
///
/// Contains the authentic Daria squircle logo badge (or a return back button when [showBackButton] is true),
/// screen title, uppercase tagline, and the "Diary >", "Dark/Light mode toggle", and "Settings" actions.
class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    this.title = 'Daria',
    this.tagline = 'CAPTURE YOUR LIFE,\nONE PHOTO AT A TIME',
    this.showBackButton = false,
    this.onBackTap,
    this.onExploreTap,
    this.onDiaryTap,
    this.onSettingsTap,
    this.onMeTap,
  });

  final String title;
  final String tagline;
  final bool showBackButton;
  final VoidCallback? onBackTap;
  final VoidCallback? onExploreTap;
  final VoidCallback? onDiaryTap;
  final VoidCallback? onSettingsTap;
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
          // Leading: Return back button or App Logo Badge
          if (showBackButton)
            IconButton(
              key: const ValueKey('full_calendar_back_button'),
              icon: Icon(
                Icons.arrow_back_rounded,
                color: AppColors.textPrimary,
                size: 24.0,
              ),
              tooltip: 'Back',
              onPressed: onBackTap ?? () => Navigator.maybePop(context),
            )
          else
            // App Logo Badge
            const DariaLogo(size: 44.0),
          const SizedBox(width: AppSpacing.md),

          // Title & Tagline
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTypography.appTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2.0),
                Text(
                  tagline,
                  style: AppTypography.appTagline,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Action Buttons (Diary, Dark/Light Mode & Settings)
          ListenableBuilder(
            listenable: AppThemeService.instance,
            builder: (context, _) {
              final isDark = AppThemeService.instance.isDark;

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppHeaderAction(
                    icon: Icons.auto_stories_rounded,
                    label: 'Diary >',
                    tooltip: 'Visual Diary',
                    onTap: onDiaryTap ?? onExploreTap,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  AppHeaderAction(
                    icon: isDark
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    label: isDark ? 'Light' : 'Dark',
                    tooltip: isDark
                        ? 'Switch to Light Mode (Daria Light)'
                        : 'Switch to Dark Mode (Daria Red)',
                    onTap: () => AppThemeService.instance.toggleDarkLight(),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  AppHeaderAction(
                    icon: Icons.settings_rounded,
                    label: 'Settings',
                    tooltip: 'Settings',
                    onTap: onSettingsTap ?? onMeTap,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
