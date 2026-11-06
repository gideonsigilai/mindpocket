import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/models/memory.dart';
import '../../../core/widgets/pocket_widgets.dart';
import '../controller/memory_detail_controller.dart';
import 'widgets/memory_widgets.dart';

class MemoryDetailPage extends GetView<MemoryDetailController> {
  const MemoryDetailPage({super.key, required this.memoryId});

  /// Captured at route creation; also the controller tag registered by the
  /// binding, so each memory route keeps its own controller even when several
  /// detail pages are stacked.
  final String memoryId;

  @override
  String? get tag => memoryId;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final Memory? memory = controller.memory.value;

      // The leading back button asks before discarding edits; the system back
      // gesture must not bypass that guard.
      return PopScope(
        canPop: !controller.dirty.value,
        onPopInvokedWithResult: (bool didPop, Object? result) async {
          if (didPop) return;
          if (await _confirmDiscard(context) && context.mounted) {
            Get.back();
          }
        },
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              onPressed: () async {
                if (controller.dirty.value) {
                  final bool leave = await _confirmDiscard(context);
                  if (!leave) return;
                }
                Get.back();
              },
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back',
            ),
            title: Text(
              memory?.title.trim().isNotEmpty == true
                  ? 'Memory'
                  : 'Untitled memory',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            actions: <Widget>[
              IconButton(
                onPressed: controller.addImageAttachment,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                tooltip: 'Attach an image',
              ),
              PopupMenuButton<String>(
                tooltip: 'More actions',
                onSelected: (String value) async {
                  switch (value) {
                    case 'delete':
                      await _confirmDelete(context);
                    case 'retry':
                      await controller.retryAllFailed();
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'retry',
                    child: ListTile(
                      leading: Icon(Icons.refresh_rounded),
                      title: Text('Retry failed processing'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.dangerFor(Theme.of(context).brightness),
                      ),
                      title: Text(
                        'Delete memory',
                        style: TextStyle(
                          color: AppColors.dangerFor(
                            Theme.of(context).brightness,
                          ),
                        ),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: _body(context, memory),
        ),
      );
    });
  }

  Widget _body(BuildContext context, Memory? memory) {
    if (controller.loading.value && memory == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.error.value.isNotEmpty && memory == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ErrorBlock(
            message: controller.error.value,
            onRetry: () => controller.load(),
          ),
        ),
      );
    }
    if (memory == null) {
      return const Center(child: Text('This memory is no longer available.'));
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 800;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            wide ? 48.w : 20.w,
            8.h,
            wide ? 48.w : 20.w,
            40.h,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Banner(controller: controller),
                  MemoryBody(controller: controller, memory: memory),
                  SizedBox(height: 24.h),
                  OutlinedButton.icon(
                    onPressed: () => _confirmDelete(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.dangerFor(
                        Theme.of(context).brightness,
                      ),
                      side: BorderSide(
                        color: AppColors.dangerFor(
                          Theme.of(context).brightness,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Delete this memory'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool> _confirmDiscard(BuildContext context) async {
    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text(
          'Your edits to the title and note have not been saved.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete this memory?'),
        content: const Text(
          'Its images, recordings, extracted text, embeddings, and processing jobs are removed. '
          'This cannot be undone. Downloaded models are kept.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
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
    if (confirmed != true) return;
    await controller.deleteMemory();
    if (!context.mounted) return;
    // Go back to wherever the memory was opened from (timeline, search, a
    // collection); only a cold deep link needs a new home route.
    if (Navigator.of(context).canPop()) {
      Get.back();
    } else {
      Get.offAllNamed(AppRoutes.home);
    }
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.controller});

  final MemoryDetailController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final String message = controller.banner.value;
      if (message.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: EdgeInsets.only(bottom: 12.h),
        child: PocketCard(
          padding: EdgeInsets.fromLTRB(16.w, 10.h, 6.w, 10.h),
          color: AppColors.highlight(Theme.of(context).brightness)
              .withValues(alpha: 0.18),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: AppColors.textPrimary(Theme.of(context).brightness),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textPrimary(Theme.of(context).brightness),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => controller.banner.value = '',
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Dismiss',
              ),
            ],
          ),
        ),
      );
    });
  }
}
