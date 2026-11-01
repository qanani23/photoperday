import 'package:flutter/material.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/screens/diary/memories_screen.dart';
import 'package:photo_per_day/screens/diary/swipe_days_screen.dart';
import 'package:photo_per_day/screens/diary/visual_diary_screen.dart';
import 'package:photo_per_day/screens/info/about_app_screen.dart';
import 'package:photo_per_day/screens/info/privacy_policy_screen.dart';
import 'package:photo_per_day/screens/info/terms_of_service_screen.dart';
import 'package:photo_per_day/screens/calendar/full_calendar_screen.dart';
import 'package:photo_per_day/screens/main_shell.dart';
import 'package:photo_per_day/screens/onboarding/onboarding_screen.dart';
import 'package:photo_per_day/screens/photo_detail/photo_detail_screen.dart';
import 'package:photo_per_day/screens/settings/settings_screen.dart';
import 'package:photo_per_day/screens/settings/theme_selection_screen.dart';
import 'package:photo_per_day/screens/statistics/statistics_screen.dart';

import 'package:photo_per_day/data/services/onboarding_service.dart';

/// Centralized application route definitions and generator.
abstract final class AppRouter {
  /// Global navigator key for notification and deep-link routing.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Navigates directly to the Today tab (e.g. from reminder notification tap).
  static void navigateToToday() {
    navigatorKey.currentState?.pushNamedAndRemoveUntil(
      AppConstants.initialRoute,
      (route) => false,
      arguments: 1,
    );
  }

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppConstants.onboardingRoute:
        return MaterialPageRoute<void>(
          builder: (_) => const OnboardingScreen(),
          settings: settings,
        );
      case AppConstants.initialRoute:
        // Check onboarding status first
        if (!OnboardingService.instance.hasCompletedOnboarding) {
          return MaterialPageRoute<void>(
            builder: (_) => const OnboardingScreen(),
            settings: settings,
          );
        }
        // Returning users who completed onboarding enter MainShell directly.
        // Google Sign-In and Google Drive connection are not required for local diary access.

        int initialIndex = 0;
        if (settings.arguments is int) {
          initialIndex = settings.arguments as int;
        }
        return MaterialPageRoute<void>(
          builder: (_) => MainShell(initialIndex: initialIndex),
          settings: settings,
        );
      case AppConstants.diaryRoute:
        return MaterialPageRoute<void>(
          builder: (_) => const VisualDiaryScreen(),
          settings: settings,
        );
      case AppConstants.fullCalendarRoute:
        final args = settings.arguments;
        if (args is FullCalendarArguments) {
          return MaterialPageRoute<void>(
            builder: (_) => FullCalendarScreen(
              wrapWithScaffold: args.wrapWithScaffold,
              onNavigateToToday: args.onNavigateToToday,
              onNavigateToSettings: args.onNavigateToSettings,
              onNavigateToProfile: args.onNavigateToProfile,
              onCaptureTap: args.onCaptureTap,
              initialDate: args.initialDate,
              initialSelectedDate: args.initialSelectedDate,
              store: args.store,
            ),
            settings: settings,
          );
        }
        return MaterialPageRoute<void>(
          builder: (_) => const FullCalendarScreen(),
          settings: settings,
        );
      case AppConstants.memoriesRoute:
        DateTime? targetDate;
        if (settings.arguments is DateTime) {
          targetDate = settings.arguments as DateTime;
        }
        return MaterialPageRoute<void>(
          builder: (_) => MemoriesScreen(targetDate: targetDate),
          settings: settings,
        );
      case AppConstants.swipeDaysRoute:
        DateKey? initialDateKey;
        String? initialPhotoId;
        List<DateKey>? filterDateKeys;
        String? customTitle;
        String? customSubtitle;

        if (settings.arguments is SwipeDaysArguments) {
          final args = settings.arguments as SwipeDaysArguments;
          initialDateKey = args.initialDateKey;
          initialPhotoId = args.initialPhotoId;
          filterDateKeys = args.filterDateKeys;
          customTitle = args.customTitle;
          customSubtitle = args.customSubtitle;
        } else if (settings.arguments is DateKey) {
          initialDateKey = settings.arguments as DateKey;
        } else if (settings.arguments is PhotoEntry) {
          final entry = settings.arguments as PhotoEntry;
          initialDateKey = entry.dateKey;
          initialPhotoId = entry.effectiveId;
        } else if (settings.arguments is DateTime) {
          initialDateKey = DateKey.fromDateTime(settings.arguments as DateTime);
        }
        return MaterialPageRoute<void>(
          builder: (_) => SwipeDaysScreen(
            initialDateKey: initialDateKey,
            initialPhotoId: initialPhotoId,
            filterDateKeys: filterDateKeys,
            customTitle: customTitle,
            customSubtitle: customSubtitle,
          ),
          settings: settings,
        );
      case AppConstants.photoDetailRoute:
        final entry = settings.arguments as PhotoEntry?;
        return MaterialPageRoute<void>(
          builder: (_) => PhotoDetailScreen(
            photoEntry:
                entry ??
                PhotoEntry(
                  date: DateTime.now(),
                  title: 'Photo Memory',
                  timeFormatted: '',
                  gradientColors: const [Color(0xFFB86B35), Color(0xFF2B2823)],
                ),
            onDeleteConfirmed: () {
              if (entry != null) {
                PersistentDailyPhotoStore.instance.removePhoto(entry.date);
              }
            },
          ),
          settings: settings,
        );
      case AppConstants.statisticsRoute:
        DateKey? todayKey;
        if (settings.arguments is DateKey) {
          todayKey = settings.arguments as DateKey;
        } else if (settings.arguments is DateTime) {
          todayKey = DateKey.fromDateTime(settings.arguments as DateTime);
        }
        return MaterialPageRoute<void>(
          builder: (_) => StatisticsScreen(todayKey: todayKey),
          settings: settings,
        );
      case AppConstants.settingsRoute:
        return MaterialPageRoute<void>(
          builder: (_) => const SettingsScreen(),
          settings: settings,
        );
      case AppConstants.themeRoute:
        return MaterialPageRoute<void>(
          builder: (_) => const ThemeSelectionScreen(),
          settings: settings,
        );
      case AppConstants.aboutRoute:
        return MaterialPageRoute<void>(
          builder: (_) => const AboutAppScreen(),
          settings: settings,
        );
      case AppConstants.privacyRoute:
        return MaterialPageRoute<void>(
          builder: (_) => const PrivacyPolicyScreen(),
          settings: settings,
        );
      case AppConstants.termsRoute:
        return MaterialPageRoute<void>(
          builder: (_) => const TermsOfServiceScreen(),
          settings: settings,
        );
      default:
        return MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: Center(child: Text('No route defined for ${settings.name}')),
          ),
          settings: settings,
        );
    }
  }
}
