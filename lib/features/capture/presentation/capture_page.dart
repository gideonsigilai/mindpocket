import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/services/processing/audio_recording_service.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/collage_art.dart';
import '../controller/capture_controller.dart';

/// Capture screen. `mode` comes from the capture sheet; each mode shows only its
/// own controls, all of which act immediately.
class CapturePage extends GetView<CaptureController> {
  const CapturePage({super.key});

  String get _mode =>
      (Get.arguments as Map<String, Object?>?)?['mode'] as String? ?? 'note';

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        final bool leave = await controller.confirmDiscard();
        if (leave && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: () async {
              final bool leave = await controller.confirmDiscard();
              if (leave) Get.back();
            },
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Close capture',
          ),
          title: Text(switch (_mode) {
            'voice' => 'Voice note',
            'image' => 'Screenshot',
            _ => 'New note',
          }),
        ),
        // The composer's primary action lives in a footer so it stays visible
        // above the keyboard instead of scrolling out of reach.
        body: SafeArea(
          child: Column(
            children: <Widget>[
              Expanded(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final bool wide = constraints.maxWidth >= 760;
                    return SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        wide ? 40.w : 20.w,
                        8.h,
                        wide ? 40.w : 20.w,
                        20.h,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 620),
                          child: switch (_mode) {
                            'voice' => _VoiceCapture(controller: controller),
                            'image' => _ImageCapture(controller: controller),
                            _ => _NoteCapture(controller: controller),
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_mode == 'note') _SaveFooter(controller: controller),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteCapture extends StatefulWidget {
  const _NoteCapture({required this.controller});

  final CaptureController controller;

  @override
  State<_NoteCapture> createState() => _NoteCaptureState();
}

class _NoteCaptureState extends State<_NoteCapture> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  final TextEditingController _tag = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _tag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'WRITTEN NOTE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 1.6,
            color: AppColors.accentText(brightness),
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 10.h),
        TextField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          onChanged: (String value) => widget.controller.title.value = value,
          style: Theme.of(context).textTheme.titleLarge,
          decoration: const InputDecoration(hintText: 'Title'),
        ),
        SizedBox(height: 12.h),
        TextField(
          controller: _body,
          minLines: 7,
          maxLines: 20,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (String value) => widget.controller.note.value = value,
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: const InputDecoration(
            hintText: 'What do you want to remember?',
            alignLabelWithHint: true,
          ),
        ),
        SizedBox(height: 16.h),
        _TagField(controller: widget.controller, field: _tag),
        _ErrorText(controller: widget.controller),
      ],
    );
  }
}

/// Persistent footer for the note composer: always reachable, keyboard or not.
class _SaveFooter extends StatelessWidget {
  const _SaveFooter({required this.controller});

  final CaptureController controller;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return Container(
      padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 12.h),
      decoration: BoxDecoration(
        color: AppColors.background(brightness),
        border: Border(top: BorderSide(color: AppColors.border(brightness))),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Obx(
            () => SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: controller.saving.value ? null : controller.saveNote,
                icon: controller.saving.value
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(
                  controller.saving.value ? 'Saving…' : 'Save to pocket',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TagField extends StatelessWidget {
  const _TagField({required this.controller, required this.field});

  final CaptureController controller;
  final TextEditingController field;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: field,
          textInputAction: TextInputAction.done,
          onSubmitted: (String value) {
            controller.addTag(value);
            field.clear();
          },
          decoration: InputDecoration(
            hintText: 'Add a tag and press enter',
            prefixIcon: const Icon(Icons.tag_rounded, size: 18),
            suffixIcon: IconButton(
              tooltip: 'Add tag',
              icon: const Icon(Icons.add_rounded, size: 18),
              onPressed: () {
                controller.addTag(field.text);
                field.clear();
              },
            ),
          ),
        ),
        Obx(
          () => controller.tags.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final String tag in controller.tags)
                        InputChip(
                          label: Text(tag),
                          onDeleted: () => controller.removeTag(tag),
                          deleteIcon: const Icon(Icons.close_rounded, size: 14),
                          deleteButtonTooltipMessage: 'Remove tag $tag',
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _ImageCapture extends StatelessWidget {
  const _ImageCapture({required this.controller});

  final CaptureController controller;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'SCREENSHOT OR IMAGE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 1.6,
            color: AppColors.accentText(brightness),
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 10.h),
        Text(
          'Importing copies the original into MindPocket first. Text extraction runs '
          'afterwards on this device, so a failed extraction never costs you the image.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        SizedBox(height: 18.h),
        ClipRRect(
          borderRadius: BorderRadius.circular(28.r),
          child: Container(
            height: 240.h,
            color: AppColors.raised(brightness),
            child: const CollageArt(
              variant: CollageVariant.capture,
              height: 240,
            ),
          ),
        ),
        SizedBox(height: 20.h),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: controller.pickImages,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Choose image'),
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          'You can also share screenshots into MindPocket from any app.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        _ErrorText(controller: controller),
      ],
    );
  }
}

class _VoiceCapture extends StatelessWidget {
  const _VoiceCapture({required this.controller});

  final CaptureController controller;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'VOICE NOTE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 1.6,
            color: AppColors.accentText(brightness),
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 10.h),
        Obx(() {
          final RecorderStatus status = controller.recorderStatus.value;
          final bool active =
              status == RecorderStatus.recording ||
              status == RecorderStatus.paused;
          return Column(
            children: <Widget>[
              SizedBox(height: 12.h),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: 26.h),
                decoration: BoxDecoration(
                  color: AppColors.surface(brightness),
                  borderRadius: BorderRadius.circular(28.r),
                  border: Border.all(color: AppColors.border(brightness)),
                ),
                child: Column(
                  children: <Widget>[
                    _Waveform(
                      amplitude: controller.recorderAmplitude,
                      active: active,
                    ),
                    SizedBox(height: 18.h),
                    Text(
                      Format.duration(controller.recorderElapsed.value),
                      style: Theme.of(context).textTheme.displayMedium
                          ?.copyWith(
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                    ),
                    SizedBox(height: 6.h),
                    Text(switch (status) {
                      RecorderStatus.recording => 'Recording',
                      RecorderStatus.paused => 'Paused',
                      RecorderStatus.stopping => 'Finishing…',
                      RecorderStatus.failed => 'Microphone unavailable',
                      RecorderStatus.idle => 'Ready when you are',
                    }, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              SizedBox(height: 18.h),
              if (status == RecorderStatus.idle ||
                  status == RecorderStatus.failed)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: controller.startRecording,
                    icon: const Icon(Icons.mic_rounded),
                    label: const Text('Start recording'),
                  ),
                )
              else
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: controller.cancelRecording,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Discard'),
                      ),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: status == RecorderStatus.recording
                            ? controller.pauseRecording
                            : controller.resumeRecording,
                        icon: Icon(
                          status == RecorderStatus.recording
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                        label: Text(
                          status == RecorderStatus.recording
                              ? 'Pause'
                              : 'Resume',
                        ),
                      ),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: controller.finishRecording,
                        icon: const Icon(Icons.stop_rounded),
                        label: const Text('Stop'),
                      ),
                    ),
                  ],
                ),
              SizedBox(height: 14.h),
              Text(
                'Audio is saved first. Transcription needs a downloaded speech model and '
                'runs offline; without one, the recording remains playable.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              _ErrorText(controller: controller),
            ],
          );
        }),
      ],
    );
  }
}

class _Waveform extends StatelessWidget {
  const _Waveform({required this.amplitude, required this.active});

  final RxDouble amplitude;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return Obx(() {
      // Always read the observable: an idle waveform still has to register a
      // dependency, or GetX rejects the builder as having nothing to update.
      final double raw = amplitude.value.clamp(0.0, 1.0);
      final double level = active ? raw : 0.12;
      return SizedBox(
        height: 54.h,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List<Widget>.generate(24, (int index) {
            final double wave = (0.35 + ((index * 7) % 11) / 18).clamp(
              0.2,
              1.0,
            );
            final double height = (10 + (30 * wave * (0.35 + level))).h;
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: 2.5.w),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 4.w,
                height: height.clamp(6.0, 48.h),
                decoration: BoxDecoration(
                  color: index.isEven
                      ? AppColors.accentText(brightness)
                      : AppColors.accent(brightness).withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            );
          }),
        ),
      );
    });
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.controller});

  final CaptureController controller;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return Obx(() {
      final String message = controller.error.value;
      if (message.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.error_outline_rounded,
              size: 18,
              color: AppColors.dangerFor(brightness),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AppColors.dangerFor(brightness)),
              ),
            ),
          ],
        ),
      );
    });
  }
}
