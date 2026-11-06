import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mindpocket/core/models/attachment.dart';
import 'package:mindpocket/core/models/enums.dart';
import 'package:mindpocket/core/models/memory.dart';
import 'package:mindpocket/core/services/ai/related_service.dart';
import 'package:mindpocket/core/services/processing/ocr_service.dart';
import 'package:mindpocket/core/services/processing/share_intake_service.dart';
import 'package:mindpocket/core/services/storage/memory_service.dart';
import 'package:mindpocket/features/memory_detail/controller/memory_detail_controller.dart';
import 'package:path/path.dart' as p;

import 'support/harness.dart';

void main() {
  late Harness harness;

  setUp(() async {
    harness = await Harness.create();
  });

  tearDown(() async {
    await harness.dispose();
  });

  MemoryDetailController controllerFor(String memoryId) =>
      MemoryDetailController(
        memoryId: memoryId,
        memories: harness.memories,
        processing: harness.processing,
        shares: ShareIntakeService(),
        related: RelatedService(harness.database, harness.memories),
        database: harness.database,
        preferences: harness.prefs,
        models: harness.models,
      );

  Future<void> settle() => harness.processing.drain();

  group('detail editing', () {
    test('title and note edits persist and are re-read from SQLite', () async {
      harness.ocr.text = 'tab bar with five destinations';
      final ImportOutcome outcome = await harness.memories.createFromImage(
        source: await harness.writePng('detail.png', size: 21),
        title: 'Original title',
      );
      await settle();

      final MemoryDetailController controller = controllerFor(outcome.memoryId);
      await controller.load();
      expect(controller.memory.value?.title, 'Original title');

      controller.editTitle('Renamed by the user');
      controller.editNote('A clearer description.');
      expect(controller.dirty.value, isTrue);
      expect(await controller.saveEdits(), isTrue);
      expect(controller.dirty.value, isFalse);

      final Memory stored = (await harness.memoryDao.findById(
        outcome.memoryId,
      ))!;
      expect(stored.title, 'Renamed by the user');
      expect(stored.note, 'A clearer description.');

      // Reopening reads the saved values, not the stale drafts.
      final MemoryDetailController reopened = controllerFor(outcome.memoryId);
      await reopened.load();
      expect(reopened.draftTitle.value, 'Renamed by the user');
      expect(reopened.draftNote.value, 'A clearer description.');
    });

    test('unsaved edits are replaced on reload only after commit', () async {
      final Memory memory = await harness.memories.createNote(
        title: 'before',
        note: 'body',
      );
      final MemoryDetailController controller = controllerFor(memory.id);
      await controller.load();

      controller.editTitle('draft only');
      await controller.load(silent: true);

      // A background refresh must not clobber what the user is typing.
      expect(controller.draftTitle.value, 'draft only');
      expect(controller.dirty.value, isTrue);
      expect((await harness.memoryDao.findById(memory.id))!.title, 'before');
    });

    test('restoring the title does not discard an unsaved note', () async {
      final Memory memory = await harness.memories.createNote(
        title: 'Original title',
        note: 'Original note',
      );
      final MemoryDetailController controller = controllerFor(memory.id);
      await controller.load();

      controller.editNote('Keep this note edit');
      controller.editTitle('Temporary title');
      controller.editTitle(memory.title);

      expect(controller.dirty.value, isTrue);
      await controller.load(silent: true);
      expect(controller.draftNote.value, 'Keep this note edit');
      expect(await controller.saveEdits(), isTrue);
      expect(
        (await harness.memoryDao.findById(memory.id))!.note,
        'Keep this note edit',
      );
    });

    test('favorite, tags, and collections write through immediately', () async {
      final Memory memory = await harness.memories.createNote(
        title: 'tagged',
        note: 'body',
      );
      final Collection design = await harness.taxonomy.createCollection(
        'Design',
      );
      final MemoryDetailController controller = controllerFor(memory.id);
      await controller.load();

      await controller.toggleFavorite();
      await controller.addTags(<String>['nav', 'ui']);
      await controller.setCollections(<String>{design.id});
      await controller.removeTag('ui');

      final Memory stored = (await harness.memoryDao.findById(memory.id))!;
      expect(stored.favorite, isTrue);
      expect(stored.tags, <String>['nav']);
      expect(await harness.taxonomy.collectionIdsFor(memory.id), <String>{
        design.id,
      });
    });

    test('attachment removal keeps the memory and drops its jobs', () async {
      final ImportOutcome outcome = await harness.memories.createFromImage(
        source: await harness.writePng('remove.png', size: 22),
      );
      final MemoryDetailController controller = controllerFor(outcome.memoryId);
      await controller.load();

      final Memory loaded = controller.memory.value!;
      final Attachment attachment = loaded.attachments.single;
      await controller.removeAttachment(attachment);

      final Memory after = (await harness.memoryDao.findById(
        outcome.memoryId,
      ))!;
      expect(after.attachments, isEmpty);
      expect(await harness.paths.exists(attachment.relativePath), isFalse);
      expect(
        await harness.jobs.jobFor(
          memoryId: outcome.memoryId,
          attachmentId: attachment.id,
          type: JobType.ocr,
        ),
        isNull,
      );
      expect(controller.memory.value!.attachments, isEmpty);
    });

    test('retry requeues a failed job and clears the failure banner', () async {
      harness.ocr.failure = OcrException('recognizer unavailable');
      final ImportOutcome outcome = await harness.memories.createFromImage(
        source: await harness.writePng('retry.png', size: 23),
      );
      await settle();

      final MemoryDetailController controller = controllerFor(outcome.memoryId);
      await controller.load();
      expect(controller.jobs.single.status, JobStatus.failed);

      harness.ocr.failure = null;
      await controller.retryAllFailed();
      await settle();

      final ProcessingJob job = (await harness.jobs.jobsForMemory(
        outcome.memoryId,
      )).single;
      expect(job.status, JobStatus.completed);
      final Memory stored = (await harness.memoryDao.findById(
        outcome.memoryId,
      ))!;
      expect(stored.processing, MemoryProcessing.done);
      expect(stored.jobError, isNull);
    });

    test(
      'a deleted memory reports an honest error instead of a blank page',
      () async {
        final Memory memory = await harness.memories.createNote(
          title: 'temporary',
          note: 'body',
        );
        final MemoryDetailController controller = controllerFor(memory.id);
        await controller.load();

        await harness.memories.deleteMemory(memory.id);
        await controller.load();

        expect(controller.memory.value, isNull);
        expect(controller.error.value, contains('no longer exists'));
      },
    );

    test('a parked transcription explains that a model is missing', () async {
      // Without a model the queue must park the job rather than fail it, and
      // the detail page has to know so it can explain the wait.
      harness.settings.transcribeAuto = true;
      harness.prefs.transcribeAuto = true;
      harness.models.ready = false;
      final Memory memory = await harness.memories.createVoiceMemory(
        title: 'voice without model',
      );
      final File wav = File(p.join(harness.tempDir.path, 'parked.wav'));
      await wav.writeAsBytes(testWav(seconds: 1), flush: true);
      await harness.memories.attachRecording(
        memoryId: memory.id,
        tempPath: wav.path,
        duration: const Duration(seconds: 1),
      );
      await settle();

      final MemoryDetailController controller = controllerFor(memory.id);
      await controller.load();

      expect(controller.jobs.single.status, JobStatus.queued);
      expect(controller.transcriptionPossible, isFalse);

      harness.models.ready = true;
      expect(controller.transcriptionPossible, isTrue);
    });

    test('transcript edits stay separate from the audio attachment', () async {
      harness.settings.transcribeAuto = true;
      harness.models.ready = true;
      final Memory memory = await harness.memories.createVoiceMemory(
        title: 'voice',
      );
      final File wav = File(p.join(harness.tempDir.path, 'note.wav'));
      await wav.writeAsBytes(testWav(seconds: 1), flush: true);
      final Attachment attachment = await harness.memories.attachRecording(
        memoryId: memory.id,
        tempPath: wav.path,
        duration: const Duration(seconds: 1),
      );
      await settle();

      final Memory before = (await harness.memoryDao.findById(memory.id))!;
      final ExtractionRecord extraction = before.extractions.single;
      final MemoryDetailController controller = controllerFor(memory.id);
      await controller.load();

      await controller.saveTranscriptionEdit(
        extraction.id,
        'edited transcript line',
      );

      final Memory after = (await harness.memoryDao.findById(memory.id))!;
      expect(after.extractions.single.editedText, 'edited transcript line');
      expect(after.extractions.single.rawText, isNotEmpty);
      expect(
        await harness.paths.exists(attachment.relativePath),
        isTrue,
        reason: 'editing text must never touch the recording',
      );
    });
  });
}
