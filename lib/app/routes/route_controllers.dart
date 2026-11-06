import 'package:get/get.dart';

import '../../core/database/app_database.dart';
import '../../core/models/memory.dart';
import '../../core/services/storage/memory_service.dart';
import '../../core/services/storage/preferences_service.dart';
import 'app_routes.dart';

/// Root navigation: onboarding on first run, home afterwards. The splash
/// resolves the branch without flashing the wrong screen.
class SplashController extends GetxController {
  SplashController(this._preferences);

  final PreferencesService _preferences;

  @override
  void onReady() {
    super.onReady();
    _decide();
  }

  Future<void> _decide() async {
    // A short frame delay avoids a jarring immediate replacement while the first
    // frame paints.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    Get.offAllNamed(
      _preferences.onboardingDone ? AppRoutes.home : AppRoutes.onboarding,
    );
  }
}

/// Opens a memory by id, showing an honest "not found" page when it was deleted
/// from another route or restored from an old link.
class MemoryRouteController extends GetxController {
  MemoryRouteController(this._memoryService, this.memoryId);

  final MemoryService _memoryService;
  final String memoryId;

  final Rx<Memory?> memory = Rx<Memory?>(null);
  final RxBool loading = true.obs;
  final RxString error = ''.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    loading.value = true;
    error.value = '';
    try {
      memory.value = await _memoryService.findById(memoryId);
      if (memory.value == null) {
        error.value = 'This memory no longer exists. It may have been deleted.';
      }
    } catch (exception) {
      error.value = 'This memory could not be opened: $exception';
    } finally {
      loading.value = false;
    }
  }
}

/// Health probe used by the splash screen's recovery path.
Future<bool> databaseIsHealthy(AppDatabase database) => database.isHealthy();
