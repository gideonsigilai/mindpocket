import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/models/memory.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/text_utils.dart';
import '../../../../core/widgets/pocket_widgets.dart';
import '../../../../core/services/storage/path_service.dart';

/// Timeline row. Kept as a small widget so only the affected card rebuilds when
/// a single memory changes.
class MemoryCard extends StatelessWidget {
  const MemoryCard({
    super.key,
    required this.memory,
    required this.onTap,
    required this.onFavorite,
    this.onDelete,
    this.onRetry,
  });

  final Memory memory;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final VoidCallback? onDelete;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final TextTheme text = Theme.of(context).textTheme;
    final String subtitle = preview(
      memory.note.isNotEmpty
          ? memory.note
          : (memory.ocrText.isNotEmpty
                ? memory.ocrText
                : (memory.transcriptText.isNotEmpty
                      ? memory.transcriptText
                      : '')),
      maxChars: 120,
    );

    return PocketCard(
      onTap: onTap,
      padding: EdgeInsets.all(14.r),
      semanticLabel: _semantics,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Thumbnail(memory: memory),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  memory.title.trim().isEmpty
                      ? 'Untitled memory'
                      : memory.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium,
                ),
                if (subtitle.isNotEmpty) ...<Widget>[
                  SizedBox(height: 4.h),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall,
                  ),
                ],
                SizedBox(height: 10.h),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    MetaLabel(
                      Format.relativeDate(memory.createdAt),
                      icon: Icons.schedule_rounded,
                    ),
                    if (memory.audioCount > 0)
                      MetaLabel(
                        Format.duration(memory.audioDuration),
                        icon: Icons.graphic_eq_rounded,
                      ),
                    if (memory.imageCount > 1)
                      MetaLabel(
                        '${memory.imageCount} images',
                        icon: Icons.photo_library_outlined,
                      ),
                    if (memory.tags.isNotEmpty)
                      MetaLabel(
                        memory.tags.take(2).map((String t) => '#$t').join(' '),
                        icon: Icons.tag_rounded,
                      ),
                    _StatusPill(memory: memory),
                  ],
                ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _IconAction(
                icon: memory.favorite
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                label: memory.favorite
                    ? 'Remove from starred'
                    : 'Star this memory',
                color: memory.favorite
                    ? AppColors.highlight(brightness)
                    : AppColors.textSecondary(brightness),
                onPressed: onFavorite,
              ),
              if (memory.processing == MemoryProcessing.failed &&
                  onRetry != null)
                _IconAction(
                  icon: Icons.refresh_rounded,
                  label: 'Retry failed processing',
                  color: AppColors.dangerFor(brightness),
                  onPressed: onRetry!,
                ),
              if (onDelete != null)
                _IconAction(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete this memory',
                  color: AppColors.textSecondary(brightness),
                  onPressed: onDelete!,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String get _semantics {
    final StringBuffer buffer = StringBuffer()
      ..write(memory.title.trim().isEmpty ? 'Untitled memory' : memory.title);
    if (memory.favorite) buffer.write(', starred');
    if (memory.audioCount > 0) {
      buffer.write(', voice note ${Format.duration(memory.audioDuration)}');
    }
    if (memory.imageCount > 0) {
      buffer.write(
        ', ${memory.imageCount} image${memory.imageCount == 1 ? '' : 's'}',
      );
    }
    buffer.write(', ${Format.relativeDate(memory.createdAt)}');
    if (memory.processing == MemoryProcessing.failed) {
      buffer.write(', processing failed');
    }
    return buffer.toString();
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.memory});

  final Memory memory;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final double size = 82.r;
    final String? relative =
        memory.primaryThumbnailPath ?? memory.thumbnailHint;
    final bool hasImage = memory.hasImages && (relative?.isNotEmpty ?? false);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18.r),
      child: Container(
        width: size,
        height: size,
        color: AppColors.raised(brightness),
        child: hasImage
            ? _LocalImage(
                relativePath: relative!,
                cacheWidth: (size * 2.4).round(),
              )
            : Center(
                child: Icon(
                  memory.hasAudio
                      ? Icons.graphic_eq_rounded
                      : Icons.sticky_note_2_outlined,
                  size: 26,
                  color: AppColors.textSecondary(brightness),
                ),
              ),
      ),
    );
  }
}

/// Decodes at display size to keep memory flat when scrolling a long timeline.
class _LocalImage extends StatelessWidget {
  const _LocalImage({required this.relativePath, required this.cacheWidth});

  final String relativePath;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: Get.find<PathService>().absolute(relativePath),
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        final String? path = snapshot.data;
        if (path == null) return const SizedBox.shrink();
        return Image.file(
          File(path),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          cacheWidth: cacheWidth,
          gaplessPlayback: true,
          errorBuilder:
              (BuildContext context, Object error, StackTrace? stack) =>
                  ColoredBox(
                    color: AppColors.raised(Theme.of(context).brightness),
                    child: Icon(
                      Icons.broken_image_outlined,
                      size: 20,
                      color: AppColors.textSecondary(
                        Theme.of(context).brightness,
                      ),
                    ),
                  ),
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.memory});

  final Memory memory;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return switch (memory.processing) {
      MemoryProcessing.running => StatusBadge(
        label: 'Working',
        color: AppColors.accentText(brightness),
        showSpinner: true,
      ),
      MemoryProcessing.queued => StatusBadge(
        label: 'Queued',
        color: AppColors.textSecondary(brightness),
        icon: Icons.hourglass_empty_rounded,
      ),
      MemoryProcessing.failed => StatusBadge(
        label: memory.jobError ?? 'Failed',
        color: AppColors.dangerFor(brightness),
        icon: Icons.error_outline_rounded,
      ),
      MemoryProcessing.none || MemoryProcessing.done => const SizedBox.shrink(),
    };
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        color: color,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
        tooltip: label,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
