import 'package:get/get.dart';

import '../../features/capture/binders/capture_binding.dart';
import '../../features/capture/presentation/capture_page.dart';
import '../../features/collections/controller/collections_controller.dart';
import '../../features/collections/presentation/collection_detail_page.dart';
import '../../features/memory_detail/controller/memory_detail_controller.dart';
import '../../features/memory_detail/presentation/memory_detail_page.dart';
import '../../features/onboarding/binders/onboarding_binding.dart';
import '../../features/onboarding/presentation/onboarding_page.dart';
import '../../features/search/binders/search_binding.dart';
import '../../features/search/presentation/search_page.dart';
import '../../features/settings/binders/settings_binding.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../routes/app_routes.dart';
import '../routes/app_shell.dart';
import 'splash_page.dart';

/// Route table. Every route declares its own binding so navigation works from a
/// cold start (deep link, share intent, restored notification) as well as from
/// the running app.
abstract final class AppPages {
  static final List<GetPage<dynamic>> pages = <GetPage<dynamic>>[
    GetPage<dynamic>(name: AppRoutes.splash, page: () => const SplashPage()),
    GetPage<dynamic>(
      name: AppRoutes.onboarding,
      page: () => const OnboardingPage(),
      binding: OnboardingBinding(),
      transition: Transition.fadeIn,
    ),
    GetPage<dynamic>(
      name: AppRoutes.home,
      // The shell owns the tab bindings; the route binding only wires the
      // app-level dependencies that a cold deep link may not have run yet.
      page: () => const AppShell(),
      transition: Transition.fadeIn,
    ),
    GetPage<dynamic>(
      name: AppRoutes.capture,
      page: () => const CapturePage(),
      binding: CaptureBinding(),
      transition: Transition.downToUp,
      fullscreenDialog: true,
    ),
    GetPage<dynamic>(
      name: AppRoutes.search,
      page: () => const SearchPage(),
      binding: SearchBinding(),
      transition: Transition.fadeIn,
    ),
    GetPage<dynamic>(
      name: AppRoutes.settings,
      page: () => const AppShell(initialIndex: 2),
      binding: SettingsBinding(),
      transition: Transition.fadeIn,
    ),
    GetPage<dynamic>(
      name: AppRoutes.models,
      page: () => const ModelsPage(),
      binding: ModelsBinding(),
      transition: Transition.cupertino,
    ),
    GetPage<dynamic>(
      name: AppRoutes.cloud,
      page: () => const CloudSettingsPage(),
      binding: CloudSettingsBinding(),
      transition: Transition.cupertino,
    ),
    GetPage<dynamic>(
      name: '/memory/:id',
      // The id is captured when this page is created. Reading Get.parameters in
      // build would follow the *current* route, so a page still in the back
      // stack would look up a controller that no longer matches it.
      page: () => MemoryDetailPage(memoryId: Get.parameters['id'] ?? ''),
      binding: _MemoryRouteBinding(),
      transition: Transition.cupertino,
    ),
    GetPage<dynamic>(
      name: '/collections/:id',
      page: () =>
          CollectionDetailPage(collectionId: Get.parameters['id'] ?? ''),
      binding: _CollectionRouteBinding(),
      transition: Transition.cupertino,
    ),
  ];
}

class _MemoryRouteBinding extends Bindings {
  @override
  void dependencies() {
    final String id = Get.parameters['id'] ?? '';
    // Tagged per memory: opening a second memory must not reuse the first
    // route's controller, which would keep rendering the old memory.
    Get.put<MemoryDetailController>(
      MemoryDetailController.fromEnvironment(id),
      tag: id,
    );
  }
}

class _CollectionRouteBinding extends Bindings {
  @override
  void dependencies() {
    final String id = Get.parameters['id'] ?? '';
    // Same reason as memory: one controller per collection route.
    Get.put<CollectionDetailController>(
      CollectionDetailController.fromEnvironment(id),
      tag: id,
    );
  }
}
