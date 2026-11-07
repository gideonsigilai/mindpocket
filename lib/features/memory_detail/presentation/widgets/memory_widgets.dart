import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../../app/routes/app_routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/controllers/app_settings_controller.dart';
import '../../../../core/models/attachment.dart';
import '../../../../core/models/enums.dart';
import '../../../../core/models/memory.dart';
import '../../../../core/services/storage/path_service.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/text_utils.dart';
import '../../../../core/widgets/pocket_widgets.dart';
import '../../controller/memory_detail_controller.dart';
import 'media_widgets.dart';

/// Image-first detail with explicit title/note saves and optional extracted text.
class MemoryBody extends StatelessWidget {
  const MemoryBody({super.key, required this.controller, required this.memory});

  final MemoryDetailController controller;
  final Memory memory;

  @override
  Widget build(BuildContext context) {
    final List<Attachment> images = memory.attachments
        .where((Attachment a) => a.isImage)
        .toList(growable: false);
    final List<Attachment> audio = memory.attachments
        .where((Attachment a) => a.isAudio)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (images.isNotEmpty) ...<Widget>[
          _ImageStrip(images: images, title: memory.title),
          SizedBox(height: 16.h),
        ],
        _TitleBlock(controller: controller, memory: memory),
        if (audio.isNotEmpty) ...<Widget>[
          SizedBox(height: 16.h),
          for (final Attachment recording in audio)
            Padding(
              padding: EdgeInsets.only(bottom: 10.h),
              child: AudioPlayerBar(attachment: recording),
            ),
        ],
        SizedBox(height: 16.h),
        _NoteEditor(controller: controller),
        SizedBox(height: 16.h),
        _TagEditor(controller: controller, memory: memory),
        SizedBox(height: 16.h),
        _CollectionsBlock(controller: controller),
        if (memory.extractions.isNotEmpty) ...<Widget>[
          SizedBox(height: 16.h),
          _ExtractionsBlock(controller: controller, memory: memory),
        ],
        _ProcessingBlock(controller: controller),
        SizedBox(height: 16.h),
        _RelatedBlock(controller: controller),
      ],
    );
  }
}

class _TitleBlock extends StatefulWidget {
  const _TitleBlock({required this.controller, required this.memory});

  final MemoryDetailController controller;
  final Memory memory;

  @override
  State<_TitleBlock> createState() => _TitleBlockState();
}

class _TitleBlockState extends State<_TitleBlock> {
  late final TextEditingController _title = TextEditingController(
    text: widget.memory.title,
  );

  @override
  void didUpdateWidget(covariant _TitleBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.controller.dirty.value && _title.text != widget.memory.title) {
      _title.text = widget.memory.title;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _title,
                maxLines: null,
                textInputAction: TextInputAction.done,
                onChanged: widget.controller.editTitle,
                style: Theme.of(context).textTheme.headlineMedium,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Memory title',
                  hintText: 'Untitled memory',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            // The page rebuilds this widget through its own Obx, so reading the
            // stored memory here needs no extra observable scope. An unstarred
            // memory must not show a filled disc, or the state reads as "on".
            IconButton(
              onPressed: widget.controller.toggleFavorite,
              style: widget.memory.favorite
                  ? IconButton.styleFrom(
                      backgroundColor: AppColors.highlight(brightness),
                      foregroundColor: AppColors.onSun,
                    )
                  : IconButton.styleFrom(
                      backgroundColor: AppColors.raised(brightness),
                      foregroundColor: AppColors.textSecondary(brightness),
                    ),
              tooltip: widget.memory.favorite
                  ? 'Remove from starred'
                  : 'Star memory',
              icon: Icon(
                widget.memory.favorite
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
              ),
            ),
          ],
        ),
        SizedBox(height: 6.h),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: <Widget>[
            MetaLabel(
              Format.relativeDate(widget.memory.createdAt),
              icon: Icons.schedule_rounded,
            ),
            if (widget.memory.updatedAt
                    .difference(widget.memory.createdAt)
                    .inMinutes >
                1)
              MetaLabel(
                'Edited ${Format.relativeDate(widget.memory.updatedAt)}',
                icon: Icons.edit_outlined,
              ),
            MetaLabel(switch (widget.memory.kind) {
              MemoryKind.image => 'Image memory',
              MemoryKind.voice => 'Voice memory',
              MemoryKind.shared => 'Shared into MindPocket',
              MemoryKind.note => 'Written note',
            }, icon: Icons.label_outline_rounded),
          ],
        ),
      ],
    );
  }
}

class _ImageStrip extends StatelessWidget {
  const _ImageStrip({required this.images, required this.title});

  final List<Attachment> images;
  final String title;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    // Match the actual page viewport rather than scaling a fixed phone height.
    final double height =
        ((media.size.height - media.padding.vertical - kToolbarHeight) * 0.75)
            .clamp(120.0, 900.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          key: const ValueKey<String>('primary-image-preview'),
          height: height,
          child: _ImagePreview(
            image: images.first,
            title: title,
            label: 'Open image 1 of ${images.length}',
            parallax: true,
          ),
        ),
        if (images.length > 1) ...<Widget>[
          SizedBox(height: 10.h),
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length - 1,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(width: 10),
              itemBuilder: (BuildContext context, int index) => SizedBox(
                width: 96,
                child: _ImagePreview(
                  image: images[index + 1],
                  title: title,
                  label: 'Open image ${index + 2} of ${images.length}',
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({
    required this.image,
    required this.title,
    required this.label,
    this.parallax = false,
  });

  final Attachment image;
  final String title;
  final String label;
  final bool parallax;

  @override
  Widget build(BuildContext context) {
    final ScrollPosition? position = Scrollable.maybeOf(context)?.position;
    final bool reducedByApp =
        Get.isRegistered<AppSettingsController>() &&
        Get.find<AppSettingsController>().reduceMotion.value;
    final bool animate =
        parallax &&
        !reducedByApp &&
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context) &&
        position != null;
    final Widget picture = RepaintBoundary(
      child: LocalImage(
        relativePath: parallax
            ? image.relativePath
            : image.thumbnailRelativePath ?? image.relativePath,
        fit: BoxFit.contain,
        cacheWidth: parallax ? 1440 : 240,
      ),
    );
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: AppColors.raised(Theme.of(context).brightness),
        borderRadius: BorderRadius.circular(22.r),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () =>
              ImageViewerPage.open(context, image.relativePath, title: title),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (animate)
                AnimatedBuilder(
                  animation: position,
                  child: picture,
                  builder: (BuildContext context, Widget? child) =>
                      Transform.translate(
                        offset: Offset(
                          0,
                          (position.pixels * 0.12).clamp(0.0, 32.0),
                        ),
                        child: child,
                      ),
                )
              else
                picture,
              Positioned(
                right: 10,
                bottom: 10,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.open_in_full_rounded, size: 18),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({required this.controller});

  final MemoryDetailController controller;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final TextEditingController _note = TextEditingController(
    text: widget.controller.draftNote.value,
  );

  @override
  void didUpdateWidget(covariant _NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.controller.dirty.value &&
        _note.text != widget.controller.draftNote.value) {
      _note.text = widget.controller.draftNote.value;
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: _note,
          // Grows with the content instead of reserving four blank lines.
          minLines: 1,
          maxLines: 18,
          onChanged: widget.controller.editNote,
          textCapitalization: TextCapitalization.sentences,
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: const InputDecoration(
            labelText: 'Your note',
            hintText: 'Add your own words about this memory',
            alignLabelWithHint: true,
          ),
        ),
        Obx(() {
          if (!widget.controller.dirty.value) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Unsaved changes',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.accentText(Theme.of(context).brightness),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    widget.controller.dirty.value = false;
                    widget.controller
                      ..draftTitle.value =
                          widget.controller.memory.value?.title ?? ''
                      ..draftNote.value =
                          widget.controller.memory.value?.note ?? '';
                    _note.text = widget.controller.draftNote.value;
                  },
                  child: const Text('Revert'),
                ),
                SizedBox(width: 8.w),
                FilledButton(
                  onPressed: widget.controller.busy.value
                      ? null
                      : () async {
                          final bool ok = await widget.controller.saveEdits();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok ? 'Saved' : 'Could not save changes',
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                  child: const Text('Save'),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _TagEditor extends StatelessWidget {
  const _TagEditor({required this.controller, required this.memory});

  final MemoryDetailController controller;
  final Memory memory;

  @override
  Widget build(BuildContext context) {
    return PocketCard(
      padding: EdgeInsets.all(16.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Tags', style: Theme.of(context).textTheme.titleSmall),
          SizedBox(height: 10.h),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              for (final String tag in memory.tags)
                InputChip(
                  label: Text('#$tag'),
                  onDeleted: () => controller.removeTag(tag),
                  deleteButtonTooltipMessage: 'Remove tag $tag',
                  deleteIcon: const Icon(Icons.close_rounded, size: 14),
                ),
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add tag'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (BuildContext context) =>
                      _AddTagDialog(controller: controller),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddTagDialog extends StatefulWidget {
  const _AddTagDialog({required this.controller});

  final MemoryDetailController controller;

  @override
  State<_AddTagDialog> createState() => _AddTagDialogState();
}

class _AddTagDialogState extends State<_AddTagDialog> {
  final TextEditingController _field = TextEditingController();
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.addTags(<String>[
        _field.text.replaceAll('#', '').trim(),
      ]);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'This tag could not be saved. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add tag'),
      scrollable: true,
      content: Form(
        key: _form,
        child: TextFormField(
          controller: _field,
          autofocus: true,
          enabled: !_saving,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _save(),
          decoration: InputDecoration(
            labelText: 'Tag',
            hintText: 'e.g. design',
            errorText: _error,
          ),
          validator: (String? value) {
            final String cleaned = (value ?? '').replaceAll('#', '').trim();
            final List<String> tags =
                widget.controller.memory.value?.tags ?? const <String>[];
            if (cleaned.isEmpty) return 'Enter a tag.';
            if (cleaned.length > 40) return 'Use 40 characters or fewer.';
            if (tags.any(
              (String tag) => tag.toLowerCase() == cleaned.toLowerCase(),
            )) {
              return 'This memory already has that tag.';
            }
            if (tags.length >= 12) return 'Use up to 12 tags per memory.';
            return null;
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Adding…' : 'Add'),
        ),
      ],
    );
  }
}

class _CollectionsBlock extends StatelessWidget {
  const _CollectionsBlock({required this.controller});

  final MemoryDetailController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final List<Collection> collections = controller.allCollections;
      return PocketCard(
        padding: EdgeInsets.all(16.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Collections',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _createCollection(context),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('New'),
                ),
              ],
            ),
            SizedBox(height: 6.h),
            if (collections.isEmpty)
              Text(
                'No collections yet. Create one to group memories by project.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final Collection collection in collections)
                    Obx(
                      () => PocketChip(
                        label: collection.name,
                        selected: controller.selectedCollections.contains(
                          collection.id,
                        ),
                        onTap: () {
                          final Set<String> next = <String>{
                            ...controller.selectedCollections,
                          };
                          if (!next.remove(collection.id)) {
                            next.add(collection.id);
                          }
                          controller.setCollections(next);
                        },
                      ),
                    ),
                ],
              ),
          ],
        ),
      );
    });
  }

  Future<void> _createCollection(BuildContext context) async {
    final TextEditingController field = TextEditingController();
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('New collection'),
        content: TextField(
          controller: field,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. Reading list'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(field.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final Collection? created = await controller.createCollection(name);
    if (created != null) {
      await controller.setCollections(<String>{
        ...controller.selectedCollections,
        created.id,
      });
    }
  }
}

class _ExtractionsBlock extends StatefulWidget {
  const _ExtractionsBlock({required this.controller, required this.memory});

  final MemoryDetailController controller;
  final Memory memory;

  @override
  State<_ExtractionsBlock> createState() => _ExtractionsBlockState();
}

class _ExtractionsBlockState extends State<_ExtractionsBlock> {
  bool _showImageText = false;

  @override
  Widget build(BuildContext context) {
    final List<ExtractionRecord> ocr = widget.memory.extractions
        .where((ExtractionRecord e) => e.kind == 'ocr')
        .toList(growable: false);
    final List<ExtractionRecord> transcripts = widget.memory.extractions
        .where((ExtractionRecord e) => e.kind == 'transcript')
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (ocr.isNotEmpty)
          PocketCard(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              title: Text(
                'Text from image',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              shape: const Border(),
              collapsedShape: const Border(),
              onExpansionChanged: (bool expanded) =>
                  setState(() => _showImageText = expanded),
              childrenPadding: EdgeInsets.fromLTRB(16.r, 0, 16.r, 16.r),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (_showImageText) ...<Widget>[
                  Text(
                    'Extracted on this device.',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  SizedBox(height: 10.h),
                  for (final ExtractionRecord record in ocr)
                    _ExtractionEditor(
                      key: ValueKey<String>(record.id),
                      record: record,
                      controller: widget.controller,
                    ),
                  if (ocr.every(
                    (ExtractionRecord record) =>
                        record.effectiveText.trim().isEmpty,
                  ))
                    Text(
                      'No readable text was found in this image.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ],
            ),
          ),
        if (ocr.isNotEmpty && transcripts.isNotEmpty) SizedBox(height: 12.h),
        if (transcripts.isNotEmpty)
          _ExtractionCard(
            title: 'Transcript',
            subtitle: 'Produced offline from the original recording. Your edits are kept separately.',
            records: transcripts,
            controller: widget.controller,
            emptyCopy: 'No speech was recognised in this recording.',
          ),
      ],
    );
  }
}

class _ExtractionCard extends StatelessWidget {
  const _ExtractionCard({
    required this.title,
    required this.subtitle,
    required this.records,
    required this.controller,
    required this.emptyCopy,
  });

  final String title;
  final String subtitle;
  final List<ExtractionRecord> records;
  final MemoryDetailController controller;
  final String emptyCopy;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return PocketCard(
      padding: EdgeInsets.all(16.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (records.any((ExtractionRecord r) => r.isEdited))
                StatusBadge(
                  label: 'Edited',
                  color: AppColors.accentText(brightness),
                  icon: Icons.edit_outlined,
                ),
            ],
          ),
          SizedBox(height: 4.h),
          Text(subtitle, style: Theme.of(context).textTheme.labelSmall),
          SizedBox(height: 10.h),
          for (final ExtractionRecord record in records)
            _ExtractionEditor(record: record, controller: controller),

          if (records.every(
            (ExtractionRecord r) => r.effectiveText.trim().isEmpty,
          ))
            Text(emptyCopy, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ExtractionEditor extends StatefulWidget {
  const _ExtractionEditor({
    super.key,
    required this.record,
    required this.controller,
  });

  final ExtractionRecord record;
  final MemoryDetailController controller;

  @override
  State<_ExtractionEditor> createState() => _ExtractionEditorState();
}

class _ExtractionEditorState extends State<_ExtractionEditor> {
  late final TextEditingController _field = TextEditingController(
    text: widget.record.effectiveText,
  );
  bool _editing = false;

  @override
  void didUpdateWidget(covariant _ExtractionEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && _field.text != widget.record.effectiveText) {
      _field.text = widget.record.effectiveText;
    }
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (!_editing)
          SelectableText(
            widget.record.effectiveText.isEmpty
                ? '—'
                : widget.record.effectiveText,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(height: 1.55),
          )
        else
          TextField(
            controller: _field,
            minLines: 2,
            maxLines: 20,
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: const InputDecoration(hintText: 'Correct the text'),
          ),
        SizedBox(height: 8.h),
        // Action groups wrap independently at narrow widths and large text.
        Wrap(
          spacing: 8.w,
          runSpacing: 4.h,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: <Widget>[
            MetaLabel(widget.record.engine, icon: Icons.memory_rounded),
            Wrap(
              spacing: 6.w,
              runSpacing: 4.h,
              children: <Widget>[
                if (!_editing)
                  TextButton(
                    onPressed: () => setState(() {
                      _field.text = widget.record.effectiveText;
                      _editing = true;
                    }),
                    child: const Text('Edit'),
                  )
                else ...<Widget>[
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _editing = false;
                        _field.text = widget.record.effectiveText;
                      });
                    },
                    child: const Text('Cancel'),
                  ),
                  if (widget.record.isEdited)
                    TextButton(
                      onPressed: () async {
                        await widget.controller.revertTranscriptionEdit(
                          widget.record.id,
                        );
                        if (mounted) setState(() => _editing = false);
                      },
                      child: const Text('Use original'),
                    ),
                  FilledButton(
                    onPressed: () async {
                      await widget.controller.saveTranscriptionEdit(
                        widget.record.id,
                        _field.text,
                      );
                      if (mounted) setState(() => _editing = false);
                    },
                    child: const Text('Save'),
                  ),
                ],
              ],
            ),
          ],
        ),
        Divider(height: 20.h, color: AppColors.border(brightness)),
      ],
    );
  }
}

class _ProcessingBlock extends StatelessWidget {
  const _ProcessingBlock({required this.controller});

  final MemoryDetailController controller;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return Obx(() {
      final List<ProcessingJob> jobs = controller.jobs
          .where(
            (ProcessingJob job) =>
                job.status.isActive || job.status == JobStatus.failed,
          )
          .toList(growable: false);
      if (jobs.isEmpty) return const SizedBox.shrink();
      final bool anyFailed = jobs.any(
        (ProcessingJob job) => job.status == JobStatus.failed,
      );
      return Padding(
        padding: EdgeInsets.only(top: 16.h),
        child: PocketCard(
          padding: EdgeInsets.all(16.r),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Processing',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (anyFailed)
                    TextButton.icon(
                      onPressed: controller.retryAllFailed,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Retry failed'),
                    ),
                ],
              ),
              SizedBox(height: 6.h),
              for (final ProcessingJob job in jobs)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        switch (job.status) {
                          JobStatus.completed =>
                            Icons.check_circle_outline_rounded,
                          JobStatus.running => Icons.autorenew_rounded,
                          JobStatus.queued => Icons.schedule_rounded,
                          JobStatus.failed => Icons.error_outline_rounded,
                          JobStatus.canceled =>
                            Icons.remove_circle_outline_rounded,
                        },
                        size: 16,
                        color: switch (job.status) {
                          JobStatus.completed => AppColors.success,
                          JobStatus.failed => AppColors.dangerFor(brightness),
                          _ => AppColors.textSecondary(brightness),
                        },
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Text(
                          '${job.type.label} · ${job.status.name}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      if (job.status.isActive)
                        TextButton(
                          onPressed: () => controller.cancelJob(job),
                          child: const Text('Cancel'),
                        )
                      else if (job.status == JobStatus.failed)
                        TextButton(
                          onPressed: () => controller.retry(
                            job.type,
                            attachmentId: job.attachmentId,
                          ),
                          child: const Text('Retry'),
                        ),
                    ],
                  ),
                ),
              if (anyFailed)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    jobs
                            .where(
                              (ProcessingJob job) =>
                                  job.status == JobStatus.failed,
                            )
                            .first
                            .error ??
                        'Processing failed. The original capture is untouched.',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: AppColors.dangerFor(brightness)),
                  ),
                ),
              // The queue parks transcription when no speech model is installed
              // or transcription is disabled. Say so, with the way to fix it:
              // an unexplained "queued" row looks like a stuck app.
              if (!anyFailed &&
                  !controller.transcriptionPossible &&
                  jobs.any(
                    (ProcessingJob job) =>
                        job.type == JobType.transcription &&
                        job.status == JobStatus.queued,
                  ))
                Padding(
                  padding: EdgeInsets.only(top: 6.h),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          controller.transcriptionEnabled
                              ? 'Transcription needs a speech model. Install one '
                                    'to finish this recording.'
                              : 'Automatic transcription is off. Enable it in '
                                    'Settings to finish this recording.',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                      TextButton(
                        onPressed: controller.transcriptionEnabled
                            ? controller.openModels
                            : () => Get.toNamed(AppRoutes.settings),
                        child: Text(
                          controller.transcriptionEnabled
                              ? 'Install'
                              : 'Settings',
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

class _RelatedBlock extends StatelessWidget {
  const _RelatedBlock({required this.controller});

  final MemoryDetailController controller;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return Obx(() {
      final List<RelatedSuggestion> related = controller.related;
      if (related.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.auto_awesome_outlined,
                size: 16,
                color: AppColors.accentText(brightness),
              ),
              SizedBox(width: 6.w),
              Expanded(
                child: Text(
                  'Possibly related to ${controller.relatedLabel.value}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.accentText(brightness),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          for (final RelatedSuggestion suggestion in related)
            Padding(
              padding: EdgeInsets.only(bottom: 8.h),
              child: _RelatedMemoryCard(
                controller: controller,
                suggestion: suggestion,
              ),
            ),
          Text(
            'At least 90% matching text, ignoring case, spacing, and punctuation. Images themselves are not compared.',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      );
    });
  }
}

class _RelatedMemoryCard extends StatelessWidget {
  const _RelatedMemoryCard({
    required this.controller,
    required this.suggestion,
  });

  final MemoryDetailController controller;
  final RelatedSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final Memory memory = suggestion.memory;
    final String? thumbnail =
        memory.primaryThumbnailPath ?? memory.thumbnailHint;
    final String note = preview(memory.note, maxChars: 60);
    final String title = memory.title.trim().isNotEmpty
        ? memory.title
        : note.isNotEmpty
        ? note
        : '${memory.hasImages ? 'Image' : 'Untitled'} memory · '
              '${Format.relativeDate(memory.createdAt)}';
    return PocketCard(
      padding: EdgeInsets.fromLTRB(10.w, 10.h, 4.w, 10.h),
      onTap: () => Get.toNamed(AppRoutes.memory(memory.id)),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 64,
              height: 80,
              child: thumbnail != null && thumbnail.isNotEmpty
                  ? LocalImage(relativePath: thumbnail, cacheWidth: 240)
                  : ColoredBox(
                      color: AppColors.raised(Theme.of(context).brightness),
                      child: Icon(
                        memory.hasAudio
                            ? Icons.graphic_eq_rounded
                            : Icons.notes_rounded,
                      ),
                    ),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                SizedBox(height: 4.h),
                Text(
                  '${(suggestion.score * 100).round()}% text match',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => controller.dismissRelated(suggestion),
            tooltip: 'Dismiss suggestion: $title',
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

/// Shared pill showing whether a file exists, used by attachment headers.
class FilePresence extends StatelessWidget {
  const FilePresence({super.key, required this.relativePath});

  final String relativePath;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: Get.find<PathService>().exists(relativePath),
      builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
        if (snapshot.data != false) return const SizedBox.shrink();
        return const MissingAudioNotice();
      },
    );
  }
}

/// Utility used by screens that need a file handle without awaiting in build.
Future<File> resolveFile(String relativePath) =>
    Get.find<PathService>().file(relativePath);
