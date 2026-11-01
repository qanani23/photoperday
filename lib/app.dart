import 'package:flutter/material.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/core/routing/app_router.dart';
import 'package:photo_per_day/core/theme/app_theme.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';

/// Root application widget configuring theme, routing, and app metadata.
class PhotoPerDayApp extends StatelessWidget {
  const PhotoPerDayApp({super.key, this.initialRoute});

  final String? initialRoute;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeService.instance,
      builder: (context, _) {
        final currentPalette = AppThemeService.instance.currentPalette;
        return MaterialApp(
          navigatorKey: AppRouter.navigatorKey,
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.themeForPalette(currentPalette),
          darkTheme: AppTheme.darkTheme,
          themeMode: currentPalette.isDark ? ThemeMode.dark : ThemeMode.light,
          initialRoute: initialRoute ?? AppConstants.initialRoute,
          onGenerateRoute: AppRouter.onGenerateRoute,
        );
      },
    );
  }
}
