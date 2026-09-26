import 'package:flutter/material.dart';
import 'package:photo_per_day/screens/home/home_screen.dart';
import 'package:photo_per_day/screens/profile/profile_screen.dart';
import 'package:photo_per_day/screens/today/today_screen.dart';
import 'package:photo_per_day/widgets/app_scaffold.dart';

/// Main navigation shell hosting the primary screens of Photo a Day.
///
/// Manages the active screen index with [IndexedStack] to preserve screen state
/// and coordinates navigation between the Calendar (tab 0), Today (tab 1),
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
  }

  void _onTabSelected(int index) {
    if (_currentIndex != index) {
      setState(() {
        _currentIndex = index;
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
        onCaptureTap: () => _onTabSelected(1),
        onMeTap: () => _onTabSelected(2),
        body: IndexedStack(
          index: _currentIndex,
          children: [
            HomeScreen(
              wrapWithScaffold: false,
              onNavigateToToday: () => _onTabSelected(1),
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
