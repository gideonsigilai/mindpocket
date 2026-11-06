import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/services/ai/nim_grouping_provider.dart';
import '../../../core/services/ai/nim_key_store.dart';
import '../../../core/services/screenshots/screenshot_autopilot.dart';
import '../../../core/services/screenshots/screenshot_sync_service.dart';

import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/controllers/app_settings_controller.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/search_dao.dart';
import '../../../core/models/attachment.dart';
import '../../../core/services/ai/model_catalog.dart';
import '../../../core/services/ai/model_manager.dart';
import '../../../core/services/storage/memory_service.dart';
import '../../../core/services/storage/preferences_service.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/logger.dart';

class SettingsController extends GetxController {
  SettingsController(
    this._preferences,
    this._models,
    this._memories,
    this._database,
  );

  final PreferencesService _preferences;
  final ModelManager _models;
  final MemoryService _memories;
  final AppDatabase _database;

  final RxBool storageLoading = true.obs;
  final RxInt totalBytes = 0.obs;
  final RxInt imageBytes = 0.obs;
  final RxInt audioBytes = 0.obs;
  final RxInt modelBytes = 0.obs;
  final RxInt attachmentCount = 0.obs;
  final RxInt memoryCount = 0.obs;
  final RxString maintenanceMessage = ''.obs;
  final RxBool maintenanceBusy = false.obs;

  PreferencesService get preferences => _preferences;

  // ---- Screenshot import and AI grouping -----------------------------------

  final RxBool syncing = false.obs;
  final RxString syncStatus = ''.obs;
  final RxInt syncProgress = 0.obs;
  final RxInt syncTotal = 0.obs;
  final Rxn<DateTime> lastScreenshotSync = Rxn<DateTime>();
  final RxBool hasScreenshotAccess = false.obs;
  late final RxBool autoImport = _preferences.screenshotAutoImport.obs;

  Future<void> setAutoImport(bool value) async {
    await _preferences.setScreenshotAutoImport(value);
    autoImport.value = value;
  }

  ScreenshotSyncService? get screenshots =>
      Get.isRegistered<ScreenshotSyncService>()
      ? Get.find<ScreenshotSyncService>()
      : null;

  /// NIM settings are kept in reactive mirrors so the fields and switches
  /// update on edit instead of showing stale values.
  late final RxString nimBaseUrl = _preferences.nimBaseUrl.obs;
  late final RxString nimModel = _preferences.nimModel.obs;
  late final RxBool nimHasKey = false.obs;
  final NimKeyStore _nimKeys = NimKeyStore();

  Future<void> _loadNimKeyFlag() async {
    nimHasKey.value = await _nimKeys.hasKey();
  }

  Future<void> loadScreenshotState() async {
    final ScreenshotSyncService? service = screenshots;
    if (service == null) return;
    hasScreenshotAccess.value = await service.hasPermission();
    lastScreenshotSync.value = await service.lastSyncedAt();
  }

  Future<void> requestScreenshotAccess() async {
    final ScreenshotSyncService? service = screenshots;
    if (service == null) return;
    hasScreenshotAccess.value = await service.requestPermission();
    if (!hasScreenshotAccess.value) {
      syncStatus.value =
          'Screenshot access was declined. You can grant it later '
          'in your device settings; nothing is imported until you do.';
    }
  }

  /// Imports new screenshots and groups them with the configured AI backend.
  Future<void> importScreenshots({bool full = false}) async {
    final ScreenshotSyncService? service = screenshots;
    if (service == null || syncing.value) return;
    if (!hasScreenshotAccess.value) {
      await requestScreenshotAccess();
      if (!hasScreenshotAccess.value) return;
    }
    syncing.value = true;
    syncStatus.value = full
        ? 'Scanning every screenshot'
        : 'Looking for new screenshots';
    try {
      final GroupingProvider? provider = await groupingProvider();
      final ScreenshotSyncResult result = await service.sync(
        full: full,
        grouping: provider,
      );
      syncStatus.value = result.summary(fullScan: full);
      if (result.imported > 0) _memories.revision.value++;
      lastScreenshotSync.value = await service.lastSyncedAt();
      if (full && result.completed) {
        await _preferences.markScreenshotFirstRunDone();
      }
    } finally {
      syncing.value = false;
    }
  }

  /// Built from current settings, so a changed key applies without a restart.
  Future<GroupingProvider?> groupingProvider() async {
    final String? key = await _nimKeys.read();
    if (key == null || !_preferences.nimConfigured) return null;
    return NimGroupingProvider(
      baseUrl: _preferences.nimBaseUrl,
      apiKey: key,
      model: _preferences.nimModel,
    );
  }

  /// Sorts what is already in the collection, for a key added after import.
  Future<void> organiseNow() async {
    final ScreenshotSyncService? service = screenshots;
    if (service == null || syncing.value) return;
    final GroupingProvider? provider = await groupingProvider();
    if (provider == null) {
      syncStatus.value = 'Add an NVIDIA NIM key first; grouping needs it.';
      return;
    }
    syncing.value = true;
    syncStatus.value = 'Sorting your screenshots into collections';
    try {
      final GroupOutcome outcome = await service.organiseExisting(
        provider: provider,
      );
      syncStatus.value = outcome.collections == 0
          ? 'Nothing to sort yet — imported screenshots are grouped once their text is read.'
          : 'Grouped ${outcome.collections} items; ${outcome.created} new collections.';
    } on GroupingException catch (error) {
      syncStatus.value = error.message;
    } finally {
      syncing.value = false;
    }
  }

  Future<void> saveNimSettings({
    required String baseUrl,
    required String model,
    required String key,
  }) async {
    await _preferences.setNimBaseUrl(baseUrl);
    await _preferences.setNimModel(model);
    if (key.trim().isNotEmpty) await _nimKeys.write(key);
    nimBaseUrl.value = _preferences.nimBaseUrl;
    nimModel.value = _preferences.nimModel;
    nimHasKey.value = await _nimKeys.hasKey();
    syncStatus.value = nimHasKey.value
        ? 'AI grouping is configured.'
        : 'Add a key to enable AI grouping.';
  }

  ModelManager get models => _models;

  /// Theme mode lives in the app-level settings service so a change repaints
  /// immediately; this mirrors it for the picker.
  ThemeMode get currentThemeMode =>
      Get.find<AppSettingsController>().themeMode.value;
  Future<void> setTheme(String name) =>
      Get.find<AppSettingsController>().setThemeMode(
        ThemeMode.values.firstWhere((ThemeMode mode) => mode.name == name),
      );

  bool? get reduceMotionOverride => _preferences.reducedMotionOverride;
  Future<void> setReducedMotion(bool value) =>
      Get.find<AppSettingsController>().setReduceMotion(value);

  String get modelSummary {
    final ModelManager manager = _models;
    final ModelSpec? spec = manager.activeModel;
    if (spec == null) return 'No model installed — recordings stay playable';
    return manager.isReady(spec.id)
        ? '${spec.displayName} installed'
        : '${spec.displayName} not downloaded';
  }

  bool get cloudConfigured => _preferences.cloudBaseUrl.trim().isNotEmpty;
  String get cloudBaseUrl => _preferences.cloudBaseUrl;

  final RxList<String> interests = <String>[].obs;

  String get interestsSummary => interests.isEmpty
      ? 'None selected — tap to choose'
      : interests.join(', ');

  Future<void> loadInterests() async {
    interests.assignAll(await TaxonomyDao(_database).interests());
  }

  Future<void> editInterests(BuildContext context) async {
    final TextEditingController field = TextEditingController(
      text: interests.join(', '),
    );
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Your interests'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Used only to suggest possibly related memories. Separate them with commas.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: field,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'design, travel, reading',
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
            onPressed: () => Navigator.of(context).pop(field.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    interests.assignAll(
      result
          .split(',')
          .map((String value) => value.trim())
          .where((String value) => value.isNotEmpty)
          .toList(growable: false),
    );
    await TaxonomyDao(_database).setInterests(interests);
    update();
  }

  Future<void> confirmDeleteAll(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete all memories?'),
        content: const Text(
          'Every memory, image, recording, transcript, and embedding will be deleted from '
          'this device. Installed speech models stay. This cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (confirmed == true) await deleteAllMemories();
  }

  /// Reactive preference mirrors. Built once so the switches observe them
  /// instead of re-reading plain getters (which would never rebuild).
  late final SettingsToggles toggles = SettingsToggles(_preferences)..load();

  ThemeMode get themeMode => switch (_preferences.themeModeName) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Future<void> setThemeModeName(String name) =>
      _preferences.setThemeModeName(name);

  @override
  void onInit() {
    super.onInit();
    refreshStorage();
    loadInterests();
    loadScreenshotState();
    _loadNimKeyFlag();
    // The importer runs in the background; keep the panel honest when it does.
    if (Get.isRegistered<ScreenshotAutopilot>()) {
      ever<String>(Get.find<ScreenshotAutopilot>().message, (String _) {
        loadScreenshotState();
        refreshStorage();
      });
    }
  }

  /// Reloads derived values (used after toggles change).
  void reloadTotals() => refreshStorage();

  Future<void> refreshStorage() async {
    storageLoading.value = true;
    try {
      final List<Attachment> attachments = await _allAttachments();
      imageBytes.value = attachments
          .where((Attachment a) => a.isImage)
          .fold<int>(0, (int sum, Attachment a) => sum + a.byteSize);
      audioBytes.value = attachments
          .where((Attachment a) => a.isAudio)
          .fold<int>(0, (int sum, Attachment a) => sum + a.byteSize);
      modelBytes.value = await _models.diskUsage();
      totalBytes.value = imageBytes.value + audioBytes.value + modelBytes.value;
      attachmentCount.value = attachments.length;
      final List<Map<String, Object?>> rows = await _database.db.rawQuery(
        'SELECT COUNT(*) AS c FROM memories WHERE deleted_at IS NULL',
      );
      memoryCount.value = (rows.first['c'] as int?) ?? 0;
    } catch (exception, stack) {
      logError('Storage accounting failed', exception, stack);
      maintenanceMessage.value = 'Storage usage could not be measured.';
    } finally {
      storageLoading.value = false;
    }
  }

  Future<List<Attachment>> _allAttachments() async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'attachments',
    );
    return rows.map(Attachment.fromRow).toList(growable: false);
  }

  /// Cleans orphaned files, requeues interrupted jobs, and rebuilds the index.
  Future<void> runMaintenance() async {
    maintenanceBusy.value = true;
    maintenanceMessage.value = '';
    try {
      final int removed = await _memories.sweepOrphans();
      final int indexed = await _memories.reindex();
      await _models.init();
      maintenanceMessage.value = removed == 0
          ? 'Index rebuilt for $indexed memories. Nothing to clean up.'
          : 'Removed $removed orphaned file${removed == 1 ? '' : 's'} and rebuilt the index for $indexed memories.';
      await refreshStorage();
    } catch (exception, stack) {
      logError('Maintenance failed', exception, stack);
      maintenanceMessage.value =
          'Maintenance could not finish. Nothing was deleted.';
    } finally {
      maintenanceBusy.value = false;
    }
  }

  /// Deletes every memory and file but keeps installed speech models.
  Future<void> deleteAllMemories() async {
    maintenanceBusy.value = true;
    try {
      final List<Map<String, Object?>> rows = await _database.db.query(
        'memories',
        columns: <String>['id'],
      );
      for (final Map<String, Object?> row in rows) {
        await _memories.deleteMemory(row['id']! as String);
      }
      // Sweep anything left behind by interrupted imports, then rebuild the
      // (now empty) index so no stale rows survive.
      await _memories.sweepOrphans();
      await _memories.reindex();
      maintenanceMessage.value =
          'All memories deleted. Installed models were kept.';
      await refreshStorage();
    } catch (exception, stack) {
      logError('Delete all failed', exception, stack);
      maintenanceMessage.value =
          'Some memories could not be deleted. Try again.';
    } finally {
      maintenanceBusy.value = false;
    }
  }

  Future<void> removeModel(ModelSpec spec) async {
    await _models.remove(spec);
    await refreshStorage();
  }

  Future<String?> downloadModel(ModelSpec spec) async {
    final String? error = await _models.download(spec);
    await refreshStorage();
    return error;
  }

  void cancelDownload() => _models.cancelDownload();

  Future<void> setActiveModel(String id) => _models.setActive(id);

  void openModels() => Get.toNamed(AppRoutes.models);
  void openCloud() => Get.toNamed(AppRoutes.cloud);

  Future<void> setInterests(List<String> names) async {
    interests.assignAll(names);
    await TaxonomyDao(_database).setInterests(names);
  }

  String get storageSummary => Format.bytes(totalBytes.value);
}

/// Helper to expose model status reactively to the settings UI.
class ModelStatusView {
  const ModelStatusView({
    required this.spec,
    required this.status,
    required this.progress,
  });

  final ModelSpec spec;
  final ModelStatus status;
  final double progress;

  bool get ready => status == ModelStatus.ready;
  bool get downloading =>
      status == ModelStatus.downloading || status == ModelStatus.verifying;
}

/// Small helper used by the settings screen for the on-device preferences that
/// are simple booleans.
/// Reactive view over preference flags, so switches update the moment they are
/// tapped instead of showing a stale value until the next rebuild.
class SettingsToggles {
  SettingsToggles(this._preferences);

  final PreferencesService _preferences;

  final RxBool ocrAuto = false.obs;
  final RxBool transcribeAuto = false.obs;
  final RxBool cloudEnabled = false.obs;
  final RxBool semanticEnabled = false.obs;
  final RxBool interestsHintDismissed = false.obs;

  void load() {
    ocrAuto.value = _preferences.ocrAuto;
    transcribeAuto.value = _preferences.transcribeAuto;
    cloudEnabled.value = _preferences.cloudEnabled;
    semanticEnabled.value = _preferences.semanticEnabled;
    interestsHintDismissed.value = _preferences.interestsHintDismissed;
  }

  Future<void> setOcrAuto(bool value) async {
    ocrAuto.value = value;
    await _preferences.setOcrAuto(value);
  }

  Future<void> setTranscribeAuto(bool value) async {
    transcribeAuto.value = value;
    await _preferences.setTranscribeAuto(value);
  }

  Future<void> setCloudEnabled(bool value) async {
    cloudEnabled.value = value;
    await _preferences.setCloudEnabled(value);
  }

  Future<void> setSemanticEnabled(bool value) async {
    semanticEnabled.value = value;
    await _preferences.setSemanticEnabled(value);
  }

  Future<void> setInterestsDismissed() async {
    interestsHintDismissed.value = true;
    await _preferences.dismissInterestsHint();
  }
}
