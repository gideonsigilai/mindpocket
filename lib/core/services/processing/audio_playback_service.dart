import 'dart:async';

import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/attachment.dart';
import '../../utils/logger.dart';
import '../storage/path_service.dart';

enum PlayerStatus { idle, loading, playing, paused, completed, error }

/// One audio player shared by the whole app so a recording never overlaps
/// itself. Owns exactly one [AudioPlayer] and disposes it with the app.
class AudioPlaybackService extends GetxService {
  AudioPlaybackService(this._paths);

  final PathService _paths;
  final AudioPlayer _player = AudioPlayer();

  final Rx<PlayerStatus> status = PlayerStatus.idle.obs;
  final RxString currentAttachmentId = ''.obs;
  final Rx<Duration> position = Duration.zero.obs;
  final Rx<Duration> duration = Duration.zero.obs;
  final RxString errorMessage = ''.obs;

  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];

  Future<void> init() async {
    _subscriptions.add(
      _player.playerStateStream.listen((PlayerState state) {
        if (state.processingState == ProcessingState.completed) {
          status.value = PlayerStatus.completed;
          position.value = duration.value;
        } else if (state.playing) {
          status.value = PlayerStatus.playing;
        } else if (status.value != PlayerStatus.loading &&
            status.value != PlayerStatus.error) {
          status.value = PlayerStatus.paused;
        }
      }),
    );
    _subscriptions.add(
      _player.positionStream.listen((Duration value) => position.value = value),
    );
    _subscriptions.add(
      _player.durationStream.listen((Duration? value) {
        if (value != null) duration.value = value;
      }),
    );
    _subscriptions.add(
      _player.errorStream.listen((PlayerException error) {
        errorMessage.value = 'Playback error: ${error.message ?? error.code}';
        status.value = PlayerStatus.error;
      }),
    );
    return;
  }

  bool isCurrent(String attachmentId) =>
      currentAttachmentId.value == attachmentId;

  /// Loads and plays [attachment]. Reuses the loaded file when the same audio is
  /// addressed again (seek/resume instead of restarting).
  Future<void> toggle(Attachment attachment) async {
    try {
      if (isCurrent(attachment.id)) {
        if (status.value == PlayerStatus.playing) {
          await _player.pause();
          return;
        }
        if (status.value == PlayerStatus.completed) {
          await _player.seek(Duration.zero);
        }
        await _player.play();
        return;
      }
      await _load(attachment);
      await _player.play();
    } on PlayerException catch (error) {
      errorMessage.value = _explainPlayback(error);
      status.value = PlayerStatus.error;
    } catch (error) {
      logWarn('Audio playback failed', error);
      errorMessage.value = 'This recording could not be played.';
      status.value = PlayerStatus.error;
    }
  }

  Future<void> _load(Attachment attachment) async {
    status.value = PlayerStatus.loading;
    errorMessage.value = '';
    position.value = Duration.zero;
    duration.value = attachment.duration ?? Duration.zero;
    final String absolute = await _paths.absolute(attachment.relativePath);
    final Duration? length = await _player.setFilePath(absolute);
    currentAttachmentId.value = attachment.id;
    if (length != null) duration.value = length;
    status.value = PlayerStatus.paused;
  }

  /// Loads without starting playback, so the waveform/seek bar can be scrubbed.
  Future<void> prepare(Attachment attachment) async {
    if (isCurrent(attachment.id)) return;
    try {
      await _load(attachment);
    } catch (error) {
      errorMessage.value = 'This recording could not be opened.';
      status.value = PlayerStatus.error;
      logWarn('Audio prepare failed', error);
    }
  }

  Future<void> seek(Duration value) async {
    if (currentAttachmentId.value.isEmpty) return;
    final Duration target = value < Duration.zero
        ? Duration.zero
        : (value > duration.value ? duration.value : value);
    await _player.seek(target);
    position.value = target;
  }

  Future<void> pause() async {
    if (status.value == PlayerStatus.playing) await _player.pause();
  }

  Future<void> stop() async {
    await _player.stop();
    currentAttachmentId.value = '';
    status.value = PlayerStatus.idle;
    position.value = Duration.zero;
  }

  String _explainPlayback(PlayerException error) =>
      error.message ?? 'Playback failed (code ${error.code}).';

  /// Pauses playback when the app is backgrounded. Called from lifecycle hooks.
  Future<void> onAppPaused() => pause();

  @override
  void onClose() {
    for (final StreamSubscription<Object?> subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _player.dispose();
    super.onClose();
  }
}
