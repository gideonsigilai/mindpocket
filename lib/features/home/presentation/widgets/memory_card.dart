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

/// Image-first grid tile. Only the affected card rebuilds when a memory changes.
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
      padding: EdgeInsets.all(12.r),
      semanticLabel: _semantics,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: _Thumbnail(memory: memory)),
          SizedBox(height: 10.r),
          Text(
            memory.title.trim().isEmpty ? 'Untitled memory' : memory.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.titleMedium,
          ),
          if (subtitle.isNotEmpty) ...<Widget>[
            SizedBox(height: 4.r),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall,
            ),
          ],
          SizedBox(height: 8.r),
          if (memory.hasAudio ||
              memory.imageCount > 1 ||
              memory.tags.isNotEmpty)
            MetaLabel(
              <String>[
                if (memory.hasAudio) Format.duration(memory.audioDuration),
                if (memory.imageCount > 1) '${memory.imageCount} images',
                ...memory.tags.take(2).map((String tag) => '#$tag'),
              ].join(' · '),
            ),
          _StatusPill(memory: memory),
          Row(
            children: <Widget>[
              Expanded(child: MetaLabel(Format.relativeDate(memory.createdAt))),
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
              if (onDelete != null ||
                  (memory.processing == MemoryProcessing.failed &&
                      onRetry != null))
                PopupMenuButton<VoidCallback>(
                  tooltip: 'Memory actions',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 160),
                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                  onSelected: (VoidCallback action) => action(),
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<VoidCallback>>[
                        if (memory.processing == MemoryProcessing.failed &&
                            onRetry != null)
                          PopupMenuItem<VoidCallback>(
                            value: onRetry,
                            child: const Text('Retry failed processing'),
                          ),
                        if (onDelete != null)
                          PopupMenuItem<VoidCallback>(
                            value: onDelete,
                            child: const Text('Delete this memory'),
                          ),
                      ],
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
    final String? relative =
        memory.primaryThumbnailPath ?? memory.thumbnailHint;
    final bool hasImage = memory.hasImages && (relative?.isNotEmpty ?? false);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) => ClipRRect(
        borderRadius: BorderRadius.circular(18.r),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: AppColors.raised(brightness),
          child: hasImage
              ? _LocalImage(
                  relativePath: relative!,
                  cacheWidth:
                      (constraints.maxWidth *
                              MediaQuery.devicePixelRatioOf(context))
                          .round(),
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
      MemoryProcessing.failed => Tooltip(
        message: memory.jobError ?? 'Processing failed',
        child: StatusBadge(
          label: 'Failed',
          color: AppColors.dangerFor(brightness),
          icon: Icons.error_outline_rounded,
        ),
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
