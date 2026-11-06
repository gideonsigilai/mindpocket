import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mindpocket/core/database/memory_dao.dart';
import 'package:mindpocket/core/models/attachment.dart';
import 'package:mindpocket/core/models/enums.dart';
import 'package:mindpocket/core/models/memory.dart';
import 'package:mindpocket/core/services/processing/ocr_service.dart';
import 'package:mindpocket/core/services/ai/model_manager.dart';
import 'package:mindpocket/core/services/storage/memory_service.dart';
import 'package:mindpocket/core/services/storage/preferences_service.dart';
import 'package:mindpocket/features/settings/controller/settings_controller.dart';
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

  group('typed notes', () {
    test('persist and are found by title and body text', () async {
      final Memory memory = await harness.memories.createNote(
        title: 'Travel Planner navigation',
        note: 'Use this navigation style for Travel Planner',
        tags: <String>['design', 'nav'],
      );

      final Memory? reloaded = await harness.memoryDao.findById(memory.id);
      expect(reloaded, isNotNull);
      expect(reloaded!.title, 'Travel Planner navigation');
      expect(reloaded.tags, containsAll(<String>['design', 'nav']));

      final List<SearchHit> hits = await harness.search.search('nav style');
      expect(hits.map((SearchHit hit) => hit.memory.id), contains(memory.id));
    });

    test('search snippets mark the match instead of repeating the title', () async {
      await harness.memories.createNote(
        title: 'Travel Planner navigation',
        note: 'Bottom tab bar with five destinations',
      );

      final SearchHit hit = (await harness.search.search('navigation')).single;
      // The snippet keeps FTS markers so the UI can emphasise the matched term;
      // stripping them here would silently lose the highlight.
      expect(hit.snippet, contains('⟦'));
      expect(hit.snippet.toLowerCase(), contains('navigation'));
    });

    test(
      'timeline filters split notes, images, voice, and favorites',
      () async {
        final Memory note = await harness.memories.createNote(
          title: 'note',
          note: 'body',
        );
        final Memory voice = await harness.memories.createVoiceMemory(
          title: 'voice',
        );
        final File wav = File(p.join(harness.tempDir.path, 'voice.wav'));
        await wav.writeAsBytes(testWav(seconds: 1), flush: true);
        await harness.memories.attachRecording(
          memoryId: voice.id,
          tempPath: wav.path,
          duration: const Duration(seconds: 1),
        );
        await harness.memories.createFromImage(
          source: await harness.writePng('a.png', size: 1),
          title: 'image',
        );
        await harness.memories.toggleFavorite(note.id, true);

        Future<Set<String>> ids(MemoryFilter filter) async =>
            (await harness.memories.timeline(
              filter: filter,
              limit: 50,
            )).map((Memory memory) => memory.id).toSet();

        expect(await ids(MemoryFilter.all), hasLength(3));
        expect(await ids(MemoryFilter.favorites), <String>{note.id});
        expect(await ids(MemoryFilter.voice), <String>{voice.id});
        // A note has no media; titles generated for screenshots must not leak
        // into this filter.
        expect(await ids(MemoryFilter.notes), <String>{note.id});
        expect((await ids(MemoryFilter.images)).length, 1);
      },
    );
  });

  group('image import', () {
    test('copies bytes into app storage and queues OCR', () async {
      final ImportOutcome outcome = await harness.memories.createFromImage(
        source: await harness.writePng('shot.png', size: 3),
        title: 'App nav screenshot',
      );

      expect(outcome.isDuplicate, isFalse);
      final Attachment attachment = outcome.attachment!;
      expect(await harness.paths.exists(attachment.relativePath), isTrue);
      expect(attachment.byteSize, greaterThan(0));
      expect(attachment.sha256, hasLength(64));

      final ProcessingJob? job = await harness.jobs.jobFor(
        memoryId: outcome.memoryId,
        attachmentId: attachment.id,
        type: JobType.ocr,
      );
      expect(job, isNotNull);
      expect(job!.status, JobStatus.queued);
    });

    test(
      'identical bytes are reported as a duplicate, not copied twice',
      () async {
        final File source = await harness.writePng('same.png', size: 2);
        final ImportOutcome first = await harness.memories.createFromImage(
          source: source,
        );
        final ImportOutcome second = await harness.memories.createFromImage(
          source: source,
        );

        expect(first.isDuplicate, isFalse);
        expect(second.isDuplicate, isTrue);
        expect(second.duplicateOf, first.memoryId);
        expect(second.attachment, isNull);
        expect(await harness.memoryDao.attachmentCount(), 1);
      },
    );

    test('OCR is not queued when the preference is off', () async {
      harness.settings.ocrAuto = false;
      final ImportOutcome outcome = await harness.memories.createFromImage(
        source: await harness.writePng('off.png', size: 4),
      );
      final List<ProcessingJob> jobs = await harness.jobs.jobsForMemory(
        outcome.memoryId,
      );
      expect(jobs, isEmpty);
    });

    test('an empty file is rejected and the memory is kept', () async {
      final File empty = File(p.join(harness.tempDir.path, 'empty.png'));
      await empty.writeAsBytes(const <int>[]);

      await expectLater(
        harness.memories.createFromImage(source: empty),
        throwsA(isA<Exception>()),
      );
      expect(await harness.memoryDao.timeline(limit: 10), hasLength(1));
    });
  });

  group('processing queue', () {
    test('a finished job notifies observers so open screens refresh', () async {
      harness.ocr.text = 'Queued text';
      int notifications = 0;
      harness.processing.onJobFinished = () => notifications++;

      await harness.memories.createFromImage(
        source: await harness.writePng('notify.png', size: 4),
      );
      await harness.processing.drain();

      // Without this signal the detail page keeps showing the job as queued.
      expect(notifications, 1);
    });

    test(
      'OCR completes, stores extraction, and makes the text searchable',
      () async {
        harness.ocr.text = 'Travel Planner navigation bar with five tabs';
        final ImportOutcome outcome = await harness.memories.createFromImage(
          source: await harness.writePng('nav.png', size: 5),
        );

        await harness.processing.drain();
        expect(harness.ocr.calls, hasLength(1));

        final ProcessingJob job = (await harness.jobs.jobsForMemory(
          outcome.memoryId,
        )).single;
        expect(job.status, JobStatus.completed);
        expect(harness.processing.completedCount, 1);

        final Memory memory = (await harness.memoryDao.findById(
          outcome.memoryId,
        ))!;
        expect(memory.processing, MemoryProcessing.done);
        expect(memory.ocrText, contains('five tabs'));

        final List<SearchHit> hits = await harness.search.search(
          'planner tabs',
        );
        expect(hits.first.memory.id, outcome.memoryId);
      },
    );

    test(
      'an image without text still completes with an honest record',
      () async {
        harness.ocr.text = '';
        final ImportOutcome outcome = await harness.memories.createFromImage(
          source: await harness.writePng('blank.png', size: 6),
        );

        await harness.processing.drain();
        final ProcessingJob job = (await harness.jobs.jobsForMemory(
          outcome.memoryId,
        )).single;
        expect(job.status, JobStatus.completed);

        final Memory memory = (await harness.memoryDao.findById(
          outcome.memoryId,
        ))!;
        expect(memory.ocrText, isEmpty);
        expect(memory.extractions.single.rawText, isEmpty);
      },
    );

    test('a failed OCR job records a retryable failure', () async {
      harness.ocr.failure = OcrException('ML Kit unavailable');
      final ImportOutcome outcome = await harness.memories.createFromImage(
        source: await harness.writePng('fail.png', size: 7),
      );

      await harness.processing.drain();
      final ProcessingJob job = (await harness.jobs.jobsForMemory(
        outcome.memoryId,
      )).single;
      expect(job.status, JobStatus.failed);
      expect(job.error, contains('ML Kit unavailable'));
      expect(job.attempts, 1);

      final Memory memory = (await harness.memoryDao.findById(
        outcome.memoryId,
      ))!;
      expect(memory.processing, MemoryProcessing.failed);
      expect(memory.jobError, contains('Text extraction failed'));

      // Retrying after the extractor recovers completes the same job row.
      harness.ocr.failure = null;
      await harness.memories.retryJob(
        outcome.memoryId,
        JobType.ocr,
        attachmentId: job.attachmentId,
      );
      await harness.processing.drain();
      final ProcessingJob retried = (await harness.jobs.jobsForMemory(
        outcome.memoryId,
      )).single;
      expect(retried.id, job.id);
      expect(retried.status, JobStatus.completed);
    });

    test('enqueue is idempotent for active and completed jobs', () async {
      final ImportOutcome outcome = await harness.memories.createFromImage(
        source: await harness.writePng('idem.png', size: 8),
      );
      final ProcessingJob first = (await harness.jobs.jobsForMemory(
        outcome.memoryId,
      )).single;

      final ProcessingJob? duplicate = await harness.jobs.enqueue(
        memoryId: outcome.memoryId,
        attachmentId: first.attachmentId,
        type: JobType.ocr,
      );
      expect(duplicate!.id, first.id);

      await harness.processing.drain();
      final ProcessingJob? afterCompletion = await harness.jobs.enqueue(
        memoryId: outcome.memoryId,
        attachmentId: first.attachmentId,
        type: JobType.ocr,
      );
      expect(afterCompletion!.id, first.id);
      expect(afterCompletion.status, JobStatus.completed);
    });

    test('interrupted jobs are requeued once, never duplicated', () async {
      final ImportOutcome outcome = await harness.memories.createFromImage(
        source: await harness.writePng('crash.png', size: 9),
      );
      final ProcessingJob job = (await harness.jobs.jobsForMemory(
        outcome.memoryId,
      )).single;
      await harness.jobs.markRunning(job.id);

      final int recovered = await harness.jobs.recoverInterrupted();
      expect(recovered, 1);

      final List<ProcessingJob> jobs = await harness.jobs.jobsForMemory(
        outcome.memoryId,
      );
      expect(jobs, hasLength(1));
      expect(jobs.single.status, JobStatus.queued);
      expect(jobs.single.attempts, 0);
    });

    test(
      'transcription parks without a model, then transcribes once ready',
      () async {
        harness.settings.transcribeAuto = true;
        final Memory memory = await harness.memories.createVoiceMemory(
          title: 'voice',
        );
        final File wav = File(p.join(harness.tempDir.path, 'clip.wav'));
        await wav.writeAsBytes(testWav(seconds: 1), flush: true);
        final Attachment attachment = await harness.memories.attachRecording(
          memoryId: memory.id,
          tempPath: wav.path,
          duration: const Duration(seconds: 1),
        );
        expect(attachment.durationMs, 1000);
        expect(await harness.paths.exists(attachment.relativePath), isTrue);

        // No model installed: the job must stay parked, not fail, and the audio
        // keeps playing.
        await harness.processing.drain();
        ProcessingJob job = (await harness.jobs.jobsForMemory(memory.id))
            .single;
        expect(
          job.status,
          JobStatus.queued,
          reason: 'a missing model is not a failure',
        );
        expect(job.attempts, 0);
        expect(harness.processing.isDraining, isFalse);

        // Installing the model resumes the same job without a duplicate row.
        harness.models.ready = true;
        await harness.processing.drain();
        job = (await harness.jobs.jobsForMemory(memory.id)).single;
        expect(job.status, JobStatus.completed);

        final Memory reloaded = (await harness.memoryDao.findById(memory.id))!;
        expect(reloaded.transcriptText, contains('travel planner'));
        expect(
          (await harness.search.search('travel planner')).single.memory.id,
          memory.id,
        );
        expect(
          harness.ocr.calls,
          isEmpty,
          reason: 'audio is never sent to OCR',
        );
      },
    );
  });

  group('user edits', () {
    test('survive reprocessing while raw engine output is replaced', () async {
      harness.ocr.text = 'initial machine text';
      final ImportOutcome outcome = await harness.memories.createFromImage(
        source: await harness.writePng('edit.png', size: 10),
      );
      await harness.processing.drain();

      final Memory memory = (await harness.memoryDao.findById(
        outcome.memoryId,
      ))!;
      final ExtractionRecord extraction = memory.extractions.single;
      expect(extraction.editedText, 'initial machine text');

      await harness.memories.saveExtractionEdit(
        extractionId: extraction.id,
        editedText: 'corrected by the user',
      );

      harness.ocr.text = 'second machine pass';
      await harness.memories.retryJob(
        outcome.memoryId,
        JobType.ocr,
        attachmentId: extraction.attachmentId,
      );
      await harness.processing.drain();

      final Memory after = (await harness.memoryDao.findById(
        outcome.memoryId,
      ))!;
      final ExtractionRecord updated = after.extractions.single;
      expect(updated.rawText, 'second machine pass');
      expect(updated.editedText, 'corrected by the user');
      expect(updated.isEdited, isTrue);

      // Search follows the user's text, not the engine's.
      expect(
        (await harness.search.search('corrected')).single.memory.id,
        outcome.memoryId,
      );
      expect(await harness.search.search('second machine'), isEmpty);

      await harness.memories.revertExtractionEdit(updated.id);
      final Memory reverted = (await harness.memoryDao.findById(
        outcome.memoryId,
      ))!;
      expect(reverted.extractions.single.editedText, 'second machine pass');
    });
  });

  group('taxonomy', () {
    test(
      'collections and tags are queryable and survive tag removal',
      () async {
        final Memory memory = await harness.memories.createNote(
          title: 'Travel Planner',
          note: 'notes',
        );
        final Collection collection = await harness.taxonomy.createCollection(
          'Design',
          description: 'UI references',
        );
        await harness.memories.setCollections(memory.id, <String>{
          collection.id,
        });
        await harness.memories.setTags(memory.id, <String>['design', 'nav']);

        final List<Collection> collections = await harness.taxonomy
            .collections();
        expect(collections.single.memoryCount, 1);
        expect(collections.single.description, 'UI references');

        expect(await harness.memories.allTags(), hasLength(2));
        await harness.memories.setTags(memory.id, <String>['design']);
        expect(
          (await harness.memories.allTags()).map((Tag tag) => tag.name),
          <String>['design'],
        );

        final List<Memory> inCollection = await harness.memories.timeline(
          collectionId: collection.id,
        );
        expect(inCollection.single.id, memory.id);
        expect(await harness.memories.timeline(tagName: 'nav'), isEmpty);
      },
    );
  });

  group('widget state', () {
    testWidgets('processing switches rebuild from reactive state', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = SettingsController(
        harness.prefs,
        ModelManager(harness.paths, harness.files, harness.prefs),
        harness.memories,
        harness.database,
      );
      expect(controller.toggles.ocrAuto.value, isTrue);

      // A plain getter here would leave the switch visually stuck after a tap.
      final List<bool> observed = <bool>[];
      controller.toggles.ocrAuto.listen(observed.add);
      await controller.toggles.setOcrAuto(false);

      expect(observed, <bool>[false]);
      expect(controller.toggles.ocrAuto.value, isFalse);
      expect(
        harness.prefs.readBool(PreferencesService.kOcrAuto, true),
        isFalse,
      );
    });
  });

  group('deletion', () {
    test('removes rows, files, jobs, and search entries', () async {
      harness.ocr.text = 'unique phrase zebra';
      final ImportOutcome outcome = await harness.memories.createFromImage(
        source: await harness.writePng('delete.png', size: 11),
      );
      await harness.processing.drain();

      final Memory memory = (await harness.memoryDao.findById(
        outcome.memoryId,
      ))!;
      final Attachment attachment = memory.attachments.single;
      expect(await harness.paths.exists(attachment.relativePath), isTrue);
      expect(await harness.search.search('zebra'), hasLength(1));

      await harness.memories.deleteMemory(outcome.memoryId);

      expect(await harness.memoryDao.findById(outcome.memoryId), isNull);
      expect(await harness.search.search('zebra'), isEmpty);
      expect(await harness.jobs.jobsForMemory(outcome.memoryId), isEmpty);
      expect(await harness.paths.exists(attachment.relativePath), isFalse);
      if (attachment.thumbnailRelativePath != null) {
        expect(
          await harness.paths.exists(attachment.thumbnailRelativePath!),
          isFalse,
        );
      }
    });

    test(
      'removing one attachment keeps the memory and its other files',
      () async {
        final ImportOutcome a = await harness.memories.createFromImage(
          source: await harness.writePng('keep.png', size: 12),
        );
        final Attachment extra = (await harness.memories.attachImageToMemory(
          a.memoryId,
          source: await harness.writePng('extra.png', size: 13),
        ))!;

        await harness.memories.removeAttachment(extra);

        final Memory memory = (await harness.memoryDao.findById(a.memoryId))!;
        expect(memory.attachments, hasLength(1));
        expect(await harness.paths.exists(extra.relativePath), isFalse);
        expect(
          await harness.jobs.jobFor(
            memoryId: a.memoryId,
            attachmentId: extra.id,
            type: JobType.ocr,
          ),
          isNull,
        );
      },
    );
  });
}
