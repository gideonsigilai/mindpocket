import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/collage_art.dart';
import '../controller/onboarding_controller.dart';
import 'widgets/onboarding_page_view.dart';

/// Onboarding follows the supplied art direction: cream canvas, monochrome
/// collage, a sun disc, a floating rounded info card, dot pager, circular
/// back/next controls, and a Skip pill.
class OnboardingPage extends GetView<OnboardingController> {
  const OnboardingPage({super.key});

  static const List<OnboardingSlide> _slides = <OnboardingSlide>[
    OnboardingSlide(
      eyebrow: 'WELCOME',
      title: 'Everything worth keeping,\nin one pocket.',
      body:
          'Screenshots and voice notes live side by side, so the thought behind '
          'a picture is never lost.',
      variant: CollageVariant.capture,
    ),
    OnboardingSlide(
      eyebrow: 'VOICE',
      title: 'Speak it while\nyou remember it.',
      body:
          'Record with pause and resume, keep the audio forever, and read a '
          'transcript produced on your phone — not in a data centre.',
      variant: CollageVariant.voice,
    ),
    OnboardingSlide(
      eyebrow: 'SEARCH',
      title: 'Find the thought,\nnot the file name.',
      body:
          'Search reads titles, notes, tags, text inside screenshots, and '
          'transcripts. Type “navigation” and get the screenshot back.',
      variant: CollageVariant.search,
    ),
    OnboardingSlide(
      eyebrow: 'PRIVATE BY DEFAULT',
      title: 'On-device by design.\nCloud only if you ask.',
      body:
          'Text extraction and transcription run locally. Nothing leaves the '
          'phone unless you explicitly tap “Analyze with cloud AI”.',
      variant: CollageVariant.collections,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // Respect the OS "remove animations" setting for the cross-fades.
    final Duration motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 420);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool wide = constraints.maxWidth >= 700;
            final double artHeight = wide
                ? (constraints.maxHeight * 0.6).clamp(240.0, 520.0)
                : (constraints.maxHeight * 0.44).clamp(180.0, 360.0);

            return Column(
              children: <Widget>[
                _TopBar(controller: controller),
                Expanded(
                  child: wide
                      ? Row(
                          children: <Widget>[
                            Expanded(
                              flex: 5,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left: 36.w,
                                  right: 8.w,
                                ),
                                child: OnboardingArt(
                                  controller: controller,
                                  slides: _slides,
                                  height: artHeight,
                                  motion: motion,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 5,
                              child: Center(
                                child: SingleChildScrollView(
                                  padding: EdgeInsets.only(
                                    right: 36.w,
                                    left: 8.w,
                                  ),
                                  child: OnboardingCard(
                                    controller: controller,
                                    slides: _slides,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: <Widget>[
                            Expanded(
                              child: OnboardingArt(
                                controller: controller,
                                slides: _slides,
                                height: artHeight,
                                motion: motion,
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.fromLTRB(16.w, 4, 16.w, 12.h),
                              child: OnboardingCard(
                                controller: controller,
                                slides: _slides,
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});

  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 4.h),
      child: Row(
        children: <Widget>[
          Semantics(
            label: 'MindPocket logo',
            image: true,
            child: Container(
              width: 52.r,
              height: 52.r,
              decoration: const BoxDecoration(
                color: AppColors.ink,
                shape: BoxShape.circle,
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: EdgeInsets.all(7.r),
                child: Image.asset(
                  'assets/images/brand_mark.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ),
          const Spacer(),
          Obx(
            () => AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: controller.isLast ? 0 : 1,
              child: IgnorePointer(
                ignoring: controller.isLast,
                child: TextButton(
                  onPressed: controller.skip,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textPrimary(brightness),
                    side: BorderSide(color: AppColors.border(brightness)),
                    shape: const StadiumBorder(),
                    padding: EdgeInsets.symmetric(
                      horizontal: 24.w,
                      vertical: 10.h,
                    ),
                  ),
                  child: const Text('Skip'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared eyebrow style helper used by the onboarding card.
TextStyle onboardingEyebrow(BuildContext context) =>
    Theme.of(context).textTheme.labelSmall!.copyWith(
      color: AppColors.accentText(Theme.of(context).brightness),
      letterSpacing: 1.8,
      fontWeight: FontWeight.w800,
    );
