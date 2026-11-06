import 'dart:async';

import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/services/screenshots/screenshot_autopilot.dart';
import '../../../core/services/storage/preferences_service.dart';

/// First-run flow. Four pages mirroring the reference collage style, then a
/// single honest promise about local processing.
class OnboardingController extends GetxController {
  OnboardingController(this._preferences);

  final PreferencesService _preferences;

  final RxInt page = 0.obs;
  static const int pageCount = 4;

  bool get isLast => page.value == pageCount - 1;

  void next() {
    if (isLast) {
      finish();
    } else {
      page.value++;
    }
  }

  void previous() {
    if (page.value > 0) page.value--;
  }

  void goTo(int index) {
    if (index >= 0 && index < pageCount) page.value = index;
  }

  Future<void> finish() async {
    await _preferences.completeOnboarding();
    Get.offAllNamed(AppRoutes.home);
    // Now that onboarding is done, ask for screenshot access and take
    // everything the gallery already holds.
    if (Get.isRegistered<ScreenshotAutopilot>()) {
      unawaited(Get.find<ScreenshotAutopilot>().run(requestAccess: true));
    }
  }

  /// Skip keeps the same destination: onboarding is optional, not a gate.
  Future<void> skip() => finish();
}
