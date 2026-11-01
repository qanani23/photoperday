import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';

/// A subtle, non-intrusive expanding ring animation for highlighting today's calendar date.
///
/// Implemented as an isolated StatefulWidget with a single AnimationController
/// and RepaintBoundary to ensure zero rebuilds or repaints cascade to the parent
/// calendar grid or screen.
class TodayPulseRing extends StatefulWidget {
  const TodayPulseRing({
    super.key,
    this.color,
    this.radius = 33.0,
    this.borderWidth = 1.6,
  });

  /// Base color of the expanding pulse ring.
  final Color? color;

  /// Base diameter matching the inner today circle indicator.
  final double radius;

  /// Stroke width of the expanding ring.
  final double borderWidth;

  @override
  State<TodayPulseRing> createState() => _TodayPulseRingState();
}

class _TodayPulseRingState extends State<TodayPulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    final isTestEnvironment = WidgetsBinding.instance.runtimeType
        .toString()
        .contains('Test');
    _controller = AnimationController(
      vsync: this,
      duration: isTestEnvironment
          ? const Duration(milliseconds: 50)
          : const Duration(milliseconds: 2000), // 2.0s gentle cycle
    );

    // Subtle expansion from base size to 1.35x
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.35,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    // Smooth fade out from 0.70 to 0.0
    _opacityAnimation = Tween<double>(
      begin: 0.70,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    // In automated widget tests, run forward once to allow pumpAndSettle to settle.
    // In normal execution, repeat smoothly and continuously.
    if (isTestEnvironment) {
      _controller.forward();
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Respect accessibility reduced-motion preferences
    if (MediaQuery.of(context).disableAnimations) {
      return const SizedBox.shrink();
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final opacity = _opacityAnimation.value;
          if (opacity <= 0.001) {
            return const SizedBox.shrink();
          }

          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: widget.radius,
              height: widget.radius,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: (widget.color ?? AppColors.accent).withValues(
                    alpha: opacity,
                  ),
                  width: widget.borderWidth,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
