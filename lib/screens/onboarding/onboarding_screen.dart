import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';
import 'package:photo_per_day/data/services/onboarding_service.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/screens/main_shell.dart';
import 'package:photo_per_day/widgets/daria_logo.dart';
import 'package:photo_per_day/screens/onboarding/onboarding_data.dart';
import 'package:photo_per_day/screens/onboarding/widgets/onboarding_page_widget.dart';

/// 3-Screen calm, editorial onboarding experience for Photo a Day.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final PageController _pageController;
  int _currentPage = 0;
  double _pageOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pageController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _pageController.removeListener(_onScroll);
    _pageController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_pageController.hasClients &&
        _pageController.position.haveDimensions &&
        _pageController.page != null) {
      setState(() {
        _pageOffset = _pageController.page!;
      });
    }
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentPage = index;
    });
  }

  void _handleNextTap() {
    if (_currentPage < OnboardingPageData.pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _completeAndExit();
    }
  }

  Future<void> _completeAndExit() async {
    await OnboardingService.instance.completeOnboarding();
    if (!mounted) return;

    final nav = Navigator.of(context);
    // After onboarding, navigate directly to the local photo diary (MainShell)
    nav.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const MainShell(),
        settings: const RouteSettings(name: AppConstants.initialRoute),
      ),
      (route) => false,
    );
  }

  void _goToPage(int pageIndex) {
    _pageController.animateToPage(
      pageIndex,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeInOutCubic,
    );
  }

  Widget _buildModernPageIndicator() {
    final pageCount = OnboardingPageData.pages.length;
    return Semantics(
      label: 'Page indicator, page ${_currentPage + 1} of $pageCount',
      child: Row(
        key: const ValueKey('onboarding_page_indicator'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(pageCount, (index) {
          final isActive = index == _currentPage;
          return GestureDetector(
            onTap: () => _goToPage(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4.0),
              height: 4.0,
              width: isActive ? 24.0 : 8.0,
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.accent
                    : AppColors.textMuted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2.0),
              ),
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeService.instance,
      builder: (context, _) {
        const pages = OnboardingPageData.pages;
        final isLastPage = _currentPage == pages.length - 1;

        return PopScope(
          canPop: _currentPage == 0,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && _currentPage > 0) {
              _pageController.previousPage(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeInOutCubic,
              );
            }
          },
          child: Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: Column(
                children: [
                  // Top bar - minimal brand mark
                  const SizedBox(height: AppSpacing.md),
                  const Center(child: DariaLogo(size: 38.0)),
                  const SizedBox(height: AppSpacing.xs),

                  // Carousel area
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: pages.length,
                      onPageChanged: _onPageChanged,
                      itemBuilder: (context, index) {
                        final pageData = pages[index];
                        final offset = _pageOffset - index;
                        return OnboardingPageWidget(
                          pageData: pageData,
                          parallaxOffset: offset,
                        );
                      },
                    ),
                  ),

                  // Bottom Controls Container
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pageHorizontal,
                      0.0,
                      AppSpacing.pageHorizontal,
                      AppSpacing.xl,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Modern page indicator with line style
                        _buildModernPageIndicator(),

                        const SizedBox(height: AppSpacing.xl),

                        // Action Bar: Skip on left, Next / Get Started on right
                        _buildBottomActionBar(isLastPage: isLastPage),
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

  Widget _buildBottomActionBar({required bool isLastPage}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: isLastPage
          ? _buildFinalActionRow(key: const ValueKey('final-action'))
          : _buildNavigationRow(key: const ValueKey('nav-action')),
    );
  }

  Widget _buildNavigationRow({required Key key}) {
    return Row(
      key: key,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Tactile Skip button
        Semantics(
          button: true,
          label: 'Skip onboarding',
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 72.0, minHeight: 48.0),
            child: TextButton(
              onPressed: _completeAndExit,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20.0,
                  vertical: 14.0,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
              ),
              child: Text(
                'Skip',
                style: TextStyle(
                  fontSize: 15.0,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),

        // Modern circular Next button with rounded pill style
        Semantics(
          button: true,
          label: 'Next page',
          child: Container(
            height: 56.0,
            decoration: BoxDecoration(
              color: const Color(0xFF9ACD32), // Lime green color from reference
              borderRadius: BorderRadius.circular(28.0),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF9ACD32).withValues(alpha: 0.3),
                  blurRadius: 12.0,
                  offset: const Offset(0, 4.0),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _handleNextTap,
                borderRadius: BorderRadius.circular(28.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 16.0,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    size: 24.0,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFinalActionRow({required Key key}) {
    return Row(
      key: key,
      children: [
        // Prominent tactile "Start My Diary" CTA (>=48dp touch target)
        Expanded(
          child: Semantics(
            button: true,
            label: 'Start My Diary',
            child: SizedBox(
              height: 52.0,
              child: ElevatedButton(
                onPressed: _completeAndExit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryButtonBackground,
                  foregroundColor: AppColors.primaryButtonForeground,
                  elevation: 1.5,
                  shadowColor: Colors.black.withValues(alpha: 0.16),
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppRadii.roundedPill,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Start My Diary',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: AppColors.primaryButtonForeground,
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 18.0,
                        color: AppColors.primaryButtonForeground,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
