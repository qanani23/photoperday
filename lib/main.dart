import 'package:flutter/material.dart';
import 'package:photo_per_day/app.dart';
import 'package:photo_per_day/core/routing/app_router.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';
import 'package:photo_per_day/data/services/daily_reminder_service.dart';
import 'package:photo_per_day/data/services/onboarding_service.dart';
import 'package:photo_per_day/data/services/pad_backup_service.dart';
import 'package:photo_per_day/data/services/pdf_diary_export_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppThemeService.instance.init();
  await PadBackupService().recoverPendingRestore();
  await PadBackupService().cleanTemporaryBackups();
  await PdfDiaryExportService.instance.cleanTemporaryExports();
  await PersistentDailyPhotoStore.instance.init();
  DailyReminderService.instance.onNotificationTap = AppRouter.navigateToToday;
  await DailyReminderService.instance.init();
  await OnboardingService.instance.init();
  runApp(const PhotoPerDayApp());
}
