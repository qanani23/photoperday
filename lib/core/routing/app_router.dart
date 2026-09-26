import 'package:flutter/material.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/mock_photo_service.dart';
import 'package:photo_per_day/screens/main_shell.dart';
import 'package:photo_per_day/screens/photo_detail/photo_detail_screen.dart';

/// Centralized application route definitions and generator.
abstract final class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppConstants.initialRoute:
        return MaterialPageRoute<void>(
          builder: (_) => const MainShell(),
          settings: settings,
        );
      case AppConstants.photoDetailRoute:
        final entry = settings.arguments as PhotoEntry?;
        return MaterialPageRoute<void>(
          builder: (_) => PhotoDetailScreen(
            photoEntry: entry ?? MockPhotoService.defaultTodayPhoto,
            onDeleteConfirmed: () {
              if (entry != null) {
                PersistentDailyPhotoStore.instance.removePhoto(entry.date);
              }
            },
          ),
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
