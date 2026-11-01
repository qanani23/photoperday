import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';

/// Reusable settings row widget adhering to the application's design system.
///
/// Features an optional leading icon badge, title, subtitle, custom trailing widget,
/// and accessible touch target sizing with [HitTestBehavior.opaque].
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leadingIcon,
    this.leadingColor,
    this.trailing,
    this.onTap,
    this.showChevron = false,
  });

  final String title;
  final String? subtitle;
  final IconData? leadingIcon;
  final Color? leadingColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final tileContent = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 12.0,
      ),
      child: Row(
        children: [
          // Leading Icon Badge
          if (leadingIcon != null) ...[
            Container(
              width: 36.0,
              height: 36.0,
              decoration: BoxDecoration(
                color: (leadingColor ?? AppColors.accent).withValues(
                  alpha: 0.12,
                ),
                borderRadius: BorderRadius.circular(10.0),
              ),
              child: Icon(
                leadingIcon,
                size: 18.0,
                color: leadingColor ?? AppColors.accent,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
          ],

          // Title & Optional Subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2.0),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      fontSize: 12.0,
                      color: AppColors.textSecondary,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Trailing Widget or Chevron
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ] else if (showChevron) ...[
            const SizedBox(width: AppSpacing.sm),
            Icon(
              Icons.chevron_right_rounded,
              size: 20.0,
              color: AppColors.textMuted,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return tileContent;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.accent.withValues(alpha: 0.08),
        highlightColor: AppColors.surfaceSubtle.withValues(alpha: 0.35),
        hoverColor: AppColors.surfaceSubtle.withValues(alpha: 0.4),
        child: tileContent,
      ),
    );
  }
}
