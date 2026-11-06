import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/services/processing/audio_playback_service.dart';
import '../../../../core/services/storage/path_service.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/models/attachment.dart';

/// Local image with a file-existence guard, so a restored backup missing a file
/// shows a clear placeholder instead of a red error box.
class LocalImage extends StatelessWidget {
  const LocalImage({
    super.key,
    required this.relativePath,
    this.fit = BoxFit.cover,
    this.cacheWidth,
  });

  final String relativePath;
  final BoxFit fit;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: Get.find<PathService>().absolute(relativePath),
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return Image.file(
          File(snapshot.data!),
          fit: fit,
          alignment: Alignment.topCenter,
          cacheWidth: cacheWidth,
          gaplessPlayback: true,
          errorBuilder:
              (BuildContext context, Object error, StackTrace? stack) {
                final Brightness brightness = Theme.of(context).brightness;
                return Semantics(
                  label: 'Image file missing',
                  child: ColoredBox(
                    color: AppColors.raised(brightness),
                    child: LayoutBuilder(
                      builder:
                          (
                            BuildContext context,
                            BoxConstraints constraints,
                          ) => Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  Icons.image_not_supported_outlined,
                                  color: AppColors.textSecondary(brightness),
                                ),
                                if (constraints.maxWidth >= 160 &&
                                    constraints.maxHeight >= 120) ...<Widget>[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Image file missing',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                    ),
                  ),
                );
              },
        );
      },
    );
  }
}

/// Full-screen, pinch-zoomable image viewer.
class ImageViewerPage extends StatelessWidget {
  const ImageViewerPage({
    super.key,
    required this.relativePath,
    this.title = '',
  });

  final String relativePath;
  final String title;

  static Future<void> open(
    BuildContext context,
    String relativePath, {
    String title = '',
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (BuildContext context) =>
            ImageViewerPage(relativePath: relativePath, title: title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Close image',
          ),
        ],
      ),
      body: InteractiveViewer(
        minScale: 1,
        maxScale: 6,
        child: Center(
          child: LocalImage(relativePath: relativePath, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

/// Compact player used in the detail page. Seeks, shows elapsed and total time,
/// and explains failures without hiding the fact that the original audio exists.
class AudioPlayerBar extends StatelessWidget {
  const AudioPlayerBar({super.key, required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    final AudioPlaybackService playback = Get.find<AudioPlaybackService>();
    final Brightness brightness = Theme.of(context).brightness;

    return Obx(() {
      final bool current = playback.isCurrent(attachment.id);
      final PlayerStatus status = current
          ? playback.status.value
          : PlayerStatus.idle;
      final Duration total = current
          ? playback.duration.value
          : (attachment.duration ?? Duration.zero);
      final Duration position = current
          ? playback.position.value
          : Duration.zero;
      final double progress = total.inMilliseconds > 0
          ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
          : 0.0;
      final bool playing = status == PlayerStatus.playing;

      return Semantics(
        label: 'Voice recording, ${Format.duration(attachment.duration)}',
        child: Container(
          padding: EdgeInsets.all(14.r),
          decoration: BoxDecoration(
            color: AppColors.surface(brightness),
            borderRadius: BorderRadius.circular(22.r),
            border: Border.all(color: AppColors.border(brightness)),
          ),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  _PlayButton(
                    playing: playing,
                    loading: status == PlayerStatus.loading,
                    onPressed: () => playback.toggle(attachment),
                    label: playing ? 'Pause recording' : 'Play recording',
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          status == PlayerStatus.loading
                              ? 'Loading audio…'
                              : '${Format.duration(position)} / ${Format.duration(total)}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          'On-device recording',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 6.h),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                ),
                child: Semantics(
                  slider: true,
                  label: 'Seek in recording',
                  value: '${(progress * 100).round()} percent',
                  child: Slider(
                    value: progress,
                    onChanged: total.inMilliseconds == 0
                        ? null
                        : (double value) {
                            if (!current) {
                              playback.prepare(attachment).then((_) {
                                playback.seek(
                                  Duration(
                                    milliseconds: (total.inMilliseconds * value)
                                        .round(),
                                  ),
                                );
                              });
                            } else {
                              playback.seek(
                                Duration(
                                  milliseconds: (total.inMilliseconds * value)
                                      .round(),
                                ),
                              );
                            }
                          },
                  ),
                ),
              ),
              if (status == PlayerStatus.error)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.volume_off_rounded,
                        size: 16,
                        color: AppColors.dangerFor(brightness),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          playback.errorMessage.value.isEmpty
                              ? 'This recording could not be played on this device.'
                              : playback.errorMessage.value,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.dangerFor(brightness),
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.loading,
    required this.onPressed,
    required this.label,
  });

  final bool playing;
  final bool loading;
  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: AppColors.accent(brightness),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: loading ? null : onPressed,
          child: SizedBox(
            width: 52.r,
            height: 52.r,
            child: loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 26,
                    color: AppColors.onAccent,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Marker used by the detail page when the audio file itself is gone.
class MissingAudioNotice extends StatelessWidget {
  const MissingAudioNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.graphic_eq_rounded,
            size: 18,
            color: AppColors.dangerFor(Theme.of(context).brightness),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'The audio file for this recording is missing.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.dangerFor(Theme.of(context).brightness),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
