import 'package:material_ui/material_ui.dart';
import 'package:file_picker/file_picker.dart';

import '../../app_controller.dart';
import '../../app_theme.dart';
import '../../models/installed_model.dart';
import '../../models/model_info.dart';
import '../app_destination.dart';
import '../widgets/app_widgets.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({
    required this.controller,
    required this.onNavigate,
    super.key,
  });

  final AppController controller;
  final ValueChanged<AppDestination> onNavigate;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: PageHeading(
                    title: 'My models',
                    subtitle: 'Models are stored in app data and remain available when internet access is off.',
                  ),
                ),
                const SizedBox(width: 16),
                FilledButton.tonalIcon(
                  onPressed:
                      controller.isImportingModel ||
                          controller.isLoadingModel ||
                          controller.isDownloading ||
                          controller.isGenerating
                      ? null
                      : () => _loadFromStorage(context),
                  icon: controller.isImportingModel
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open_outlined),
                  label: const Text('Load from storage'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (controller.libraryError != null) ...[
              InlineNotice(message: controller.libraryError!, isError: true),
              const SizedBox(height: 14),
            ],
            Expanded(
              child: controller.installedModels.isEmpty
                  ? EmptyState(
                      icon: Icons.storage_outlined,
                      title: 'Your library is empty',
                      description: 'Load a GGUF file from your storage or find a model in the catalog.',
                      action: FilledButton.icon(
                        onPressed: () => onNavigate(AppDestination.catalog),
                        icon: const Icon(Icons.explore_outlined),
                        label: const Text('Browse model catalog'),
                      ),
                    )
                  : ListView.separated(
                      itemCount: controller.installedModels.length + 1,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        if (index == 0) return const _LibraryHeader();
                        final model = controller.installedModels[index - 1];
                        return _InstalledModelTile(
                          controller: controller,
                          model: model,
                          onChat: () => onNavigate(AppDestination.chat),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _loadFromStorage(BuildContext context) async {
    try {
      final selection = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['gguf'],
      );
      if (selection == null || !context.mounted) return;

      final path = selection.path;
      if (path == null) {
        throw StateError('Could not access the selected model file.');
      }
      if (await controller.importAndLoadModel(path) && context.mounted) {
        onNavigate(AppDestination.chat);
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
    child: Row(
      children: [
        const Expanded(child: SectionLabel('Installed files')),
        Text(
          'GGUF · local storage',
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: AppColors.muted),
        ),
      ],
    ),
  );
}

class _InstalledModelTile extends StatelessWidget {
  const _InstalledModelTile({
    required this.controller,
    required this.model,
    required this.onChat,
  });

  final AppController controller;
  final InstalledModel model;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final isLoaded = controller.localModelPath == model.path;
    return SurfacePanel(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isLoaded
                  ? AppColors.teal.withValues(alpha: 0.1)
                  : AppColors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isLoaded
                  ? Icons.check_circle_outline_rounded
                  : Icons.memory_rounded,
              color: isLoaded ? AppColors.teal : AppColors.blue,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        model.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (isLoaded) ...[
                      const SizedBox(width: 9),
                      const StatusTag('Loaded', icon: Icons.check_rounded),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '${model.repository}/${model.filename}  /  ${formatByteSize(model.sizeBytes)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          if (isLoaded) ...[
            OutlinedButton.icon(
              onPressed: onChat,
              icon: const Icon(Icons.forum_outlined, size: 17),
              label: const Text('Chat'),
            ),
            const SizedBox(width: 6),
            TextButton.icon(
              onPressed: controller.isGenerating
                  ? null
                  : () => controller.unloadModel(),
              icon: const Icon(Icons.memory_outlined, size: 17),
              label: const Text('Unload'),
            ),
          ] else
            FilledButton.icon(
              onPressed: controller.isLoadingModel
                  ? null
                  : () async {
                      if (await controller.loadModel(model)) onChat();
                    },
              icon: controller.isLoadingModel
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 19),
              label: const Text('Load'),
            ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Remove ${model.name}',
            onPressed:
                controller.isLoadingModel ||
                    controller.isDownloading ||
                    controller.isGenerating
                ? null
                : () => _confirmRemove(context, model),
            icon: const Icon(Icons.delete_outline_rounded),
            color: AppColors.muted,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    InstalledModel model,
  ) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this model?'),
        content: Text(
          '${model.name} will be deleted from local storage. You can download it again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep model'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove file'),
          ),
        ],
      ),
    );
    if (remove != true || !context.mounted) return;

    try {
      await controller.deleteModel(model);
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}
