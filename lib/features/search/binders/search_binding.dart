import 'package:get/get.dart';

import '../../../core/services/ai/related_service.dart';
import '../../../core/services/storage/memory_service.dart';
import '../controller/search_page_controller.dart';

class SearchBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SearchPageController>(
      () => SearchPageController(
        Get.find<MemoryService>(),
        Get.find<RelatedService>(),
      ),
      fenix: true,
    );
  }
}
