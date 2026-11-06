import 'package:get/get.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/processing/processing_service.dart';
import '../../../core/services/storage/memory_service.dart';
import '../../../core/services/storage/preferences_service.dart';
import '../controller/home_controller.dart';

class HomeBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<HomeController>(
      () => HomeController(
        Get.find<MemoryService>(),
        Get.find<ProcessingService>(),
        Get.find<PreferencesService>(),
        Get.find<AppDatabase>(),
      ),
    );
  }
}
