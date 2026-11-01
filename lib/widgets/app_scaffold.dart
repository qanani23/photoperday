import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_per_day/core/layout/app_breakpoints.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';
import 'package:photo_per_day/widgets/bottom_nav_dock.dart';

/// Application scaffold providing standard safe-area handling, page background,
/// dark status-bar icons, responsive desktop centering, and the floating bottom navigation dock.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.body,
    this.bottomNav,
    this.showDefaultDock = true,
    this.currentNavIndex = 0,
    this.maxContentWidth,
    this.onHomeTap,
    this.onCaptureTap,
    this.onMeTap,
  });

  final Widget body;
  final Widget? bottomNav;
  final bool showDefaultDock;
  final int currentNavIndex;

  /// Optional maximum content width override. Defaults to [AppBreakpoints.maxContentWidth].
  final double? maxContentWidth;

  final VoidCallback? onHomeTap;
  final VoidCallback? onCaptureTap;
  final VoidCallback? onMeTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeService.instance,
      builder: (context, _) {
        final isDark = AppColors.current.isDark;
        final effectiveMaxWidth =
            maxContentWidth ?? AppBreakpoints.maxContentWidth;

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () {
              Navigator.maybePop(context);
            },
          },
          child: Focus(
            autofocus: true,
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: isDark
                    ? Brightness.light
                    : Brightness.dark,
                statusBarBrightness: isDark
                    ? Brightness.dark
                    : Brightness.light,
              ),
              child: Scaffold(
                backgroundColor: AppColors.background,
                body: SafeArea(
                  bottom: false,
                  child: Stack(
                    children: [
                      // Main scrollable content with responsive max-width centering for wide desktop windows
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: effectiveMaxWidth,
                            ),
                            child: body,
                          ),
                        ),
                      ),

                      // Floating Bottom Dock (centered with max width for desktop)
                      if (showDefaultDock)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: MediaQuery.of(context).padding.bottom + 8.0,
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: AppBreakpoints.maxBottomDockWidth,
                              ),
                              child:
                                  bottomNav ??
                                  BottomNavDock(
                                    currentIndex: currentNavIndex,
                                    onHomeTap: onHomeTap,
                                    onCaptureTap: onCaptureTap,
                                    onMeTap: onMeTap,
                                  ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
