import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';

/// Reusable month / section title matching the reference design.
///
/// Optionally includes previous/next month chevron buttons.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.onPrevious,
    this.onNext,
    this.previousTooltip = 'Previous month',
    this.nextTooltip = 'Next month',
    this.isHeader = true,
  });

  final String title;
  final Widget? trailing;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final String previousTooltip;
  final String nextTooltip;
  final bool isHeader;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.pageHorizontal,
        right: AppSpacing.pageHorizontal,
        top: AppSpacing.md,
        bottom: AppSpacing.sectionBottomGap,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Semantics(
              header: isHeader,
              child: Text(
                title,
                style: AppTypography.sectionTitle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (trailing != null) ...[
            trailing!,
            if (onPrevious != null || onNext != null)
              const SizedBox(width: 8.0),
          ],
          if (onPrevious != null || onNext != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onPrevious != null)
                  _buildChevronButton(
                    icon: Icons.chevron_left_rounded,
                    tooltip: previousTooltip,
                    onTap: onPrevious!,
                  ),
                if (onNext != null) ...[
                  const SizedBox(width: 4.0),
                  _buildChevronButton(
                    icon: Icons.chevron_right_rounded,
                    tooltip: nextTooltip,
                    onTap: onNext!,
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildChevronButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: tooltip,
      button: true,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48.0, minHeight: 48.0),
            child: Center(
              child: Container(
                width: 38.0,
                height: 38.0,
                decoration: BoxDecoration(
                  color: AppColors.surfaceSubtle,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 22.0, color: AppColors.textPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
