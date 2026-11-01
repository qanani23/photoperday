import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_shadows.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';

/// Visual card container for grouping related settings tiles.
///
/// Features an optional section title and automatic dividers between child rows.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4.0, bottom: AppSpacing.xs),
            child: Text(
              title!.toUpperCase(),
              style: TextStyle(
                fontSize: 11.0,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.card,
            border: Border.all(color: AppColors.border, width: 0.8),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  Divider(
                    height: 1.0,
                    thickness: 0.8,
                    indent: AppSpacing.md,
                    endIndent: AppSpacing.md,
                    color: AppColors.borderSubtle,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
