import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:get/get.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/collage_art.dart';
import '../../controller/onboarding_controller.dart';

class OnboardingSlide {
  const OnboardingSlide({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.variant,
  });

  final String eyebrow;
  final String title;
  final String body;
  final CollageVariant variant;
}

/// The stacked "sheets" of illustration, one per slide, cross-faded as the page
/// changes. Keeping them all mounted lets the painter's deterministic grain stay
/// stable while swiping.
class OnboardingArt extends StatelessWidget {
  const OnboardingArt({
    super.key,
    required this.controller,
    required this.slides,
    required this.height,
    required this.motion,
  });

  final OnboardingController controller;
  final List<OnboardingSlide> slides;
  final double height;
  final Duration motion;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.2, -0.35),
                radius: 1.05,
                colors: <Color>[
                  AppColors.surface(brightness),
                  AppColors.background(brightness),
                ],
              ),
            ),
          ),
        ),
        Obx(() {
          final int current = controller.page.value;
          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              for (int index = 0; index < slides.length; index++)
                AnimatedOpacity(
                  duration: motion,
                  curve: Curves.easeOutCubic,
                  opacity: index == current ? 1 : 0,
                  child: AnimatedSlide(
                    duration: motion,
                    curve: Curves.easeOutCubic,
                    offset: index == current
                        ? Offset.zero
                        : Offset(index < current ? -0.06 : 0.06, 0),
                    child: CollageArt(
                      variant: slides[index].variant,
                      height: height,
                    ),
                  ),
                ),
            ],
          );
        }),
      ],
    );
  }
}

/// Floating card with title, body, pager dots, and circular navigation.
class OnboardingCard extends StatelessWidget {
  const OnboardingCard({
    super.key,
    required this.controller,
    required this.slides,
  });

  final OnboardingController controller;
  final List<OnboardingSlide> slides;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      padding: EdgeInsets.fromLTRB(24.w, 26.h, 20.w, 20.h),
      decoration: BoxDecoration(
        color: AppColors.surface(brightness),
        borderRadius: BorderRadius.circular(32.r),
        border: Border.all(color: AppColors.border(brightness)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(
              alpha: brightness == Brightness.dark ? 0.35 : 0.06,
            ),
            blurRadius: 34,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Obx(() {
        final int index = controller.page.value;
        final OnboardingSlide slide = slides[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              slide.eyebrow,
              style: text.labelSmall?.copyWith(
                color: AppColors.accentText(brightness),
                letterSpacing: 1.8,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 10.h),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: Text(
                slide.title,
                key: ValueKey<int>(index),
                style: text.headlineMedium?.copyWith(height: 1.15),
              ),
            ),
            SizedBox(height: 10.h),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: Text(
                slide.body,
                key: ValueKey<String>('body-$index'),
                style: text.bodyMedium?.copyWith(
                  color: AppColors.textSecondary(brightness),
                ),
              ),
            ),
            SizedBox(height: 22.h),
            Row(
              children: <Widget>[
                _Dots(
                  count: slides.length,
                  index: index,
                  brightness: brightness,
                ),
                const Spacer(),
                if (index > 0) ...<Widget>[
                  _CircleButton(
                    icon: Icons.arrow_back_rounded,
                    filled: false,
                    label: 'Previous tip',
                    onPressed: controller.previous,
                  ),
                  SizedBox(width: 12.w),
                ],
                _CircleButton(
                  icon: controller.isLast
                      ? Icons.check_rounded
                      : Icons.arrow_forward_rounded,
                  filled: true,
                  label: controller.isLast
                      ? 'Start using MindPocket'
                      : 'Next tip',
                  onPressed: controller.next,
                ),
              ],
            ),
          ],
        );
      }),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({
    required this.count,
    required this.index,
    required this.brightness,
  });

  final int count;
  final int index;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step ${index + 1} of $count',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List<Widget>.generate(count, (int dot) {
          final bool active = dot == index;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            margin: const EdgeInsets.only(right: 6),
            width: active ? 18 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: active
                  ? AppColors.highlight(brightness)
                  : AppColors.border(brightness),
              borderRadius: BorderRadius.circular(999),
            ),
          );
        }),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.filled,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final bool filled;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final double size = 54.r;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: filled ? AppColors.highlight(brightness) : Colors.transparent,
        shape: CircleBorder(
          side: BorderSide(
            color: filled
                ? AppColors.highlight(brightness)
                : AppColors.border(brightness),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: 22,
              color: filled
                  ? AppColors.onSun
                  : AppColors.textPrimary(brightness),
            ),
          ),
        ),
      ),
    );
  }
}
