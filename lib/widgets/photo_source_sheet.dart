import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';

/// Available photo acquisition sources.
enum PhotoSource { camera, gallery }

/// Minimalist modal bottom sheet prompting the user to select between
/// capturing with the live camera or choosing an existing photo from the device gallery.
class PhotoSourceSheet extends StatelessWidget {
  const PhotoSourceSheet({super.key});

  /// Displays the modal sheet and returns the selected [PhotoSource],
  /// or `null` if dismissed.
  static Future<PhotoSource?> show(BuildContext context) {
    return showModalBottomSheet<PhotoSource>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const PhotoSourceSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.sheetRadius,
        boxShadow: [
          BoxShadow(
            color: Color(0x2A000000),
            blurRadius: 20.0,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        top: AppSpacing.sm,
        left: AppSpacing.pageHorizontal,
        right: AppSpacing.pageHorizontal,
        bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 36.0,
              height: 4.0,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2.0),
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // Header
          const Text(
            'Add Daily Photo',
            style: TextStyle(
              fontSize: 18.0,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 3.0),
          const Text(
            'Choose how you\'d like to capture today\'s memory',
            style: AppTypography.screenSubtitle,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: AppSpacing.lg),

          // Option 1: Take Photo (Camera)
          _buildSourceTile(
            context: context,
            source: PhotoSource.camera,
            icon: Icons.photo_camera_rounded,
            iconColor: AppColors.accent,
            badgeBgColor: AppColors.surfaceSubtle,
            title: 'Take Photo',
            subtitle: 'Use device camera to snap a moment',
          ),

          const SizedBox(height: AppSpacing.sm),

          // Option 2: Choose from Gallery (Photo Library)
          _buildSourceTile(
            context: context,
            source: PhotoSource.gallery,
            icon: Icons.photo_library_rounded,
            iconColor: AppColors.accent,
            badgeBgColor: AppColors.surfaceSubtle,
            title: 'Choose from Gallery',
            subtitle: 'Select an existing photo from your library',
          ),

          const SizedBox(height: AppSpacing.md),

          // Cancel Action
          SizedBox(
            width: double.infinity,
            child: Semantics(
              button: true,
              label: 'Cancel photo selection',
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  minimumSize: const Size(double.infinity, 48.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14.0),
                  ),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceTile({
    required BuildContext context,
    required PhotoSource source,
    required IconData icon,
    required Color iconColor,
    required Color badgeBgColor,
    required String title,
    required String subtitle,
  }) {
    return Material(
      color: AppColors.surfaceSubtle,
      borderRadius: AppRadii.card,
      child: Semantics(
        button: true,
        label: '$title. $subtitle.',
        child: InkWell(
          onTap: () => Navigator.of(context).pop(source),
          borderRadius: AppRadii.card,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 14.0,
            ),
            decoration: BoxDecoration(
              borderRadius: AppRadii.card,
              border: Border.all(color: AppColors.border, width: 0.8),
            ),
            child: Row(
              children: [
                // Icon Badge
                Container(
                  width: 44.0,
                  height: 44.0,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border, width: 0.8),
                  ),
                  child: Icon(icon, size: 20.0, color: iconColor),
                ),

                const SizedBox(width: AppSpacing.md),

                // Title and Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15.0,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 1.5),
                      Text(
                        subtitle,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 12.0,
                        ),
                      ),
                    ],
                  ),
                ),

                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20.0,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
