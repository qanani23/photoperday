import 'package:flutter/material.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/core/layout/app_breakpoints.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_shadows.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';
import 'package:photo_per_day/data/services/daily_reminder_service.dart';
import 'package:photo_per_day/data/services/diary_export_service.dart';
import 'package:photo_per_day/data/services/local_storage_calculator.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/streak_service.dart';
import 'package:photo_per_day/widgets/pad_backup_export_dialog.dart';
import 'package:photo_per_day/widgets/pad_backup_restore_dialog.dart';
import 'package:photo_per_day/widgets/pdf_export_dialog.dart';
import 'package:photo_per_day/widgets/scrolling_time_picker.dart';
import 'package:photo_per_day/widgets/settings_group.dart';
import 'package:photo_per_day/widgets/settings_tile.dart';
import 'package:photo_per_day/widgets/daria_logo.dart';

/// Profile and Settings screen for Photo a Day.
///
/// Features a personal local diary header, photo streak overview,
/// customizable preferences (daily reminders, start of week, theme),
/// memories navigation, and local storage management (export & deletion).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _startOfWeek = 'Sunday';
  int _localPhotoBytes = 0;
  bool _isLoadingStorage = false;
  bool _isExporting = false;
  bool _isDeletingLocal = false;

  @override
  void initState() {
    super.initState();
    _localPhotoBytes = LocalStorageCalculator.calculateTotalPhotoBytesSync(
      store: PersistentDailyPhotoStore.instance,
    );
    _refreshLocalStorageUsage();
    PersistentDailyPhotoStore.instance.addListener(_onStoreChangedForStorage);
  }

  void _onStoreChangedForStorage() {
    _refreshLocalStorageUsage();
  }

  Future<void> _refreshLocalStorageUsage() async {
    final bytes = await LocalStorageCalculator.calculateTotalPhotoBytes(
      store: PersistentDailyPhotoStore.instance,
    );
    if (mounted) {
      setState(() {
        _localPhotoBytes = bytes;
        _isLoadingStorage = false;
      });
    }
  }

  @override
  void dispose() {
    PersistentDailyPhotoStore.instance.removeListener(
      _onStoreChangedForStorage,
    );
    super.dispose();
  }

  Future<void> _toggleReminder(bool value) async {
    final reminderService = DailyReminderService.instance;
    final success = await reminderService.setEnabled(value);

    if (!mounted) return;

    if (value && !success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Notification permission is required to enable daily reminders.',
          ),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Daily reminder enabled for ${reminderService.settings.formattedTime}'
                : 'Daily reminder disabled',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pickReminderTime() async {
    final reminderService = DailyReminderService.instance;
    final selected = await ScrollingTimePickerDialog.show(
      context,
      initialTime: TimeOfDay(
        hour: reminderService.settings.hour,
        minute: reminderService.settings.minute,
      ),
    );

    if (selected != null && mounted) {
      await reminderService.setTime(
        hour: selected.hour,
        minute: selected.minute,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Daily reminder time set to ${reminderService.settings.formattedTime}',
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showStartOfWeekDialog() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.dialogRadius,
            side: BorderSide(color: AppColors.border, width: 0.8),
          ),
          title: Text(
            'Start of Week',
            style: TextStyle(
              fontSize: 17.0,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          children: [
            SimpleDialogOption(
              onPressed: () {
                setState(() => _startOfWeek = 'Sunday');
                Navigator.of(context).pop();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Sunday',
                      style: TextStyle(
                        fontSize: 15.0,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (_startOfWeek == 'Sunday')
                      Icon(
                        Icons.check_rounded,
                        color: AppColors.accent,
                        size: 20.0,
                      ),
                  ],
                ),
              ),
            ),
            SimpleDialogOption(
              onPressed: () {
                setState(() => _startOfWeek = 'Monday');
                Navigator.of(context).pop();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Monday',
                      style: TextStyle(
                        fontSize: 15.0,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (_startOfWeek == 'Monday')
                      Icon(
                        Icons.check_rounded,
                        color: AppColors.accent,
                        size: 20.0,
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleExportDiary() async {
    final store = PersistentDailyPhotoStore.instance;
    if (store.totalPhotos == 0) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.dialogRadius,
            side: BorderSide(color: AppColors.border, width: 0.8),
          ),
          title: Text(
            'Export Diary',
            style: TextStyle(
              fontSize: 18.0,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          content: Text(
            'Your diary does not contain any photos to export yet.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'OK',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.dialogRadius,
          side: BorderSide(color: AppColors.border, width: 0.8),
        ),
        title: Text(
          'Export Your Diary',
          style: TextStyle(
            fontSize: 18.0,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'Export ${store.totalPhotos} photo${store.totalPhotos == 1 ? '' : 's'} and diary metadata into a standard ZIP archive.\n\n'
          'The export includes your captured photos and a manifest.json file containing your dates, titles, and locations.\n\n'
          'The archive is created locally on your device without transmitting data over the internet.',
          style: AppTypography.body.copyWith(
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
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Export',
              style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isExporting = true);

    final ExportResult result;
    try {
      result = await DiaryExportService.instance.exportDiary();
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }

    if (!mounted) return;

    if (result.isSuccess) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.dialogRadius,
            side: BorderSide(color: AppColors.border, width: 0.8),
          ),
          title: Row(
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                color: AppColors.statDaysGreen,
                size: 22.0,
              ),
              const SizedBox(width: 8.0),
              Text(
                'Export Complete',
                style: TextStyle(
                  fontSize: 18.0,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          content: Text(
            '${result.exportedCount} photo${result.exportedCount == 1 ? '' : 's'} exported successfully.\n\n'
            'Archive size: ${LocalStorageCalculator.formatBytes(result.archiveSizeBytes)}.\n\n'
            'Your photos and metadata manifest have been bundled into a standard ZIP archive.',
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                DiaryExportService.instance.cleanTemporaryExports();
                Navigator.of(context).pop();
              },
              child: Text(
                'Done',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    } else if (result.isPartial) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.dialogRadius,
            side: BorderSide(color: AppColors.border, width: 0.8),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.warning,
                size: 22.0,
              ),
              const SizedBox(width: 8.0),
              Text(
                'Partial Export Complete',
                style: TextStyle(
                  fontSize: 18.0,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          content: Text(
            '${result.exportedCount} photo${result.exportedCount == 1 ? '' : 's'} were exported successfully.\n\n'
            '${result.skippedCount} photo${result.skippedCount == 1 ? ' was' : 's were'} skipped because the local file was missing or unreadable on disk.\n\n'
            'Archive size: ${LocalStorageCalculator.formatBytes(result.archiveSizeBytes)}.\n'
            'Skipped entries are documented in the manifest.json file.',
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                DiaryExportService.instance.cleanTemporaryExports();
                Navigator.of(context).pop();
              },
              child: Text(
                'Done',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    } else if (result.errorMessage != null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.dialogRadius,
            side: BorderSide(color: AppColors.border, width: 0.8),
          ),
          title: const Text(
            'Export Failed',
            style: TextStyle(
              fontSize: 18.0,
              fontWeight: FontWeight.w700,
              color: AppColors.error,
            ),
          ),
          content: Text(
            result.errorMessage!,
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Close',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _handleDeleteLocalDiary() async {
    final store = PersistentDailyPhotoStore.instance;
    final photoCount = store.totalPhotos;

    if (photoCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No local photos to delete.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final String contentText =
        'This will permanently delete all $photoCount locally stored photo${photoCount == 1 ? '' : 's'} and diary entries from this device.\n\n'
        'Because Daria operates entirely offline, this action cannot be undone.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.dialogRadius,
          side: BorderSide(color: AppColors.border, width: 0.8),
        ),
        title: Text(
          'Delete Local Diary?',
          style: TextStyle(
            fontSize: 18.0,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          contentText,
          style: AppTypography.body.copyWith(
            color: AppColors.textSecondary,
            height: 1.45,
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 10.0,
        ),
        actions: [
          Semantics(
            button: true,
            label: 'Cancel local diary deletion',
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(minimumSize: const Size(48.0, 48.0)),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Confirm deleting local diary',
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(minimumSize: const Size(48.0, 48.0)),
              child: const Text(
                'Delete Local Diary',
                style: TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeletingLocal = true);
    try {
      await store.deleteLocalDiary();
      await _refreshLocalStorageUsage();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Local diary photos and metadata have been deleted.'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDeletingLocal = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeService.instance,
      builder: (context, _) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageHorizontal,
            AppSpacing.sm,
            AppSpacing.pageHorizontal,
            AppSpacing.dockClearanceExtended,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppBreakpoints.maxSettingsWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Screen Header
                  _buildScreenHeader(),

                  const SizedBox(height: AppSpacing.md),

                  // Local Diary Info Card & Storage Transparency Banner
                  ListenableBuilder(
                    listenable: Listenable.merge([
                      PersistentDailyPhotoStore.instance,
                      AppThemeService.instance,
                    ]),
                    builder: (context, _) {
                      final photoStore = PersistentDailyPhotoStore.instance;

                      return Column(
                        children: [
                          _buildProfileCard(),
                          const SizedBox(height: AppSpacing.sm),
                          _buildStorageSyncIndicatorCard(photoStore),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: AppSpacing.md),

                  // Photo Statistics Row (Understated)
                  _buildStatisticsSection(),

                  const SizedBox(height: AppSpacing.lg),

                  // Preferences Group
                  ListenableBuilder(
                    listenable: DailyReminderService.instance,
                    builder: (context, _) {
                      final reminderService = DailyReminderService.instance;
                      final String reminderSubtitle;
                      if (reminderService.permissionDenied) {
                        reminderSubtitle =
                            'Permission denied • Enable in system settings';
                      } else if (reminderService.isEnabled) {
                        reminderSubtitle =
                            'Every day · ${reminderService.settings.formattedTime}';
                      } else {
                        reminderSubtitle =
                            'Get a daily reminder to capture your photo.';
                      }

                      return SettingsGroup(
                        title: 'Preferences',
                        children: [
                          SettingsTile(
                            title: 'App Settings',
                            subtitle:
                                'Preferences, reminders, layout, and options',
                            leadingIcon: Icons.settings_outlined,
                            leadingColor: AppColors.accent,
                            showChevron: true,
                            onTap: () => Navigator.pushNamed(
                              context,
                              AppConstants.settingsRoute,
                            ),
                          ),
                          SettingsTile(
                            title: 'Daily Reminder',
                            subtitle: reminderSubtitle,
                            leadingIcon: Icons.notifications_outlined,
                            leadingColor: AppColors.accent,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10.0,
                                    vertical: 5.0,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceSubtle,
                                    borderRadius: BorderRadius.circular(8.0),
                                    border: Border.all(
                                      color: AppColors.border,
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    reminderService.settings.formattedTime,
                                    style: TextStyle(
                                      fontSize: 12.0,
                                      fontWeight: FontWeight.w600,
                                      color: reminderService.isEnabled
                                          ? AppColors.textPrimary
                                          : AppColors.textMuted,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Semantics(
                                  button: true,
                                  label: 'Change reminder time',
                                  child: OutlinedButton(
                                    onPressed: _pickReminderTime,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.textPrimary,
                                      side: BorderSide(
                                        color: AppColors.border,
                                        width: 0.8,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10.0,
                                        vertical: 4.0,
                                      ),
                                      minimumSize: const Size(48.0, 48.0),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          8.0,
                                        ),
                                      ),
                                    ),
                                    child: const Text(
                                      'Edit',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Semantics(
                                  label: 'Daily reminder notification toggle',
                                  child: Switch.adaptive(
                                    value: reminderService.isEnabled,
                                    onChanged: _toggleReminder,
                                    activeThumbColor: AppColors.accent,
                                    activeTrackColor: AppColors.accent
                                        .withValues(alpha: 0.35),
                                  ),
                                ),
                              ],
                            ),
                            onTap: _pickReminderTime,
                          ),
                          SettingsTile(
                            title: 'Start of Week',
                            subtitle: 'Calendar grid layout',
                            leadingIcon: Icons.calendar_view_week_outlined,
                            leadingColor: AppColors.statDaysGreen,
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10.0,
                                vertical: 4.0,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceSubtle,
                                borderRadius: BorderRadius.circular(8.0),
                                border: Border.all(
                                  color: AppColors.border,
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                _startOfWeek,
                                style: TextStyle(
                                  fontSize: 12.0,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            onTap: _showStartOfWeekDialog,
                          ),
                          ListenableBuilder(
                            listenable: AppThemeService.instance,
                            builder: (context, _) {
                              final themeService = AppThemeService.instance;
                              final palette = themeService.currentPalette;
                              final isDark = themeService.isDark;
                              final followSystem = themeService.followSystem;

                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SettingsTile(
                                    title: 'Dark Mode',
                                    subtitle: isDark
                                        ? 'Midnight theme active'
                                        : 'Linen light theme active',
                                    leadingIcon: isDark
                                        ? Icons.dark_mode_rounded
                                        : Icons.light_mode_rounded,
                                    leadingColor: isDark
                                        ? const Color(0xFF818CF8)
                                        : const Color(0xFFF59E0B),
                                    trailing: Switch.adaptive(
                                      value: isDark,
                                      activeTrackColor: AppColors.accent,
                                      onChanged: (_) {
                                        themeService.toggleDarkLight();
                                      },
                                    ),
                                  ),
                                  SettingsTile(
                                    title: 'Match System Theme',
                                    subtitle: followSystem
                                        ? 'Auto-switches between Linen and Midnight based on phone settings'
                                        : 'Manual theme active',
                                    leadingIcon: Icons.brightness_auto_rounded,
                                    leadingColor: AppColors.statDaysGreen,
                                    trailing: Switch.adaptive(
                                      value: followSystem,
                                      activeTrackColor: AppColors.accent,
                                      onChanged: (val) {
                                        themeService.setFollowSystem(val);
                                      },
                                    ),
                                  ),
                                  SettingsTile(
                                    title: 'Theme & Palettes',
                                    subtitle:
                                        '${palette.name} • ${palette.description}',
                                    leadingIcon: Icons.palette_outlined,
                                    leadingColor: palette.accent,
                                    showChevron: true,
                                    onTap: () => Navigator.pushNamed(
                                      context,
                                      AppConstants.themeRoute,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  // Memories & Journal
                  SettingsGroup(
                    title: 'Memories & Journal',
                    children: [
                      SettingsTile(
                        title: 'Visual Diary',
                        subtitle:
                            'Browse your daily photo journal chronologically',
                        leadingIcon: Icons.auto_stories_rounded,
                        leadingColor: AppColors.accent,
                        showChevron: true,
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppConstants.diaryRoute,
                        ),
                      ),
                      SettingsTile(
                        title: 'On This Day',
                        subtitle: 'Look back at memories from years past',
                        leadingIcon: Icons.history_rounded,
                        leadingColor: AppColors.accent,
                        showChevron: true,
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppConstants.memoriesRoute,
                        ),
                      ),
                      SettingsTile(
                        title: 'Statistics',
                        subtitle: 'See your Daria history',
                        leadingIcon: Icons.insights_rounded,
                        leadingColor: AppColors.statDaysGreen,
                        showChevron: true,
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppConstants.statisticsRoute,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  // Storage & Data Section (Local-Only)
                  ListenableBuilder(
                    listenable: Listenable.merge([
                      PersistentDailyPhotoStore.instance,
                      AppThemeService.instance,
                    ]),
                    builder: (context, _) {
                      final photoStore = PersistentDailyPhotoStore.instance;
                      return SettingsGroup(
                        title: 'Data & Storage',
                        children: [
                          _buildLocalStorageTile(photoStore),
                          if (LocalStorageCalculator.isStorageWarning(
                            bytes: _localPhotoBytes,
                          ))
                            _buildStorageWarningTile(),
                          _buildCreatePortableBackupTile(),
                          _buildImportRestoreBackupTile(),
                          _buildExportPdfDiaryTile(),
                          _buildExportDiaryTile(),
                          _buildDeleteLocalDiaryTile(),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  // About & Legal
                  SettingsGroup(
                    title: 'About',
                    children: [
                      SettingsTile(
                        title: 'About Daria',
                        subtitle: 'The philosophy, pillars, and craftsmanship',
                        leadingIcon: Icons.info_outline_rounded,
                        leadingColor: AppColors.accent,
                        showChevron: true,
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppConstants.aboutRoute,
                        ),
                      ),
                      SettingsTile(
                        title: 'Privacy Policy',
                        subtitle:
                            'Local-first, zero trackers, your data stays yours',
                        leadingIcon: Icons.shield_outlined,
                        leadingColor: AppColors.statDaysGreen,
                        showChevron: true,
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppConstants.privacyRoute,
                        ),
                      ),
                      SettingsTile(
                        title: 'Licenses & Attributions',
                        subtitle: 'Open source packages and design assets',
                        leadingIcon: Icons.article_outlined,
                        leadingColor: AppColors.textSecondary,
                        showChevron: true,
                        onTap: () => showLicensePage(
                          context: context,
                          applicationName: AppConstants.appName,
                          applicationVersion: AppConstants.appVersion,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  // App Version Footer
                  Center(
                    child: Column(
                      children: [
                        const DariaLogo(size: 28.0),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${AppConstants.appName} v${AppConstants.appVersion}',
                          style: TextStyle(
                            fontSize: 12.0,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 2.0),
                        Text(
                          'One photo at a time.',
                          style: TextStyle(
                            fontSize: 11.0,
                            fontWeight: FontWeight.w400,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Screen Title Header
  Widget _buildScreenHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Profile', style: AppTypography.appTitle),
        const SizedBox(height: 2.0),
        Text(
          'Personal Diary & Preferences',
          style: AppTypography.screenSubtitle,
        ),
      ],
    );
  }

  /// Profile Summary Card
  Widget _buildProfileCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          // Diary icon container (warm subtle aesthetic)
          Container(
            width: 56.0,
            height: 56.0,
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            child: Center(
              child: Icon(
                Icons.auto_stories_rounded,
                color: AppColors.accent,
                size: 24.0,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'Daily Photo Diary',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(width: 6.0),
                    Icon(
                      Icons.shield_rounded,
                      size: 15.0,
                      color: AppColors.statDaysGreen,
                    ),
                  ],
                ),
                const SizedBox(height: 2.0),
                Text(
                  'Stored on device • Private & offline',
                  style: TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 6.0),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(10.0),
                    border: Border.all(color: AppColors.border, width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6.0,
                        height: 6.0,
                        decoration: const BoxDecoration(
                          color: AppColors.statusActiveGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5.0),
                      Text(
                        'Active Local Diary',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Prominent Storage Transparency Card
  Widget _buildStorageSyncIndicatorCard(PersistentDailyPhotoStore photoStore) {
    final int localPhotos = photoStore.totalPhotos;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36.0,
                height: 36.0,
                decoration: BoxDecoration(
                  color: AppColors.statIconBrown.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  color: AppColors.statIconBrown,
                  size: 20.0,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Local-Only Storage',
                      style: TextStyle(
                        fontSize: 15.0,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      'On Device Only',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.statIconBrown,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your $localPhotos daily photo${localPhotos == 1 ? '' : 's'} and diary memories are stored exclusively on this device. '
            'No cloud account or internet connection is required. Your personal memories are 100% private.',
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  /// Photo Streak Section reflecting live persistent photo records
  Widget _buildStatisticsSection() {
    return ListenableBuilder(
      listenable: Listenable.merge([
        PersistentDailyPhotoStore.instance,
        AppThemeService.instance,
      ]),
      builder: (context, _) {
        final summary = StreakService.instance.calculateStreak();
        const footnoteText =
            'Local diary streak derived from your daily photos.';

        return GestureDetector(
          onTap: () =>
              Navigator.pushNamed(context, AppConstants.statisticsRoute),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.card,
              border: Border.all(color: AppColors.border, width: 0.8),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('PHOTO STREAK', style: AppTypography.appTagline),
                    Icon(
                      Icons.local_fire_department_rounded,
                      size: 16.0,
                      color: summary.currentStreak > 0
                          ? AppColors.statStreakOrange
                          : AppColors.textMuted,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatItem(
                        value: summary.currentStreak == 1
                            ? '1 day'
                            : '${summary.currentStreak} days',
                        label: 'Current Streak',
                        icon: Icons.local_fire_department_rounded,
                        color: summary.currentStreak > 0
                            ? AppColors.statStreakOrange
                            : AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _buildStatItem(
                        value: summary.longestStreak == 1
                            ? '1 day'
                            : '${summary.longestStreak} days',
                        label: 'Longest Streak',
                        icon: Icons.trending_up_rounded,
                        color: summary.longestStreak > 0
                            ? AppColors.accent
                            : AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _buildStatItem(
                        value: summary.totalRecordedDays == 1
                            ? '1 day'
                            : '${summary.totalRecordedDays} days',
                        label: 'Recorded Days',
                        icon: Icons.calendar_today_outlined,
                        color: summary.totalRecordedDays > 0
                            ? AppColors.statDaysGreen
                            : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  footnoteText,
                  style: TextStyle(
                    fontSize: 11.0,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatItem({
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 4.0),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      child: Column(
        children: [
          Icon(icon, size: 15.0, color: color),
          const SizedBox(height: 3.0),
          Text(
            value,
            style: TextStyle(
              fontSize: 14.0,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 1.0),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.0,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLocalStorageTile(PersistentDailyPhotoStore photoStore) {
    final totalPhotos = photoStore.count;
    final storageSizeText = _isLoadingStorage
        ? 'Calculating...'
        : LocalStorageCalculator.formatBytes(_localPhotoBytes);
    final photoWord = totalPhotos == 1 ? 'photo' : 'photos';
    final subtitleText = '$totalPhotos $photoWord • $storageSizeText';

    return SettingsTile(
      title: 'Local Photo Storage',
      subtitle: subtitleText,
      leadingIcon: Icons.sd_storage_outlined,
      leadingColor: AppColors.statIconBlueGrey,
      showChevron: true,
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (context) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadii.dialogRadius,
                side: BorderSide(color: AppColors.border, width: 0.8),
              ),
              title: Text(
                'Local Photo Storage',
                style: TextStyle(
                  fontSize: 18.0,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$totalPhotos $photoWord stored locally on this device.',
                    style: AppTypography.body.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'App photo storage: $storageSizeText\n\n'
                    'All original photos are stored in app-managed persistent storage. '
                    'Storage calculation verifies actual on-disk file sizes.\n\n'
                    'This represents only the storage used by Daria photos, not your entire phone storage.',
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
              actionsPadding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 10.0,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Close',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildStorageWarningTile() {
    final formattedSize = LocalStorageCalculator.formatBytes(_localPhotoBytes);
    final formattedThreshold = LocalStorageCalculator.formatBytes(
      LocalStorageCalculator.storageWarningThresholdBytes,
    );

    return SettingsTile(
      title: 'Photo storage is getting large',
      subtitle:
          'Local photos use $formattedSize (advisory threshold: $formattedThreshold). Tap for details.',
      leadingIcon: Icons.warning_amber_rounded,
      leadingColor: AppColors.warning,
      showChevron: true,
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (context) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadii.dialogRadius,
                side: BorderSide(color: AppColors.border, width: 0.8),
              ),
              title: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.warning,
                    size: 22.0,
                  ),
                  const SizedBox(width: 8.0),
                  Text(
                    'Storage Advisory',
                    style: TextStyle(
                      fontSize: 18.0,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              content: Text(
                'Your Daria local storage has reached $formattedSize, '
                'which exceeds the advisory milestone guideline of $formattedThreshold.\n\n'
                'The app will continue saving your daily photos normally without disruption. '
                'If your device is low on storage, you can export your diary and manage older entries.',
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Understood',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCreatePortableBackupTile() {
    return SettingsTile(
      title: 'Create Portable Backup',
      subtitle: 'Export complete diary with original photos (.padbackup)',
      leadingIcon: Icons.archive_outlined,
      leadingColor: AppColors.accent,
      showChevron: true,
      onTap: () => PadBackupExportDialog.show(context),
    );
  }

  Widget _buildImportRestoreBackupTile() {
    return SettingsTile(
      title: 'Import / Restore Backup',
      subtitle: 'Restore memories from a .padbackup file',
      leadingIcon: Icons.unarchive_outlined,
      leadingColor: AppColors.accent,
      showChevron: true,
      onTap: () => PadBackupRestoreDialog.show(context),
    );
  }

  Widget _buildExportPdfDiaryTile() {
    return SettingsTile(
      title: 'Export as PDF Diary',
      subtitle: 'Print-ready photo book to save, share, or print',
      leadingIcon: Icons.picture_as_pdf_outlined,
      leadingColor: AppColors.accent,
      showChevron: true,
      onTap: () => PdfExportDialog.show(context),
    );
  }

  Widget _buildExportDiaryTile() {
    return SettingsTile(
      title: 'Export Diary',
      subtitle: _isExporting
          ? 'Preparing export archive...'
          : 'Export photos and metadata manifest as ZIP',
      leadingIcon: Icons.file_download_outlined,
      leadingColor: AppColors.accent,
      showChevron: !_isExporting,
      trailing: _isExporting
          ? SizedBox(
              width: 18.0,
              height: 18.0,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
                color: AppColors.accent,
              ),
            )
          : null,
      onTap: _isExporting ? null : _handleExportDiary,
    );
  }

  Widget _buildDeleteLocalDiaryTile() {
    return SettingsTile(
      title: 'Delete Local Diary',
      subtitle: _isDeletingLocal
          ? 'Deleting local diary data...'
          : 'Permanently remove all local photos and metadata',
      leadingIcon: Icons.delete_outline_rounded,
      leadingColor: AppColors.error,
      showChevron: !_isDeletingLocal,
      trailing: _isDeletingLocal
          ? const SizedBox(
              width: 18.0,
              height: 18.0,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
                color: AppColors.error,
              ),
            )
          : null,
      onTap: _isDeletingLocal ? null : _handleDeleteLocalDiary,
    );
  }
}
