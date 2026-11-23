import 'package:material_ui/material_ui.dart';

import '../../app_controller.dart';
import '../../app_theme.dart';
import '../../models/model_info.dart';
import '../app_destination.dart';
import '../widgets/app_widgets.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    required this.controller,
    required this.onNavigate,
    super.key,
  });

  final AppController controller;
  final ValueChanged<AppDestination> onNavigate;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _WelcomePanel(
                compact: constraints.maxWidth < 720,
                onBrowse: () => onNavigate(AppDestination.catalog),
                onChat: () => onNavigate(AppDestination.chat),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricTile(
                    label: 'Available memory',
                    value: controller.resources == null
                        ? 'Checking'
                        : formatByteSize(
                            controller.resources!.availableMemoryBytes.toInt(),
                          ),
                    detail: controller.resources == null
                        ? controller.resourceError ?? 'Reading system resources'
                        : '${formatByteSize(controller.resources!.totalMemoryBytes.toInt())} total',
                    icon: Icons.memory_rounded,
                    accent: AppColors.blue,
                  ),
                  _MetricTile(
                    label: 'Model storage free',
                    value: controller.resources == null
                        ? 'Unavailable'
                        : formatByteSize(
                            controller.resources!.modelDiskAvailableBytes.toInt(),
                          ),
                    detail: 'On the models drive',
                    icon: Icons.storage_rounded,
                    accent: AppColors.teal,
                  ),
                  _MetricTile(
                    label: 'Models in library',
                    value: '${controller.installedModels.length}',
                    detail: controller.localModelPath == null
                        ? 'None active'
                        : 'A local model is ready',
                    icon: Icons.layers_outlined,
                    accent: AppColors.amber,
                  ),
                  _MetricTile(
                    label: 'Processor threads',
                    value: controller.resources == null
                        ? '—'
                        : '${controller.resources!.logicalProcessors}',
                    detail: 'Available to local inference',
                    icon: Icons.developer_board_outlined,
                    accent: AppColors.blue,
                  ),
                ],
              ),
              const SizedBox(height: 30),
              Row(
                children: [
                  const Expanded(child: SectionLabel('Your workspace')),
                  TextButton.icon(
                    onPressed: () => onNavigate(AppDestination.library),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                    label: const Text('Open library'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (controller.installedModels.isEmpty)
                _LibraryPrompt(onBrowse: () => onNavigate(AppDestination.catalog))
              else
                _ModelShelf(
                  controller: controller,
                  onOpenLibrary: () => onNavigate(AppDestination.library),
                  onOpenChat: () => onNavigate(AppDestination.chat),
                ),
              if (controller.resourceError != null) ...[
                const SizedBox(height: 14),
                InlineNotice(
                  message: 'Hardware details are unavailable. Model loading still depends on the memory and storage available on this device.',
                  isError: true,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel({
    required this.compact,
    required this.onBrowse,
    required this.onChat,
  });

  final bool compact;
  final VoidCallback onBrowse;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StatusTag(
          'Private by default',
          icon: Icons.shield_outlined,
          color: AppColors.teal,
        ),
        const SizedBox(height: 20),
        Text(
          'Your AI,\non this machine.',
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.08,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Text(
            'Find open GGUF models, keep them in your library, and run chat locally. Internet access stays under your control.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppColors.muted,
              height: 1.55,
            ),
          ),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: onBrowse,
              icon: const Icon(Icons.explore_outlined),
              label: const Text('Browse models'),
            ),
            OutlinedButton.icon(
              onPressed: onChat,
              icon: const Icon(Icons.forum_outlined),
              label: const Text('Open chat'),
            ),
          ],
        ),
      ],
    );

    final motif = Container(
      width: 210,
      height: 210,
      decoration: BoxDecoration(
        color: AppColors.canvas.withValues(alpha: 0.65),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.line, width: 1.2),
      ),
      child: Center(
        child: Container(
          width: 132,
          height: 132,
          decoration: BoxDecoration(
            color: AppColors.raised,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.blue.withValues(alpha: 0.55)),
          ),
          child: const Icon(
            Icons.blur_on_rounded,
            size: 64,
            color: AppColors.blue,
          ),
        ),
      ),
    );

    return SurfacePanel(
      color: AppColors.raised,
      padding: const EdgeInsets.all(28),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [intro, const SizedBox(height: 24), Center(child: motif)],
            )
          : Row(
              children: [
                Expanded(child: intro),
                const SizedBox(width: 28),
                motif,
              ],
            ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 205, maxWidth: 310),
    width: 240,
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: accent, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.muted)),
              const SizedBox(height: 4),
              Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              Text(detail, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.muted)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _LibraryPrompt extends StatelessWidget {
  const _LibraryPrompt({required this.onBrowse});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) => SurfacePanel(
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(Icons.download_for_offline_outlined, color: AppColors.blue),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('No models yet', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Choose a GGUF model to download into your local library.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        FilledButton(onPressed: onBrowse, child: const Text('Find a model')),
      ],
    ),
  );
}

class _ModelShelf extends StatelessWidget {
  const _ModelShelf({
    required this.controller,
    required this.onOpenLibrary,
    required this.onOpenChat,
  });

  final AppController controller;
  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    final activePath = controller.localModelPath;
    final activeIndex = controller.installedModels.indexWhere(
      (model) => model.path == activePath,
    );
    final activeModel = activeIndex < 0
        ? null
        : controller.installedModels[activeIndex];
    if (activeModel != null) {
      return SurfacePanel(
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.teal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.memory_rounded, color: AppColors.teal),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(activeModel.name, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    '${activeModel.repository}  /  ${formatByteSize(activeModel.sizeBytes)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const StatusTag('Loaded', icon: Icons.check_rounded),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: onOpenChat,
              icon: const Icon(Icons.forum_outlined),
              label: const Text('Chat'),
            ),
          ],
        ),
      );
    }

    return SurfacePanel(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      child: Column(
        children: [
          for (final model in controller.installedModels.take(3))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.insert_drive_file_outlined, color: AppColors.blue),
              title: Text(model.name),
              subtitle: Text('${model.repository}  /  ${formatByteSize(model.sizeBytes)}'),
              trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              onTap: onOpenLibrary,
            ),
        ],
      ),
    );
  }
}
