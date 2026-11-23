import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../app_controller.dart';
import '../../app_theme.dart';
import '../../data/api_key_store.dart';
import '../../data/openai_api_server.dart';
import '../../data/openai_compatible_client.dart';
import '../../models/app_settings.dart';
import '../../models/model_info.dart';

import 'package:local_ai_studio/src/rust/api/resources.dart';

import '../widgets/app_widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelController;
  late final TextEditingController _apiTokenController;
  late final TextEditingController _huggingFaceTokenController;
  late final TextEditingController _servedApiKeyNameController;
  late final TextEditingController _servedApiPortController;
  bool _hideApiToken = true;
  bool _hideHuggingFaceToken = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = widget.controller.settings;
    _baseUrlController = TextEditingController(text: settings.remoteBaseUrl);
    _modelController = TextEditingController(text: settings.remoteModel);
    _apiTokenController = TextEditingController(text: settings.remoteApiToken);
    _huggingFaceTokenController = TextEditingController(
      text: settings.huggingFaceToken,
    );
    _servedApiKeyNameController = TextEditingController();
    _servedApiPortController = TextEditingController(
      text:
          widget.controller.apiServerPort?.toString() ??
          OpenAiApiServer.defaultPort.toString(),
    );
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    _apiTokenController.dispose();
    _huggingFaceTokenController.dispose();
    _servedApiKeyNameController.dispose();
    _servedApiPortController.dispose();
    super.dispose();
  }

  Future<void> _save({required bool testConnection}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.controller.saveApiSettings(
        baseUrl: _baseUrlController.text,
        model: _modelController.text,
        apiToken: _apiTokenController.text,
        huggingFaceToken: _huggingFaceTokenController.text,
      );
      if (testConnection) {
        final connected = await widget.controller.testRemoteConnection();
        _modelController.text = widget.controller.settings.remoteModel;
        if (connected && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Connected. Found ${widget.controller.remoteModels.length} API models.',
              ),
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('API settings saved.')));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validateBaseUrl(String? value) {
    try {
      apiResourceUri(value ?? '', 'models');
      return null;
    } on Object catch (error) {
      return error.toString();
    }
  }

  Future<void> _createServedApiKey() async {
    try {
      await widget.controller.createServedApiKey(
        _servedApiKeyNameController.text,
      );
      _servedApiKeyNameController.clear();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _toggleApiServer() async {
    try {
      if (widget.controller.isApiServerRunning) {
        await widget.controller.stopApiServer();
      } else {
        final port = int.tryParse(_servedApiPortController.text);
        if (port == null || port < 1 || port > 65535) {
          throw const FormatException('Choose a port between 1 and 65535.');
        }
        await widget.controller.startApiServer(port: port);
        _servedApiPortController.text = widget.controller.apiServerPort
            .toString();
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _revokeApiKey(ApiKeyMetadata key) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke API key?'),
        content: Text(
          'Apps using "${key.name}" will no longer be able to access the API.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke key'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.controller.revokeServedApiKey(key.id);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _copyText(String text, String successMessage) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successMessage)));
    }
  }

  String _providerYaml(CreatedApiKey key) {
    final port =
        widget.controller.apiServerPort ??
        int.tryParse(_servedApiPortController.text) ??
        OpenAiApiServer.defaultPort;
    final models = widget.controller.servedApiModels;
    return openAiProviderYaml(
      apiKey: key.secret,
      modelId: models.isEmpty ? 'MODEL_ID' : models.first,
      port: port,
    );
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(28),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHeading(
              title: 'Settings',
              subtitle: 'Choose when this app can use the network and configure an optional OpenAI-compatible API.',
            ),
            const SizedBox(height: 22),
            _NetworkPanel(controller: widget.controller),
            const SizedBox(height: 16),
            _ServedApiPanel(
              controller: widget.controller,
              keyNameController: _servedApiKeyNameController,
              portController: _servedApiPortController,
              onCreateKey: _createServedApiKey,
              onToggleServer: _toggleApiServer,
              onRevokeKey: _revokeApiKey,
              onCopy: _copyText,
              providerYaml: _providerYaml,
            ),
            const SizedBox(height: 16),
            SurfacePanel(
              padding: const EdgeInsets.all(22),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppColors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: const Icon(
                            Icons.api_rounded,
                            color: AppColors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Remote API',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                'OpenAI-compatible chat completions',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: AppColors.muted),
                              ),
                            ],
                          ),
                        ),
                        const StatusTag('Optional', color: AppColors.amber),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _baseUrlController,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'API base address',
                        hintText: 'https://api.example.com/v1',
                        helperText: 'Use HTTPS for network services. HTTP is allowed only for localhost.',
                        prefixIcon: Icon(Icons.link_rounded),
                      ),
                      validator: _validateBaseUrl,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _modelController,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Remote model ID',
                        hintText: 'Select one after testing the connection',
                        prefixIcon: Icon(Icons.memory_rounded),
                      ),
                      validator: (value) => value != null && value.length > 256
                          ? 'Use 256 characters or fewer.'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _apiTokenController,
                      obscureText: _hideApiToken,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: 'API token',
                        hintText: 'Optional for local endpoints',
                        prefixIcon: const Icon(Icons.key_rounded),
                        suffixIcon: IconButton(
                          tooltip: _hideApiToken
                              ? 'Show API token'
                              : 'Hide API token',
                          onPressed: () =>
                              setState(() => _hideApiToken = !_hideApiToken),
                          icon: Icon(
                            _hideApiToken
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: _saving
                              ? null
                              : () => _save(testConnection: false),
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: const Text('Save settings'),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => _save(testConnection: true),
                          icon: const Icon(Icons.network_check_rounded),
                          label: const Text('Save & test connection'),
                        ),
                      ],
                    ),
                    if (widget.controller.remoteModels.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const SectionLabel('Models returned by this API'),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final model
                              in widget.controller.remoteModels.take(16))
                            ActionChip(
                              label: Text(model),
                              onPressed: () => _modelController.text = model,
                            ),
                        ],
                      ),
                    ],
                    if (widget.controller.settingsError != null) ...[
                      const SizedBox(height: 14),
                      InlineNotice(
                        message: widget.controller.settingsError!,
                        isError: true,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SurfacePanel(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hugging Face access',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'A token is optional. Add one only for private repositories or gated models you have permission to use.',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: AppColors.muted, height: 1.45),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _huggingFaceTokenController,
                    obscureText: _hideHuggingFaceToken,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Hugging Face token',
                      hintText: 'Optional',
                      prefixIcon: const Icon(Icons.key_outlined),
                      suffixIcon: IconButton(
                        tooltip: _hideHuggingFaceToken
                            ? 'Show Hugging Face token'
                            : 'Hide Hugging Face token',
                        onPressed: () => setState(
                          () => _hideHuggingFaceToken = !_hideHuggingFaceToken,
                        ),
                        icon: Icon(
                          _hideHuggingFaceToken
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _save(testConnection: false),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save credentials'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'API tokens use the platform secure-storage plugin. They are not written to the regular preferences file.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: AppColors.muted, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _LocalStoragePanel(
              settings: widget.controller.settings,
              resources: widget.controller.resources,
              resourceError: widget.controller.resourceError,
              modelsDirectory: widget.controller.modelsDirectory,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ServedApiPanel extends StatelessWidget {
  const _ServedApiPanel({
    required this.controller,
    required this.keyNameController,
    required this.portController,
    required this.onCreateKey,
    required this.onToggleServer,
    required this.onRevokeKey,
    required this.onCopy,
    required this.providerYaml,
  });

  final AppController controller;
  final TextEditingController keyNameController;
  final TextEditingController portController;
  final Future<void> Function() onCreateKey;
  final Future<void> Function() onToggleServer;
  final Future<void> Function(ApiKeyMetadata) onRevokeKey;
  final Future<void> Function(String, String) onCopy;
  final String Function(CreatedApiKey) providerYaml;

  @override
  Widget build(BuildContext context) => SurfacePanel(
    padding: const EdgeInsets.all(22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.teal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.hub_outlined, color: AppColors.teal),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Use Loom from another app',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    'Expose the currently selected model through an OpenAI-compatible local API.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            StatusTag(
              controller.isApiServerRunning ? 'Running' : 'Stopped',
              color: controller.isApiServerRunning
                  ? AppColors.teal
                  : AppColors.amber,
            ),
          ],
        ),
        const SizedBox(height: 18),
        InlineNotice(
          message: 'This endpoint listens only on this computer (127.0.0.1). It is not a public internet or LAN endpoint.',
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            SizedBox(
              width: 150,
              child: TextField(
                controller: portController,
                enabled: !controller.isApiServerRunning,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Local port',
                  prefixIcon: Icon(Icons.settings_ethernet_rounded),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed:
                  controller.isApiServerRunning || controller.apiKeys.isNotEmpty
                  ? onToggleServer
                  : null,
              icon: Icon(
                controller.isApiServerRunning
                    ? Icons.stop_circle_outlined
                    : Icons.play_circle_outline_rounded,
              ),
              label: Text(
                controller.isApiServerRunning ? 'Stop API' : 'Start API',
              ),
            ),
            if (controller.isApiServerRunning) ...[
              const SizedBox(width: 14),
              Expanded(
                child: SelectableText(
                  controller.apiServerBaseUrl,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.teal,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ],
        ),
        if (controller.apiServerError != null) ...[
          const SizedBox(height: 12),
          InlineNotice(message: controller.apiServerError!, isError: true),
        ],
        const SizedBox(height: 16),
        Text('Endpoints', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        const SelectableText(
          'GET  /v1/models\nPOST /v1/chat/completions\n'
          'Send: Authorization: Bearer YOUR_API_KEY\n'
          'Chat requests use JSON with model, messages, and stream: false. Set stream: true for SSE streaming.',
        ),
        const SizedBox(height: 22),
        const Divider(),
        const SizedBox(height: 12),
        Text('API keys', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 5),
        Text(
          'Create a separate key for each app or environment. There is no app-imposed key count limit. '
          'Secrets are stored as hashes and cannot be viewed again after this screen.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: AppColors.muted, height: 1.45),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: keyNameController,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Key name',
                  hintText: 'e.g. My desktop app',
                  counterText: '',
                ),
                onSubmitted: (_) => onCreateKey(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: onCreateKey,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create key'),
            ),
          ],
        ),
        if (controller.apiKeys.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'No keys yet. Create one before starting the API.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.muted),
          ),
        ] else ...[
          const SizedBox(height: 8),
          for (final key in controller.apiKeys)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.key_outlined, color: AppColors.blue),
              title: Text(key.name),
              subtitle: Text(
                '${key.prefix}...  ·  Created ${key.createdAt.toLocal().toString().split('.').first}',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AppColors.muted),
              ),
              trailing: IconButton(
                tooltip: 'Revoke ${key.name}',
                onPressed: () => onRevokeKey(key),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.red,
                ),
              ),
            ),
        ],
        if (controller.createdApiKey case final created?) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.teal.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.teal.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Copy this key now — Loom will not show it again.',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: AppColors.teal),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  created.secret,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () =>
                          onCopy(created.secret, 'API key copied.'),
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Copy key'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => onCopy(
                        providerYaml(created),
                        'Provider config copied.',
                      ),
                      icon: const Icon(Icons.code_rounded),
                      label: const Text('Copy provider config'),
                    ),
                    TextButton(
                      onPressed: controller.dismissCreatedApiKey,
                      child: const Text('Hide key'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  providerYaml(created),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'Use the generated YAML in an OpenAI-compatible client. For external apps on this same computer, '
          'set the base URL to http://127.0.0.1:<port>/v1 and keep the API key in the app’s server-side configuration, never browser code.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: AppColors.muted, height: 1.45),
        ),
      ],
    ),
  );
}

class _NetworkPanel extends StatelessWidget {
  const _NetworkPanel({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => SurfacePanel(
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.teal.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            controller.settings.internetEnabled
                ? Icons.public_rounded
                : Icons.cloud_off_rounded,
            color: controller.settings.internetEnabled
                ? AppColors.teal
                : AppColors.amber,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Internet access',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                controller.settings.internetEnabled
                    ? 'Catalog search, downloads, and remote APIs are allowed.'
                    : 'Only models already stored on this device can be used.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
        Switch.adaptive(
          value: controller.settings.internetEnabled,
          onChanged: controller.setInternetEnabled,
        ),
      ],
    ),
  );
}

class _LocalStoragePanel extends StatelessWidget {
  const _LocalStoragePanel({
    required this.settings,
    required this.resources,
    required this.resourceError,
    required this.modelsDirectory,
  });

  final AppSettings settings;
  final HostResources? resources;
  final String? resourceError;
  final String modelsDirectory;

  @override
  Widget build(BuildContext context) => SurfacePanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Local storage', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          modelsDirectory,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: AppColors.muted, fontFamily: 'monospace'),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 20,
          runSpacing: 10,
          children: [
            _ResourceValue(
              label: 'Available memory',
              value: resources == null
                  ? resourceError ?? 'Checking'
                  : formatByteSize(resources!.availableMemoryBytes.toInt()),
            ),
            _ResourceValue(
              label: 'Free on models drive',
              value: resources == null
                  ? 'Unavailable'
                  : formatByteSize(resources!.modelDiskAvailableBytes.toInt()),
            ),
            _ResourceValue(
              label: 'Processor threads',
              value: resources?.logicalProcessors.toString() ?? 'Unavailable',
            ),
          ],
        ),
      ],
    ),
  );
}

class _ResourceValue extends StatelessWidget {
  const _ResourceValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 210,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleSmall),
      ],
    ),
  );
}
