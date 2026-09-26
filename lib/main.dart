import 'package:flutter/material.dart';
import 'package:photo_per_day/app.dart';
import 'package:photo_per_day/core/routing/app_router.dart';
import 'package:photo_per_day/data/services/daily_reminder_service.dart';
import 'package:photo_per_day/data/services/google_auth_service.dart';
import 'package:photo_per_day/data/services/google_drive_auth_service.dart';
import 'package:photo_per_day/data/services/google_drive_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/sync_coordinator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PersistentDailyPhotoStore.instance.init();
  await GoogleAuthService.instance.init();
  await GoogleDriveAuthService.instance.init();
  await GoogleDriveService.instance.init();
  await SyncCoordinator.instance.init();
  DailyReminderService.instance.onNotificationTap = AppRouter.navigateToToday;
  await DailyReminderService.instance.init();
  runApp(const PhotoPerDayApp());
}
