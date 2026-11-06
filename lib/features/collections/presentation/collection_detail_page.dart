import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/models/attachment.dart';
import '../../../core/models/memory.dart';
import '../../../core/widgets/pocket_widgets.dart';
import '../../memory_detail/presentation/widgets/media_widgets.dart';
import '../../search/presentation/search_page.dart';
import '../controller/collections_controller.dart';
import 'collections_page.dart';

class CollectionDetailPage extends GetView<CollectionDetailController> {
  const CollectionDetailPage({super.key, required this.collectionId});

  /// Captured at route creation; also the tag registered by the binding.
  final String collectionId;

  @override
  String? get tag => collectionId;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return Obx(() {
      final Collection? collection = controller.collection.value;
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => Get.back(),
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
          ),
          title: Text(collection?.name ?? 'Collection'),
        ),
        body: _body(context, collection, brightness),
      );
    });
  }

  Widget _body(
    BuildContext context,
    Collection? collection,
    Brightness brightness,
  ) {
    if (controller.loading.value && collection == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.error.value.isNotEmpty && collection == null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: ErrorBlock(
          message: controller.error.value,
          onRetry: controller.load,
        ),
      );
    }
    if (collection == null) return const SizedBox.shrink();

    return ListView(
      padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 32.h),
      children: <Widget>[
        if (collection.description.trim().isNotEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: 14.h),
            child: Text(
              collection.description,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textSecondary(brightness)),
            ),
          ),
        Text(
          '${controller.memories.length} memor${controller.memories.length == 1 ? 'y' : 'ies'}',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary(brightness),
          ),
        ),
        SizedBox(height: 10.h),
        if (controller.memories.isEmpty)
          EmptyState(
            title: 'This collection is empty',
            message: 'Open a memory and tap this collection under Collection to file it here.',
          )
        else
          for (final Memory memory in controller.memories)
            Padding(
              padding: EdgeInsets.only(bottom: 8.h),
              child: MemoryListRow(
                memory: memory,
                onTap: () => controller.openMemory(memory.id),
                trailing: IconButton(
                  onPressed: () => controller.removeMemory(memory),
                  tooltip: 'Remove from collection',
                  icon: const Icon(
                    Icons.remove_circle_outline_rounded,
                    size: 18,
                  ),
                ),
              ),
            ),
        if (controller.related.isNotEmpty) ...<Widget>[
          SizedBox(height: 16.h),
          RelatedStrip(
            label: collection.name,
            suggestions: controller.related,
            onOpen: (suggestion) => controller.openMemory(suggestion.memory.id),
            onDismiss: controller.dismiss,
          ),
        ],
        if (controller.memories.isNotEmpty) ...<Widget>[
          SizedBox(height: 20.h),
          Text(
            'Related items come from shared words in your own notes and transcripts. '
            'They are suggestions, not findings about meaning.',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          SizedBox(height: 20.h),
          OutlinedButton.icon(
            onPressed: () => Get.toNamed('/search'),
            icon: const Icon(Icons.search_rounded, size: 18),
            label: const Text('Search the whole pocket'),
          ),
        ],
      ],
    );
  }
}

/// Small helper: preview tile used inside collection detail header.
class CollectionCover extends StatelessWidget {
  const CollectionCover({super.key, required this.memories});

  final List<Memory> memories;

  @override
  Widget build(BuildContext context) {
    final List<String> images = memories
        .map((Memory m) => m.primaryThumbnailPath ?? '')
        .where((String path) => path.isNotEmpty)
        .take(3)
        .toList(growable: false);
    if (images.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 110.h,
      child: Row(
        children: <Widget>[
          for (final String path in images)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: 6.w),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16.r),
                  child: LocalImage(relativePath: path, cacheWidth: 400),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
