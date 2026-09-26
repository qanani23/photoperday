import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/widgets/bottom_nav_dock.dart';

/// Application scaffold providing standard safe-area handling, page background,
/// dark status-bar icons, and the floating bottom navigation dock.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.body,
    this.bottomNav,
    this.showDefaultDock = true,
    this.currentNavIndex = 0,
    this.onHomeTap,
    this.onCaptureTap,
    this.onMeTap,
  });

  final Widget body;
  final Widget? bottomNav;
  final bool showDefaultDock;
  final int currentNavIndex;
  final VoidCallback? onHomeTap;
  final VoidCallback? onCaptureTap;
  final VoidCallback? onMeTap;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              // Main scrollable content with bottom padding for the floating dock
              Positioned.fill(child: body),

              // Floating Bottom Dock
              if (showDefaultDock)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: MediaQuery.of(context).padding.bottom + 8.0,
                  child:
                      bottomNav ??
                      BottomNavDock(
                        currentIndex: currentNavIndex,
                        onHomeTap: onHomeTap,
                        onCaptureTap: onCaptureTap,
                        onMeTap: onMeTap,
                      ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
