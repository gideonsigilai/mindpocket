import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/services/ai/model_manager.dart';
import '../../../core/services/storage/preferences_service.dart';
import '../controller/cloud_settings_controller.dart';
import '../controller/models_controller.dart';
import '../controller/settings_controller.dart';

class SettingsBinding extends Bindings {
  @override
  void dependencies() {
    final SettingsController controller = Get.find<SettingsController>();
    // Bootstrap builds this controller before the first import has run, so
    // opening the page must re-read the facts it displays. Both reads mutate
    // observables, and dependencies() runs inside initState — i.e. during the
    // build phase — so they are deferred until the frame is complete.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.refreshStorage();
      controller.loadScreenshotState();
    });
  }
}

class ModelsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ModelsController>(
      () => ModelsController(
        Get.find<ModelManager>(),
        Get.find<SettingsController>(),
      ),
      fenix: true,
    );
  }
}

class CloudSettingsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<CloudSettingsController>(
      () => CloudSettingsController(Get.find<PreferencesService>()),
      fenix: true,
    );
  }
}

/// Route paths referenced by the pages themselves.
String get modelRoute => AppRoutes.models;
String get cloudRoute => AppRoutes.cloud;
