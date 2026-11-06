import 'package:get/get.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/storage/memory_service.dart';
import '../controller/collections_controller.dart';

class CollectionsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<CollectionsController>(
      () => CollectionsController(
        Get.find<AppDatabase>(),
        Get.find<MemoryService>(),
      ),
      fenix: true,
    );
  }
}

