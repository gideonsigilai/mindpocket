import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/search_dao.dart';
import '../../../core/models/attachment.dart';
import '../../../core/models/memory.dart';
import '../../../core/services/ai/related_service.dart';
import '../../../core/services/storage/memory_service.dart';
import '../../../core/utils/logger.dart';

/// Collections overview and detail.
// ignore_for_file: prefer_initializing_formals
class CollectionsController extends GetxController {
  CollectionsController(this._database, this._memories);

  final AppDatabase _database;
  final MemoryService _memories;

  final RxList<Collection> collections = <Collection>[].obs;
  final RxBool loading = true.obs;
  final RxString error = ''.obs;
  final RxList<TagCount> tags = <TagCount>[].obs;
  final RxString selectedTag = ''.obs;
  final RxList<Memory> tagResults = <Memory>[].obs;

  Worker? _revisionWorker;

  @override
  void onInit() {
    super.onInit();
    // Collections are also created by the screenshot importer, long after this
    // page was built; without this the list would stay empty.
    _revisionWorker = ever<int>(_memories.revision, (int _) => load());
    load();
  }

  @override
  void onClose() {
    _revisionWorker?.dispose();
    super.onClose();
  }

  Future<void> load() async {
    loading.value = true;
    error.value = '';
    try {
      collections.assignAll(await TaxonomyDao(_database).collections());
      tags.assignAll(await _memories.tagCounts());
    } catch (exception, stack) {
      logError('Collections load failed', exception, stack);
      error.value = 'Collections could not be loaded.';
    } finally {
      loading.value = false;
    }
  }

  Future<Collection?> create(String name, {String description = ''}) async {
    if (name.trim().isEmpty) return null;
    try {
      final Collection collection = await TaxonomyDao(_database)
          .createCollection(name, description: description);
      await load();
      return collection;
    } catch (exception) {
      error.value = 'A collection named “${name.trim()}” already exists.';
      return null;
    }
  }

  Future<void> rename(
    Collection collection,
    String name,
    String description,
  ) async {
    if (name.trim().isEmpty) return;
    await TaxonomyDao(_database).updateCollection(
      collection.copyWith(name: name.trim(), description: description.trim()),
    );
    await load();
  }

  Future<void> remove(Collection collection) async {
    await TaxonomyDao(_database).deleteCollection(collection.id);
    await load();
  }

  Future<void> selectTag(String tag) async {
    if (selectedTag.value == tag) {
      selectedTag.value = '';
      tagResults.clear();
      return;
    }
    selectedTag.value = tag;
    tagResults.assignAll(await _memories.timeline(tagName: tag, limit: 100));
  }

  void open(Collection collection) =>
      Get.toNamed(AppRoutes.collection(collection.id));
  void openMemory(String id) => Get.toNamed(AppRoutes.memory(id));

  @override
  Future<void> refresh() => load();
}

/// One collection: its memories plus explicit related suggestions.
class CollectionDetailController extends GetxController {
  CollectionDetailController({
    required this.collectionId,
    required AppDatabase database,
    required MemoryService memories,
    required RelatedService related,
  }) : _database = database,
       _memories = memories,
       _related = related;

  final String collectionId;
  final AppDatabase _database;
  final MemoryService _memories;
  final RelatedService _related;

  final Rxn<Collection> collection = Rxn<Collection>();
  final RxList<Memory> memories = <Memory>[].obs;
  final RxList<RelatedSuggestion> related = <RelatedSuggestion>[].obs;
  final RxBool loading = true.obs;
  final RxString error = ''.obs;

  Worker? _revisionWorker;

  @override
  void onInit() {
    super.onInit();
    // Collections are also created by the screenshot importer, long after this
    // page was built; without this the list would stay empty.
    _revisionWorker = ever<int>(_memories.revision, (int _) => load());
    load();
  }

  @override
  void onClose() {
    _revisionWorker?.dispose();
    super.onClose();
  }

  Future<void> load() async {
    loading.value = true;
    error.value = '';
    try {
      final List<Collection> all = await TaxonomyDao(_database).collections();
      collection.value = all
          .where((Collection c) => c.id == collectionId)
          .firstOrNull;
      if (collection.value == null) {
        error.value = 'This collection no longer exists.';
        memories.clear();
        return;
      }
      memories.assignAll(
        await _memories.timeline(collectionId: collectionId, limit: 100),
      );
      final List<RelatedSuggestion> suggestions = await _related.forCollection(
        collection.value!,
      );
      final Set<String> dismissed = await _related.dismissedIds(
        collectionId,
        RelatedReference.collection,
      );
      related.assignAll(
        suggestions.where(
          (RelatedSuggestion s) => !dismissed.contains(s.memory.id),
        ),
      );
    } catch (exception, stack) {
      logError('Collection detail failed', exception, stack);
      error.value = 'This collection could not be opened.';
    } finally {
      loading.value = false;
    }
  }

  Future<void> removeMemory(Memory memory) async {
    await _memories.setCollections(
      memory.id,
      await TaxonomyDao(_database).collectionIdsFor(memory.id)
        ..remove(collectionId),
    );
    await load();
  }

  Future<void> addMemory(Memory memory) async {
    await TaxonomyDao(_database).addToCollection(collectionId, memory.id);
    await load();
  }

  Future<void> dismiss(RelatedSuggestion suggestion) async {
    related.removeWhere(
      (RelatedSuggestion s) => s.memory.id == suggestion.memory.id,
    );
    await _related.dismiss(suggestion.memory.id, suggestion);
  }

  void openMemory(String id) => Get.toNamed(AppRoutes.memory(id));

  static CollectionDetailController fromEnvironment(String collectionId) =>
      CollectionDetailController(
        collectionId: collectionId,
        database: Get.find<AppDatabase>(),
        memories: Get.find<MemoryService>(),
        related: Get.find<RelatedService>(),
      );
}
