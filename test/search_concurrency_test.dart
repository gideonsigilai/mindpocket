import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mindpocket/core/models/memory.dart';
import 'package:mindpocket/core/services/ai/related_service.dart';
import 'package:mindpocket/core/services/storage/memory_service.dart';
import 'package:mindpocket/features/search/controller/search_page_controller.dart';

import 'support/harness.dart';

void main() {
  late Harness harness;
  late _ControlledSearch memories;
  late SearchPageController controller;

  setUp(() async {
    harness = await Harness.create();
    memories = _ControlledSearch(harness);
    controller = SearchPageController(
      memories,
      RelatedService(harness.database, harness.memories),
    );
  });

  tearDown(() async {
    controller.onClose();
    await harness.dispose();
  });

  test('an older search cannot replace a newer result', () async {
    final Memory old = await harness.memories.createNote(
      title: 'Old',
      note: '',
    );
    final Memory latest = await harness.memories.createNote(
      title: 'Latest',
      note: '',
    );
    final Future<void> first = controller.run('old');
    final Future<void> second = controller.run('latest');
    memories.requests['latest']!.complete(<SearchHit>[
      SearchHit(memory: latest, snippet: 'Latest', score: 1),
    ]);
    await second;
    memories.requests['old']!.complete(<SearchHit>[
      SearchHit(memory: old, snippet: 'Old', score: 1),
    ]);
    await first;
    expect(controller.results.single.memory.id, latest.id);
    expect(controller.relatedReference.value, 'latest');
    expect(controller.searching.value, isFalse);
  });

  test(
    'clearing search prevents an in-flight response from returning',
    () async {
      final Memory memory = await harness.memories.createNote(
        title: 'Travel',
        note: '',
      );
      final Future<void> pending = controller.run('travel');
      controller.clear();
      memories.requests['travel']!.complete(<SearchHit>[
        SearchHit(memory: memory, snippet: 'Travel', score: 1),
      ]);
      await pending;
      expect(controller.results, isEmpty);
      expect(controller.related, isEmpty);
      expect(controller.hasSearched.value, isFalse);
      expect(controller.searching.value, isFalse);
    },
  );
}

class _ControlledSearch extends MemoryService {
  _ControlledSearch(Harness harness)
    : super(
        database: harness.database,
        memories: harness.memoryDao,
        jobs: harness.jobs,
        search: harness.search,
        taxonomy: harness.taxonomy,
        files: harness.files,
        paths: harness.paths,
        settings: harness.settings,
      );

  final Map<String, Completer<List<SearchHit>>> requests =
      <String, Completer<List<SearchHit>>>{};

  @override
  Future<List<SearchHit>> search(
    String query, {
    int limit = 40,
    int offset = 0,
  }) {
    final Completer<List<SearchHit>> request = Completer<List<SearchHit>>();
    requests[query] = request;
    return request.future;
  }
}
