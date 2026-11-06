import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/controllers/app_settings_controller.dart';
import '../../../core/services/ai/model_catalog.dart';
import '../../../core/services/ai/model_manager.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/pocket_widgets.dart';
import '../controller/cloud_settings_controller.dart';
import '../controller/models_controller.dart';
import '../controller/settings_controller.dart';

class SettingsPage extends GetView<SettingsController> {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Obx(() {
          return ListView(
            padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 40.h),
            children: <Widget>[
              Text(
                'SETTINGS',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 2,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accentText(brightness),
                ),
              ),
              SizedBox(height: 6.h),
              Text(
                'Own your pocket',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              SizedBox(height: 6.h),
              Text(
                'Everything works without an account. Cloud analysis is opt-in and off by default.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              SizedBox(height: 20.h),
              _Section(
                title: 'Appearance',
                children: <Widget>[
                  _ThemePicker(controller: controller),
                  Obx(() {
                    final AppSettingsController motion =
                        Get.find<AppSettingsController>();
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: motion.reduceMotion.value,
                      onChanged: (bool value) =>
                          controller.setReducedMotion(value),
                      title: const Text('Reduce motion'),
                      subtitle: const Text(
                        'Shortens transitions and disables decorative loops.',
                      ),
                    );
                  }),
                ],
              ),
              SizedBox(height: 14.h),
              _Section(
                title: 'On-device processing',
                children: <Widget>[
                  Obx(
                    () => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: controller.toggles.ocrAuto.value,
                      onChanged: (bool value) async {
                        await controller.toggles.setOcrAuto(value);
                        controller.reloadTotals();
                      },
                      title: const Text('Extract text from new images'),
                      subtitle: const Text(
                        'Runs ML Kit on this device. Text only — it does not interpret the picture.',
                      ),
                    ),
                  ),
                  Obx(
                    () => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: controller.toggles.transcribeAuto.value,
                      onChanged: (bool value) async {
                        await controller.toggles.setTranscribeAuto(value);
                        controller.reloadTotals();
                      },
                      title: const Text('Transcribe new recordings'),
                      subtitle: const Text(
                        'Runs offline with an installed Whisper model. Recordings stay playable without one.',
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.download_for_offline_outlined),
                    title: const Text('Speech models'),
                    subtitle: Text(controller.modelSummary),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: controller.openModels,
                  ),
                ],
              ),
              SizedBox(height: 14.h),
              _Section(
                title: 'Storage',
                children: <Widget>[
                  if (controller.storageLoading.value)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: LinearProgressIndicator(),
                    )
                  else ...<Widget>[
                    _StorageBar(controller: controller),
                    SizedBox(height: 10.h),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            '${controller.memoryCount.value} memories · '
                            '${controller.attachmentCount.value} files',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        Text(
                          Format.bytes(controller.totalBytes.value),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                    SizedBox(height: 6.h),
                    Text(
                      'Images ${Format.bytes(controller.imageBytes.value)} · '
                      'Audio ${Format.bytes(controller.audioBytes.value)} · '
                      'Models ${Format.bytes(controller.modelBytes.value)}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ],
              ),
              SizedBox(height: 14.h),
              _Section(
                title: 'Screenshots',
                children: <Widget>[
                  Obx(
                    () => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: controller.hasScreenshotAccess.value,
                      onChanged: (bool value) async {
                        if (value) {
                          await controller.requestScreenshotAccess();
                        } else {
                          controller.syncStatus.value = 'Revoke access in Android settings; imports stop immediately.';
                        }
                      },
                      title: const Text('Screenshot access'),
                      subtitle: Text(
                        controller.hasScreenshotAccess.value
                            ? 'Allowed — imports read only the Screenshots folder.'
                            : 'Not granted — tap to ask Android for access.',
                      ),
                    ),
                  ),
                  Obx(
                    () => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: controller.autoImport.value,
                      onChanged: (bool value) =>
                          controller.setAutoImport(value),
                      title: const Text('Import automatically'),
                      subtitle: const Text(
                        'When on, new screenshots are taken on launch and resume. '
                        'When off, imports only run from this screen.',
                      ),
                    ),
                  ),
                  Obx(
                    () => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.photo_library_outlined),
                      title: const Text('Import new screenshots'),
                      subtitle: Text(
                        controller.lastScreenshotSync.value == null
                            ? 'Never imported — the first run takes everything.'
                            : 'Last import ${_ago(controller.lastScreenshotSync.value!)}',
                      ),
                      trailing: controller.syncing.value
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: controller.syncing.value
                          ? null
                          : () => controller.importScreenshots(),
                    ),
                  ),
                  Obx(
                    () => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.photo_library),
                      title: const Text('Import every screenshot again'),
                      subtitle: const Text(
                        'Rescans the whole gallery. Copies already saved are skipped.',
                      ),
                      onTap: controller.syncing.value
                          ? null
                          : () => controller.importScreenshots(full: true),
                    ),
                  ),
                  Obx(
                    () => controller.syncStatus.value.isEmpty
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: EdgeInsets.only(bottom: 8.h),
                            child: Text(
                              controller.syncStatus.value,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                  ),
                ],
              ),
              SizedBox(height: 14.h),
              _Section(
                title: 'AI grouping',
                children: <Widget>[
                  Obx(
                    () => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.auto_awesome_outlined),
                      title: const Text('NVIDIA NIM'),
                      subtitle: Text(
                        controller.nimHasKey.value
                            ? '${controller.nimModel.value} via ${controller.nimBaseUrl.value}'
                            : 'No key — imports group by nothing until one is added',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _editNim(context, controller),
                    ),
                  ),
                  Obx(
                    () => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.category_outlined),
                      title: const Text('Sort existing screenshots now'),
                      subtitle: const Text(
                        'Groups what is already saved by its extracted text.',
                      ),
                      onTap: controller.syncing.value
                          ? null
                          : () => controller.organiseNow(),
                    ),
                  ),
                  Text(
                    'Grouping sends the text extracted from each screenshot, never the '
                    'image itself.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              SizedBox(height: 14.h),
              _Section(
                title: 'Cloud analysis',
                children: <Widget>[
                  Obx(
                    () => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: controller.toggles.cloudEnabled.value,
                      onChanged: (bool value) async {
                        await controller.toggles.setCloudEnabled(value);
                        controller.update();
                      },
                      title: const Text('Enable cloud analysis'),
                      subtitle: const Text(
                        'Off by default. Even when on, nothing is uploaded until you tap '
                        '“Analyze with cloud AI” on a memory and confirm what will be sent.',
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.cloud_outlined),
                    title: const Text('Backend and disclosure'),
                    subtitle: Text(
                      controller.cloudConfigured ? controller.cloudBaseUrl : 'No backend configured — cloud analysis unavailable',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: controller.openCloud,
                  ),
                ],
              ),
              SizedBox(height: 14.h),
              _Section(
                title: 'Local intelligence',
                children: <Widget>[
                  Obx(
                    () => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: controller.toggles.semanticEnabled.value,
                      onChanged: (bool value) async {
                        await controller.toggles.setSemanticEnabled(value);
                        controller.update();
                      },
                      title: const Text('Show “possibly related” suggestions'),
                      subtitle: const Text(
                        'Compares words in your own content. These are suggestions, not a '
                        'confidence score, and image-only content cannot be understood this way.',
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.interests_outlined),
                    title: const Text('Your interests'),
                    subtitle: Obx(() => Text(controller.interestsSummary)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => controller.editInterests(context),
                  ),
                ],
              ),
              SizedBox(height: 14.h),
              _Section(
                title: 'Data',
                children: <Widget>[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.build_outlined),
                    title: const Text('Rebuild index and clean files'),
                    subtitle: const Text(
                      'Reindexes searchable text and removes orphaned files. Nothing else is deleted.',
                    ),
                    trailing: controller.maintenanceBusy.value
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right_rounded),
                    onTap: controller.maintenanceBusy.value
                        ? null
                        : controller.runMaintenance,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.delete_forever_outlined,
                      color: AppColors.dangerFor(brightness),
                    ),
                    title: Text(
                      'Delete all memories',
                      style: TextStyle(color: AppColors.dangerFor(brightness)),
                    ),
                    subtitle: const Text(
                      'Removes every memory, image, recording, transcript, and embedding. '
                      'Installed speech models are kept.',
                    ),
                    onTap: () => controller.confirmDeleteAll(context),
                  ),
                ],
              ),
              Obx(() {
                final String message = controller.maintenanceMessage.value;
                if (message.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: EdgeInsets.only(top: 12.h),
                  child: PocketCard(
                    padding: EdgeInsets.all(14.r),
                    child: Row(
                      children: <Widget>[
                        const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            message,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              SizedBox(height: 20.h),
              Text(
                'MindPocket 1.0.0 · Android',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              SizedBox(height: 4.h),
              Text(
                'No account. No analytics. No uploads without your action.',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return PocketCard(
      padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.4,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary(brightness),
            ),
          ),
          SizedBox(height: 6.h),
          ...children,
        ],
      ),
    );
  }
}

class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final String current = controller.currentThemeMode.name;
      const List<(String, ThemeMode, IconData)> options =
          <(String, ThemeMode, IconData)>[
            ('System', ThemeMode.system, Icons.brightness_auto_outlined),
            ('Light', ThemeMode.light, Icons.light_mode_outlined),
            ('Dark', ThemeMode.dark, Icons.dark_mode_outlined),
          ];
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 4.h),
        child: Row(
          children: <Widget>[
            for (final (String label, ThemeMode mode, IconData icon) in options)
              Padding(
                padding: EdgeInsets.only(right: 8.w),
                child: PocketChip(
                  label: label,
                  leading: Icon(icon),
                  selected: current == mode.name,
                  onTap: () => controller.setTheme(mode.name),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _StorageBar extends StatelessWidget {
  const _StorageBar({required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final int total = controller.totalBytes.value;
    double ratio(int value) => total == 0 ? 0 : value / total;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 10,
        child: Row(
          children: <Widget>[
            if (total == 0)
              Expanded(child: ColoredBox(color: AppColors.raised(brightness)))
            else ...<Widget>[
              Expanded(
                flex: (ratio(controller.imageBytes.value) * 1000).round().clamp(
                  1,
                  1000,
                ),
                child: ColoredBox(color: AppColors.accent(brightness)),
              ),
              Expanded(
                flex: (ratio(controller.audioBytes.value) * 1000).round().clamp(
                  1,
                  1000,
                ),
                child: ColoredBox(color: AppColors.highlight(brightness)),
              ),
              Expanded(
                flex: (ratio(controller.modelBytes.value) * 1000).round().clamp(
                  1,
                  1000,
                ),
                child: ColoredBox(color: AppColors.textSecondary(brightness)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Model list page with honest download, verification, and removal controls.
class ModelsPage extends GetView<ModelsController> {
  const ModelsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Speech models'),
        leading: IconButton(
          onPressed: () => Get.back(),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 32.h),
        children: <Widget>[
          Text(
            'Transcription runs offline with sherpa-onnx and Whisper. '
            'Install a model once; after that, airplane mode is fine.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          SizedBox(height: 6.h),
          Text(
            'Downloads are verified against published SHA-256 checksums. '
            'Cancelling leaves no partial files behind.',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          SizedBox(height: 16.h),
          // Feedback for "Verify files" and downloads belongs above the cards:
          // below them it lands off-screen and the action looks dead.
          Obx(() {
            final String notice = controller.notice.value;
            final String error = controller.error.value;
            if (notice.isEmpty && error.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: ErrorBlock(
                message: error.isNotEmpty ? error : notice,
                onRetry: null,
              ),
            );
          }),
          // _ModelCard owns its own Obx: wrapping it here would evaluate no
          // observable in this scope and GetX would reject the builder.
          for (final ModelSpec spec in modelCatalog)
            Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: _ModelCard(controller: controller, spec: spec),
            ),
          SizedBox(height: 12.h),
          Text('Licences', style: Theme.of(context).textTheme.titleSmall),
          SizedBox(height: 6.h),
          Text(
            ModelsController.licences(),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          SizedBox(height: 6.h),
          Obx(
            () => Text(
              'Device storage: ${controller.storageSummary} used by installed models.',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: AppColors.textSecondary(brightness)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.controller, required this.spec});

  final ModelsController controller;
  final ModelSpec spec;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    // The statuses/progress/active reads must happen inside the Obx callback
    // below: building the card from an outer Obx would evaluate these in this
    // widget's own build, where GetX cannot attribute a dependency to it.
    return Obx(() {
      final ModelStatus status =
          controller.manager.statuses[spec.id] ?? ModelStatus.notDownloaded;
      final double progress = controller.manager.progress[spec.id] ?? 0;
      final bool active = controller.manager.activeModelId == spec.id;
      final bool busy = controller.manager.isBusy;
      return PocketCard(
        padding: EdgeInsets.all(16.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    spec.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (active && status == ModelStatus.ready)
                  StatusBadge(
                    label: 'Active',
                    color: AppColors.accentText(brightness),
                    icon: Icons.check_circle_outline_rounded,
                  ),
              ],
            ),
            SizedBox(height: 4.h),
            Text(
              spec.description,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SizedBox(height: 8.h),
            Text(
              ModelsController.requirementText(spec),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            SizedBox(height: 10.h),
            switch (status) {
              ModelStatus.ready => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(
                        Icons.verified_outlined,
                        size: 16,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Installed and verified',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                  SizedBox(height: 8.h),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      if (!active)
                        FilledButton(
                          onPressed: () => controller.setActive(spec),
                          child: const Text('Use this model'),
                        ),
                      OutlinedButton(
                        onPressed: controller.verifying.value
                            ? null
                            : () => controller.verify(spec),
                        child: Text(
                          controller.verifying.value
                              ? 'Verifying…'
                              : 'Verify files',
                        ),
                      ),
                      TextButton(
                        onPressed: () => _confirmRemove(context),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                ],
              ),
              ModelStatus.downloading || ModelStatus.verifying => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  linearProgress(context, progress),
                  SizedBox(height: 6.h),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          status == ModelStatus.verifying
                              ? 'Checking integrity…'
                              : 'Downloading ${Format.progress(progress)}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                      TextButton(
                        onPressed: controller.cancel,
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ],
              ),
              _ => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(height: 2.h),
                  FilledButton.icon(
                    onPressed: busy ? null : () => controller.download(spec),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Download for offline use'),
                  ),
                  if (status == ModelStatus.corrupt) ...<Widget>[
                    SizedBox(height: 6.h),
                    Text(
                      'The last download failed its integrity check and was discarded.',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: AppColors.dangerFor(brightness)),
                    ),
                  ],
                ],
              ),
            },
          ],
        ),
      );
    });
  }

  Widget linearProgress(BuildContext context, double progress) => ClipRRect(
    borderRadius: BorderRadius.circular(999),
    child: LinearProgressIndicator(
      value: progress == 0 ? null : progress,
      minHeight: 6,
    ),
  );

  Future<void> _confirmRemove(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Remove this model?'),
        content: const Text(
          'Future recordings will not be transcribed until a model is installed again. '
          'Existing recordings and transcripts are untouched.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.remove(spec);
  }
}

/// Cloud backend configuration page. No provider key fields, because keys in an
/// APK cannot be protected.
class CloudSettingsPage extends GetView<CloudSettingsController> {
  const CloudSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final TextEditingController url = TextEditingController(
      text: controller.baseUrl.value,
    );
    final TextEditingController token = TextEditingController();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloud analysis'),
        leading: IconButton(
          onPressed: () => Get.back(),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 32.h),
        children: <Widget>[
          PocketCard(
            padding: EdgeInsets.all(16.r),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'How this works',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                SizedBox(height: 6.h),
                Text(
                  'MindPocket never ships an AI provider key. Keys embedded in an APK can be '
                  'extracted, and local secure storage would only protect a key that was already '
                  'shipped. Instead, point MindPocket at your own backend that holds the key.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                SizedBox(height: 8.h),
                Text(
                  'The backend receives only what you confirm in the analysis sheet: the note, '
                  'extracted text, transcript, tags, and — only if you tick it — the images. '
                  'Imported content is sent as data, never as instructions.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          SizedBox(height: 16.h),
          TextField(
            controller: url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Backend URL',
              hintText: 'https://your-backend.example.com/analyse',
            ),
            onSubmitted: controller.saveUrl,
          ),
          SizedBox(height: 10.h),
          TextField(
            controller: token,
            obscureText: true,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Bearer token (optional)',
              hintText: 'Stored in the device keystore',
            ),
          ),
          SizedBox(height: 12.h),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton(
                onPressed: () => controller.saveUrl(url.text),
                child: const Text('Save URL'),
              ),
              OutlinedButton(
                onPressed: () => controller.saveToken(token.text),
                child: const Text('Save token'),
              ),
              OutlinedButton(
                onPressed: controller.testing.value
                    ? null
                    : controller.testConnection,
                child: Text(
                  controller.testing.value ? 'Testing…' : 'Send test request',
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Obx(() {
            final Brightness brightness = Theme.of(context).brightness;
            final String result = controller.testResult.value;
            if (result.isEmpty) return const SizedBox.shrink();
            return PocketCard(
              padding: EdgeInsets.all(14.r),
              color:
                  (controller.testSucceeded.value
                          ? AppColors.success
                          : AppColors.dangerFor(brightness))
                      .withValues(alpha: 0.08),
              child: Row(
                children: <Widget>[
                  Icon(
                    controller.testSucceeded.value
                        ? Icons.check_circle_outline_rounded
                        : Icons.error_outline_rounded,
                    size: 18,
                    color: controller.testSucceeded.value
                        ? AppColors.success
                        : AppColors.dangerFor(brightness),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      result,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            );
          }),
          SizedBox(height: 16.h),
          Text(
            'Without a backend, everything except cloud analysis still works: capture, '
            'OCR, offline transcription, and search.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Short, honest relative time for the last import.
String _ago(DateTime when) {
  final Duration delta = DateTime.now().difference(when);
  if (delta.inMinutes < 1) return 'just now';
  if (delta.inMinutes < 60) return '${delta.inMinutes} min ago';
  if (delta.inHours < 24) return '${delta.inHours} h ago';
  return '${delta.inDays} d ago';
}

/// Edits the NIM endpoint. The key field starts empty every time, so a stored
/// key is never displayed back.
Future<void> _editNim(BuildContext context, SettingsController controller) =>
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) =>
          _NimDialog(controller: controller),
    );

class _NimDialog extends StatefulWidget {
  const _NimDialog({required this.controller});

  final SettingsController controller;

  @override
  State<_NimDialog> createState() => _NimDialogState();
}

class _NimDialogState extends State<_NimDialog> {
  late final TextEditingController _base = TextEditingController(
    text: widget.controller.nimBaseUrl.value,
  );
  late final TextEditingController _model = TextEditingController(
    text: widget.controller.nimModel.value,
  );
  final TextEditingController _key = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    // Owned here, so they are torn down before the route that references them
    // goes away (disposing earlier trips a framework assertion).
    _base.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.controller.saveNimSettings(
      baseUrl: _base.text,
      model: _model.text,
      key: _key.text,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final SettingsController controller = widget.controller;
    return AlertDialog(
      title: const Text('NVIDIA NIM'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _base,
              decoration: const InputDecoration(labelText: 'Base URL'),
            ),
            SizedBox(height: 8.h),
            TextField(
              controller: _model,
              decoration: const InputDecoration(labelText: 'Model'),
            ),
            SizedBox(height: 8.h),
            TextField(
              controller: _key,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'API key',
                hintText: controller.nimHasKey.value
                    ? 'Stored — leave blank to keep'
                    : 'nvapi-…',
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
