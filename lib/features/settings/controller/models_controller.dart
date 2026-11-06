import 'dart:async';

import 'package:get/get.dart';

import '../../../core/services/ai/model_catalog.dart';
import '../../../core/services/processing/processing_service.dart';
import '../../../core/services/ai/model_manager.dart';
import '../../../core/services/ai/sherpa_transcriber.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/logger.dart';
import 'settings_controller.dart';

/// Model download UI state: progress, cancellation, integrity, removal, and a
/// real test-transcription check with a bundled silence sample would be
/// misleading, so the check is a model-file verification instead.
class ModelsController extends GetxController {
  ModelsController(this._models, this._settings);

  final ModelManager _models;
  final SettingsController _settings;

  final RxString error = ''.obs;
  final RxString notice = ''.obs;
  final RxBool verifying = false.obs;

  ModelManager get manager => _models;

  Future<void> download(ModelSpec spec) async {
    error.value = '';
    notice.value = '';
    final String? failure = await _settings.downloadModel(spec);
    if (failure != null) {
      error.value = failure;
    } else {
      // Jobs parked for want of a model resume the moment one exists, so the
      // "queued" badge does not survive the download that unblocked it.
      if (Get.isRegistered<ProcessingService>()) {
        unawaited(Get.find<ProcessingService>().resumeQueue());
      }
      notice.value =
          '${spec.displayName} is installed and verified. '
          'Transcription now runs entirely on this device.';
    }
  }

  void cancel() => _models.cancelDownload();

  Future<void> remove(ModelSpec spec) async {
    await _settings.removeModel(spec);
    notice.value =
        '${spec.displayName} removed. Audio and transcripts are untouched.';
  }

  Future<void> setActive(ModelSpec spec) async {
    await _models.setActive(spec.id);
    notice.value = '${spec.displayName} will be used for new transcriptions.';
  }

  /// Re-hashes the installed files and reports whether they still match.
  Future<void> verify(ModelSpec spec) async {
    verifying.value = true;
    error.value = '';
    notice.value = '';
    try {
      final bool ok = await _models.verifyIntegrity(spec);
      if (ok) {
        notice.value =
            'All ${spec.files.length} files match their published checksums.';
      } else {
        error.value =
            'A model file failed verification. Remove and download it again.';
      }
    } catch (exception, stack) {
      logError('Model verification failed', exception, stack);
      error.value = 'Verification could not run.';
    } finally {
      verifying.value = false;
    }
  }

  String get storageSummary => Format.bytes(
    _models.statuses.isNotEmpty
        ? modelCatalog
              .where((ModelSpec spec) => _models.isReady(spec.id))
              .fold<int>(0, (int sum, ModelSpec spec) => sum + spec.totalBytes)
        : 0,
  );

  /// Human-readable constraints shown next to each model.
  static String requirementText(ModelSpec spec) =>
      '${Format.bytes(spec.totalBytes)} download · needs about '
      '${Format.bytes(spec.requiredFreeBytes)} free while installing · '
      'network required once · ${spec.language}';

  static String licences() => modelCatalog
      .map((ModelSpec spec) => '${spec.displayName}: ${spec.license}')
      .join('\n');
}

/// Model verification lives with the transcriber so the checksum rules have a
/// single owner. Exposed here as an extension for the settings UI.
extension ModelVerification on ModelManager {
  Future<bool> verifyIntegrity(ModelSpec spec) async {
    final ModelPaths paths = await pathsFor(spec);
    return ModelIntegrity.verify(paths, spec);
  }
}
