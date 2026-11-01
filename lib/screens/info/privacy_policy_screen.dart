import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_shadows.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';

/// Dedicated Privacy Policy Screen providing transparent, plain-English
/// disclosure of data storage, permissions, and zero-tracking commitment.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeService.instance,
      builder: (context, _) {
        final currentPalette = AppThemeService.instance.currentPalette;

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: currentPalette.isDark
                ? Brightness.light
                : Brightness.dark,
            statusBarBrightness: currentPalette.isDark
                ? Brightness.dark
                : Brightness.light,
          ),
          child: Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: Column(
                children: [
                  _buildHeader(context),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pageHorizontal,
                        AppSpacing.xs,
                        AppSpacing.pageHorizontal,
                        AppSpacing.xxl,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Hero Privacy Pledge Card
                          _buildHeroManifesto(),

                          const SizedBox(height: AppSpacing.lg),

                          // Trust Badges Grid
                          _buildTrustBadges(),

                          const SizedBox(height: AppSpacing.lg),

                          // Privacy Principles List
                          _buildSectionHeader(
                            title: 'PRIVACY PILLARS',
                            subtitle:
                                'Every principle engineered into the codebase',
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _buildPrivacyPillars(),

                          const SizedBox(height: AppSpacing.lg),

                          // Device Permissions Transparency
                          _buildSectionHeader(
                            title: 'PERMISSIONS TRANSPARENCY',
                            subtitle:
                                'Why and when device permissions are needed',
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _buildPermissionsCard(),

                          const SizedBox(height: AppSpacing.lg),

                          // Data Portability & Rights
                          _buildSectionHeader(
                            title: 'YOUR RIGHTS & CONTROL',
                            subtitle:
                                'Export, archive, or erase your diary anytime',
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _buildRightsCard(),

                          const SizedBox(height: AppSpacing.lg),

                          // Verification & Transparency Note
                          _buildVerificationCard(),

                          const SizedBox(height: AppSpacing.xl),

                          // Footer
                          _buildFooter(),
                        ],
                      ),
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

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageHorizontal,
        AppSpacing.sm,
        AppSpacing.pageHorizontal,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Semantics(
            label: 'Navigate back',
            button: true,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(24.0),
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 44.0,
                  height: 44.0,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSubtle,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border, width: 0.8),
                  ),
                  child: Icon(
                    Icons.arrow_back_rounded,
                    size: 20.0,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Privacy Policy',
                  style: TextStyle(
                    fontSize: 20.0,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 1.0),
                Text(
                  'Your Memories Belong 100% to You',
                  style: AppTypography.screenSubtitle.copyWith(fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroManifesto() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          // Security Shield Icon Badge
          Container(
            width: 60.0,
            height: 60.0,
            decoration: BoxDecoration(
              color: AppColors.statDaysGreen.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.statDaysGreen.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            child: Icon(
              Icons.verified_user_rounded,
              size: 32.0,
              color: AppColors.statDaysGreen,
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          Text(
            'The Privacy Manifesto',
            style: TextStyle(
              fontSize: 18.0,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),

          const SizedBox(height: 6.0),

          Text(
            'Effective Date: October 2026 • Plain-English Promise',
            style: AppTypography.caption.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          Text(
            'We built Daria on an uncompromising premise: your photos, notes, and daily moments are profoundly personal. '
            'We do not operate a user database, we do not monetize user data, and we do not install analytics trackers. '
            'Your device is your private vault.',
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(
              fontSize: 13.0,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrustBadges() {
    final badges = [
      (
        Icons.storage_rounded,
        AppColors.accent,
        'Local-First',
        'Saved on device',
      ),
      (
        Icons.block_rounded,
        AppColors.statStreakOrange,
        'No Trackers',
        '0 analytics SDKs',
      ),
      (
        Icons.cloud_done_outlined,
        AppColors.statDaysGreen,
        'Direct Drive',
        'Your cloud only',
      ),
    ];

    return Row(
      children: [
        for (int i = 0; i < badges.length; i++) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(
                vertical: 12.0,
                horizontal: 8.0,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppRadii.card,
                border: Border.all(color: AppColors.border, width: 0.8),
                boxShadow: AppShadows.card,
              ),
              child: Column(
                children: [
                  Icon(badges[i].$1, size: 22.0, color: badges[i].$2),
                  const SizedBox(height: 5.0),
                  Text(
                    badges[i].$3,
                    style: TextStyle(
                      fontSize: 12.0,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 1.0),
                  Text(
                    badges[i].$4,
                    style: TextStyle(
                      fontSize: 10.0,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          if (i < badges.length - 1) const SizedBox(width: AppSpacing.sm),
        ],
      ],
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11.0,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 1.0),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12.0,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyPillars() {
    final pillars = [
      (
        Icons.phonelink_lock_rounded,
        AppColors.accent,
        '1. Local-First Architecture',
        'All photos captured and diary entries written are saved directly in app-isolated persistent storage on your physical device. '
            'They are never streamed or uploaded to any proprietary application server or database.',
      ),
      (
        Icons.cloud_sync_outlined,
        AppColors.statDaysGreen,
        '2. Optional User-Owned Google Drive',
        'Cloud backup is completely optional. When enabled, Daria requests exclusively the restricted "drive.file" scope. '
            'This means the app can only see and access files it specifically created in its designated "Daria" folder. '
            'The app CANNOT access, read, or see any of your other personal Google Drive documents, folders, or spreadsheets.',
      ),
      (
        Icons.do_not_disturb_on_outlined,
        AppColors.statIconPurple,
        '3. Zero Ads, Telemetry, or Analytics',
        'Daria contains zero advertising SDKs, behavioral fingerprinting modules, tracking pixels, or third-party telemetry. '
            'We do not monetize your attention, and we have no mechanism to observe your journal entries.',
      ),
      (
        Icons.share_location_outlined,
        AppColors.statIconBrown,
        '4. Location Metadata is Fully Optional',
        'Attaching a location to your photo entry is entirely manual and optional. '
            'The app does not continuously poll background GPS coordinates or broadcast your whereabouts to anyone.',
      ),
    ];

    return Column(
      children: [
        for (final p in pillars) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.card,
              border: Border.all(color: AppColors.border, width: 0.8),
              boxShadow: AppShadows.card,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36.0,
                  height: 36.0,
                  decoration: BoxDecoration(
                    color: p.$2.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  child: Icon(p.$1, color: p.$2, size: 19.0),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.$3,
                        style: TextStyle(
                          fontSize: 14.0,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3.0),
                      Text(
                        p.$4,
                        style: AppTypography.body.copyWith(
                          fontSize: 12.0,
                          color: AppColors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPermissionsCard() {
    final permissions = [
      (
        Icons.camera_alt_outlined,
        'Camera',
        'Live Capture',
        'Used strictly when you tap the camera viewfinder to snap today\'s single photo memory. Never accessed in the background.',
      ),
      (
        Icons.photo_library_outlined,
        'Photos / Storage',
        'Memory Selection & Export',
        'Used when you choose an existing photo from device storage, or when you save an exported ZIP diary archive to disk.',
      ),
      (
        Icons.notifications_outlined,
        'Notifications',
        'Daily Reminder Alarm',
        'Used only to schedule an optional daily local alarm at your selected reminder hour. No marketing or push notifications are ever sent.',
      ),
    ];

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
        children: [
          for (int i = 0; i < permissions.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32.0,
                  height: 32.0,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Icon(
                    permissions[i].$1,
                    size: 17.0,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              permissions[i].$2,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6.0,
                              vertical: 2.0,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceSubtle,
                              borderRadius: BorderRadius.circular(4.0),
                            ),
                            child: Text(
                              permissions[i].$3,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2.0),
                      Text(
                        permissions[i].$4,
                        style: AppTypography.body.copyWith(
                          fontSize: 12.0,
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (i < permissions.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Divider(
                  height: 1.0,
                  thickness: 0.8,
                  color: AppColors.borderSubtle,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildRightsCard() {
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
              Icon(
                Icons.lock_reset_rounded,
                size: 18.0,
                color: AppColors.statDaysGreen,
              ),
              const SizedBox(width: 8.0),
              Expanded(
                child: Text(
                  'Complete Data Control & Erasure',
                  style: TextStyle(
                    fontSize: 14.0,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Because you own your data, you possess absolute sovereignty over it:\n\n'
            '• Export Anywhere: Tap "Export Diary" in Settings to generate a complete ZIP archive containing every captured JPEG photo and a standard manifest.json.\n'
            '• Wipe Local Data: Delete all local diary photos from your device at any time.\n'
            '• Purge Cloud Backup: Move your entire Google Drive "Daria" backup folder to the Trash with a single tap.\n'
            '• Instant Revocation: Disconnect your Google account to immediately revoke all Drive authorization tokens.',
            style: AppTypography.body.copyWith(
              fontSize: 12.5,
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18.0,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Technical Verification: You can audit Daria\'s network traffic with any standard network proxy (such as Charles or Wireshark). '
              'You will observe zero calls to any proprietary tracking domain or backend server.',
              style: AppTypography.caption.copyWith(
                fontSize: 11.5,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Center(
      child: Text(
        'Daria • Mindful, Private Journaling',
        style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
      ),
    );
  }
}
