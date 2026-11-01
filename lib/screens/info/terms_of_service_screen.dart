import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_shadows.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';

/// Dedicated Terms of Service Screen providing clear, honest, and respectful
/// guidelines for personal use and copyright ownership.
class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

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
                          // Hero Header Card
                          _buildHeroAgreement(),

                          const SizedBox(height: AppSpacing.lg),

                          // Highlights Row
                          _buildHighlightsRow(),

                          const SizedBox(height: AppSpacing.lg),

                          // Terms Articles
                          _buildSectionHeader(
                            title: 'TERMS ARTICLES',
                            subtitle:
                                'Plain-English provisions regarding ownership & use',
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _buildTermsArticles(),

                          const SizedBox(height: AppSpacing.lg),

                          // Fair Use Pledge Card
                          _buildFairUsePledge(),

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
                  'Terms of Service',
                  style: TextStyle(
                    fontSize: 20.0,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 1.0),
                Text(
                  'Simple, Fair & Respectful Agreement',
                  style: AppTypography.screenSubtitle.copyWith(fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroAgreement() {
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
          Container(
            width: 60.0,
            height: 60.0,
            decoration: BoxDecoration(
              color: AppColors.statIconNeutral.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.statIconNeutral.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            child: Icon(
              Icons.gavel_rounded,
              size: 28.0,
              color: AppColors.statIconNeutral,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Terms at a Glance',
            style: TextStyle(
              fontSize: 18.0,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6.0),
          Text(
            'Last Updated: October 2026 • Honest Guidelines',
            style: AppTypography.caption.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Daria is dedicated to personal, mindful memory keeping. '
            'We believe legal agreements should be easy to understand: you maintain 100% ownership of your photos, '
            'we claim no rights to your content, and you are free to export or delete your diary whenever you wish.',
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

  Widget _buildHighlightsRow() {
    final highlights = [
      (
        Icons.copyright_rounded,
        AppColors.accent,
        '100% You Own It',
        'Zero IP claims',
      ),
      (
        Icons.money_off_rounded,
        AppColors.statDaysGreen,
        'No Subscriptions',
        'No hidden paywalls',
      ),
      (
        Icons.person_outline_rounded,
        AppColors.statStreakOrange,
        'Personal Journal',
        'Non-commercial use',
      ),
    ];

    return Row(
      children: [
        for (int i = 0; i < highlights.length; i++) ...[
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
                  Icon(highlights[i].$1, size: 22.0, color: highlights[i].$2),
                  const SizedBox(height: 5.0),
                  Text(
                    highlights[i].$3,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 1.0),
                  Text(
                    highlights[i].$4,
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
          if (i < highlights.length - 1) const SizedBox(width: AppSpacing.sm),
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

  Widget _buildTermsArticles() {
    final articles = [
      (
        '1. Content Ownership & Copyright',
        Icons.auto_stories_rounded,
        AppColors.accent,
        'You retain full and unrestricted copyright, ownership, and moral rights to every single photograph, title, and note you record in Daria. '
            'We do not claim any copyright, sub-license, commercial exploitation right, or AI training entitlement over your images.',
      ),
      (
        '2. Personal Journaling License',
        Icons.favorite_border_rounded,
        AppColors.statStreakOrange,
        'Daria is provided to you as an application for private, personal daily journaling and memory preservation. '
            'You agree not to reverse engineer, decompile, or redistribute malicious modifications of the software.',
      ),
      (
        '3. Device Storage & Backup Responsibility',
        Icons.sd_storage_outlined,
        AppColors.statDaysGreen,
        'Because Daria is built with a local-first philosophy, your memories are stored physically on your device rather than our servers. '
            'You are responsible for safeguarding your device and utilizing the built-in Google Drive backup or ZIP export features to prevent data loss in the event of hardware damage.',
      ),
      (
        '4. Google Drive Cloud Services',
        Icons.cloud_outlined,
        AppColors.statIconForest,
        'When you optionally connect your Google account to enable Drive backup, your use of Google Drive is subject to Google\'s own Terms of Service. '
            'Daria uses official Google APIs with the restricted "drive.file" scope and does not act as a custodian for Google services.',
      ),
      (
        '5. Offline Functionality & Continuity',
        Icons.wifi_off_rounded,
        AppColors.statIconPurple,
        'The application does not depend on an internet connection to capture, view, edit, or search your diary. '
            'You can continue using your journal anywhere on Earth, with or without network connectivity.',
      ),
      (
        '6. Changes to Terms',
        Icons.update_rounded,
        AppColors.statIconNeutral,
        'Should these terms ever require adjustment in future versions, updates will be accompanied by transparent changelog notes directly within the app.',
      ),
    ];

    return Column(
      children: [
        for (final a in articles) ...[
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
                    color: a.$3.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  child: Icon(a.$2, color: a.$3, size: 19.0),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.$1,
                        style: TextStyle(
                          fontSize: 14.0,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3.0),
                      Text(
                        a.$4,
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

  Widget _buildFairUsePledge() {
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
          Container(
            width: 36.0,
            height: 36.0,
            decoration: BoxDecoration(
              color: AppColors.statDaysGreen.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_circle_outline_rounded,
              size: 20.0,
              color: AppColors.statDaysGreen,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Our Commitment to You',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2.0),
                Text(
                  'No subscriptions, no ads, and no locked memories. Ever.',
                  style: AppTypography.caption.copyWith(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Center(
      child: Text(
        '© 2026 ${AppConstants.appName} • Mindful Memory Keeping',
        style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
      ),
    );
  }
}
