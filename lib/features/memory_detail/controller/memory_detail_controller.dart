import 'dart:async';
import 'dart:io';

// Private fields cannot be initializing formals for public named parameters.
// ignore_for_file: prefer_initializing_formals

import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/search_dao.dart';
import '../../../core/models/attachment.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/memory.dart';
import '../../../core/services/ai/model_catalog.dart';
import '../../../core/services/ai/model_manager.dart';
import '../../../core/services/processing/processing_contracts.dart';
import '../../../core/services/ai/related_service.dart';
import '../../../core/services/processing/processing_service.dart';
import '../../../core/services/processing/share_intake_service.dart';
import '../../../core/services/storage/memory_service.dart';
import '../../../core/services/storage/preferences_service.dart';
import '../../../core/utils/logger.dart';

/// Detail state for one memory: editing, attachments, tags, collections,
/// processing, related suggestions, and deletion.
class MemoryDetailController extends GetxController {
  MemoryDetailController({
    required this.memoryId,
    required MemoryService memories,
    required ProcessingService processing,
    required ShareIntakeService shares,
    required RelatedService related,
    required AppDatabase database,
    required PreferencesService preferences,
    required SpeechModelProvider models,
  }) : _memories = memories,
       _processing = processing,
       _shares = shares,
       _related = related,
       _database = database,
       _preferences = preferences,
       _models = models;

  final String memoryId;
  final MemoryService _memories;
  final ProcessingService _processing;
  final ShareIntakeService _shares;
  final RelatedService _related;
  final AppDatabase _database;
  final PreferencesService _preferences;
  final SpeechModelProvider _models;

  final Rxn<Memory> memory = Rxn<Memory>();
  final RxBool loading = true.obs;
  final RxString error = ''.obs;
  final RxList<ProcessingJob> jobs = <ProcessingJob>[].obs;
  final RxList<RelatedSuggestion> related = <RelatedSuggestion>[].obs;
  final RxString relatedLabel = ''.obs;
  final Rx<RelatedReference> relatedKind = RelatedReference.memory.obs;
  final RxString banner = ''.obs;
  final RxBool busy = false.obs;
  final RxList<Collection> allCollections = <Collection>[].obs;
  final RxSet<String> selectedCollections = <String>{}.obs;
  final Rxn<AiSuggestion> suggestion = Rxn<AiSuggestion>();

  // Edit buffers, committed explicitly so typing never writes to SQLite.
  final RxString draftTitle = ''.obs;
  final RxString draftNote = ''.obs;
  final RxBool dirty = false.obs;

  Worker? _revisionWorker;

  @override
  void onInit() {
    super.onInit();
    _revisionWorker = ever<int>(
      _memories.revision,
      (int _) => load(silent: true),
    );
    load();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) loading.value = true;
    error.value = '';
    try {
      final Memory? value = await _memories.findById(memoryId);
      if (value == null) {
        error.value = 'This memory no longer exists. It may have been deleted.';
        memory.value = null;
        return;
      }
      memory.value = value;
      if (!dirty.value) {
        draftTitle.value = value.title;
        draftNote.value = value.note;
      }
      jobs.assignAll(await _processing.jobsFor(memoryId));
      final TaxonomyDao taxonomy = TaxonomyDao(_database);
      allCollections.assignAll(await taxonomy.collections());
      selectedCollections.assignAll(await taxonomy.collectionIdsFor(memoryId));
      suggestion.value = await SuggestionDao(_database).latestFor(memoryId);
      await _loadRelated(value);
    } catch (exception, stack) {
      logError('Memory detail load failed', exception, stack);
      error.value = 'This memory could not be opened. Try again.';
    } finally {
      loading.value = false;
    }
  }

  Future<void> _loadRelated(Memory value) async {
    final List<RelatedSuggestion> suggestions = await _related.forMemory(value);
    final Set<String> dismissed = await _related.dismissedIds(
      memoryId,
      RelatedReference.memory,
    );
    related.assignAll(
      suggestions.where(
        (RelatedSuggestion s) => !dismissed.contains(s.memory.id),
      ),
    );
    relatedLabel.value = value.title.isEmpty ? 'this memory' : value.title;
    relatedKind.value = RelatedReference.memory;
  }

  Future<void> dismissRelated(RelatedSuggestion suggestion) async {
    related.removeWhere(
      (RelatedSuggestion item) => item.memory.id == suggestion.memory.id,
    );
    await _related.dismiss(suggestion.memory.id, suggestion);
  }

  void editTitle(String value) {
    draftTitle.value = value;
    dirty.value =
        value.trim() != (memory.value?.title ?? '') ||
        draftNote.value.trim() != (memory.value?.note ?? '');
  }

  void editNote(String value) {
    draftNote.value = value;
    dirty.value =
        value.trim() != (memory.value?.note ?? '') ||
        draftTitle.value.trim() != (memory.value?.title ?? '');
  }

  Future<bool> saveEdits() async {
    if (!dirty.value) return true;
    busy.value = true;
    try {
      await _memories.updateText(
        memoryId: memoryId,
        title: draftTitle.value,
        note: draftNote.value,
      );
      dirty.value = false;
      await load(silent: true);
      return true;
    } catch (exception) {
      logError('Saving edit failed', exception);
      banner.value = 'Those changes could not be saved.';
      return false;
    } finally {
      busy.value = false;
    }
  }

  Future<void> toggleFavorite() async {
    final Memory? value = memory.value;
    if (value == null) return;
    await _memories.toggleFavorite(memoryId, !value.favorite);
  }

  Future<void> addTags(List<String> tags) async {
    final Memory? value = memory.value;
    if (value == null || tags.isEmpty) return;
    final List<String> merged = <String>{...value.tags, ...tags}.toList();
    await _memories.setTags(memoryId, merged);
    await load(silent: true);
  }

  Future<void> removeTag(String tag) async {
    final Memory? value = memory.value;
    if (value == null) return;
    await _memories.setTags(
      memoryId,
      value.tags.where((String t) => t != tag).toList(),
    );
    await load(silent: true);
  }

  Future<void> setCollections(Set<String> ids) async {
    busy.value = true;
    try {
      await _memories.setCollections(memoryId, ids);
      selectedCollections.assignAll(ids);
      await load(silent: true);
    } finally {
      busy.value = false;
    }
  }

  Future<Collection?> createCollection(String name) async {
    try {
      final Collection collection = await TaxonomyDao(_database)
          .createCollection(name.trim());
      await load(silent: true);
      return collection;
    } catch (exception) {
      banner.value = 'A collection named “${name.trim()}” already exists.';
      return null;
    }
  }

  Future<void> addImageAttachment() async {
    try {
      final List<File> files = await _shares.pickImages();
      if (files.isEmpty) return;
      busy.value = true;
      for (final File file in files) {
        final Attachment? attachment = await _memories.attachImageToMemory(
          memoryId,
          source: file,
        );
        if (attachment == null) {
          banner.value = 'That image is already attached to another memory.';
        }
      }
      _processing.schedule();
      await load(silent: true);
    } catch (exception) {
      banner.value = exception.toString();
    } finally {
      busy.value = false;
    }
  }

  Future<void> removeAttachment(Attachment attachment) async {
    await _memories.removeAttachment(attachment);
    await load(silent: true);
  }

  Future<void> saveTranscriptionEdit(String extractionId, String text) async {
    await _memories.saveExtractionEdit(
      extractionId: extractionId,
      editedText: text,
    );
    await load(silent: true);
  }

  Future<void> revertTranscriptionEdit(String extractionId) async {
    await _memories.revertExtractionEdit(extractionId);
    await load(silent: true);
  }

  Future<void> retry(JobType type, {String? attachmentId}) async {
    await _memories.retryJob(memoryId, type, attachmentId: attachmentId);
    _processing.schedule();
    banner.value = '${type.label} queued again.';
    await load(silent: true);
  }

  Future<void> retryAllFailed() async {
    final int count = await _processing.retryFailedFor(memoryId);
    if (count == 0) {
      banner.value = 'Nothing failed for this memory.';
    } else {
      _processing.schedule();
      banner.value = 'Retrying $count job${count == 1 ? '' : 's'}.';
    }
    await load(silent: true);
  }

  Future<void> cancelJob(ProcessingJob job) async {
    await _processing.cancelJob(job.id);
    await load(silent: true);
  }

  Future<bool> deleteMemory() async {
    await _memories.deleteMemory(memoryId);
    return true;
  }

  void openCollection(String collectionId) =>
      Get.toNamed(AppRoutes.collection(collectionId));

  bool get transcriptionEnabled => _preferences.transcribeAuto;

  /// Whether a transcript can be produced at all: transcription must be
  /// enabled and a speech model must be installed. Without this the queue
  /// parks the job, and the UI has to say why instead of showing "queued"
  /// forever.
  bool get transcriptionPossible {
    if (!_preferences.transcribeAuto) return false;
    final ModelSpec? spec = _models.activeModel;
    return spec != null && _models.isReady(spec.id);
  }

  /// Installs the missing speech model, then resumes the parked queue.
  void openModels() => Get.toNamed(AppRoutes.models);

  @override
  void onClose() {
    _revisionWorker?.dispose();
    super.onClose();
  }

  /// Builds the controller from the DI container plus the current route.
  static MemoryDetailController fromEnvironment(String memoryId) =>
      MemoryDetailController(
        memoryId: memoryId,
        memories: Get.find<MemoryService>(),
        processing: Get.find<ProcessingService>(),
        shares: Get.find<ShareIntakeService>(),
        related: Get.find<RelatedService>(),
        database: Get.find<AppDatabase>(),
        preferences: Get.find<PreferencesService>(),
        models: ModelManagerProvider(Get.find<ModelManager>()),
      );
}

/// Helper to open a memory route with a scoped controller.
class MemoryDetailBinding extends Bindings {
  MemoryDetailBinding(this.memoryId);

  final String memoryId;

  @override
  void dependencies() {
    Get.put<MemoryDetailController>(
      MemoryDetailController(
        memoryId: memoryId,
        memories: Get.find<MemoryService>(),
        processing: Get.find<ProcessingService>(),
        shares: Get.find<ShareIntakeService>(),
        related: Get.find<RelatedService>(),
        database: Get.find<AppDatabase>(),
        preferences: Get.find<PreferencesService>(),
        models: ModelManagerProvider(Get.find<ModelManager>()),
      ),
    );
  }
}

/// Shared tag suggestions from existing tags.
Future<List<Tag>> suggestTags(AppDatabase database) =>
    TaxonomyDao(database).allTags();

/// Triggers related lookups for a search query on the search page.
extension RelatedForQuery on RelatedService {
  Future<List<RelatedSuggestion>> query(String value) => forQuery(value);
}
