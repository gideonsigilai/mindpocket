import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/memory.dart';
import '../../../core/services/processing/audio_recording_service.dart';
import '../../../core/services/processing/processing_service.dart';
import '../../../core/services/processing/share_intake_service.dart';
import '../../../core/services/storage/memory_service.dart';
import '../../../core/services/storage/preferences_service.dart';
import '../../../core/services/storage/share_import_service.dart';
import '../../../core/utils/logger.dart';
import '../../home/controller/home_controller.dart';

/// State for the capture flow: note text, tag entry, image import, and audio.
class CaptureController extends GetxController {
  CaptureController(
    this._memories,
    this._recording,
    this._shares,
    this._processing,
    this._preferences,
  );

  final MemoryService _memories;
  final AudioRecordingService _recording;
  final ShareIntakeService _shares;
  final ProcessingService _processing;
  final PreferencesService _preferences;

  final RxString title = ''.obs;
  final RxString note = ''.obs;
  final RxList<String> tags = <String>[].obs;
  final RxBool saving = false.obs;
  final RxString error = ''.obs;
  final RxList<File> pendingImages = <File>[].obs;

  final Rx<RecorderStatus> recorderStatus = RecorderStatus.idle.obs;
  final Rx<Duration> recorderElapsed = Duration.zero.obs;
  final RxDouble recorderAmplitude = 0.0.obs;

  final List<Worker> _workers = <Worker>[];

  @override
  void onInit() {
    super.onInit();
    _workers.add(
      ever<RecorderStatus>(_recording.status, (RecorderStatus status) {
        recorderStatus.value = status;
      }),
    );
    _workers.add(
      ever<Duration>(_recording.elapsed, (Duration value) {
        recorderElapsed.value = value;
      }),
    );
    _workers.add(
      ever<double>(_recording.amplitude, (double value) {
        recorderAmplitude.value = value;
      }),
    );
  }

  Future<void> pickImages() async {
    error.value = '';
    try {
      final List<File> files = await _shares.pickImages();
      if (files.isEmpty) return;
      int saved = 0;
      bool duplicated = false;
      for (final File file in files) {
        final ImportOutcome outcome = await _memories.createFromImage(
          source: file,
          // Named for how it arrived; the extracted text becomes the real body.
          title: 'Screenshot',
          memorySource: MemorySource.picker,
        );
        if (outcome.isDuplicate) {
          // The service already dropped its provisional row; `outcome.memoryId`
          // is the existing memory and must not be deleted.
          duplicated = true;
        } else {
          saved++;
        }
      }
      _processing.schedule();
      // Reported through the timeline banner, the same channel shares use.
      if (Get.isRegistered<ShareImportService>()) {
        Get.find<ShareImportService>().lastMessage.value = duplicated
            ? (saved == 0
                  ? 'That image is already in your pocket.'
                  : 'Saved $saved of ${files.length} images; the rest were already in your pocket.')
            : 'Saved $saved image${saved == 1 ? '' : 's'}. '
                  'Text extraction runs on this device.';
      }
      if (Get.isRegistered<HomeController>()) {
        Get.find<HomeController>().requestScrollToTop();
      }
      // Pop the composer rather than routing to home: `offAllNamed` would
      // discard the live timeline and rebuild the shell, leaving the finished
      // import and its processing banner unseen under a stale controller.
      Get.back();
    } catch (exception) {
      error.value = exception.toString();
    }
  }

  Future<void> saveNote() async {
    if (title.value.trim().isEmpty && note.value.trim().isEmpty) {
      error.value = 'Write something first — a title or a few words.';
      return;
    }
    saving.value = true;
    error.value = '';
    try {
      final Memory memory = await _memories.createNote(
        title: title.value,
        note: note.value,
        tags: tags,
      );
      // Replace the composer with the saved memory, so Back returns to the
      // timeline instead of stranding the user with no route underneath.
      Get.offNamed(AppRoutes.memory(memory.id));
    } catch (exception) {
      logError('Note save failed', exception);
      error.value = 'That note could not be saved. Try again.';
    } finally {
      saving.value = false;
    }
  }

  void addTag(String value) {
    final String cleaned = value.trim().replaceAll('#', '');
    if (cleaned.isEmpty || tags.length >= 12) return;
    if (tags.any((String tag) => tag.toLowerCase() == cleaned.toLowerCase())) {
      return;
    }
    tags.add(cleaned);
  }

  void removeTag(String value) => tags.remove(value);

  Future<String?> startRecording() async {
    error.value = '';
    final String? failure = await _recording.start();
    if (failure != null) error.value = failure;
    return failure;
  }

  Future<void> pauseRecording() => _recording.pause();
  Future<void> resumeRecording() => _recording.resume();

  Future<void> cancelRecording() async {
    await _recording.cancel();
    recorderElapsed.value = Duration.zero;
  }

  /// Stops, saves as a new voice memory, and schedules transcription when a
  /// model is installed. Audio is always kept even if the model is missing.
  Future<void> finishRecording() async {
    final RecordedAudio? audio = await _recording.stop();
    if (audio == null) {
      error.value = _recording.errorMessage.value.isNotEmpty
          ? _recording.errorMessage.value
          : 'Nothing was recorded.';
      return;
    }
    saving.value = true;
    try {
      final Memory memory = await _memories.createVoiceMemory(
        title: title.value,
      );
      await _memories.attachRecording(
        memoryId: memory.id,
        tempPath: audio.tempPath,
        duration: audio.duration,
      );
      await File(audio.tempPath)
          .delete()
          .catchError((Object _) => File(audio.tempPath));
      _processing.schedule();
      Get.offNamed(AppRoutes.memory(memory.id));
    } catch (exception) {
      logError('Voice save failed', exception);
      error.value = 'The recording could not be saved to your pocket.';
    } finally {
      saving.value = false;
    }
  }

  /// True when the composer holds anything the user would lose by leaving.
  bool get hasDraft =>
      title.value.trim().isNotEmpty ||
      note.value.trim().isNotEmpty ||
      tags.isNotEmpty ||
      pendingImages.isNotEmpty;

  Future<bool> confirmDiscard() async {
    final bool recording = _recording.isActive;
    if (!recording && !hasDraft) return true;
    final bool? discard = await Get.dialog<bool>(
      AlertDialog(
        title: Text(
          recording ? 'Discard this recording?' : 'Discard this draft?',
        ),
        content: Text(
          recording
              ? 'The audio has not been saved yet.'
              : 'What you entered has not been saved yet.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Get.back<bool>(result: false),
            child: Text(recording ? 'Keep recording' : 'Keep editing'),
          ),
          FilledButton(
            onPressed: () => Get.back<bool>(result: true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true) {
      if (recording) await _recording.cancel();
      return true;
    }
    return false;
  }

  bool get autoOcr => _preferences.ocrAuto;
  bool get autoTranscribe => _preferences.transcribeAuto;

  @override
  void onClose() {
    for (final Worker worker in _workers) {
      worker.dispose();
    }
    super.onClose();
  }
}
