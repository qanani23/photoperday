import 'package:flutter/material.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';
import 'package:photo_per_day/screens/home/home_screen.dart';
import 'package:photo_per_day/screens/profile/profile_screen.dart';
import 'package:photo_per_day/screens/today/today_screen.dart';
import 'package:photo_per_day/services/daily_capture_workflow.dart';
import 'package:photo_per_day/widgets/app_scaffold.dart';

/// Main navigation shell hosting the primary screens of Photo a Day.
///
/// Manages the active screen index with [IndexedStack] to preserve screen state
/// and coordinates navigation between the Calendar (tab 0), direct Camera capture,
/// and Profile / Settings (tab 2) via the persistent floating [BottomNavDock].
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    AppThemeService.instance.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    AppThemeService.instance.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onTabSelected(int index) {
    if (_currentIndex != index) {
      setState(() {
        _currentIndex = index;
      });
    }
  }

  Future<void> _handleCaptureTap() async {
    final savedPhoto = await DailyCaptureWorkflow.execute(context);
    if (savedPhoto != null && mounted) {
      setState(() {
        _currentIndex =
            1; // Transition to Today tab to display the captured photo
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _currentIndex != 0) {
          setState(() {
            _currentIndex = 0;
          });
        }
      },
      child: AppScaffold(
        currentNavIndex: _currentIndex,
        onHomeTap: () => _onTabSelected(0),
        onCaptureTap: _handleCaptureTap,
        onMeTap: () => _onTabSelected(2),
        body: IndexedStack(
          index: _currentIndex,
          children: [
            HomeScreen(
              wrapWithScaffold: false,
              onNavigateToToday: () => _onTabSelected(1),
              onNavigateToSettings: () =>
                  Navigator.pushNamed(context, AppConstants.settingsRoute),
              onNavigateToProfile: () => _onTabSelected(2),
            ),
            TodayScreen(onNavigateToCalendar: () => _onTabSelected(0)),
            const ProfileScreen(),
          ],
        ),
      ),
    );
  }
}
