import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_shadows.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';
import 'package:photo_per_day/widgets/daria_logo.dart';

/// Dedicated About Screen highlighting the philosophy, core pillars,
/// architecture, and craftsmanship of "Photo a Day".
class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

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
                          // Hero App Branding Section
                          _buildHeroBanner(context),

                          const SizedBox(height: AppSpacing.lg),

                          // The Philosophy Card
                          _buildPhilosophyCard(),

                          const SizedBox(height: AppSpacing.lg),

                          // Core Pillars Grid
                          _buildSectionTitle(
                            title: 'CORE PILLARS',
                            subtitle:
                                'Built from first principles for mindful memory keeping',
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _buildCorePillars(context),

                          const SizedBox(height: AppSpacing.lg),

                          // 3-Step Journey
                          _buildSectionTitle(
                            title: 'HOW IT WORKS',
                            subtitle:
                                'A quiet, intentional rhythm for every day',
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _buildJourneySteps(),

                          const SizedBox(height: AppSpacing.lg),

                          // Technical Craft & Architecture
                          _buildSectionTitle(
                            title: 'CRAFT & INTEGRITY',
                            subtitle:
                                'Engineered for privacy, longevity, and speed',
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _buildSpecsCard(),

                          const SizedBox(height: AppSpacing.lg),

                          // Quick Navigation Actions
                          _buildQuickLinks(context),

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
                  'About',
                  style: TextStyle(
                    fontSize: 20.0,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 1.0),
                Text(
                  'The Story Behind Daria',
                  style: AppTypography.screenSubtitle.copyWith(fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          // Official Daria Logo
          const DariaLogo(size: 72.0),
          const SizedBox(height: AppSpacing.md),
          // App Title
          Text(
            AppConstants.appName,
            style: TextStyle(
              fontSize: 24.0,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),

          const SizedBox(height: 6.0),

          // Version & Tag Chip
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10.0,
              vertical: 4.0,
            ),
            decoration: BoxDecoration(
              color: AppColors.accentLight,
              borderRadius: BorderRadius.circular(20.0),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.3),
                width: 0.8,
              ),
            ),
            child: Text(
              'v${AppConstants.appVersion} • Local-First Edition',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
                letterSpacing: 0.2,
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // Poetic Tagline
          Text(
            'Capture your life, one authentic photograph at a time.\nNo noise. No algorithms. Just pure memory.',
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(
              fontSize: 13.5,
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhilosophyCard() {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36.0,
                height: 36.0,
                decoration: BoxDecoration(
                  color: AppColors.accentLight,
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: Icon(
                  Icons.format_quote_rounded,
                  color: AppColors.accent,
                  size: 20.0,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'The Philosophy',
                  style: TextStyle(
                    fontSize: 16.0,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Modern life moves in a rush of fleeting notifications and thousands of forgotten camera roll photos. '
            'Daria imposes an intentional creative restraint: exactly one photograph per calendar day.\n\n'
            'When you take only one photo, you become present. You look at your surroundings, choose the memory that truly matters, and preserve the real texture of your days without performance anxiety or social vanity.',
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

  Widget _buildSectionTitle({required String title, required String subtitle}) {
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

  Widget _buildCorePillars(BuildContext context) {
    final pillars = [
      _PillarItem(
        icon: Icons.camera_alt_rounded,
        iconColor: AppColors.accent,
        title: 'One Frame Per Day',
        description:
            'A mindful limit that turns daily photography into an intentional ritual rather than compulsive snapping.',
      ),
      _PillarItem(
        icon: Icons.shield_outlined,
        iconColor: AppColors.statDaysGreen,
        title: '100% Local-First',
        description:
            'All photos and journals remain on your device. No central servers, no trackers, no surveillance capitalism.',
      ),
      _PillarItem(
        icon: Icons.cloud_done_outlined,
        iconColor: AppColors.statIconForest,
        title: 'User-Owned Cloud Sync',
        description:
            'Optional backup directly to your personal Google Drive with strict file-level app isolation.',
      ),
      _PillarItem(
        icon: Icons.palette_outlined,
        iconColor: AppColors.statIconPurple,
        title: 'Curated Color Themes',
        description:
            '8 hand-crafted minimal color palettes including Midnight dark mode, tailored for soothing focus.',
      ),
      _PillarItem(
        icon: Icons.history_rounded,
        iconColor: AppColors.statStreakOrange,
        title: 'On This Day Flashbacks',
        description:
            'Relive heartfelt memories from one, two, or five years ago with nostalgia calendar reflections.',
      ),
      _PillarItem(
        icon: Icons.file_download_outlined,
        iconColor: AppColors.statIconBlueGrey,
        title: 'Complete Data Portability',
        description:
            'Export your entire diary archive with original photos and manifest.json anytime as a standard ZIP file.',
      ),
    ];

    return Column(
      children: [
        for (final pillar in pillars) ...[
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
                  width: 40.0,
                  height: 40.0,
                  decoration: BoxDecoration(
                    color: pillar.iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  child: Icon(pillar.icon, color: pillar.iconColor, size: 20.0),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pillar.title,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3.0),
                      Text(
                        pillar.description,
                        style: AppTypography.body.copyWith(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                          height: 1.4,
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

  Widget _buildJourneySteps() {
    final steps = [
      (
        '1',
        'Capture the Day',
        'Snap a moment with the camera or pick from your device gallery. Only one photo per day.',
        Icons.add_a_photo_outlined,
      ),
      (
        '2',
        'Add Heart & Context',
        'Write a title, attach a location, or leave a quiet note describing what made the day memorable.',
        Icons.edit_note_rounded,
      ),
      (
        '3',
        'Cherish the Timeline',
        'Review your month in a visual calendar grid, maintain your streak, and rediscover past years.',
        Icons.auto_stories_outlined,
      ),
    ];

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
          for (int i = 0; i < steps.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28.0,
                  height: 28.0,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      steps[i].$1,
                      style: TextStyle(
                        fontSize: 13.0,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accentForeground,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        steps[i].$2,
                        style: TextStyle(
                          fontSize: 14.0,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2.0),
                      Text(
                        steps[i].$3,
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
            if (i < steps.length - 1)
              Padding(
                padding: const EdgeInsets.only(
                  left: 13.0,
                  top: 4.0,
                  bottom: 4.0,
                ),
                child: Container(
                  width: 2.0,
                  height: 22.0,
                  color: AppColors.border,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSpecsCard() {
    final specs = [
      ('Platform', 'Flutter Cross-Platform Engine'),
      ('Storage Architecture', 'Local-First Sandboxed Storage'),
      ('Cloud Integration', 'User-Owned Google Drive (v3)'),
      ('Data Ownership', '100% User Owned (Exportable ZIP)'),
      ('Analytics & Trackers', 'Zero (0) SDKs or Ad Networks'),
      ('Network Dependency', 'Fully Functional Offline'),
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
          for (int i = 0; i < specs.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      specs[i].$1,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      specs[i].$2,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (i < specs.length - 1)
              Divider(
                height: 1.0,
                thickness: 0.8,
                color: AppColors.borderSubtle,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickLinks(BuildContext context) {
    return Column(
      children: [
        _buildNavTile(
          context: context,
          icon: Icons.shield_outlined,
          iconColor: AppColors.statDaysGreen,
          title: 'Privacy Policy',
          subtitle: 'Read our plain-English promise and data principles',
          onTap: () => Navigator.pushNamed(context, AppConstants.privacyRoute),
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildNavTile(
          context: context,
          icon: Icons.description_outlined,
          iconColor: AppColors.statIconNeutral,
          title: 'Terms of Service',
          subtitle: 'Simple, respectful terms for personal journaling',
          onTap: () => Navigator.pushNamed(context, AppConstants.termsRoute),
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildNavTile(
          context: context,
          icon: Icons.palette_outlined,
          iconColor: AppColors.accent,
          title: 'Themes & Color Palettes',
          subtitle: 'Personalize the app with curated aesthetic palettes',
          onTap: () => Navigator.pushNamed(context, AppConstants.themeRoute),
        ),
      ],
    );
  }

  Widget _buildNavTile({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadii.card,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.card,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 14.0,
          ),
          decoration: BoxDecoration(
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
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: Icon(icon, color: iconColor, size: 19.0),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      subtitle,
                      style: AppTypography.caption.copyWith(
                        fontSize: 12.0,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20.0,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Center(
      child: Column(
        children: [
          Text.rich(
            TextSpan(
              text: 'Crafted with ',
              style: TextStyle(fontSize: 12.0, color: AppColors.textMuted),
              children: [
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.0),
                    child: Icon(
                      Icons.favorite_rounded,
                      size: 13.0,
                      color: AppColors.statStreakOrange,
                    ),
                  ),
                ),
                const TextSpan(text: 'for mindful living'),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4.0),
          Text(
            '© 2026 ${AppConstants.appName}. All memories belong to you.',
            style: TextStyle(fontSize: 11.0, color: AppColors.textMutedSubtle),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PillarItem {
  const _PillarItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
}
