import 'package:flutter/material.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_shadows.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';
import 'package:photo_per_day/data/models/auth_status.dart';
import 'package:photo_per_day/data/models/drive_auth_status.dart';
import 'package:photo_per_day/data/models/drive_folder_result.dart';
import 'package:photo_per_day/data/models/drive_folder_status.dart';
import 'package:photo_per_day/data/models/drive_photo_upload_result.dart';
import 'package:photo_per_day/data/models/sync_operation_status.dart';
import 'package:photo_per_day/data/models/sync_operation_type.dart';
import 'package:photo_per_day/data/models/sync_presentation_model.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/google_auth_service.dart';
import 'package:photo_per_day/data/services/google_drive_auth_service.dart';
import 'package:photo_per_day/data/services/google_drive_photo_upload_service.dart';
import 'package:photo_per_day/data/services/google_drive_service.dart';
import 'package:photo_per_day/data/services/local_storage_calculator.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/sync_coordinator.dart';
import 'package:photo_per_day/data/services/sync_queue.dart';
import 'package:photo_per_day/data/services/sync_worker.dart';
import 'package:photo_per_day/utils/time_ago_formatter.dart';
import 'package:photo_per_day/widgets/settings_group.dart';
import 'package:photo_per_day/widgets/settings_tile.dart';

/// Profile and Settings screen for Photo a Day.
///
/// Features a personal user profile header, understated photo statistics,
/// customizable preferences (daily reminders, week start, theme),
/// cloud backup status preview, account rows, and informational modals.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _reminderEnabled = true;
  final String _reminderTime = '8:00 PM';
  String _startOfWeek = 'Sunday';
  double? _uploadProgress;
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

  Future<void> _handleSignIn() async {
    final user = await GoogleAuthService.instance.signIn();
    if (mounted && user != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Signed in as ${user.email}'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleSignOut() async {
    await GoogleAuthService.instance.signOut();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Signed out of Google account'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleAuthorizeDrive() async {
    final success = await GoogleDriveAuthService.instance.authorizeDrive();
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google Drive authorized successfully!'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        final error = GoogleDriveAuthService.instance.errorMessage;
        if (error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _handleSetupFolder() async {
    final result = await GoogleDriveService.instance.setupFolder();
    if (mounted) {
      if (result is DriveFolderSuccess) {
        final msg = result.wasCreated
            ? 'Created "Photo a Day" folder in Google Drive!'
            : 'Connected to "Photo a Day" folder in Google Drive!';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (result is DriveFolderFailure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleDisconnect() async {
    await GoogleDriveService.instance.clearFolderReference();
    await GoogleDriveAuthService.instance.clearAuthorization();
    await GoogleAuthService.instance.disconnect();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Disconnected Google account and revoked permissions'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _toggleReminder(bool value) {
    setState(() {
      _reminderEnabled = value;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? 'Daily reminder enabled for $_reminderTime'
              : 'Daily reminder disabled',
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showStartOfWeekDialog() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          backgroundColor: AppColors.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadii.dialogRadius,
            side: BorderSide(color: AppColors.border, width: 0.8),
          ),
          title: const Text(
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
                    const Text('Sunday', style: TextStyle(fontSize: 15.0)),
                    if (_startOfWeek == 'Sunday')
                      const Icon(
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
                    const Text('Monday', style: TextStyle(fontSize: 15.0)),
                    if (_startOfWeek == 'Monday')
                      const Icon(
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

  void _showThemeInfoDialog() {
    _showInfoDialog(
      title: 'Theme & Appearance',
      content:
          'Photo a Day is tuned with a custom "Warm Linen" palette designed for calm, personal daily journaling. Dynamic dark mode and seasonal tints will be available in future releases.',
    );
  }

  void _showCloudBackupDialog() {
    final drive = GoogleDriveService.instance;
    final driveAuth = GoogleDriveAuthService.instance;
    final String content;
    if (drive.isReady) {
      final folder = drive.currentFolder;
      content =
          'Google Drive "Photo a Day" folder is ready!\n\n'
          'Folder: ${folder?.folderName ?? "Photo a Day"}\n'
          'Account: ${folder?.authorizedEmail ?? "Connected Google Account"}\n\n'
          'Your dedicated folder has been resolved in your Google Drive. In upcoming milestones, photos will sync here. No photos have been uploaded yet.';
    } else if (driveAuth.isAuthorized) {
      content =
          'Google Drive authorization is granted!\n\n'
          'Tap "Set Up" to locate or create your user-visible "Photo a Day" folder in Google Drive.';
    } else {
      content =
          'User-owned cloud backup connects directly to your personal Google Drive. Your daily photos and journal memories will always remain 100% under your ownership and control.';
    }

    _showInfoDialog(
      title: 'Google Drive Backup',
      content: content,
      actionText: 'Got It',
    );
  }

  void _showAboutDialog() {
    _showInfoDialog(
      title: 'About Photo a Day',
      content:
          'Photo a Day is a mindful, single-moment daily photograph journal. Designed to help you capture your life one photo at a time, without social media noise or algorithmic feeds.',
      actionText: 'Close',
    );
  }

  void _showPrivacyDialog() {
    _showInfoDialog(
      title: 'Privacy Policy',
      content:
          'Your memories belong entirely to you.\n\nAll photos are stored locally on your device. Photo a Day does not track your location, sell personal data, or upload your memories to third-party advertising servers.',
      actionText: 'I Understand',
    );
  }

  void _showTermsDialog() {
    _showInfoDialog(
      title: 'Terms of Service',
      content:
          'Photo a Day is provided for personal, non-commercial daily journaling. You retain full copyright and ownership of all photos captured or imported into the application.',
      actionText: 'Close',
    );
  }

  void _showInfoDialog({
    required String title,
    required String content,
    String actionText = 'Close',
  }) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadii.dialogRadius,
            side: BorderSide(color: AppColors.border, width: 0.8),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 18.0,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          content: Text(
            content,
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
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                actionText,
                style: const TextStyle(
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageHorizontal,
        AppSpacing.sm,
        AppSpacing.pageHorizontal,
        AppSpacing.dockClearanceExtended,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Screen Header
          _buildScreenHeader(),

          const SizedBox(height: AppSpacing.md),

          // Profile Info Card
          _buildProfileCard(),

          const SizedBox(height: AppSpacing.md),

          // Photo Statistics Row (Understated)
          _buildStatisticsSection(),

          const SizedBox(height: AppSpacing.lg),

          // Preferences Group
          SettingsGroup(
            title: 'Preferences',
            children: [
              SettingsTile(
                title: 'Daily Reminder',
                subtitle: _reminderEnabled
                    ? '$_reminderTime • Evening reflection'
                    : 'Reminders turned off',
                leadingIcon: Icons.notifications_outlined,
                leadingColor: AppColors.accent,
                trailing: Switch.adaptive(
                  value: _reminderEnabled,
                  onChanged: _toggleReminder,
                  activeThumbColor: AppColors.textPrimary,
                  activeTrackColor: AppColors.surfaceSubtle,
                ),
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
                    border: Border.all(color: AppColors.border, width: 0.8),
                  ),
                  child: Text(
                    _startOfWeek,
                    style: const TextStyle(
                      fontSize: 12.0,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                onTap: _showStartOfWeekDialog,
              ),
              SettingsTile(
                title: 'Theme & Palette',
                subtitle: 'Warm Linen (Tailored)',
                leadingIcon: Icons.palette_outlined,
                leadingColor: AppColors.statIconBrown,
                showChevron: true,
                onTap: _showThemeInfoDialog,
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),

          // Memories & Journal
          SettingsGroup(
            title: 'Memories & Journal',
            children: [
              SettingsTile(
                title: 'Visual Diary',
                subtitle: 'Browse your daily photo journal chronologically',
                leadingIcon: Icons.auto_stories_rounded,
                leadingColor: AppColors.accent,
                showChevron: true,
                onTap: () =>
                    Navigator.pushNamed(context, AppConstants.diaryRoute),
              ),
              SettingsTile(
                title: 'On This Day',
                subtitle: 'Look back at memories from years past',
                leadingIcon: Icons.history_rounded,
                leadingColor: AppColors.accent,
                showChevron: true,
                onTap: () =>
                    Navigator.pushNamed(context, AppConstants.memoriesRoute),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),

          // Storage & Cloud Backup and Account Sections
          ListenableBuilder(
            listenable: Listenable.merge([
              GoogleAuthService.instance,
              GoogleDriveAuthService.instance,
              GoogleDriveService.instance,
              GoogleDrivePhotoUploadService.instance,
              SyncWorker.instance,
              SyncCoordinator.instance,
              PersistentDailyPhotoStore.instance,
            ]),
            builder: (context, _) {
              final auth = GoogleAuthService.instance;
              final driveAuth = GoogleDriveAuthService.instance;
              final drive = GoogleDriveService.instance;
              final syncWorker = SyncWorker.instance;
              final photoStore = PersistentDailyPhotoStore.instance;
              final coordinator = SyncCoordinator.instance;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsGroup(
                    title: 'Storage & Backup',
                    children: [
                      _buildBackupStatusTile(
                        auth,
                        driveAuth,
                        drive,
                        syncWorker,
                        photoStore,
                        coordinator,
                      ),
                      _buildSyncSummaryTile(photoStore, auth),
                      _buildDriveBackupTile(auth, driveAuth, drive),
                      if (drive.isReady) _buildTestUploadTile(),
                      _buildSyncNowTile(
                        auth,
                        driveAuth,
                        drive,
                        syncWorker,
                        photoStore,
                      ),
                      _buildLocalStorageTile(photoStore),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  SettingsGroup(
                    title: 'Account',
                    children: [
                      _buildAccountTile(auth),
                      if (auth.isSignedIn)
                        SettingsTile(
                          title: 'Revoke Permissions',
                          subtitle:
                              'Disconnect Google account and revoke access',
                          leadingIcon: Icons.link_off_rounded,
                          leadingColor: AppColors.statIconNeutral,
                          showChevron: true,
                          onTap: _handleDisconnect,
                        ),
                    ],
                  ),
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
                title: 'About Photo a Day',
                leadingIcon: Icons.info_outline_rounded,
                leadingColor: AppColors.accent,
                showChevron: true,
                onTap: _showAboutDialog,
              ),
              SettingsTile(
                title: 'Privacy Policy',
                leadingIcon: Icons.lock_outline_rounded,
                leadingColor: AppColors.statIconPurple,
                showChevron: true,
                onTap: _showPrivacyDialog,
              ),
              SettingsTile(
                title: 'Terms of Service',
                leadingIcon: Icons.description_outlined,
                leadingColor: AppColors.statIconNeutral,
                showChevron: true,
                onTap: _showTermsDialog,
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),

          // App Version Footer
          const Center(
            child: Column(
              children: [
                Text(
                  '${AppConstants.appName} v${AppConstants.appVersion}',
                  style: TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                SizedBox(height: 2.0),
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
    );
  }

  /// Screen Title Header
  Widget _buildScreenHeader() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Profile & Settings', style: AppTypography.appTitle),
        SizedBox(height: 2.0),
        Text(
          'Personal preferences & memory vault',
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
          // Avatar Container
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
            child: const Center(
              child: Text(
                'SJ',
                style: TextStyle(
                  fontSize: 19.0,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),

          const SizedBox(width: AppSpacing.md),

          // User info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                  children: [
                    Text(
                      'Sarah Jenkins',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(width: 6.0),
                    Icon(
                      Icons.verified_rounded,
                      size: 15.0,
                      color: AppColors.accent,
                    ),
                  ],
                ),
                const SizedBox(height: 2.0),
                const Text(
                  'Member since January 2026',
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
                      const Text(
                        'Active Journal',
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

  /// Builds reactive Account SettingsTile reflecting current GoogleAuthService status
  Widget _buildAccountTile(GoogleAuthService auth) {
    switch (auth.status) {
      case AuthStatus.signingIn:
        return const SettingsTile(
          title: 'Google Account',
          subtitle: 'Signing in to Google...',
          leadingIcon: Icons.account_circle_outlined,
          leadingColor: AppColors.textPrimary,
          trailing: SizedBox(
            width: 18.0,
            height: 18.0,
            child: CircularProgressIndicator(
              strokeWidth: 2.0,
              color: AppColors.accent,
            ),
          ),
        );
      case AuthStatus.signedIn:
        final user = auth.currentUser;
        return SettingsTile(
          title: user?.displayName ?? user?.email ?? 'Google Account',
          subtitle: user != null ? user.email : 'Signed in',
          leadingIcon: Icons.account_circle_rounded,
          leadingColor: AppColors.accent,
          trailing: TextButton(
            onPressed: _handleSignOut,
            child: const Text(
              'Sign Out',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 13.0,
              ),
            ),
          ),
        );
      case AuthStatus.error:
        return SettingsTile(
          title: 'Google Account',
          subtitle: auth.errorMessage ?? 'Sign-in failed. Tap retry.',
          leadingIcon: Icons.error_outline_rounded,
          leadingColor: AppColors.error,
          trailing: TextButton(
            onPressed: _handleSignIn,
            child: const Text(
              'Retry',
              style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
                fontSize: 13.0,
              ),
            ),
          ),
        );
      case AuthStatus.signedOut:
        return SettingsTile(
          title: 'Google Account',
          subtitle: 'Sign in to enable future cloud sync',
          leadingIcon: Icons.account_circle_outlined,
          leadingColor: AppColors.textPrimary,
          trailing: TextButton(
            onPressed: _handleSignIn,
            child: const Text(
              'Sign In',
              style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
                fontSize: 13.0,
              ),
            ),
          ),
        );
    }
  }

  /// Builds derived Backup Status tile reflecting account, Drive auth, and queue/store state
  Widget _buildBackupStatusTile(
    GoogleAuthService auth,
    GoogleDriveAuthService driveAuth,
    GoogleDriveService drive,
    SyncWorker syncWorker,
    PersistentDailyPhotoStore photoStore,
    SyncCoordinator coordinator,
  ) {
    final queue = photoStore.syncQueue;
    final currentEmail = auth.currentUser?.email;
    final summary = SyncSummary.compute(
      store: photoStore,
      queue: queue,
      currentAccountEmail: currentEmail,
    );

    final isSyncing = coordinator.isSyncing || syncWorker.isSyncing;
    final hasFailedOps = queue.pendingOperations.any(
      (op) => op.status == SyncOperationStatus.failed,
    );

    final String backupStatus;
    final IconData statusIcon;
    final Color statusColor;

    if (isSyncing) {
      backupStatus = 'Backing up...';
      statusIcon = Icons.cloud_sync_outlined;
      statusColor = AppColors.accent;
    } else if (hasFailedOps || summary.failedCount > 0) {
      backupStatus = 'Backup failed';
      statusIcon = Icons.error_outline_rounded;
      statusColor = AppColors.error;
    } else if (summary.waitingCount > 0 || queue.pendingOperations.isNotEmpty) {
      final waitingNum = summary.waitingCount > 0
          ? summary.waitingCount
          : queue.pendingOperations.length;
      backupStatus =
          '$waitingNum photo${waitingNum == 1 ? '' : 's'} waiting to sync';
      statusIcon = Icons.schedule_rounded;
      statusColor = AppColors.accent;
    } else if (!auth.isSignedIn || !driveAuth.isAuthorized || !drive.isReady) {
      backupStatus = 'Not connected';
      statusIcon = Icons.cloud_off_outlined;
      statusColor = AppColors.textMuted;
    } else {
      if (coordinator.lastSyncSuccessAt != null) {
        final timeStr = TimeAgoFormatter.format(coordinator.lastSyncSuccessAt!);
        backupStatus = 'Up to date • Last backed up $timeStr';
      } else {
        backupStatus = 'Up to date';
      }
      statusIcon = Icons.cloud_done_outlined;
      statusColor = AppColors.statIconForest;
    }

    final accountText = auth.isSignedIn
        ? (auth.currentUser?.email ?? 'signed in')
        : 'signed out';
    final driveAuthText = driveAuth.isAuthorized
        ? 'authorized'
        : 'not authorized';

    return SettingsTile(
      title: 'Backup Status',
      subtitle:
          '$backupStatus\nGoogle account: $accountText • Drive: $driveAuthText',
      leadingIcon: statusIcon,
      leadingColor: statusColor,
    );
  }

  /// Builds derived Backup Summary tile showing aggregate photo sync counts
  Widget _buildSyncSummaryTile(
    PersistentDailyPhotoStore photoStore,
    GoogleAuthService auth,
  ) {
    final queue = photoStore.syncQueue;
    final currentEmail = auth.currentUser?.email;
    final summary = SyncSummary.compute(
      store: photoStore,
      queue: queue,
      currentAccountEmail: currentEmail,
    );

    return SettingsTile(
      title: 'Backup Summary',
      subtitle:
          'Backed up: ${summary.backedUpCount} • Waiting: ${summary.waitingCount} • Failed: ${summary.failedCount} • Local only: ${summary.localOnlyCount}',
      leadingIcon: Icons.pie_chart_outline_rounded,
      leadingColor: AppColors.statIconForest,
    );
  }

  /// Builds accurate local device storage tile calculated from actual on-disk files
  Widget _buildLocalStorageTile(PersistentDailyPhotoStore photoStore) {
    final totalMemories = photoStore.count;
    final storageSizeText = _isLoadingStorage
        ? 'Calculating...'
        : LocalStorageCalculator.formatBytes(_localPhotoBytes);
    final subtitleText = '$totalMemories memories • $storageSizeText';

    return SettingsTile(
      title: 'Local Device Storage',
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
              shape: const RoundedRectangleBorder(
                borderRadius: AppRadii.dialogRadius,
                side: BorderSide(color: AppColors.border, width: 0.8),
              ),
              title: const Text(
                'Local Storage',
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
                    '$totalMemories memories stored locally on this device.',
                    style: AppTypography.body.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Total storage used: $storageSizeText\n\n'
                    'All original photos are stored in app-managed persistent storage. '
                    'Storage calculation verifies actual on-disk file sizes.',
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
                  child: const Text(
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

  /// Builds reactive Google Drive Backup SettingsTile reflecting authorization and folder state
  Widget _buildDriveBackupTile(
    GoogleAuthService auth,
    GoogleDriveAuthService driveAuth,
    GoogleDriveService drive,
  ) {
    if (!auth.isSignedIn) {
      return SettingsTile(
        title: 'Google Drive Backup',
        subtitle: 'Not connected • Cloud storage',
        leadingIcon: Icons.cloud_outlined,
        leadingColor: AppColors.statIconForest,
        trailing: OutlinedButton(
          onPressed: _showCloudBackupDialog,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.border),
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 6.0,
            ),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
          ),
          child: const Text(
            'Connect',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    switch (driveAuth.status) {
      case DriveAuthStatus.authorizing:
        return const SettingsTile(
          title: 'Google Drive Backup',
          subtitle: 'Requesting Drive permission...',
          leadingIcon: Icons.cloud_sync_outlined,
          leadingColor: AppColors.accent,
          trailing: SizedBox(
            width: 18.0,
            height: 18.0,
            child: CircularProgressIndicator(
              strokeWidth: 2.0,
              color: AppColors.accent,
            ),
          ),
        );
      case DriveAuthStatus.authorized:
        switch (drive.status) {
          case DriveFolderStatus.settingUp:
            return const SettingsTile(
              title: 'Google Drive Backup',
              subtitle: 'Setting up Google Drive...',
              leadingIcon: Icons.cloud_sync_outlined,
              leadingColor: AppColors.accent,
              trailing: SizedBox(
                width: 18.0,
                height: 18.0,
                child: CircularProgressIndicator(
                  strokeWidth: 2.0,
                  color: AppColors.accent,
                ),
              ),
            );
          case DriveFolderStatus.ready:
            return SettingsTile(
              title: 'Google Drive Backup',
              subtitle: 'Google Drive • Photo a Day folder ready',
              leadingIcon: Icons.cloud_done_outlined,
              leadingColor: AppColors.statIconForest,
              trailing: OutlinedButton(
                onPressed: _showCloudBackupDialog,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 6.0,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                ),
                child: const Text(
                  'Details',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
            );
          case DriveFolderStatus.error:
            return SettingsTile(
              title: 'Google Drive Backup',
              subtitle: drive.errorMessage ?? "Couldn't set up Google Drive",
              leadingIcon: Icons.error_outline_rounded,
              leadingColor: AppColors.error,
              trailing: OutlinedButton(
                onPressed: _handleSetupFolder,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.accent),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 6.0,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
            );
          case DriveFolderStatus.uninitialized:
            return SettingsTile(
              title: 'Google Drive Backup',
              subtitle: 'Drive authorized • Setup required',
              leadingIcon: Icons.create_new_folder_outlined,
              leadingColor: AppColors.accent,
              trailing: OutlinedButton(
                onPressed: _handleSetupFolder,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.accent),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 6.0,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                ),
                child: const Text(
                  'Set Up',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
            );
        }
      case DriveAuthStatus.denied:
        return SettingsTile(
          title: 'Google Drive Backup',
          subtitle: 'Permission denied • Tap to authorize',
          leadingIcon: Icons.cloud_off_outlined,
          leadingColor: AppColors.error,
          trailing: OutlinedButton(
            onPressed: _handleAuthorizeDrive,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: AppColors.accent),
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 6.0,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
            ),
            child: const Text(
              'Authorize',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ),
        );
      case DriveAuthStatus.error:
        return SettingsTile(
          title: 'Google Drive Backup',
          subtitle:
              driveAuth.errorMessage ?? 'Authorization failed. Tap to retry.',
          leadingIcon: Icons.error_outline_rounded,
          leadingColor: AppColors.error,
          trailing: OutlinedButton(
            onPressed: _handleAuthorizeDrive,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: AppColors.accent),
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 6.0,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
            ),
            child: const Text(
              'Retry',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ),
        );
      case DriveAuthStatus.notAuthorized:
        return SettingsTile(
          title: 'Google Drive Backup',
          subtitle: 'Not authorized • Cloud storage',
          leadingIcon: Icons.cloud_outlined,
          leadingColor: AppColors.statIconForest,
          trailing: OutlinedButton(
            onPressed: _handleAuthorizeDrive,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 6.0,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
            ),
            child: const Text(
              'Enable Drive Backup',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ),
        );
    }
  }

  /// Single photo upload proof tile shown when Drive folder is ready
  Widget _buildTestUploadTile() {
    final uploadService = GoogleDrivePhotoUploadService.instance;
    final isUploading = uploadService.hasActiveUpload;

    return SettingsTile(
      title: 'Upload Test Photo',
      subtitle: isUploading
          ? (_uploadProgress != null
                ? 'Uploading to Drive... (${(_uploadProgress! * 100).clamp(0, 100).toInt()}%)'
                : 'Uploading photo to Drive...')
          : 'Proof of concept • Upload 1 photo to Drive',
      leadingIcon: Icons.cloud_upload_outlined,
      leadingColor: AppColors.accent,
      trailing: isUploading
          ? SizedBox(
              width: 18.0,
              height: 18.0,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
                value: _uploadProgress,
                color: AppColors.accent,
              ),
            )
          : OutlinedButton(
              onPressed: _handleTestUploadPhoto,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: const BorderSide(color: AppColors.accent),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 6.0,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
              ),
              child: const Text(
                'Upload',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
            ),
    );
  }

  Future<void> _handleTestUploadPhoto() async {
    final uploadService = GoogleDrivePhotoUploadService.instance;
    if (uploadService.hasActiveUpload) return;

    final allPhotos = PersistentDailyPhotoStore.instance.allEntries;
    final candidatePhotos = allPhotos
        .where((p) => p.hasRealImage && p.imagePath != null)
        .toList();

    if (candidatePhotos.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No local photo available to upload. Capture or add a photo first.',
            ),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // Pick first un-synced photo if available, otherwise first photo
    final photoToUpload = candidatePhotos.firstWhere(
      (p) => p.syncStatus != SyncStatus.synced,
      orElse: () => candidatePhotos.first,
    );

    // Confirmation Dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadii.dialogRadius,
            side: BorderSide(color: AppColors.border, width: 0.8),
          ),
          title: const Text(
            'Upload Test Photo',
            style: TextStyle(
              fontSize: 18.0,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          content: Text(
            'Upload memory for ${photoToUpload.dateKey.format()} to "Photo a Day" in Google Drive?\n\nThis will test uploading exactly one photo directly to your Drive folder.',
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
              child: const Text(
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
                'Upload',
                style: TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _uploadProgress = 0.0;
    });

    try {
      final result = await uploadService.uploadPhoto(
        entry: photoToUpload,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _uploadProgress = progress;
            });
          }
        },
      );

      if (mounted) {
        if (result is DrivePhotoUploadSuccess) {
          final shortId = result.fileId.length > 8
              ? result.fileId.substring(0, 8)
              : result.fileId;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Uploaded "${result.remoteFilename}" successfully! (ID: $shortId...)',
              ),
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else if (result is DrivePhotoUploadAlreadySynced) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Photo for ${result.dateKey.format()} is already synced to Google Drive.',
              ),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else if (result is DrivePhotoUploadFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploadProgress = null;
        });
      }
    }
  }

  /// Manual Sync Now tile allowing user to trigger SyncQueue processing
  Widget _buildSyncNowTile(
    GoogleAuthService auth,
    GoogleDriveAuthService driveAuth,
    GoogleDriveService drive,
    SyncWorker syncWorker,
    PersistentDailyPhotoStore photoStore,
  ) {
    final isSyncing = syncWorker.isSyncing;
    final queue = photoStore.syncQueue;
    final totalPending = queue.count;
    final pendingUploads = queue.operations
        .where((op) => op.type == SyncOperationType.upload)
        .length;

    String subtitle;
    if (isSyncing) {
      final progress = syncWorker.activeProgress;
      if (progress != null) {
        subtitle =
            'Syncing to Drive... (${(progress * 100).clamp(0, 100).toInt()}%)';
      } else {
        subtitle = 'Syncing outbox to Google Drive...';
      }
    } else if (!auth.isSignedIn) {
      subtitle = 'Google account sign-in required';
    } else if (!driveAuth.isAuthorized) {
      subtitle = 'Google Drive authorization required';
    } else if (!drive.isReady) {
      subtitle = 'Drive folder setup required';
    } else if (totalPending == 0) {
      subtitle = 'Outbox is empty • All memories synced';
    } else if (pendingUploads == totalPending) {
      subtitle =
          '$pendingUploads pending memory upload${pendingUploads == 1 ? '' : 's'}';
    } else {
      subtitle =
          '$totalPending pending change${totalPending == 1 ? '' : 's'} to sync';
    }

    return SettingsTile(
      title: 'Manual Cloud Sync',
      subtitle: subtitle,
      leadingIcon: Icons.sync_rounded,
      leadingColor: AppColors.accent,
      trailing: isSyncing
          ? SizedBox(
              width: 18.0,
              height: 18.0,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
                value: syncWorker.activeProgress,
                color: AppColors.accent,
              ),
            )
          : OutlinedButton(
              onPressed: () =>
                  _handleSyncNow(auth, driveAuth, drive, syncWorker, queue),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: const BorderSide(color: AppColors.accent),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 6.0,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
              ),
              child: const Text(
                'Sync Now',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
            ),
    );
  }

  Future<void> _handleSyncNow(
    GoogleAuthService auth,
    GoogleDriveAuthService driveAuth,
    GoogleDriveService drive,
    SyncWorker syncWorker,
    SyncQueue queue,
  ) async {
    if (syncWorker.isSyncing) return;

    if (!auth.isSignedIn) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google account sign-in required to sync.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    if (!driveAuth.isAuthorized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google Drive authorization required to sync.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    if (!drive.isReady) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google Drive folder setup required to sync.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    if (queue.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nothing to sync.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    final result = await syncWorker.syncNow();

    if (!mounted) return;

    if (result.alreadyRunning) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sync is already in progress.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
    } else if (result.succeededCount > 0 && result.failedCount == 0) {
      String successMessage;
      if (result.uploadedCount > 0 &&
          result.updatedCount == 0 &&
          result.deletedCount == 0) {
        successMessage =
            'Synced ${result.uploadedCount} photo${result.uploadedCount == 1 ? '' : 's'}.';
      } else if (result.updatedCount > 0 &&
          result.uploadedCount == 0 &&
          result.deletedCount == 0) {
        successMessage =
            'Updated ${result.updatedCount} photo${result.updatedCount == 1 ? '' : 's'}.';
      } else if (result.deletedCount > 0 &&
          result.uploadedCount == 0 &&
          result.updatedCount == 0) {
        successMessage =
            'Deleted ${result.deletedCount} remote photo${result.deletedCount == 1 ? '' : 's'}.';
      } else {
        final parts = <String>[];
        if (result.uploadedCount > 0) {
          parts.add('${result.uploadedCount} uploaded');
        }
        if (result.updatedCount > 0) {
          parts.add('${result.updatedCount} updated');
        }
        if (result.deletedCount > 0) {
          parts.add('${result.deletedCount} deleted');
        }
        successMessage =
            'Synced ${result.succeededCount} changes (${parts.join(', ')}).';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } else if (result.failedCount > 0 && result.succeededCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sync completed with ${result.failedCount} failure${result.failedCount == 1 ? '' : 's'}.',
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } else if (result.failedCount > 0 && result.succeededCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Synced ${result.succeededCount} change${result.succeededCount == 1 ? '' : 's'}, ${result.failedCount} failed.',
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } else if (result.unsupportedCount > 0 && result.processedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No supported operations. ${result.unsupportedCount} operations queued for future milestones.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } else if (result.skippedCount > 0 && result.processedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Operations waiting for retry backoff.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing to sync.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  /// Understated Statistics Section
  Widget _buildStatisticsSection() {
    return Row(
      children: [
        Expanded(
          child: _buildStatItem(
            value: '74',
            label: 'Photos',
            icon: Icons.photo_library_outlined,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _buildStatItem(
            value: '74',
            label: 'Days',
            icon: Icons.calendar_today_outlined,
            color: AppColors.statDaysGreen,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _buildStatItem(
            value: '18',
            label: 'Streak',
            icon: Icons.local_fire_department_rounded,
            color: AppColors.statStreakOrange,
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          Icon(icon, size: 16.0, color: color),
          const SizedBox(height: 4.0),
          Text(
            value,
            style: const TextStyle(
              fontSize: 17.0,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 1.0),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.0,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
