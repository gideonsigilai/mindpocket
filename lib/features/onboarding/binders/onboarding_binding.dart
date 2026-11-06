import 'package:get/get.dart';

import '../../../core/services/storage/preferences_service.dart';
import '../controller/onboarding_controller.dart';

class OnboardingBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<OnboardingController>(
      () => OnboardingController(Get.find<PreferencesService>()),
    );
  }
}
