// Private fields are assigned from clearly named parameters: exposing the
// underscore-prefixed names as initializing formals would leak odd public API.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';

import '../../database/app_database.dart';
import '../../database/job_dao.dart';
import '../../database/memory_dao.dart';
import '../../database/search_dao.dart';
import '../../models/attachment.dart';
import '../../models/enums.dart';
import '../../models/memory.dart';
import '../../utils/ids.dart';
import '../../utils/logger.dart';
import '../ai/model_catalog.dart';
import '../ai/model_manager.dart';
import '../ai/sherpa_transcriber.dart';
import 'ocr_service.dart';
import 'processing_contracts.dart';

/// Runs OCR and transcription jobs one at a time.
///
/// Design constraints this enforces:
/// * jobs are persisted first, so a crash loses nothing;
/// * one job at a time keeps memory and battery predictable;
/// * `(attachment, type)` uniqueness makes retries idempotent;
/// * a job marked `running` at startup is requeued, never duplicated;
/// * failures are recorded with a human-readable reason and never discard the
///   original capture.
///
/// Delivery is app-process scoped on purpose: Android does not permit unrestricted
/// background execution, so work resumes when the app returns to the foreground
/// instead of promising an always-on queue.
class ProcessingService extends GetxService {
  ProcessingService({
    required AppDatabase database,
    required MemoryDao memories,
    required JobDao jobs,
    required SearchDao search,
    required TextExtractor ocr,
    required SpeechModelProvider models,
    required MediaPathResolver paths,
    required ProcessingSettings settings,
    required TranscriptEngine transcripts,
  }) : _database = database,
       _memories = memories,
       _jobs = jobs,
       _search = search,
       _ocr = ocr,
       _models = models,
       _paths = paths,
       _prefs = settings,
       _transcripts = transcripts;

  final AppDatabase _database;
  final MemoryDao _memories;
  final JobDao _jobs;
  final SearchDao _search;
  final TextExtractor _ocr;
  final SpeechModelProvider _models;
  final MediaPathResolver _paths;
  final ProcessingSettings _prefs;
  final TranscriptEngine _transcripts;

  final RxBool _draining = false.obs;
  final RxInt _completed = 0.obs;
  final RxString _currentLabel = ''.obs;
  Timer? _kick;

  /// Cancellation tokens for the in-flight job, keyed by job id.
  final Set<String> _canceled = <String>{};

  bool get isDraining => _draining.value;
  int get completedCount => _completed.value;
  String get currentLabel => _currentLabel.value;

  /// Called after every job reaches a terminal state. Bound at bootstrap to
  /// [MemoryService] so an open detail page or timeline refreshes itself when
  /// a background job lands, instead of showing "queued" indefinitely.
  void Function()? onJobFinished;

  /// Recovers interrupted work and starts the queue. Safe to call on every
  /// app resume.
  Future<void> resumeQueue() async {
    final int recovered = await _jobs.recoverInterrupted();
    if (recovered > 0) {
      logDebug('Requeued $recovered interrupted job(s)');
    }
    unawaited(drain());
  }

  /// Kicks the queue without awaiting; used after creating captures.
  void schedule() {
    _kick?.cancel();
    _kick = Timer(const Duration(milliseconds: 50), () {
      unawaited(drain());
    });
  }

  Future<void> drain() async {
    if (_draining.value) {
      // Another drain owns the loop; the pending kick will pick up new work.
      return;
    }
    // Absorb any scheduled kick, so awaiting drain() also awaits work that a
    // retry or a fresh capture queued moments earlier.
    _kick?.cancel();
    _kick = null;
    _draining.value = true;
    try {
      while (true) {
        final ModelSpec? model = _models.activeModel;
        final bool canTranscribe =
            _prefs.transcribeAuto && model != null && _models.isReady(model.id);
        final List<ProcessingJob> next = await _jobs.nextQueued(
          limit: 1,
          excludeTypes: canTranscribe
              ? const <JobType>[]
              : const <JobType>[JobType.transcription],
        );
        if (next.isEmpty) break;
        final ProcessingJob job = next.first;
        if (await _attempt(job) == _AttemptOutcome.retryLater) break;
        // The job just reached a terminal state; any screen showing this
        // memory must re-read it rather than keep the stale "queued" badge.
        onJobFinished?.call();
      }
    } finally {
      _draining.value = false;
      _currentLabel.value = '';
    }
  }

  /// Runs one job. Returns `retryLater` when prerequisites are missing so the
  /// queue stays parked without burning retries.
  Future<_AttemptOutcome> _attempt(ProcessingJob job) async {
    if (_canceled.remove(job.id)) return _AttemptOutcome.done;
    final Memory? memory = await _memories.findById(job.memoryId);
    if (memory == null) {
      await _jobs.markCanceled(job.id);
      return _AttemptOutcome.done;
    }

    final Attachment? attachment = job.attachmentId == null
        ? null
        : memory.attachments
              .where((Attachment value) => value.id == job.attachmentId)
              .firstOrNull;
    if (attachment == null) {
      await _jobs.markCanceled(job.id);
      return _AttemptOutcome.done;
    }

    switch (job.type) {
      case JobType.ocr:
        return _runOcr(job, attachment);
      case JobType.transcription:
        if (!_prefs.transcribeAuto) return _AttemptOutcome.retryLater;
        final ModelSpec? spec = _models.activeModel;
        if (spec == null || !_models.isReady(spec.id)) {
          // Park the job; the UI shows "model required" and the user can install
          // it, after which the queue resumes.
          return _AttemptOutcome.retryLater;
        }
        return _runTranscription(job, attachment, spec);
    }
  }

  Future<_AttemptOutcome> _runOcr(
    ProcessingJob job,
    Attachment attachment,
  ) async {
    await _jobs.markRunning(job.id);
    _currentLabel.value = 'Extracting text';
    try {
      final String absolute = await _paths.absolute(attachment.relativePath);
      final OcrResult result = await _ocr.recognize(File(absolute));
      if (_canceled.contains(job.id)) {
        await _jobs.markCanceled(job.id);
        return _AttemptOutcome.done;
      }
      if (!result.hasText) {
        // A screenshot with no readable text is a normal outcome, not an error.
        await _upsertExtraction(
          memoryId: job.memoryId,
          attachment: attachment,
          kind: 'ocr',
          rawText: '',
          engine: result.engine,
          language: result.language,
          emptyReason: 'No readable text found in this image.',
        );
        await _jobs.markCompleted(job.id);
        _completed.value++;
        return _AttemptOutcome.done;
      }
      await _upsertExtraction(
        memoryId: job.memoryId,
        attachment: attachment,
        kind: 'ocr',
        rawText: result.text,
        engine: result.engine,
        language: result.language,
      );
      await _jobs.markCompleted(job.id);
      _completed.value++;
      return _AttemptOutcome.done;
    } on OcrException catch (error) {
      await _jobs.markFailed(job.id, error.message);
      return _AttemptOutcome.done;
    } catch (error, stack) {
      logError('OCR job crashed', error, stack);
      await _jobs.markFailed(job.id, 'Text extraction failed: $error');
      return _AttemptOutcome.done;
    } finally {
      await _search.indexMemory(job.memoryId);
    }
  }

  Future<_AttemptOutcome> _runTranscription(
    ProcessingJob job,
    Attachment attachment,
    ModelSpec spec,
  ) async {
    await _jobs.markRunning(job.id);
    _currentLabel.value = 'Transcribing';
    try {
      final ModelPaths paths = await _models.pathsFor(spec);
      final String absolute = await _paths.absolute(attachment.relativePath);
      // CPU-heavy decode: the production engine runs it in a background
      // isolate; the interface keeps tests synchronous and deterministic.
      final TranscriptionOutput result = await _transcripts.transcribe(
        wavPath: absolute,
        spec: spec,
        paths: paths,
      );
      if (_canceled.contains(job.id)) {
        await _jobs.markCanceled(job.id);
        return _AttemptOutcome.done;
      }
      await _upsertExtraction(
        memoryId: job.memoryId,
        attachment: attachment,
        kind: 'transcript',
        rawText: result.text,
        engine: result.engine,
        language: result.language,
      );
      await _jobs.markCompleted(job.id);
      _completed.value++;
      return _AttemptOutcome.done;
    } on TranscriptionException catch (error) {
      await _jobs.markFailed(job.id, error.message);
      return _AttemptOutcome.done;
    } catch (error, stack) {
      logError('Transcription job crashed', error, stack);
      await _jobs.markFailed(job.id, 'On-device transcription failed: $error');
      return _AttemptOutcome.done;
    } finally {
      await _search.indexMemory(job.memoryId);
    }
  }

  /// Writes extraction output while preserving any user edit. When a record
  /// already exists and has been edited, only `raw_text` changes.
  Future<void> _upsertExtraction({
    required String memoryId,
    required Attachment attachment,
    required String kind,
    required String rawText,
    required String engine,
    String? language,
    String? emptyReason,
  }) async {
    await _database.db.transaction((txn) async {
      final List<Map<String, Object?>> existing = await txn.query(
        'extractions',
        where: 'attachment_id = ? AND kind = ?',
        whereArgs: <Object?>[attachment.id, kind],
        limit: 1,
      );
      final DateTime now = DateTime.now();
      if (existing.isEmpty) {
        final ExtractionRecord record = ExtractionRecord(
          id: Ids.newId('ext'),
          attachmentId: attachment.id,
          memoryId: memoryId,
          kind: kind,
          rawText: rawText,
          editedText: rawText,
          engine: engine,
          language: language,
          updatedAt: now,
        );
        await txn.insert('extractions', record.toRow());
      } else {
        final ExtractionRecord previous = ExtractionRecord.fromRow(
          existing.first,
        );
        await txn.update(
          'extractions',
          <String, Object?>{
            'raw_text': rawText,
            // The read and write share a transaction, so a concurrent user
            // correction cannot land between them and then be overwritten.
            'edited_text': previous.isEdited ? previous.editedText : rawText,
            'engine': engine,
            'language': language,
            'updated_at': now.millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: <Object?>[previous.id],
        );
      }
    });
    if (emptyReason != null) {
      logDebug(
        'Extraction produced no text for ${attachment.id} ($emptyReason)',
      );
    }
  }

  /// Marks a queued/running job as canceled and stops it at the next checkpoint.
  Future<void> cancelJob(String jobId) async {
    _canceled.add(jobId);
    await _jobs.markCanceled(jobId);
  }

  /// Retries every failed job for a memory.
  Future<int> retryFailedFor(String memoryId) async {
    final List<ProcessingJob> jobs = await _jobs.jobsForMemory(memoryId);
    int count = 0;
    for (final ProcessingJob job in jobs) {
      if (job.status == JobStatus.failed) {
        await _jobs.enqueue(
          memoryId: job.memoryId,
          attachmentId: job.attachmentId,
          type: job.type,
          force: true,
        );
        count++;
      }
    }
    schedule();
    return count;
  }

  Future<List<ProcessingJob>> jobsFor(String memoryId) =>
      _jobs.jobsForMemory(memoryId);

  Future<int> pendingCount() => _jobs.pendingCount();

  @override
  void onClose() {
    _kick?.cancel();
    super.onClose();
  }
}

enum _AttemptOutcome { done, retryLater }
