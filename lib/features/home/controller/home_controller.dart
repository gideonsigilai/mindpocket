import 'package:get/get.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/memory_dao.dart';
import '../../../core/models/memory.dart';
import '../../../core/services/processing/processing_service.dart';
import '../../../core/services/storage/memory_service.dart';
import '../../../core/services/storage/preferences_service.dart';
import '../../../core/services/screenshots/screenshot_autopilot.dart';
import '../../../core/services/storage/share_import_service.dart';
import '../../../core/utils/logger.dart';

/// Timeline state: filter, sort, pagination, and a real refresh path.
class HomeController extends GetxController {
  HomeController(
    this._memoryService,
    this._processing,
    this._preferences,
    this._database,
  );

  final MemoryService _memoryService;
  final ProcessingService _processing;
  final PreferencesService _preferences;
  final AppDatabase _database;

  static const int _pageSize = 20;

  final RxList<Memory> memories = <Memory>[].obs;
  final Rx<MemoryFilter> filter = MemoryFilter.all.obs;
  final RxBool oldestFirst = false.obs;
  final RxBool loading = true.obs;
  final RxBool loadingMore = false.obs;
  final RxBool hasMore = true.obs;
  final RxString error = ''.obs;
  final RxInt totalCount = 0.obs;
  final RxInt pendingJobs = 0.obs;
  final RxString banner = ''.obs;

  /// Bumped when new items land at the top (a picker import, for example), so
  /// the page can scroll back to them instead of leaving the user mid-list with
  /// the new card and its banner off-screen.
  final RxInt scrollToTopTick = 0.obs;

  void requestScrollToTop() => scrollToTopTick.value++;

  Worker? _revisionWorker;
  Worker? _importedWorker;
  Worker? _messageWorker;

  @override
  void onInit() {
    super.onInit();
    oldestFirst.value = _preferences.sortOldest;
    _revisionWorker = ever<int>(
      _memoryService.revision,
      (int _) => reload(quiet: true),
    );
    // Shares import while this page is already built, so the list must react to
    // the importer itself; `revision` fires before the share reaches the UI.
    // `lastMessage` is watched too: the picker reports through it without
    // bumping `importedCount`, and that outcome would otherwise be silent.
    if (Get.isRegistered<ShareImportService>()) {
      final ShareImportService share = Get.find<ShareImportService>();
      _importedWorker = ever<int>(share.importedCount, (int _) {
        banner.value = share.lastMessage.value;
        share.lastMessage.value = '';
        reload(quiet: true);
      });
      _messageWorker = ever<String>(share.lastMessage, (String value) {
        if (value.isEmpty) return;
        banner.value = value;
        share.lastMessage.value = '';
      });
      // A cold-start share is consumed during bootstrap, before this page
      // exists, so its outcome is reported once here instead of being lost.
      if (share.importedCount.value > 0 && share.lastMessage.value.isNotEmpty) {
        banner.value = share.lastMessage.value;
        share.lastMessage.value = '';
      }
    }
    // Screenshot imports happen in the background; report them here rather
    // than opening a page the user did not ask for.
    if (Get.isRegistered<ScreenshotAutopilot>()) {
      final ScreenshotAutopilot autopilot = Get.find<ScreenshotAutopilot>();
      ever<String>(autopilot.message, (String value) {
        if (value.isEmpty) return;
        banner.value = value;
        reload(quiet: true);
      });
    }
    load();
  }

  Future<void> load() async {
    loading.value = true;
    error.value = '';
    try {
      await _fetchPage(offset: 0);
      totalCount.value = await _database.db
          .rawQuery(
            'SELECT COUNT(*) AS c FROM memories WHERE deleted_at IS NULL',
          )
          .then(
            (List<Map<String, Object?>> rows) => (rows.first['c'] as int?) ?? 0,
          );
      pendingJobs.value = await _processing.pendingCount();
    } catch (exception, stack) {
      logError('Timeline load failed', exception, stack);
      error.value = 'Your timeline could not be loaded. Pull down to retry.';
    } finally {
      loading.value = false;
    }
  }

  /// Refreshes without the full-screen spinner, used after edits/deletes.
  Future<void> reload({bool quiet = false}) async {
    if (!quiet) loading.value = memories.isEmpty;
    try {
      await load();
    } catch (_) {
      // load() already surfaces errors.
    }
  }

  Future<void> _fetchPage({required int offset}) async {
    final List<Memory> page = await _memoryService.timeline(
      filter: filter.value,
      oldestFirst: oldestFirst.value,
      limit: _pageSize,
      offset: offset,
    );
    if (offset == 0) {
      memories.assignAll(page);
    } else {
      memories.addAll(page);
    }
    hasMore.value = page.length == _pageSize;
  }

  Future<void> loadMore() async {
    if (loadingMore.value || !hasMore.value || loading.value) return;
    loadingMore.value = true;
    try {
      await _fetchPage(offset: memories.length);
    } catch (exception) {
      logWarn('Timeline pagination failed', exception);
    } finally {
      loadingMore.value = false;
    }
  }

  Future<void> setFilter(MemoryFilter value) async {
    if (filter.value == value) return;
    filter.value = value;
    await load();
  }

  Future<void> setSort({required bool oldest}) async {
    if (oldestFirst.value == oldest) return;
    oldestFirst.value = oldest;
    await _preferences.setSortOldest(oldest);
    await load();
  }

  Future<void> toggleFavorite(Memory memory) async {
    await _memoryService.toggleFavorite(memory.id, !memory.favorite);
  }

  Future<void> deleteMemory(Memory memory) async {
    await _memoryService.deleteMemory(memory.id);
  }

  Future<void> retryJobs(Memory memory) async {
    final int count = await _processing.retryFailedFor(memory.id);
    if (count == 0) {
      banner.value = 'Nothing to retry for this memory.';
    } else {
      banner.value = 'Retrying $count job${count == 1 ? '' : 's'}…';
      _processing.schedule();
    }
    await reload(quiet: true);
  }

  void dismissBanner() => banner.value = '';

  Future<void> recoverJobs() async {
    await _processing.resumeQueue();
    pendingJobs.value = await _processing.pendingCount();
  }

  /// Counts used by the filter chips; computed once per refresh to avoid a query
  /// per chip build.
  final RxMap<MemoryFilter, int> filterCounts = <MemoryFilter, int>{}.obs;

  Future<void> loadFilterCounts() async {
    final Map<MemoryFilter, int> counts = <MemoryFilter, int>{};
    for (final MemoryFilter value in MemoryFilter.values) {
      counts[value] = await MemoryDao(_database).count(filter: value);
    }
    filterCounts.assignAll(counts);
  }

  @override
  void onClose() {
    _revisionWorker?.dispose();
    _importedWorker?.dispose();
    _messageWorker?.dispose();
    super.onClose();
  }
}
