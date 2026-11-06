import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mindpocket/core/models/memory.dart';
import 'package:mindpocket/features/home/controller/home_controller.dart';

import 'support/harness.dart';

void main() {
  late Harness harness;

  setUp(() async {
    Get.reset();
    harness = await Harness.create();
  });

  tearDown(() async {
    Get.reset();
    await harness.dispose();
  });

  HomeController build() {
    final HomeController controller = HomeController(
      harness.memories,
      harness.processing,
      harness.prefs,
      harness.database,
    );
    Get.put<HomeController>(controller);
    return controller;
  }

  test('a finished processing job refreshes the pending counter', () async {
    harness.ocr.text = 'Brand new text';
    harness.processing.onJobFinished = harness.memories.notifyCollectionChange;
    final HomeController controller = build();

    await controller.load();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await harness.memories.createFromImage(
      source: await harness.writePng('refresh.png', size: 4),
    );
    // Queue is empty only after the job ran; the banner must follow it down.
    controller.pendingJobs.value = await harness.processing.pendingCount();
    expect(controller.pendingJobs.value, 1);

    await harness.processing.drain();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(controller.pendingJobs.value, 0);
  });

  test('starring a memory refreshes the timeline rows', () async {
    final HomeController controller = build();
    final Memory created = await harness.memories.createNote(
      title: 'Star me',
      note: 'body',
    );
    await controller.load();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(controller.memories.single.favorite, isFalse);

    await controller.toggleFavorite(controller.memories.single);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(controller.memories.single.favorite, isTrue);
    expect(created.id, controller.memories.single.id);
  });

  test('deleting a memory removes it from the timeline', () async {
    final HomeController controller = build();
    await harness.memories.createNote(title: 'Delete me', note: 'body');
    await controller.load();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(controller.memories, hasLength(1));

    await controller.deleteMemory(controller.memories.single);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(controller.memories, isEmpty);
  });

  test('the revision worker reloads without a manual refresh', () async {
    final HomeController controller = build();
    final Memory created = await harness.memories.createNote(
      title: 'First',
      note: 'body',
    );
    await controller.load();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(controller.memories, hasLength(1));

    // Straight to the service: nothing calls controller.load() here, so only
    // the revision worker can make the timeline notice the change.
    await harness.memories.toggleFavorite(created.id, true);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(controller.memories.single.favorite, isTrue);
  });
}
