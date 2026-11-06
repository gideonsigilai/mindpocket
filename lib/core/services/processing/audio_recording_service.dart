import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import '../../utils/logger.dart';
import '../permissions/permissions_service.dart';
import '../storage/path_service.dart';

enum RecorderStatus { idle, recording, paused, stopping, failed }

/// Microphone capture: start, pause, resume, stop, plus live amplitude for the
/// waveform. Writes a 16 kHz mono WAV that the offline recogniser can read
/// directly, so no transcoding step can fail between recording and transcription.
class AudioRecordingService extends GetxService {
  AudioRecordingService(this._paths, this._permissions);

  final PathService _paths;
  final PermissionsService _permissions;

  final AudioRecorder _recorder = AudioRecorder();

  final Rx<RecorderStatus> status = RecorderStatus.idle.obs;
  final Rx<Duration> elapsed = Duration.zero.obs;
  final Rx<double> amplitude = 0.0.obs;
  final RxString errorMessage = ''.obs;

  Timer? _ticker;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  Stopwatch _stopwatch = Stopwatch();
  Duration _accumulated = Duration.zero;
  String? _currentPath;

  bool get isRecording => status.value == RecorderStatus.recording;
  bool get isPaused => status.value == RecorderStatus.paused;
  bool get isActive =>
      status.value == RecorderStatus.recording ||
      status.value == RecorderStatus.paused;

  /// Starts a new recording. Returns an explanatory message on failure so the UI
  /// can offer Settings, while keeping the "type a note" path available.
  Future<String?> start() async {
    if (isActive) return 'A recording is already in progress.';
    final PermissionOutcome mic = await _permissions.ensureMicrophone();
    if (!mic.isGranted) {
      return permissionMessage(mic, 'Recording');
    }
    try {
      final Directory temp = await _paths.temporary;
      final String path = p.join(
        temp.path,
        'rec_${DateTime.now().microsecondsSinceEpoch}.wav',
      );
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 256000,
          autoGain: true,
          echoCancel: true,
        ),
        path: path,
      );
      _currentPath = path;
      _accumulated = Duration.zero;
      _stopwatch = Stopwatch()..start();
      elapsed.value = Duration.zero;
      errorMessage.value = '';
      status.value = RecorderStatus.recording;
      _startTicker();
      _listenAmplitude();
      return null;
    } catch (error) {
      logWarn('Recorder start failed', error);
      status.value = RecorderStatus.failed;
      errorMessage.value =
          'The microphone could not be started. Another app may be using it.';
      return errorMessage.value;
    }
  }

  Future<void> pause() async {
    if (status.value != RecorderStatus.recording) return;
    try {
      await _recorder.pause();
      _stopwatch.stop();
      _accumulated += _stopwatch.elapsed;
      _stopwatch = Stopwatch();
      _stopTicker();
      amplitude.value = 0;
      status.value = RecorderStatus.paused;
    } catch (error) {
      logWarn('Recorder pause failed', error);
    }
  }

  Future<void> resume() async {
    if (status.value != RecorderStatus.paused) return;
    try {
      await _recorder.resume();
      _stopwatch = Stopwatch()..start();
      status.value = RecorderStatus.recording;
      _startTicker();
      _listenAmplitude();
    } catch (error) {
      logWarn('Recorder resume failed', error);
      errorMessage.value = 'Could not resume recording.';
    }
  }

  /// Stops and returns the temp file path plus total duration, or null when the
  /// recording was abandoned.
  Future<RecordedAudio?> stop() async {
    if (!isActive) return null;
    status.value = RecorderStatus.stopping;
    final Duration total = duration;
    _stopTicker();
    _stopwatch.stop();
    try {
      final String? path = await _recorder.stop();
      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = null;
      final String? finalPath = path ?? _currentPath;
      _currentPath = null;
      status.value = RecorderStatus.idle;
      amplitude.value = 0;
      if (finalPath == null) return null;
      final File file = File(finalPath);
      if (!await file.exists() || await file.length() < 1024) {
        // Shorter than ~30 ms of audio: nothing useful was captured.
        if (await file.exists()) await file.delete();
        errorMessage.value = 'That recording was too short to save.';
        return null;
      }
      return RecordedAudio(tempPath: finalPath, duration: total);
    } catch (error) {
      logWarn('Recorder stop failed', error);
      status.value = RecorderStatus.idle;
      errorMessage.value = 'The recording could not be finished.';
      return null;
    } finally {
      _accumulated = Duration.zero;
      elapsed.value = Duration.zero;
    }
  }

  /// Throws away the current recording without keeping the file.
  Future<void> cancel() async {
    if (!isActive) return;
    _stopTicker();
    _stopwatch.stop();
    try {
      await _recorder.cancel();
    } catch (_) {
      // Nothing durable to clean up.
    }
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    final String? path = _currentPath;
    _currentPath = null;
    if (path != null) {
      final File file = File(path);
      if (await file.exists()) await file.delete();
    }
    _accumulated = Duration.zero;
    elapsed.value = Duration.zero;
    amplitude.value = 0;
    status.value = RecorderStatus.idle;
  }

  Duration get duration => _accumulated + _stopwatch.elapsed;

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      elapsed.value = duration;
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    elapsed.value = duration;
  }

  void _listenAmplitude() {
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 120))
        .listen((Amplitude value) {
          // Normalize -60..0 dBFS to 0..1 for the waveform bars.
          final double normalized = ((value.current + 55) / 55).clamp(0.0, 1.0);
          amplitude.value = normalized;
        }, onError: (Object error) => logWarn('Amplitude stream error', error));
  }

  @override
  void onClose() {
    _ticker?.cancel();
    _amplitudeSubscription?.cancel();
    _recorder.dispose();
    super.onClose();
  }
}

class RecordedAudio {
  const RecordedAudio({required this.tempPath, required this.duration});

  final String tempPath;
  final Duration duration;
}
