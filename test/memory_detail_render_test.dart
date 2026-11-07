import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mindpocket/app/theme/app_theme.dart';
import 'package:mindpocket/core/models/attachment.dart';
import 'package:mindpocket/core/models/enums.dart';
import 'package:mindpocket/core/models/memory.dart';
import 'package:mindpocket/core/services/ai/related_service.dart';
import 'package:mindpocket/core/services/processing/share_intake_service.dart';
import 'package:mindpocket/core/services/storage/path_service.dart';
import 'package:mindpocket/features/memory_detail/controller/memory_detail_controller.dart';
import 'package:mindpocket/features/memory_detail/presentation/memory_detail_page.dart';
import 'package:mindpocket/features/memory_detail/presentation/widgets/media_widgets.dart';

import 'support/harness.dart';

MemoryDetailController _controller(Harness harness, String id) =>
    MemoryDetailController(
      memoryId: id,
      memories: harness.memories,
      processing: harness.processing,
      shares: ShareIntakeService(),
      related: RelatedService(harness.database, harness.memories),
      database: harness.database,
      preferences: harness.prefs,
      models: harness.models,
    );

Future<Harness> _createHarness(WidgetTester tester) async {
  Get.testMode = true;
  final Harness harness = (await tester.runAsync(Harness.create))!;
  Get.put<PathService>(harness.paths);
  addTearDown(() async {
    await _waitForIo(
      tester,
      () => tester.binding.imageCache.pendingImageCount == 0,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.imageCache.clear();
    tester.binding.imageCache.clearLiveImages();
    Get.reset();
    await harness.dispose();
  });
  return harness;
}

Future<Memory> _image(
  WidgetTester tester,
  Harness harness, {
  String title = 'Saved interface',
  String fileName = 'detail.png',
  int size = 21,
}) async {
  return (await tester.runAsync(() async {
    final outcome = await harness.memories.createFromImage(
      source: await harness.writePng(fileName, size: size),
      title: title,
    );
    await harness.processing.drain();
    return (await harness.memories.findById(outcome.memoryId))!;
  }))!;
}

Future<MemoryDetailController> _pumpDetail(
  WidgetTester tester,
  Harness harness,
  Memory memory, {
  Size size = const Size(390, 844),
  double textScale = 1,
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final MemoryDetailController controller = Get.put<MemoryDetailController>(
    _controller(harness, memory.id),
    tag: memory.id,
  );
  await tester.runAsync(() => controller.load());
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (BuildContext context, Widget? child) => GetMaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: child!,
        ),
        home: MemoryDetailPage(memoryId: memory.id),
        getPages: <GetPage<dynamic>>[
          GetPage<dynamic>(
            name: '/memory/:id',
            page: () => MemoryDetailPage(memoryId: Get.parameters['id']!),
            binding: BindingsBuilder(() {
              final String id = Get.parameters['id']!;
              Get.put<MemoryDetailController>(
                _controller(harness, id),
                tag: id,
              );
            }),
          ),
        ],
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _waitForIo(WidgetTester tester, bool Function() finished) async {
  final Stopwatch timeout = Stopwatch()..start();
  while (!finished() && timeout.elapsed < const Duration(seconds: 5)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(finished(), isTrue);
  await tester.pumpAndSettle();
}

Finder _titleField(String title) => find.byWidgetPredicate(
  (Widget widget) => widget is TextField && widget.controller?.text == title,
);

void main() {
  testWidgets(
    'image leads the page, opens its original, and OCR starts hidden',
    (WidgetTester tester) async {
      final Harness harness = await _createHarness(tester);
      harness.ocr.text = 'Captured text is only shown on request';
      final Memory image = await _image(tester, harness);
      final MemoryDetailController controller = await _pumpDetail(
        tester,
        harness,
        image,
      );
      // A thumbnail must never be substituted for the original in the viewer.
      controller.memory.value = controller.memory.value!.copyWith(
        attachments: <Attachment>[
          image.primaryImage!.copyWith(
            thumbnailRelativePath: 'thumbnails/preview-only.png',
          ),
        ],
      );
      await tester.pumpAndSettle();

      final Finder preview = find.byKey(
        const ValueKey<String>('primary-image-preview'),
      );
      expect(
        tester.getSize(preview).height,
        closeTo((844 - kToolbarHeight) * .75, 1),
      );
      expect(
        tester.getBottomLeft(preview).dy,
        lessThan(tester.getTopLeft(_titleField(image.title)).dy),
      );
      expect(find.text(harness.ocr.text), findsNothing);
      expect(find.text('Processing'), findsNothing);

      await tester.tap(preview);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ImageViewerPage>(find.byType(ImageViewerPage))
            .relativePath,
        image.primaryImage!.relativePath,
      );
      await tester.tap(find.byTooltip('Close image'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Text from image'));
      await tester.tap(find.text('Text from image'));
      await tester.pumpAndSettle();
      expect(find.text(harness.ocr.text), findsOneWidget);
      await tester.tap(find.text('Text from image'));
      await tester.pumpAndSettle();
      expect(find.text(harness.ocr.text), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Add tag focuses a dialog and validates before persisting', (
    WidgetTester tester,
  ) async {
    final Harness harness = await _createHarness(tester);
    final Memory note = (await tester.runAsync(
      () => harness.memories.createNote(
        title: 'Editable note',
        note: 'Words written by the user',
        tags: <String>['design'],
      ),
    ))!;
    final MemoryDetailController controller = await _pumpDetail(
      tester,
      harness,
      note,
      size: const Size(320, 700),
      textScale: 1.8,
    );
    final Finder addTag = find.widgetWithText(ActionChip, 'Add tag');
    expect(find.byType(TextFormField), findsNothing);
    await tester.ensureVisible(addTag);
    await tester.tap(addTag);
    await tester.pumpAndSettle();
    final Finder input = find.byType(TextFormField);
    final EditableText editable = tester.widget<EditableText>(
      find.descendant(of: input, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isTrue);
    final Finder add = find.widgetWithText(FilledButton, 'Add');
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.text('Enter a tag.'), findsOneWidget);
    await tester.enterText(input, 'DESIGN');
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.text('This memory already has that tag.'), findsOneWidget);
    await tester.enterText(input, 'x' * 41);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.text('Use 40 characters or fewer.'), findsOneWidget);

    await tester.enterText(input, '#navigation');
    final ModalRoute<dynamic> dialog = ModalRoute.of(tester.element(input))!;
    await tester.tap(add);
    await _waitForIo(tester, () => !dialog.isCurrent);
    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.memory.value!.tags, contains('navigation'));
    final Memory stored = (await tester.runAsync<Memory?>(
      () => harness.memories.findById(note.id),
    ))!;
    expect(stored.tags, containsAll(<String>['design', 'navigation']));
    expect(tester.takeException(), isNull);
  });

  testWidgets('processing hides terminal jobs but retains actionable states', (
    WidgetTester tester,
  ) async {
    final Harness harness = await _createHarness(tester);
    final Memory image = await _image(tester, harness);
    final MemoryDetailController controller = await _pumpDetail(
      tester,
      harness,
      image,
    );
    final ProcessingJob completed = controller.jobs.single;
    expect(completed.status, JobStatus.completed);
    expect(find.text('Processing'), findsNothing);

    controller.jobs.assignAll(<ProcessingJob>[
      completed.copyWith(status: JobStatus.canceled),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Processing'), findsNothing);
    for (final JobStatus status in <JobStatus>[
      JobStatus.queued,
      JobStatus.running,
      JobStatus.failed,
    ]) {
      controller.jobs.assignAll(<ProcessingJob>[
        completed.copyWith(
          status: status,
          error: status == JobStatus.failed ? 'OCR unavailable' : null,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Processing'), findsOneWidget);
      if (status == JobStatus.failed) {
        expect(find.text('OCR unavailable'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
      } else {
        expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
      }
    }
    final DateTime now = DateTime.now();
    controller.jobs.assignAll(<ProcessingJob>[
      ProcessingJob(
        id: 'parked-transcription',
        memoryId: image.id,
        type: JobType.transcription,
        status: JobStatus.queued,
        attempts: 0,
        createdAt: now,
        updatedAt: now,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Automatic transcription is off'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'related screenshots show local thumbnails and open a distinct memory',
    (WidgetTester tester) async {
      final Harness harness = await _createHarness(tester);
      final Memory first = await _image(
        tester,
        harness,
        title: 'Pocket navigation first',
      );
      final Memory second = await _image(
        tester,
        harness,
        title: 'Pocket navigation first!',
        fileName: 'second.png',
        size: 22,
      );
      final MemoryDetailController original = await _pumpDetail(
        tester,
        harness,
        first,
      );
      expect(
        original.related.any(
          (RelatedSuggestion item) => item.memory.id == second.id,
        ),
        isTrue,
      );
      final Finder thumbnail = find.byWidgetPredicate(
        (Widget widget) =>
            widget is LocalImage &&
            widget.relativePath == second.primaryThumbnailPath,
      );
      expect(thumbnail, findsOneWidget);
      expect(find.text(second.title), findsOneWidget);
      await tester.ensureVisible(thumbnail);
      await tester.tap(thumbnail);
      await tester.pump();
      final MemoryDetailController opened = Get.find<MemoryDetailController>(
        tag: second.id,
      );
      await tester.runAsync(() => opened.load());
      await tester.pumpAndSettle();
      expect(opened.memoryId, second.id);
      expect(_titleField(second.title), findsOneWidget);
      expect(Get.find<MemoryDetailController>(tag: first.id), same(original));
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(_titleField(first.title), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final bool reduced in <bool>[false, true]) {
    testWidgets('image scroll respects reduced motion = $reduced', (
      WidgetTester tester,
    ) async {
      final Harness harness = await _createHarness(tester);
      final Memory image = await _image(tester, harness);
      await _pumpDetail(tester, harness, image, reduceMotion: reduced);
      final Finder preview = find.byKey(
        const ValueKey<String>('primary-image-preview'),
      );
      final Finder picture = find.descendant(
        of: preview,
        matching: find.byType(LocalImage),
      );
      final double before = tester.getTopLeft(picture).dy;
      final ScrollPosition position = Scrollable.of(tester.element(preview))
          .position;
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      final double travel = before - tester.getTopLeft(picture).dy;
      expect(position.pixels, greaterThan(0));
      if (reduced) {
        expect(travel, closeTo(position.pixels, 1));
      } else {
        expect(travel, lessThan(position.pixels - 1));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
