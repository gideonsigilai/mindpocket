import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/models/memory.dart';
import '../../../core/services/storage/path_service.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/text_utils.dart';
import '../../../core/widgets/pocket_widgets.dart';
import '../controller/search_page_controller.dart';

class SearchPage extends GetView<SearchPageController> {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final TextEditingController field = TextEditingController(
      text: controller.query.value,
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Get.back(),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
        ),
        titleSpacing: 0,
        title: TextField(
          controller: field,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: controller.setQuery,
          onSubmitted: controller.run,
          style: Theme.of(context).textTheme.titleMedium,
          decoration: InputDecoration(
            hintText: 'Search everything',
            filled: false,
            contentPadding: EdgeInsets.zero,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            suffixIcon: Obx(
              () => controller.query.value.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      onPressed: () {
                        field.clear();
                        controller.clear();
                      },
                      icon: const Icon(Icons.close_rounded, size: 18),
                      tooltip: 'Clear search',
                    ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Obx(() {
          if (controller.query.value.trim().isEmpty) {
            return _SearchHints();
          }
          if (controller.searching.value && controller.results.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (controller.error.value.isNotEmpty) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: ErrorBlock(
                message: controller.error.value,
                onRetry: controller.retry,
              ),
            );
          }
          if (controller.results.isEmpty && controller.hasSearched.value) {
            return _NoResults(
              query: controller.query.value,
              related: controller.related,
              onDismiss: controller.dismiss,
            );
          }
          return ListView(
            padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 32.h),
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    '${controller.results.length} result${controller.results.length == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary(brightness),
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Text, tags, OCR, transcripts',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
              SizedBox(height: 10.h),
              for (final SearchHit hit in controller.results)
                Padding(
                  padding: EdgeInsets.only(bottom: 10.h),
                  child: SearchResultCard(
                    hit: hit,
                    onTap: () => controller.open(hit.memory.id),
                  ),
                ),
              if (controller.related.isNotEmpty) ...<Widget>[
                SizedBox(height: 12.h),
                RelatedStrip(
                  label: controller.relatedReference.value,
                  suggestions: controller.related,
                  onOpen: (RelatedSuggestion s) => controller.open(s.memory.id),
                  onDismiss: controller.dismiss,
                ),
              ],
            ],
          );
        }),
      ),
    );
  }
}

class SearchResultCard extends StatelessWidget {
  const SearchResultCard({super.key, required this.hit, required this.onTap});

  final SearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return PocketCard(
      onTap: onTap,
      padding: EdgeInsets.all(14.r),
      semanticLabel: '${hit.memory.title}. ${hit.snippet}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (hit.memory.thumbnailHint?.isNotEmpty == true)
            ClipRRect(
              borderRadius: BorderRadius.circular(14.r),
              child: SizedBox(
                width: 62.r,
                height: 62.r,
                child: _Thumb(path: hit.memory.thumbnailHint!),
              ),
            )
          else
            Container(
              width: 62.r,
              height: 62.r,
              decoration: BoxDecoration(
                color: AppColors.raised(brightness),
                borderRadius: BorderRadius.circular(14.r),
              ),
              child: Icon(
                hit.memory.hasAudio
                    ? Icons.graphic_eq_rounded
                    : Icons.sticky_note_2_outlined,
                size: 22,
                color: AppColors.textSecondary(brightness),
              ),
            ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _Snippet(
                  text: _titleSpan(hit),
                  maxLines: 1,
                  baseStyle: Theme.of(context).textTheme.titleSmall!,
                  markerSeed: hit.memory.title.trim().isEmpty
                      ? 'Untitled memory'
                      : null,
                ),
                SizedBox(height: 4.h),
                _Snippet(text: _preview(hit)),
                SizedBox(height: 6.h),
                Wrap(
                  spacing: 10,
                  children: <Widget>[
                    MetaLabel(Format.relativeDate(hit.memory.createdAt)),
                    if (hit.memory.audioCount > 0)
                      MetaLabel(
                        Format.duration(hit.memory.audioDuration),
                        icon: Icons.graphic_eq_rounded,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Title with the query's matched terms marked. When FTS only matched the title,
/// the snippet is that title again, so the highlight is taken from there.
String _titleSpan(SearchHit hit) {
  final String title = hit.memory.title.trim();
  final String snippet = hit.snippet;
  final bool snippetIsTitle =
      snippet.replaceAll(RegExp('[⟦⟧]'), '').trim().toLowerCase() ==
      title.toLowerCase();
  if (snippetIsTitle && snippet.contains('⟦')) return snippet;
  return title;
}

/// Prefers a snippet that adds information: when the indexed snippet is just the
/// title again, the note is more useful.
String _preview(SearchHit hit) {
  final String flat = hit.snippet.replaceAll(RegExp('[⟦⟧]'), '').trim();
  if (flat.isEmpty) return hit.memory.note;
  if (flat.toLowerCase() == hit.memory.title.trim().toLowerCase()) {
    return hit.memory.note.isEmpty ? hit.snippet : hit.memory.note;
  }
  return hit.snippet;
}

/// Splits the FTS markers into highlighted spans.
class _Snippet extends StatelessWidget {
  const _Snippet({
    required this.text,
    this.maxLines = 2,
    this.baseStyle,
    this.markerSeed,
  });

  final String text;
  final int maxLines;
  final TextStyle? baseStyle;

  /// Rendered verbatim (never highlighted) when [text] is empty.
  final String? markerSeed;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final TextStyle base = (baseStyle ?? Theme.of(context).textTheme.bodySmall!)
        .copyWith(
          color: baseStyle == null ? AppColors.textSecondary(brightness) : null,
          height: baseStyle == null ? 1.45 : null,
        );
    // The matched terms carry real weight and ink colour, so the reason a result
    // matched is visible rather than implied.
    final TextStyle emphasised = base.copyWith(
      color: AppColors.textPrimary(brightness),
      fontWeight: FontWeight.w700,
    );
    final List<InlineSpan> spans = <InlineSpan>[];
    final RegExp pattern = RegExp(r'([⟦⟧])');
    int start = 0;
    bool highlight = false;
    for (final RegExpMatch match in pattern.allMatches(text)) {
      if (match.start > start) {
        spans.add(
          TextSpan(
            text: text.substring(start, match.start),
            style: highlight ? emphasised : base,
          ),
        );
      }
      highlight = !highlight;
      start = match.end;
    }
    if (start < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(start),
          style: highlight ? emphasised : base,
        ),
      );
    }

    final String flat = text.replaceAll(RegExp('[⟦⟧]'), '');
    if (flat.trim().isEmpty) {
      if (markerSeed == null) return const SizedBox.shrink();
      return Text(
        markerSeed!,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: base,
      );
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: base,
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: Get.find<PathService>().absolute(path),
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        return Image.file(
          File(snapshot.data!),
          fit: BoxFit.cover,
          cacheWidth: 180,
          errorBuilder: (
            BuildContext context,
            Object error,
            StackTrace? stack,
          ) => const SizedBox.shrink(),
        );
      },
    );
  }
}

class _SearchHints extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final List<(IconData, String, String)> hints = <(IconData, String, String)>[
      (
        Icons.image_outlined,
        'Text inside screenshots',
        'OCR output is indexed locally',
      ),
      (Icons.graphic_eq_rounded, 'Transcripts', 'Words spoken in voice notes'),
      (Icons.tag_rounded, 'Tags and titles', 'Your own organisation'),
    ];
    return ListView(
      padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 32.h),
      children: <Widget>[
        Text(
          'Search your pocket',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        SizedBox(height: 6.h),
        Text(
          'Type any word from a title, note, tag, screenshot, or transcript. '
          'Results are ranked with SQLite full-text search on this device.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        SizedBox(height: 20.h),
        for (final (IconData icon, String title, String subtitle) in hints)
          Padding(
            padding: EdgeInsets.only(bottom: 10.h),
            child: Row(
              children: <Widget>[
                Container(
                  width: 40.r,
                  height: 40.r,
                  decoration: BoxDecoration(
                    color: AppColors.raised(brightness),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: AppColors.accentText(brightness),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({
    required this.query,
    required this.related,
    required this.onDismiss,
  });

  final String query;
  final List<RelatedSuggestion> related;
  final Future<void> Function(RelatedSuggestion) onDismiss;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 32.h),
      children: <Widget>[
        EmptyState(
          title: 'No matches for “${query.trim()}”',
          message:
              'Try a shorter word, or check that the content has been processed. '
              'Text extraction and transcription run on this device and can take a moment.',
        ),
        if (related.isNotEmpty)
          RelatedStrip(
            label: query.trim(),
            suggestions: related,
            onOpen: (RelatedSuggestion s) =>
                Get.toNamed(AppRoutes.memory(s.memory.id)),
            onDismiss: onDismiss,
          ),
      ],
    );
  }
}

/// "Possibly related to X" block shared by search and collections.
class RelatedStrip extends StatelessWidget {
  const RelatedStrip({
    super.key,
    required this.label,
    required this.suggestions,
    required this.onOpen,
    required this.onDismiss,
  });

  final String label;
  final List<RelatedSuggestion> suggestions;
  final void Function(RelatedSuggestion) onOpen;
  final Future<void> Function(RelatedSuggestion) onDismiss;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              Icons.auto_awesome_outlined,
              size: 15,
              color: AppColors.accentText(brightness),
            ),
            SizedBox(width: 6.w),
            Expanded(
              child: Text(
                'Possibly related to “${preview(label, maxChars: 40)}”',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.accentText(brightness),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 8.h),
        for (final RelatedSuggestion suggestion in suggestions)
          Padding(
            padding: EdgeInsets.only(bottom: 8.h),
            child: PocketCard(
              onTap: () => onOpen(suggestion),
              padding: EdgeInsets.fromLTRB(14.w, 10.h, 6.w, 10.h),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          suggestion.memory.title.trim().isEmpty
                              ? preview(suggestion.memory.note, maxChars: 50)
                              : suggestion.memory.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          'Shares ${suggestion.sharedTerms.join(', ')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => onDismiss(suggestion),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    tooltip: 'Dismiss suggestion',
                    color: AppColors.textSecondary(brightness),
                  ),
                ],
              ),
            ),
          ),
        Text(
          'Based on shared words in your own content, not a confidence score.',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}
