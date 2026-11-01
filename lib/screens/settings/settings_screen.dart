import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/core/layout/app_breakpoints.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';
import 'package:photo_per_day/data/services/daily_reminder_service.dart';
import 'package:photo_per_day/data/services/diary_export_service.dart';
import 'package:photo_per_day/data/services/local_storage_calculator.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/widgets/pad_backup_export_dialog.dart';
import 'package:photo_per_day/widgets/pad_backup_restore_dialog.dart';
import 'package:photo_per_day/widgets/pdf_export_dialog.dart';
import 'package:photo_per_day/widgets/scrolling_time_picker.dart';
import 'package:photo_per_day/widgets/settings_group.dart';
import 'package:photo_per_day/widgets/settings_tile.dart';
import 'package:photo_per_day/widgets/daria_logo.dart';

/// Dedicated Settings screen for Photo a Day.
///
/// Houses application preferences (daily reminders, calendar layout, theme),
/// shortcuts to journal sections, data export/reset controls, legal notices,
/// and application version information.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _startOfWeek = 'Sunday';
  bool _isExporting = false;
  bool _isDeletingLocal = false;
  int _localPhotoBytes = 0;
  bool _isLoadingStorage = false;

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
      final msg = value
          ? 'Daily reminder enabled for ${reminderService.settings.formattedTime}'
          : 'Daily reminder disabled';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pickReminderTime() async {
    final reminderService = DailyReminderService.instance;
    final pickedTime = await ScrollingTimePickerDialog.show(
      context,
      initialTime: TimeOfDay(
        hour: reminderService.settings.hour,
        minute: reminderService.settings.minute,
      ),
    );

    if (pickedTime != null && mounted) {
      await reminderService.setTime(
        hour: pickedTime.hour,
        minute: pickedTime.minute,
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
    final photoCount = PersistentDailyPhotoStore.instance.totalPhotos;
    if (photoCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No photos to export yet. Take a photo first!'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isExporting = true);
    try {
      final result = await DiaryExportService.instance.exportDiary();
      if (!mounted) return;

      if (result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Diary exported successfully! (${result.exportedCount} photo${result.exportedCount == 1 ? '' : 's'})',
            ),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.errorMessage ?? 'Export failed. Please try again.',
            ),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  void _showLocalStorageDialog() {
    final totalPhotos = PersistentDailyPhotoStore.instance.totalPhotos;
    final storageSizeText = _isLoadingStorage
        ? 'Calculating...'
        : LocalStorageCalculator.formatBytes(_localPhotoBytes);
    final photoWord = totalPhotos == 1 ? 'photo' : 'photos';

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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.dialogRadius,
            side: BorderSide(color: AppColors.border, width: 0.8),
          ),
          title: const Text(
            'Delete Local Diary?',
            style: TextStyle(
              fontSize: 18.0,
              fontWeight: FontWeight.w700,
              color: AppColors.error,
            ),
          ),
          content: Text(
            'This will permanently delete all $photoCount locally stored photo${photoCount == 1 ? '' : 's'} and diary entries from this device.\n\n'
            'Because Daria operates entirely offline, this action cannot be undone.',
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
              child: const Text(
                'Delete Local Photos',
                style: TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeletingLocal = true);
    try {
      await store.deleteLocalDiary();
      await _refreshLocalStorageUsage();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Local diary photos and metadata have been deleted.'),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clear local diary: $e'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
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
        final isDark = AppColors.current.isDark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isDark
                ? Brightness.light
                : Brightness.dark,
            statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          ),
          child: Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppBreakpoints.maxSettingsWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Screen Header with back arrow
                      _buildHeader(),

                      // Scrollable Settings Content
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.pageHorizontal,
                            AppSpacing.xs,
                            AppSpacing.pageHorizontal,
                            AppSpacing.xl,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Preferences Group
                              ListenableBuilder(
                                listenable: DailyReminderService.instance,
                                builder: (context, _) {
                                  final reminderService =
                                      DailyReminderService.instance;
                                  final isEnabled = reminderService.isEnabled;

                                  return SettingsGroup(
                                    title: 'Preferences',
                                    children: [
                                      // 1. Daily Reminder Toggle Row
                                      SettingsTile(
                                        title: 'Daily Reminder',
                                        subtitle:
                                            'Receive a reminder to capture today\'s photo',
                                        leadingIcon:
                                            Icons.notifications_outlined,
                                        leadingColor: AppColors.accent,
                                        trailing: Semantics(
                                          label:
                                              'Daily reminder notification toggle, currently ${isEnabled ? "ON" : "OFF"}',
                                          child: Switch.adaptive(
                                            value: isEnabled,
                                            onChanged: _toggleReminder,
                                            activeThumbColor: AppColors.accent,
                                            activeTrackColor: AppColors.accent
                                                .withValues(alpha: 0.35),
                                          ),
                                        ),
                                      ),

                                      // 2. Reminder Time with Explicit Edit Button
                                      SettingsTile(
                                        title: isEnabled
                                            ? 'Reminder Time'
                                            : 'Time',
                                        subtitle: isEnabled
                                            ? 'Daily alert at ${reminderService.settings.formattedTime}'
                                            : 'Subdued while reminder is off',
                                        leadingIcon: Icons.access_time_rounded,
                                        leadingColor: isEnabled
                                            ? AppColors.accent
                                            : AppColors.textMuted,
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10.0,
                                                    vertical: 5.0,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: AppColors.surfaceSubtle,
                                                borderRadius:
                                                    BorderRadius.circular(8.0),
                                                border: Border.all(
                                                  color: AppColors.border,
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: Text(
                                                reminderService
                                                    .settings
                                                    .formattedTime,
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: isEnabled
                                                      ? AppColors.textPrimary
                                                      : AppColors.textMuted,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(
                                              width: AppSpacing.sm,
                                            ),
                                            Semantics(
                                              button: true,
                                              label: 'Edit reminder time',
                                              child: OutlinedButton(
                                                onPressed: _pickReminderTime,
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      AppColors.textPrimary,
                                                  side: BorderSide(
                                                    color: AppColors.border,
                                                    width: 0.8,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 14.0,
                                                        vertical: 6.0,
                                                      ),
                                                  minimumSize: const Size(
                                                    48.0,
                                                    34.0,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10.0,
                                                        ),
                                                  ),
                                                ),
                                                child: const Text(
                                                  'Edit',
                                                  style: TextStyle(
                                                    fontSize: 12.0,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        onTap: _pickReminderTime,
                                      ),

                                      // 3. Start of Week
                                      SettingsTile(
                                        title: 'Start of Week',
                                        subtitle: 'Calendar grid layout',
                                        leadingIcon:
                                            Icons.calendar_view_week_outlined,
                                        leadingColor: AppColors.statDaysGreen,
                                        trailing: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10.0,
                                            vertical: 4.0,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.surfaceSubtle,
                                            borderRadius: BorderRadius.circular(
                                              8.0,
                                            ),
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

                                      // 4. Appearance & Theme Controls
                                      ListenableBuilder(
                                        listenable: AppThemeService.instance,
                                        builder: (context, _) {
                                          final themeService =
                                              AppThemeService.instance;
                                          final palette =
                                              themeService.currentPalette;
                                          final isDark = themeService.isDark;
                                          final followSystem =
                                              themeService.followSystem;

                                          return Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SettingsTile(
                                                title: 'Dark Mode',
                                                subtitle: isDark
                                                    ? '${themeService.currentPalette.name} theme active'
                                                    : '${themeService.currentPalette.name} light theme active',
                                                leadingIcon: isDark
                                                    ? Icons.dark_mode_rounded
                                                    : Icons.light_mode_rounded,
                                                leadingColor: isDark
                                                    ? const Color(0xFF818CF8)
                                                    : const Color(0xFFF59E0B),
                                                trailing: Switch.adaptive(
                                                  value: isDark,
                                                  activeTrackColor:
                                                      AppColors.accent,
                                                  onChanged: (_) {
                                                    themeService
                                                        .toggleDarkLight();
                                                  },
                                                ),
                                              ),
                                              SettingsTile(
                                                title: 'Match System Theme',
                                                subtitle: followSystem
                                                    ? 'Auto-switches between Linen and Midnight based on phone settings'
                                                    : 'Manual theme active',
                                                leadingIcon: Icons
                                                    .brightness_auto_rounded,
                                                leadingColor:
                                                    AppColors.statDaysGreen,
                                                trailing: Switch.adaptive(
                                                  value: followSystem,
                                                  activeTrackColor:
                                                      AppColors.accent,
                                                  onChanged: (val) {
                                                    themeService
                                                        .setFollowSystem(val);
                                                  },
                                                ),
                                              ),
                                              SettingsTile(
                                                title: 'Theme & Palettes',
                                                subtitle:
                                                    '${palette.name} • ${palette.description}',
                                                leadingIcon:
                                                    Icons.palette_outlined,
                                                leadingColor: palette.accent,
                                                showChevron: true,
                                                onTap: () =>
                                                    Navigator.pushNamed(
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
                                    subtitle:
                                        'Look back at memories from years past',
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

                              // Data & Storage
                              SettingsGroup(
                                title: 'Data & Storage',
                                children: [
                                  SettingsTile(
                                    title: 'Local Photo Storage',
                                    subtitle:
                                        '${PersistentDailyPhotoStore.instance.totalPhotos} ${PersistentDailyPhotoStore.instance.totalPhotos == 1 ? "photo" : "photos"} • ${_isLoadingStorage ? "Calculating..." : LocalStorageCalculator.formatBytes(_localPhotoBytes)}',
                                    leadingIcon: Icons.sd_storage_outlined,
                                    leadingColor: AppColors.statIconBlueGrey,
                                    showChevron: true,
                                    onTap: _showLocalStorageDialog,
                                  ),
                                  SettingsTile(
                                    title: 'Create Portable Backup',
                                    subtitle:
                                        'Export complete diary with original photos (.padbackup)',
                                    leadingIcon: Icons.archive_outlined,
                                    leadingColor: AppColors.accent,
                                    showChevron: true,
                                    onTap: () =>
                                        PadBackupExportDialog.show(context),
                                  ),
                                  SettingsTile(
                                    title: 'Import / Restore Backup',
                                    subtitle:
                                        'Restore memories from a .padbackup file',
                                    leadingIcon: Icons.unarchive_outlined,
                                    leadingColor: AppColors.accent,
                                    showChevron: true,
                                    onTap: () =>
                                        PadBackupRestoreDialog.show(context),
                                  ),
                                  SettingsTile(
                                    title: 'Export as PDF Diary',
                                    subtitle:
                                        'Print-ready photo book to save, share, or print',
                                    leadingIcon: Icons.picture_as_pdf_outlined,
                                    leadingColor: AppColors.accent,
                                    showChevron: true,
                                    onTap: () => PdfExportDialog.show(context),
                                  ),
                                  SettingsTile(
                                    title: 'Export Diary',
                                    subtitle:
                                        'Save all photos & memories as a ZIP archive',
                                    leadingIcon: Icons.file_download_outlined,
                                    leadingColor: AppColors.accent,
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
                                    showChevron: !_isExporting,
                                    onTap: _isExporting
                                        ? null
                                        : _handleExportDiary,
                                  ),
                                  SettingsTile(
                                    title: 'Delete Local Diary',
                                    subtitle:
                                        'Permanently remove all local photos and metadata',
                                    leadingIcon: Icons.delete_outline_rounded,
                                    leadingColor: AppColors.error,
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
                                    showChevron: !_isDeletingLocal,
                                    onTap: _isDeletingLocal
                                        ? null
                                        : _handleDeleteLocalDiary,
                                  ),
                                ],
                              ),

                              const SizedBox(height: AppSpacing.lg),

                              // About & Legal
                              SettingsGroup(
                                title: 'About',
                                children: [
                                  SettingsTile(
                                    title: 'About Daria',
                                    subtitle:
                                        'The philosophy, pillars, and craftsmanship',
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
                                    title: 'Terms of Service',
                                    subtitle:
                                        'Simple, fair terms and full copyright ownership',
                                    leadingIcon: Icons.description_outlined,
                                    leadingColor: AppColors.statIconNeutral,
                                    showChevron: true,
                                    onTap: () => Navigator.pushNamed(
                                      context,
                                      AppConstants.termsRoute,
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
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageHorizontal,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.arrow_back_rounded,
              color: AppColors.textPrimary,
              size: 22.0,
            ),
            tooltip: 'Back',
            onPressed: () => Navigator.maybePop(context),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Settings', style: AppTypography.appTitle),
                const SizedBox(height: 2.0),
                Text(
                  'APP PREFERENCES & CONFIGURATION',
                  style: AppTypography.appTagline,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
