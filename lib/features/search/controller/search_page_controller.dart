import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/models/memory.dart';
import '../../../core/services/ai/related_service.dart';
import '../../../core/services/storage/memory_service.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/text_utils.dart';

/// Search state with debouncing, snippet results, and explicit related
/// suggestions tied to the typed query.
class SearchPageController extends GetxController {
  SearchPageController(this._memories, this._related);

  final MemoryService _memories;
  final RelatedService _related;

  final RxString query = ''.obs;
  final RxList<SearchHit> results = <SearchHit>[].obs;
  final RxBool searching = false.obs;
  final RxBool hasSearched = false.obs;
  final RxString error = ''.obs;
  final RxList<RelatedSuggestion> related = <RelatedSuggestion>[].obs;
  final RxString relatedReference = ''.obs;

  final Debouncer _debouncer = Debouncer(const Duration(milliseconds: 280));
  final List<Worker> _workers = <Worker>[];
  int _generation = 0;

  @override
  void onInit() {
    super.onInit();
    _workers.add(
      ever<String>(query, (String value) {
        _debouncer.run(() => run(value));
      }),
    );
  }

  void setQuery(String value) {
    if (query.value == value) return;
    _generation++;
    query.value = value;
  }

  Future<void> run(String raw) async {
    final int generation = ++_generation;
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      results.clear();
      related.clear();
      hasSearched.value = false;
      searching.value = false;
      return;
    }
    searching.value = true;
    error.value = '';
    try {
      final List<SearchHit> hits = await _memories.search(trimmed);
      if (generation != _generation) return;
      results.assignAll(hits);
      hasSearched.value = true;
      relatedReference.value = trimmed;
      final List<RelatedSuggestion> suggestions = await _related.forQuery(
        trimmed,
        limit: 4,
      );
      if (generation != _generation) return;
      final Set<String> hitIds = hits.map((SearchHit h) => h.memory.id).toSet();
      related.assignAll(
        suggestions.where(
          (RelatedSuggestion s) => !hitIds.contains(s.memory.id),
        ),
      );
    } catch (exception, stack) {
      if (generation != _generation) return;
      logError('Search failed', exception, stack);
      error.value = 'Search could not run. Try a different word.';
    } finally {
      if (generation == _generation) searching.value = false;
    }
  }

  void clear() {
    _generation++;
    query.value = '';
    results.clear();
    related.clear();
    hasSearched.value = false;
    _debouncer.cancel();
    searching.value = false;
    error.value = '';
    relatedReference.value = '';
  }

  /// Retries the current query without waiting for the debounce.
  Future<void> retry() => run(query.value);

  void open(String memoryId) => Get.toNamed(AppRoutes.memory(memoryId));

  /// Dismisses a related suggestion for the current query.
  Future<void> dismiss(RelatedSuggestion suggestion) async {
    related.removeWhere(
      (RelatedSuggestion s) => s.memory.id == suggestion.memory.id,
    );
    await _related.dismiss(
      suggestion.memory.id,
      RelatedSuggestion(
        memory: suggestion.memory,
        sharedTerms: suggestion.sharedTerms,
        referenceLabel: suggestion.referenceLabel,
        referenceKind: RelatedReference.query,
      ),
    );
  }

  @override
  void onClose() {
    _generation++;
    _debouncer.dispose();
    for (final Worker worker in _workers) {
      worker.dispose();
    }
    super.onClose();
  }
}
