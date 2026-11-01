import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/screens/camera/camera_screen.dart';

/// Central domain workflow orchestrating the direct camera capture flow for today's photo.
///
/// Features:
/// 1. Directly launches [CameraScreen] without intermediate source selection.
/// 2. Automatically determines today's local date ([DateKey.fromDateTime(DateTime.now())]).
/// 3. Appends captured photo to today's [DayEntry] collection without destroying existing memories.
/// 4. Discards captured image safely if user backs out of camera.
/// 5. Automatically commits photo and updates store reactivity upon capture.
/// 6. Supports explicit intentional replacement when requested via [isReplacement].
class DailyCaptureWorkflow {
  /// Executes the direct camera capture flow from [context].
  ///
  /// Returns the saved [PhotoEntry] if captured/saved, or `null` if cancelled.
  static Future<PhotoEntry?> execute(
    BuildContext context, {
    PersistentDailyPhotoStore? store,
    DateTime? overrideToday,
    bool isReplacement = false,
    String? targetPhotoId,
  }) async {
    final effectiveStore = store ?? PersistentDailyPhotoStore.instance;

    // 1. Immediately launch CameraScreen
    final capturedPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const CameraScreen()),
    );

    if (capturedPath == null || !context.mounted) {
      return null;
    }

    // 2. Automatically determine TODAY using local date
    final now = overrideToday ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayKey = DateKey.fromDateTime(today);

    // 3. If explicit replacement was requested, confirm with user
    if (isReplacement) {
      final shouldReplace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.dialogRadius,
            side: BorderSide(color: AppColors.border, width: 0.8),
          ),
          title: Text(
            'Replace Photo',
            style: TextStyle(
              fontSize: 18.0,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          content: Text(
            'Would you like to replace this photo with the new capture?',
            style: TextStyle(
              fontSize: 14.0,
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 10.0,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryButtonBackground,
                foregroundColor: AppColors.primaryButtonForeground,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.0),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
              ),
              child: const Text(
                'Replace',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );

      if (shouldReplace != true || !context.mounted) {
        return null;
      }
    }

    // 4. Format current capture time
    final period = now.hour >= 12 ? 'PM' : 'AM';
    final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minuteFormatted = now.minute.toString().padLeft(2, '0');
    final formattedTime = '$hour12:$minuteFormatted $period';

    try {
      final PhotoEntry savedEntry;
      if (isReplacement && targetPhotoId != null) {
        final replacementPhoto = PhotoEntry(
          id: targetPhotoId,
          date: todayKey.toDateTime(hour: now.hour, minute: now.minute),
          title: 'Daily Capture',
          timeFormatted: formattedTime,
          imagePath: capturedPath,
          location: 'Camera Capture',
          gradientColors: const [Color(0xFFE8DCC4), Color(0xFFD4C3A3)],
        );
        savedEntry = await effectiveStore.savePhoto(
          entry: replacementPhoto,
          sourceTempPath: capturedPath,
        );
      } else {
        final newPhoto = PhotoEntry(
          date: todayKey.toDateTime(hour: now.hour, minute: now.minute),
          title: 'Daily Capture',
          timeFormatted: formattedTime,
          imagePath: capturedPath,
          location: 'Camera Capture',
          gradientColors: const [Color(0xFFE8DCC4), Color(0xFFD4C3A3)],
        );
        savedEntry = await effectiveStore.addPhotoToDay(
          dateKey: todayKey,
          photo: newPhoto,
          sourceTempPath: capturedPath,
        );
      }

      if (context.mounted) {
        final day = effectiveStore.getDay(todayKey);
        final count = day?.photoCount ?? 1;
        final message = isReplacement
            ? "Today's photo replaced successfully!"
            : (count > 1
                  ? "Photo added to today's collection ($count photos)!"
                  : "Today's photo captured successfully!");

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      return savedEntry;
    } catch (e) {
      debugPrint('Failed to save captured photo: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to save photo. Please try again.'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
          ),
        );
      }
      return null;
    }
  }
}
