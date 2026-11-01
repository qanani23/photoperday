import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';

/// Minimal, tactile page indicator adhering to the Photo a Day design tokens.
class OnboardingPageIndicator extends StatelessWidget {
  const OnboardingPageIndicator({
    super.key,
    required this.currentPage,
    this.pageCount = 3,
    this.onDotTapped,
  });

  final int currentPage;
  final int pageCount;
  final ValueChanged<int>? onDotTapped;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Page indicator, page ${currentPage + 1} of $pageCount',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(pageCount, (index) {
          final isSelected = index == currentPage;
          return GestureDetector(
            onTap: onDotTapped != null ? () => onDotTapped!(index) : null,
            behavior: HitTestBehavior.opaque,
            child: Semantics(
              button: onDotTapped != null,
              selected: isSelected,
              label: 'Go to page ${index + 1}',
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4.0,
                  vertical: 8.0,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  width: isSelected ? 24.0 : 7.0,
                  height: 7.0,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.accent
                        : AppColors.borderSubtle,
                    borderRadius: AppRadii.roundedPill,
                    border: Border.all(
                      color: isSelected
                          ? AppColors.accent
                          : AppColors.border.withValues(alpha: 0.8),
                      width: 1.0,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
