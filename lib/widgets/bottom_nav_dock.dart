import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_shadows.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';

/// Floating bottom navigation dock reproducing the reference design.
///
/// Features a floating pill container with a Home tab, an elevated center
/// Capture pill with camera controls, and a Me profile tab.
class BottomNavDock extends StatelessWidget {
  const BottomNavDock({
    super.key,
    this.currentIndex = 0,
    this.onHomeTap,
    this.onCaptureTap,
    this.onMeTap,
  });

  final int currentIndex;
  final VoidCallback? onHomeTap;
  final VoidCallback? onCaptureTap;
  final VoidCallback? onMeTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(28.0, 0, 28.0, 16.0),
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: AppColors.dockBackground,
        borderRadius: AppRadii.bottomDock,
        border: Border.all(color: AppColors.dockBorder, width: 1.0),
        boxShadow: AppShadows.bottomDock,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Home Tab
          _buildNavTab(
            icon: Icons.home_rounded,
            label: 'Home',
            isSelected: currentIndex == 0,
            onTap: onHomeTap,
          ),

          // Center Capture Pill
          Semantics(
            label: 'Today tab, capture daily photo',
            button: true,
            selected: currentIndex == 1,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onCaptureTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14.0,
                  vertical: 6.0,
                ),
                decoration: BoxDecoration(
                  color: currentIndex == 1
                      ? AppColors.surfaceDark
                      : AppColors.dockCapturePill,
                  borderRadius: BorderRadius.circular(24.0),
                  border: Border.all(
                    color: currentIndex == 1
                        ? AppColors.surfaceDark
                        : AppColors.border,
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.photo_library_outlined,
                      size: 16.0,
                      color: currentIndex == 1
                          ? Colors.white.withValues(alpha: 0.6)
                          : AppColors.textMuted,
                    ),
                    const SizedBox(width: 8.0),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.camera_alt_rounded,
                          size: 20.0,
                          color: currentIndex == 1
                              ? Colors.white
                              : AppColors.textPrimary,
                        ),
                        const SizedBox(height: 2.0),
                        Text(
                          'Capture',
                          style: TextStyle(
                            fontSize: 10.0,
                            fontWeight: FontWeight.w700,
                            color: currentIndex == 1
                                ? Colors.white
                                : AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8.0),
                    Icon(
                      Icons.flare_rounded,
                      size: 16.0,
                      color: currentIndex == 1
                          ? Colors.white.withValues(alpha: 0.6)
                          : AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Me Tab
          _buildNavTab(
            icon: Icons.person_rounded,
            label: 'Me',
            isSelected: currentIndex == 2,
            onTap: onMeTap,
          ),
        ],
      ),
    );
  }

  Widget _buildNavTab({
    required IconData icon,
    required String label,
    required bool isSelected,
    VoidCallback? onTap,
  }) {
    final color = isSelected ? AppColors.textPrimary : AppColors.textMuted;

    return Semantics(
      label: '$label tab',
      button: true,
      selected: isSelected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22.0, color: color),
              const SizedBox(height: 2.0),
              Text(
                label,
                style: AppTypography.navLabel.copyWith(
                  color: color,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
