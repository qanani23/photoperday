import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_shadows.dart';

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
            key: const ValueKey('dock_home_tab'),
            icon: Icons.home_rounded,
            label: 'Home',
            isSelected: currentIndex == 0,
            onTap: onHomeTap,
          ),

          // Center Capture Pill
          _buildNavTab(
            key: const ValueKey('dock_capture_tab'),
            icon: Icons.camera_alt_rounded,
            label: 'Capture',
            isSelected: currentIndex == 1,
            onTap: onCaptureTap,
            semanticLabel: 'Today tab, capture daily photo',
          ),

          // Me Tab
          _buildNavTab(
            key: const ValueKey('dock_me_tab'),
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
    Key? key,
    required IconData icon,
    required String label,
    required bool isSelected,
    VoidCallback? onTap,
    String? semanticLabel,
  }) {
    final fgColor = isSelected ? Colors.white : AppColors.textMuted;

    return Semantics(
      label: semanticLabel ?? '$label tab',
      button: true,
      selected: isSelected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 6.0,
            ),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.surfaceDark : Colors.transparent,
              borderRadius: BorderRadius.circular(24.0),
              border: Border.all(
                color: isSelected ? AppColors.surfaceDark : Colors.transparent,
                width: 0.8,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20.0, color: fgColor),
                const SizedBox(height: 2.0),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.0,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: fgColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
