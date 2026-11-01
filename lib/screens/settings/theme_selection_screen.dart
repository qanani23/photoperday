import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_palette.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_shadows.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';

/// Screen allowing users to browse and select from curated minimal color palettes.
class ThemeSelectionScreen extends StatelessWidget {
  const ThemeSelectionScreen({super.key});

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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context),
                  Expanded(
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pageHorizontal,
                        AppSpacing.xs,
                        AppSpacing.pageHorizontal,
                        AppSpacing.xxl,
                      ),
                      children: [
                        _buildQuickAppearanceSection(context),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'ALL CURATED PALETTES',
                          style: AppTypography.sectionTitle.copyWith(
                            color: AppColors.textMuted,
                            fontSize: 11.0,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        for (final palette in AppPalettes.all) ...[
                          _buildPaletteCard(
                            context,
                            palette: palette,
                            isSelected: palette.id == currentPalette.id,
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
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
            label: 'Navigate back to Settings',
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
              children: [
                Text(
                  'Theme & Palettes',
                  style: AppTypography.appTitle.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2.0),
                Text(
                  'Curated palettes for your daily photo journal',
                  style: AppTypography.screenSubtitle.copyWith(
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

  Widget _buildQuickAppearanceSection(BuildContext context) {
    final themeService = AppThemeService.instance;
    final currentPalette = themeService.currentPalette;
    final followSystem = themeService.followSystem;

    return Container(
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
                width: 32.0,
                height: 32.0,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Icon(
                  Icons.brightness_medium_rounded,
                  size: 18.0,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quick Appearance Toggle',
                      style: TextStyle(
                        fontSize: 14.0,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Daria Light (Default) • Daria Red • Midnight',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _buildQuickButton(
                  context: context,
                  label: 'Daria Light',
                  icon: Icons.light_mode_rounded,
                  isSelected: currentPalette.id == 'daria_red_light',
                  accentColor: AppPalettes.dariaRedLight.accent,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    themeService.setPalette(AppPalettes.dariaRedLight);
                  },
                ),
              ),
              const SizedBox(width: 6.0),
              Expanded(
                child: _buildQuickButton(
                  context: context,
                  label: 'Daria Red',
                  icon: Icons.dark_mode_rounded,
                  isSelected: currentPalette.id == 'daria_red',
                  accentColor: AppPalettes.dariaRed.accent,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    themeService.setPalette(AppPalettes.dariaRed);
                  },
                ),
              ),
              const SizedBox(width: 6.0),
              Expanded(
                child: _buildQuickButton(
                  context: context,
                  label: 'Midnight',
                  icon: Icons.nightlight_round,
                  isSelected: currentPalette.id == 'midnight',
                  accentColor: AppPalettes.midnight.accent,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    themeService.setPalette(AppPalettes.midnight);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(
            height: 1.0,
            thickness: 0.8,
            color: AppColors.border.withValues(alpha: 0.6),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Match System Theme',
                      style: TextStyle(
                        fontSize: 13.0,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Sync automatically with phone brightness',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: followSystem,
                activeTrackColor: AppColors.accent,
                onChanged: (val) {
                  HapticFeedback.selectionClick();
                  themeService.setFollowSystem(val);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool isSelected,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10.0),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9.0, horizontal: 4.0),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: 0.15)
              : AppColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(10.0),
          border: Border.all(
            color: isSelected ? accentColor : AppColors.border,
            width: isSelected ? 1.5 : 0.8,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15.0,
              color: isSelected ? accentColor : AppColors.textSecondary,
            ),
            const SizedBox(width: 4.0),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaletteCard(
    BuildContext context, {
    required AppPalette palette,
    required bool isSelected,
  }) {
    return Semantics(
      button: true,
      selected: isSelected,
      label:
          '${palette.name} palette. ${palette.description}. ${isSelected ? "Currently selected." : "Double tap to apply."}',
      child: Material(
        color: palette.surface,
        borderRadius: AppRadii.card,
        elevation: 0,
        child: InkWell(
          borderRadius: AppRadii.card,
          onTap: () {
            HapticFeedback.selectionClick();
            AppThemeService.instance.setPalette(palette);
          },
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: AppRadii.card,
              border: Border.all(
                color: isSelected ? palette.accent : palette.border,
                width: isSelected ? 2.0 : 0.8,
              ),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row with Name and Checkmark Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          palette.name,
                          style: TextStyle(
                            fontSize: 16.0,
                            fontWeight: FontWeight.w700,
                            color: palette.textPrimary,
                          ),
                        ),
                        if (palette.id == 'daria_red_light') ...[
                          const SizedBox(width: 8.0),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7.0,
                              vertical: 2.0,
                            ),
                            decoration: BoxDecoration(
                              color: palette.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6.0),
                            ),
                            child: Text(
                              'Default',
                              style: TextStyle(
                                fontSize: 10.0,
                                fontWeight: FontWeight.w600,
                                color: palette.accent,
                              ),
                            ),
                          ),
                        ] else if (palette.id == 'daria_red') ...[
                          const SizedBox(width: 8.0),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7.0,
                              vertical: 2.0,
                            ),
                            decoration: BoxDecoration(
                              color: palette.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6.0),
                            ),
                            child: Text(
                              'Signature Dark',
                              style: TextStyle(
                                fontSize: 10.0,
                                fontWeight: FontWeight.w600,
                                color: palette.accent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (isSelected)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8.0,
                          vertical: 4.0,
                        ),
                        decoration: BoxDecoration(
                          color: palette.accent,
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_rounded,
                              size: 13.0,
                              color: Colors.white,
                            ),
                            SizedBox(width: 3.0),
                            Text(
                              'Active',
                              style: TextStyle(
                                fontSize: 11.0,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4.0),
                Text(
                  palette.description,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: palette.textSecondary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Miniature UI Card Preview demonstrating palette in context
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 10.0,
                  ),
                  decoration: BoxDecoration(
                    color: palette.background,
                    borderRadius: BorderRadius.circular(12.0),
                    border: Border.all(color: palette.borderSubtle, width: 0.8),
                  ),
                  child: Row(
                    children: [
                      // Mini Today Pulse / Accent Ring
                      Container(
                        width: 32.0,
                        height: 32.0,
                        decoration: BoxDecoration(
                          color: palette.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.accent, width: 1.8),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.camera_alt_rounded,
                            size: 15.0,
                            color: palette.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Daily Photograph',
                              style: TextStyle(
                                fontSize: 12.0,
                                fontWeight: FontWeight.w700,
                                color: palette.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2.0),
                            Text(
                              'Daria UI preview',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: palette.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Swatch Pill preview
                      _buildSwatchPill(palette),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwatchPill(AppPalette palette) {
    return Container(
      padding: const EdgeInsets.all(3.0),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: palette.border, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSwatchDot(palette.background, tooltip: 'Background'),
          const SizedBox(width: 3.0),
          _buildSwatchDot(palette.surface, tooltip: 'Surface'),
          const SizedBox(width: 3.0),
          _buildSwatchDot(palette.accent, tooltip: 'Accent'),
          const SizedBox(width: 3.0),
          _buildSwatchDot(palette.textPrimary, tooltip: 'Text'),
        ],
      ),
    );
  }

  Widget _buildSwatchDot(Color color, {required String tooltip}) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 12.0,
        height: 12.0,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.1),
            width: 0.5,
          ),
        ),
      ),
    );
  }
}
