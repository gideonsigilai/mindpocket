import 'package:material_ui/material_ui.dart';

import '../../models/installed_model.dart';

class LocalModelPicker extends StatelessWidget {
  const LocalModelPicker({
    required this.models,
    required this.selectedPath,
    required this.enabled,
    required this.onSelected,
    this.isLoading = false,
    super.key,
  });

  final List<InstalledModel> models;
  final String? selectedPath;
  final bool enabled;
  final bool isLoading;
  final ValueChanged<InstalledModel> onSelected;

  @override
  Widget build(BuildContext context) => DropdownButton<String>(
    value: models.any((model) => model.path == selectedPath)
        ? selectedPath
        : null,
    isExpanded: true,
    underline: const SizedBox.shrink(),
    hint: Text(isLoading ? 'Loading model…' : 'Choose a local model'),
    onChanged: enabled
        ? (path) {
            if (path == null) return;
            onSelected(models.firstWhere((model) => model.path == path));
          }
        : null,
    items: [
      for (final model in models)
        DropdownMenuItem(
          value: model.path,
          child: Text(
            '${model.name} · ${model.repository}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
  );
}
