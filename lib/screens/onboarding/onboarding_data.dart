import 'package:flutter/material.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';

/// Presentation data model for each screen in the Photo a Day onboarding experience.
@immutable
class OnboardingPageData {
  const OnboardingPageData({
    required this.index,
    required this.title,
    required this.description,
    required this.imageAssetPath,
    required this.imageSemanticLabel,
    required this.badgeLabel,
    required this.cardRotationAngle,
  });

  /// Zero-based page index (0, 1, 2).
  final int index;

  /// Concise editorial title.
  final String title;

  /// Calm supporting description.
  final String description;

  /// Bundled image asset path.
  final String imageAssetPath;

  /// High-accessibility screen reader description of the photograph.
  final String imageSemanticLabel;

  /// Subtle editorial badge text rendered on top of the composition.
  final String badgeLabel;

  /// Subtle rotation angle (in radians) for the background offset card.
  final double cardRotationAngle;

  /// The curated list of 3 onboarding screens for Photo a Day.
  static const List<OnboardingPageData> pages = [
    OnboardingPageData(
      index: 0,
      title: 'One photo. Every day.',
      description:
          'Turn everyday moments into a visual diary, one photo at a time.',
      imageAssetPath: AppConstants.onboardingImage1,
      imageSemanticLabel:
          'Person capturing a photo of their daily moment with a smartphone',
      badgeLabel: 'Today • 8:15 AM',
      cardRotationAngle: -0.035,
    ),
    OnboardingPageData(
      index: 1,
      title: 'Your life, in photos.',
      description:
          'Browse your moments through a beautiful calendar and revisit the days you\'ve captured.',
      imageAssetPath: AppConstants.onboardingImage2,
      imageSemanticLabel:
          'Calendar view showing a collection of daily photos arranged by date',
      badgeLabel: 'Visual Diary',
      cardRotationAngle: 0.030,
    ),
    OnboardingPageData(
      index: 2,
      title: 'Make every day count.',
      description:
          'Build a lasting collection of memories and see your photo streak grow over time.',
      imageAssetPath: AppConstants.onboardingImage3,
      imageSemanticLabel:
          'Streak counter displaying a growing collection of consecutive daily photos',
      badgeLabel: '14 Day Streak',
      cardRotationAngle: -0.025,
    ),
  ];
}
