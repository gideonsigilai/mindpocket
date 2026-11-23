import 'package:material_ui/material_ui.dart';

import '../../app_controller.dart';
import '../../app_theme.dart';
import '../../models/model_info.dart';
import '../widgets/app_widgets.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.controller.catalogQuery);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _search() => widget.controller.searchModels(query: _searchController.text);

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 8),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1320),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PageHeading(
                    title: 'Model catalog',
                    subtitle: 'Search Hugging Face for downloadable GGUF models. Select a quantization that fits your machine.',
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _search(),
                          decoration: const InputDecoration(
                            labelText: 'Search model names or authors',
                            hintText: 'Try Qwen, Llama, Gemma…',
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: widget.controller.settings.internetEnabled &&
                                !widget.controller.isLoadingCatalog
                            ? _search
                            : null,
                        icon: const Icon(Icons.search_rounded),
                        label: const Text('Search'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const StatusTag(
                        'GGUF',
                        icon: Icons.memory_rounded,
                        color: AppColors.blue,
                      ),
                      const Text(
                        'Text-generation models · sorted by downloads',
                        style: TextStyle(color: AppColors.muted),
                      ),
                      if (widget.controller.isLoadingCatalog)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  if (widget.controller.catalogError != null) ...[
                    const SizedBox(height: 14),
                    InlineNotice(
                      message: widget.controller.catalogError!,
                      isError: true,
                      action: TextButton(
                        onPressed: _search,
                        child: const Text('Try again'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      if (!widget.controller.settings.internetEnabled)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Internet access is off',
            description: 'Turn it on in the top bar to search and download models. Your installed models remain available offline.',
          ),
        )
      else if (widget.controller.isLoadingCatalog &&
          widget.controller.catalogModels.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        )
      else if (widget.controller.catalogModels.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.manage_search_rounded,
            title: 'No matching models',
            description: 'Search by model family, author, or repository name. Only GGUF files can be loaded locally.',
          ),
        )
      else ...[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 22),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 430,
              mainAxisExtent: 240,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemCount: widget.controller.catalogModels.length,
            itemBuilder: (context, index) => _ModelCard(
              model: widget.controller.catalogModels[index],
              controller: widget.controller,
            ),
          ),
        ),
        if (widget.controller.catalogNextCursor != null)
          SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: OutlinedButton.icon(
                  onPressed: widget.controller.isLoadingCatalog
                      ? null
                      : () => widget.controller.searchModels(loadMore: true),
                  icon: widget.controller.isLoadingCatalog
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more_rounded),
                  label: const Text('Load more models'),
                ),
              ),
            ),
          ),
      ],
    ],
  );
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.model, required this.controller});

  final AvailableModel model;
  final AppController controller;

  @override
  Widget build(BuildContext context) => SurfacePanel(
    padding: const EdgeInsets.all(17),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.memory_rounded, color: AppColors.blue, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    model.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (model.isGated)
              const Tooltip(
                message: 'Access may require a Hugging Face token',
                child: Icon(Icons.lock_outline_rounded, size: 17, color: AppColors.amber),
              ),
          ],
        ),
        const SizedBox(height: 13),
        Text(
          model.id,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.muted,
            fontFamily: 'monospace',
          ),
        ),
        const Spacer(),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            _MetadataChip(icon: Icons.download_outlined, label: formatCount(model.downloads)),
            _MetadataChip(icon: Icons.favorite_border_rounded, label: formatCount(model.likes)),
            if (model.tags.contains('conversational'))
              const StatusTag('Chat tuned', color: AppColors.teal),
          ],
        ),
        const SizedBox(height: 13),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _showArtifacts(context),
            icon: const Icon(Icons.download_for_offline_outlined, size: 18),
            label: const Text('Choose a model file'),
          ),
        ),
      ],
    ),
  );

  void _showArtifacts(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => _ArtifactDialog(
        controller: controller,
        model: model,
      ),
    );
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.canvas,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.muted),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    ),
  );
}

class _ArtifactDialog extends StatefulWidget {
  const _ArtifactDialog({required this.controller, required this.model});

  final AppController controller;
  final AvailableModel model;

  @override
  State<_ArtifactDialog> createState() => _ArtifactDialogState();
}

class _ArtifactDialogState extends State<_ArtifactDialog> {
  late final Future<List<ModelArtifact>> _artifacts;

  @override
  void initState() {
    super.initState();
    _artifacts = widget.controller.listArtifacts(widget.model);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final maxHeight = (screenSize.height - 170).clamp(0.0, 620.0).toDouble();
    final maxWidth = (screenSize.width - 80).clamp(0.0, 760.0).toDouble();
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.model.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 5),
          Text(
            widget.model.id,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.muted,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: maxWidth,
        height: maxHeight,
        child: FutureBuilder<List<ModelArtifact>>(
          future: _artifacts,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return InlineNotice(message: snapshot.error.toString(), isError: true);
            }
            final artifacts = snapshot.data ?? const <ModelArtifact>[];
            if (artifacts.isEmpty) {
              return const EmptyState(
                icon: Icons.insert_drive_file_outlined,
                title: 'No GGUF files found',
                description: 'This repository does not contain a downloadable GGUF model.',
              );
            }

            return AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.model.isGated &&
                      widget.controller.settings.huggingFaceToken.isEmpty) ...[
                    const InlineNotice(
                      message: 'This repository may require access approval. Add a Hugging Face token in Settings if the download is denied.',
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (widget.controller.downloadError != null) ...[
                    InlineNotice(
                      message: widget.controller.downloadError!,
                      isError: true,
                    ),
                    const SizedBox(height: 12),
                  ],
                  Expanded(
                    child: ListView.separated(
                      itemCount: artifacts.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) => _ArtifactRow(
                        controller: widget.controller,
                        artifact: artifacts[index],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _ArtifactRow extends StatelessWidget {
  const _ArtifactRow({required this.controller, required this.artifact});

  final AppController controller;
  final ModelArtifact artifact;

  @override
  Widget build(BuildContext context) {
    final installed = controller.installedModels.any(
      (model) => model.repository == artifact.repository && model.filename == artifact.filename,
    );
    final downloading = controller.isDownloading &&
        controller.activeDownloadName == '${artifact.repository}/${artifact.filename}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Icon(
            installed ? Icons.check_circle_outline_rounded : Icons.description_outlined,
            color: installed ? AppColors.teal : AppColors.blue,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(artifact.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      formatByteSize(artifact.sizeBytes),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                    if (artifact.sha256 != null)
                      const Text(
                        'SHA-256 available',
                        style: TextStyle(color: AppColors.teal, fontSize: 11),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (installed)
            const StatusTag('In library', icon: Icons.check_rounded)
          else if (downloading)
            TextButton.icon(
              onPressed: controller.cancelDownload,
              icon: const Icon(Icons.close_rounded, size: 17),
              label: const Text('Cancel'),
            )
          else
            FilledButton.icon(
              onPressed: controller.isDownloading
                  ? null
                  : () async {
                      final file = await controller.downloadArtifact(artifact);
                      if (file != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Downloaded ${artifact.name}')),
                        );
                      }
                    },
              icon: const Icon(Icons.download_rounded, size: 17),
              label: const Text('Download'),
            ),
          if (downloading) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              child: LinearProgressIndicator(value: controller.downloadFraction),
            ),
          ],
        ],
      ),
    );
  }
}
