import 'package:flutter/material.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/core/routing/app_router.dart';
import 'package:photo_per_day/core/theme/app_theme.dart';

/// Root application widget configuring theme, routing, and app metadata.
class PhotoPerDayApp extends StatelessWidget {
  const PhotoPerDayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: AppRouter.navigatorKey,
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      initialRoute: AppConstants.initialRoute,
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
