import 'package:get/get.dart';

import '../../../core/services/processing/audio_recording_service.dart';
import '../../../core/services/processing/processing_service.dart';
import '../../../core/services/processing/share_intake_service.dart';
import '../../../core/services/storage/memory_service.dart';
import '../../../core/services/storage/preferences_service.dart';
import '../controller/capture_controller.dart';

class CaptureBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<CaptureController>(
      () => CaptureController(
        Get.find<MemoryService>(),
        Get.find<AudioRecordingService>(),
        Get.find<ShareIntakeService>(),
        Get.find<ProcessingService>(),
        Get.find<PreferencesService>(),
      ),
    );
  }
}
