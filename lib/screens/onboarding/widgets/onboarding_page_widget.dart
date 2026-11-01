import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/screens/onboarding/onboarding_data.dart';

/// Single page visual presentation for the Photo a Day onboarding carousel.
class OnboardingPageWidget extends StatelessWidget {
  const OnboardingPageWidget({
    super.key,
    required this.pageData,
    this.parallaxOffset = 0.0,
  });

  final OnboardingPageData pageData;
  final double parallaxOffset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Adapt image container dimensions responsively to viewport size
        final double maxImageHeight = (constraints.maxHeight * 0.45).clamp(
          220.0,
          380.0,
        );
        final double imageWidth =
            (constraints.maxWidth - AppSpacing.pageHorizontal * 2 - 32.0).clamp(
              200.0,
              400.0,
            );

        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pageHorizontal,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
              maxWidth: 520.0,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: AppSpacing.xl),

                // Layered tilted photo composition
                _buildTiltedLayeredComposition(
                  context,
                  maxImageHeight: maxImageHeight,
                  imageWidth: imageWidth,
                ),

                const SizedBox(height: AppSpacing.xxl * 1.2),

                // Title
                Semantics(
                  header: true,
                  child: Text(
                    pageData.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26.0,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: AppColors.textPrimary,
                      height: 1.2,
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                // Description
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Text(
                    pageData.description,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTiltedLayeredComposition(
    BuildContext context, {
    required double maxImageHeight,
    required double imageWidth,
  }) {
    // Create a more dynamic tilt based on page index
    final double primaryTilt = pageData.cardRotationAngle * 1.8;
    final double secondaryTilt = -pageData.cardRotationAngle * 2.2;

    return Center(
      child: SizedBox(
        height: maxImageHeight + 60.0,
        width: imageWidth + 60.0,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Background image layer - smaller and more tilted
            Positioned(
              bottom: 0,
              right: 8,
              child: Transform.rotate(
                angle: secondaryTilt,
                child: Transform.translate(
                  offset: Offset(parallaxOffset * 15.0, 8.0),
                  child: Container(
                    width: imageWidth * 0.75,
                    height: maxImageHeight * 0.75,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20.0),
                      border: Border.all(
                        color: AppColors.borderSubtle.withValues(alpha: 0.3),
                        width: 2.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18.0),
                      child: Opacity(
                        opacity: 0.6,
                        child: Image.asset(
                          pageData.imageAssetPath,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(color: AppColors.surfaceSubtle);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Primary Hero Image - larger and prominent
            Positioned(
              top: 0,
              left: 8,
              child: Transform.rotate(
                angle: primaryTilt,
                child: Transform.translate(
                  offset: Offset(-parallaxOffset * 12.0, 0),
                  child: Container(
                    width: imageWidth * 0.88,
                    height: maxImageHeight * 0.88,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(22.0),
                      border: Border.all(color: AppColors.surface, width: 3.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 30.0,
                          offset: const Offset(0, 12.0),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10.0,
                          offset: const Offset(0, 4.0),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(19.0),
                      child: Semantics(
                        image: true,
                        label: pageData.imageSemanticLabel,
                        child: Image.asset(
                          pageData.imageAssetPath,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: AppColors.surfaceSubtle,
                              child: Center(
                                child: Icon(
                                  Icons.photo_library_outlined,
                                  size: 48.0,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
