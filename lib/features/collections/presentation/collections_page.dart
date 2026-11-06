import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/models/attachment.dart';
import '../../../core/models/memory.dart';
import '../../../core/utils/text_utils.dart';
import '../../../core/widgets/collage_art.dart';
import '../../../core/widgets/pocket_widgets.dart';
import '../controller/collections_controller.dart';

class CollectionsPage extends GetView<CollectionsController> {
  const CollectionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.accentText(brightness),
          onRefresh: controller.refresh,
          child: Obx(() {
            if (controller.loading.value && controller.collections.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 32.h),
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'COLLECTIONS',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  letterSpacing: 2,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.accentText(brightness),
                                ),
                          ),
                          SizedBox(height: 6.h),
                          Text(
                            'Projects and piles',
                            style: Theme.of(context).textTheme.displaySmall,
                          ),
                          SizedBox(height: 6.h),
                          Text(
                            'Screenshots are sorted here by their text. '
                            'You can also file anything by hand.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: () => _createCollection(context),
                      tooltip: 'New collection',
                      icon: const Icon(Icons.add_rounded, size: 20),
                    ),
                  ],
                ),
                SizedBox(height: 18.h),
                if (controller.error.value.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(bottom: 12.h),
                    child: ErrorBlock(
                      message: controller.error.value,
                      onRetry: controller.refresh,
                    ),
                  ),
                if (controller.collections.isEmpty)
                  EmptyState(
                    title: 'No collections yet',
                    message:
                        'Keep related memories together — “Travel plans”, “Reading list”, “Ideas”. '
                        'Create one and add memories from their detail screen.',
                    illustration: SizedBox(
                      height: 140.h,
                      child: const CollageArt(
                        variant: CollageVariant.collections,
                        height: 140,
                        showGrain: false,
                      ),
                    ),
                    actionLabel: 'New collection',
                    onAction: () => _createCollection(context),
                  )
                else
                  for (final Collection collection in controller.collections)
                    Padding(
                      padding: EdgeInsets.only(bottom: 10.h),
                      child: _CollectionCard(
                        collection: collection,
                        onTap: () => controller.open(collection),
                        onEdit: () => _editCollection(context, collection),
                        onDelete: () => _deleteCollection(context, collection),
                      ),
                    ),
                if (controller.tags.isNotEmpty) ...<Widget>[
                  SizedBox(height: 12.h),
                  Text(
                    'Pick a tag',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  SizedBox(height: 10.h),
                  Obx(
                    () => Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final TagCount tag in controller.tags)
                          PocketChip(
                            label: '#${tag.name}',
                            count: tag.count,
                            selected: controller.selectedTag.value == tag.name,
                            onTap: () => controller.selectTag(tag.name),
                          ),
                      ],
                    ),
                  ),
                  Obx(() {
                    if (controller.selectedTag.value.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    if (controller.tagResults.isEmpty) {
                      return Padding(
                        padding: EdgeInsets.only(top: 12.h),
                        child: Text(
                          'No memories carry this tag any more.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(height: 14.h),
                        Text(
                          'Tagged #${controller.selectedTag.value}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        SizedBox(height: 8.h),
                        for (final Memory memory in controller.tagResults)
                          Padding(
                            padding: EdgeInsets.only(bottom: 8.h),
                            child: _MemoryRow(
                              memory: memory,
                              onTap: () => controller.openMemory(memory.id),
                            ),
                          ),
                      ],
                    );
                  }),
                ],
              ],
            );
          }),
        ),
      ),
    );
  }

  Future<void> _createCollection(BuildContext context) async {
    final (String, String)? result = await showDialog<(String, String)>(
      context: context,
      builder: (BuildContext context) => const _CollectionDialog(),
    );
    if (result == null) return;
    await controller.create(result.$1, description: result.$2);
  }

  Future<void> _editCollection(
    BuildContext context,
    Collection collection,
  ) async {
    final (String, String)? result = await showDialog<(String, String)>(
      context: context,
      builder: (BuildContext context) =>
          _CollectionDialog(collection: collection),
    );
    if (result == null) return;
    await controller.rename(collection, result.$1, result.$2);
  }

  Future<void> _deleteCollection(
    BuildContext context,
    Collection collection,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Delete “${collection.name}”?'),
        content: const Text(
          'The collection is removed. Its memories stay in your pocket.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.remove(collection);
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({
    required this.collection,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final Collection collection;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return PocketCard(
      onTap: onTap,
      padding: EdgeInsets.all(16.r),
      semanticLabel: '${collection.name}, ${collection.memoryCount} memories',
      child: Row(
        children: <Widget>[
          Container(
            width: 46.r,
            height: 46.r,
            decoration: BoxDecoration(
              color: AppColors.accent(brightness).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14.r),
            ),
            child: Icon(
              Icons.folder_outlined,
              size: 20,
              color: AppColors.accentText(brightness),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  collection.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                SizedBox(height: 2.h),
                Text(
                  collection.description.isEmpty
                      ? '${collection.memoryCount} memor${collection.memoryCount == 1 ? 'y' : 'ies'}'
                      : '${collection.memoryCount} · ${preview(collection.description, maxChars: 60)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Collection options',
            onSelected: (String value) {
              if (value == 'edit') onEdit();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (BuildContext context) =>
                const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'edit',
                    child: Text('Rename or describe'),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Text('Delete collection'),
                  ),
                ],
          ),
        ],
      ),
    );
  }
}

class _CollectionDialog extends StatefulWidget {
  const _CollectionDialog({this.collection});

  final Collection? collection;

  @override
  State<_CollectionDialog> createState() => _CollectionDialogState();
}

class _CollectionDialogState extends State<_CollectionDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.collection?.name ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.collection?.description ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool editing = widget.collection != null;
    return AlertDialog(
      title: Text(editing ? 'Edit collection' : 'New collection'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Name, e.g. Travel plans',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Description (optional)',
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop((_name.text, _description.text)),
          child: Text(editing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}

class _MemoryRow extends StatelessWidget {
  const _MemoryRow({required this.memory, required this.onTap});

  final Memory memory;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return PocketCard(
      onTap: onTap,
      padding: EdgeInsets.all(12.r),
      child: Row(
        children: <Widget>[
          Icon(
            memory.hasImages
                ? Icons.image_outlined
                : (memory.hasAudio
                      ? Icons.graphic_eq_rounded
                      : Icons.sticky_note_2_outlined),
            size: 18,
            color: AppColors.textSecondary(brightness),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              memory.title.trim().isEmpty
                  ? preview(memory.note, maxChars: 60)
                  : memory.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: AppColors.textSecondary(brightness),
          ),
        ],
      ),
    );
  }
}

/// Shared row used by collection detail.
class MemoryListRow extends StatelessWidget {
  const MemoryListRow({
    super.key,
    required this.memory,
    required this.onTap,
    this.trailing,
  });

  final Memory memory;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return PocketCard(
      onTap: onTap,
      padding: EdgeInsets.all(12.r),
      child: Row(
        children: <Widget>[
          Container(
            width: 42.r,
            height: 42.r,
            decoration: BoxDecoration(
              color: AppColors.raised(brightness),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(
              memory.hasImages
                  ? Icons.image_outlined
                  : (memory.hasAudio
                        ? Icons.graphic_eq_rounded
                        : Icons.sticky_note_2_outlined),
              size: 18,
              color: AppColors.textSecondary(brightness),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  memory.title.trim().isEmpty
                      ? 'Untitled memory'
                      : memory.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (memory.tags.isNotEmpty)
                  Text(
                    memory.tags.take(3).map((String t) => '#$t').join(' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
