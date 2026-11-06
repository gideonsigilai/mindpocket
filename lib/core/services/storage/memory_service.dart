// Private fields are assigned from clearly named parameters: exposing the
// underscore-prefixed names as initializing formals would leak odd public API.
// ignore_for_file: prefer_initializing_formals

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../../database/app_database.dart';
import '../../database/job_dao.dart';
import '../../database/memory_dao.dart';
import '../../database/search_dao.dart';
import '../../models/attachment.dart';
import '../../models/enums.dart';
import '../../models/memory.dart';
import '../../utils/ids.dart';
import '../../utils/logger.dart';
import '../processing/processing_contracts.dart';
import 'file_store.dart';
import 'path_service.dart';

/// Result of importing one file, so the caller can report duplicates honestly.
class ImportOutcome {
  const ImportOutcome({
    required this.memoryId,
    required this.attachment,
    required this.duplicateOf,
  });

  final String memoryId;
  final Attachment? attachment;

  /// Set when the same bytes already exist in the collection. The user decides
  /// what to do; imports are never silently merged.
  final String? duplicateOf;

  bool get isDuplicate => duplicateOf != null;
}

/// Orchestrates memories: creation, attachments, edits, deletion, and index
/// maintenance. Services own persistence; controllers own UI state.
class _AttachResult {
  const _AttachResult({required this.attachment, required this.duplicateOf});

  final Attachment? attachment;
  final String? duplicateOf;
}

class MemoryService extends GetxService {
  MemoryService({
    required AppDatabase database,
    required MemoryDao memories,
    required JobDao jobs,
    required SearchDao search,
    required TaxonomyDao taxonomy,
    required FileStore files,
    required PathService paths,
    required ProcessingSettings settings,
  }) : _database = database,
       _memories = memories,
       _jobs = jobs,
       _search = search,
       _taxonomy = taxonomy,
       _files = files,
       _paths = paths,
       _settings = settings;

  /// Called after work is queued so the processor starts without waiting for
  /// the user to touch the UI. Wired at bootstrap.
  VoidCallback? onWorkQueued;

  final AppDatabase _database;
  final MemoryDao _memories;
  final JobDao _jobs;
  final SearchDao _search;
  final TaxonomyDao _taxonomy;
  final FileStore _files;
  final PathService _paths;
  final ProcessingSettings _settings;

  /// Bumped whenever the collection changes, so timeline controllers can react
  /// without polling the database.
  final RxInt revision = 0.obs;

  void _bump() => revision.value++;

  /// Signals that derived data changed (filing, AI grouping, a finished
  /// processing job) so any list showing it reloads instead of waiting for the
  /// next app launch.
  Future<void> notifyCollectionChange() async => _bump();

  /// Queues work and tells the processor there is something to do. Every path
  /// that schedules OCR or transcription goes through here so a new import type
  /// cannot silently sit in the queue.
  Future<ProcessingJob?> _enqueue({
    required String memoryId,
    required String? attachmentId,
    required JobType type,
    bool force = false,
  }) async {
    final ProcessingJob? job = await _jobs.enqueue(
      memoryId: memoryId,
      attachmentId: attachmentId,
      type: type,
      force: force,
    );
    if (job != null) onWorkQueued?.call();
    return job;
  }

  Future<Memory> createNote({
    required String title,
    required String note,
    List<String> tags = const <String>[],
    MemorySource source = MemorySource.typed,
  }) async {
    final DateTime now = DateTime.now();
    final Memory memory = Memory(
      id: Ids.newId('mem'),
      title: title.trim(),
      note: note.trim(),
      kind: MemoryKind.note,
      source: source,
      createdAt: now,
      updatedAt: now,
    );
    await _memories.insert(memory);
    if (tags.isNotEmpty) {
      await _taxonomy.setTags(memory.id, tags);
      await _memories.touch(memory.id, at: now);
    }
    await _search.indexMemory(memory.id);
    _bump();
    return (await findById(memory.id)) ?? memory;
  }

  /// Copies the bytes first, then creates the memory around them. Doing it in
  /// this order means a duplicate leaves no empty row behind and a failed copy
  /// leaves nothing behind at all: an empty image memory is a broken entry, not
  /// a saved capture. OCR/transcription still never runs before the bytes are
  /// safe, because the job is queued only after the attachment is stored.
  Future<ImportOutcome> createFromImage({
    required File source,
    String title = '',
    String note = '',
    MemorySource memorySource = MemorySource.picker,
    String? extensionHint,

    /// When the image was captured on the device. Defaults to import time, which
    /// is correct for a picker or a share.
    DateTime? capturedAt,
  }) async {
    final DateTime now = capturedAt ?? DateTime.now();
    final Memory memory = Memory(
      id: Ids.newId('mem'),
      title: title.trim(),
      note: note.trim(),
      kind: MemoryKind.image,
      source: memorySource,
      createdAt: now,
      updatedAt: now,
    );
    await _memories.insert(memory);

    try {
      final _AttachResult result = await _attachImage(
        memory: memory,
        source: source,
        extensionHint: extensionHint,
      );
      if (result.duplicateOf != null) {
        // Nothing was attached, so the provisional row must not survive as an
        // empty entry in the timeline.
        await _memories.hardDelete(memory.id);
        return ImportOutcome(
          memoryId: result.duplicateOf!,
          attachment: null,
          duplicateOf: result.duplicateOf,
        );
      }
      await _search.indexMemory(memory.id);
      _bump();
      return ImportOutcome(
        memoryId: memory.id,
        attachment: result.attachment,
        duplicateOf: null,
      );
    } catch (error) {
      // Keep the (empty) memory so the user can attach a different file.
      logWarn('Image import failed', error);
      rethrow;
    }
  }

  Future<_AttachResult> _attachImage({
    required Memory memory,
    required File source,
    String? extensionHint,
  }) async {
    final StoredFile stored = await _files.importImage(
      source,
      extensionHint: extensionHint,
    );

    final Attachment? existing = await _memories.findByHash(
      stored.sha256,
      excludingMemoryId: memory.id,
    );
    if (existing != null) {
      // The bytes are already in the collection: drop the fresh copy and let the
      // caller tell the user instead of creating a silent duplicate.
      await _files.deleteRelative(stored.relativePath);
      return _AttachResult(attachment: null, duplicateOf: existing.memoryId);
    }

    final (int?, int?) size = await _files.imageSize(stored.relativePath);
    final String? thumbnail = await _files.createThumbnail(
      relativePath: stored.relativePath,
      width: size.$1,
      height: size.$2,
    );

    final Attachment attachment = Attachment(
      id: Ids.newId('att'),
      memoryId: memory.id,
      type: AttachmentType.image,
      relativePath: stored.relativePath,
      storedName: stored.storedName,
      mimeType: stored.mimeType,
      byteSize: stored.byteSize,
      sha256: stored.sha256,
      width: size.$1,
      height: size.$2,
      thumbnailRelativePath: thumbnail,
      sourceUri: source.path,
      createdAt: DateTime.now(),
    );
    await _memories.insertAttachment(attachment);

    if (_settings.ocrAuto) {
      await _enqueue(
        memoryId: memory.id,
        attachmentId: attachment.id,
        type: JobType.ocr,
      );
    }
    await _memories.touch(memory.id);
    return _AttachResult(attachment: attachment, duplicateOf: null);
  }

  /// Attaches an extra image to an existing memory.
  Future<Attachment?> attachImageToMemory(
    String memoryId, {
    required File source,
    String? extensionHint,
  }) async {
    final Memory? memory = await _memories.findById(memoryId);
    if (memory == null) throw StateError('Memory not found');
    final _AttachResult result = await _attachImage(
      memory: memory,
      source: source,
      extensionHint: extensionHint,
    );
    await _search.indexMemory(memoryId);
    _bump();
    return result.attachment;
  }

  /// Persists a finished recording and schedules transcription when a model is
  /// ready. Recording/playback are never blocked by a missing model.
  Future<Attachment> attachRecording({
    required String memoryId,
    required String tempPath,
    required Duration duration,
    Memory? createMemoryIfMissing,
  }) async {
    final Memory? memory = await _memories.findById(memoryId);
    if (memory == null) throw StateError('Memory not found');
    final StoredFile stored = await _files.persistAudio(
      tempPath,
      durationMs: duration.inMilliseconds,
    );
    final Attachment attachment = Attachment(
      id: Ids.newId('att'),
      memoryId: memoryId,
      type: AttachmentType.audio,
      relativePath: stored.relativePath,
      storedName: stored.storedName,
      mimeType: stored.mimeType,
      byteSize: stored.byteSize,
      sha256: stored.sha256,
      durationMs: duration.inMilliseconds,
      createdAt: DateTime.now(),
    );
    await _memories.insertAttachment(attachment);
    if (_settings.transcribeAuto) {
      await _enqueue(
        memoryId: memoryId,
        attachmentId: attachment.id,
        type: JobType.transcription,
      );
    }
    await _memories.touch(memoryId);
    await _search.indexMemory(memoryId);
    _bump();
    return attachment;
  }

  Future<Memory> createVoiceMemory({String title = ''}) async {
    final DateTime now = DateTime.now();
    final Memory memory = Memory(
      id: Ids.newId('mem'),
      title: title.trim(),
      note: '',
      kind: MemoryKind.voice,
      source: MemorySource.typed,
      createdAt: now,
      updatedAt: now,
    );
    await _memories.insert(memory);
    return memory;
  }

  Future<void> updateText({
    required String memoryId,
    required String title,
    required String note,
  }) async {
    final String clipped = note.length > 20000
        ? note.substring(0, 20000)
        : note;
    await _memories.updateText(
      id: memoryId,
      title: title.trim(),
      note: clipped,
    );
    await _search.indexMemory(memoryId);
    _bump();
  }

  Future<void> setTags(String memoryId, List<String> tags) async {
    await _taxonomy.setTags(memoryId, tags);
    await _search.indexMemory(memoryId);
    _bump();
  }

  Future<void> setCollections(
    String memoryId,
    Set<String> collectionIds,
  ) async {
    await _taxonomy.setCollections(memoryId, collectionIds);
    await _memories.touch(memoryId);
    _bump();
  }

  /// Renames without touching the body, used by grouping to give untitled
  /// imports a concrete subject.
  Future<void> renameMemory(String memoryId, String title) async {
    final Memory? memory = await _memories.findById(memoryId);
    if (memory == null) return;
    await updateText(memoryId: memoryId, title: title, note: memory.note);
  }

  Future<void> toggleFavorite(String memoryId, bool favorite) async {
    await _memories.setFavorite(memoryId, favorite);
    _bump();
  }

  /// Saves a user-edited transcript/OCR text without touching the original
  /// machine output, so reprocessing can never overwrite corrections.
  Future<void> saveExtractionEdit({
    required String extractionId,
    required String editedText,
  }) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'extractions',
      where: 'id = ?',
      whereArgs: <Object?>[extractionId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final ExtractionRecord record = ExtractionRecord.fromRow(rows.first);
    await _database.db.update(
      'extractions',
      <String, Object?>{
        'edited_text': editedText.trim(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[extractionId],
    );
    await _search.indexMemory(record.memoryId);
    _bump();
  }

  /// Reverts to the machine output by clearing the user's edit.
  Future<void> revertExtractionEdit(String extractionId) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'extractions',
      where: 'id = ?',
      whereArgs: <Object?>[extractionId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final ExtractionRecord record = ExtractionRecord.fromRow(rows.first);
    await _database.db.update(
      'extractions',
      <String, Object?>{'edited_text': record.rawText},
      where: 'id = ?',
      whereArgs: <Object?>[extractionId],
    );
    await _search.indexMemory(record.memoryId);
    _bump();
  }

  Future<void> retryJob(
    String memoryId,
    JobType type, {
    String? attachmentId,
  }) async {
    await _enqueue(
      memoryId: memoryId,
      attachmentId: attachmentId,
      type: type,
      force: true,
    );
    _bump();
  }

  /// Deletes a memory and everything derived from it: attachment files,
  /// thumbnails, extraction rows, index entry, embeddings, jobs, AI suggestions.
  /// Shared model assets under `models/` are never touched.
  Future<void> deleteMemory(String memoryId) async {
    final List<Attachment> attachments = await _memories.attachmentsFor(
      memoryId,
    );
    await _memories.softDelete(memoryId);
    await _search.removeMemory(memoryId);
    await _database.db.delete(
      'embeddings',
      where: 'memory_id = ?',
      whereArgs: <Object?>[memoryId],
    );
    await _jobs.deleteForMemory(memoryId);
    await SuggestionDao(_database).deleteForMemory(memoryId);
    await _database.db.delete(
      'related_dismissals',
      where: 'memory_id = ? OR related_id = ?',
      whereArgs: <Object?>[memoryId, memoryId],
    );
    await _memories.hardDelete(memoryId);

    for (final Attachment attachment in attachments) {
      await _files.deleteRelative(attachment.relativePath);
      await _files.deleteRelative(attachment.thumbnailRelativePath);
    }
    _bump();
  }

  Future<void> removeAttachment(Attachment attachment) async {
    await _memories.deleteAttachment(attachment.id);
    await _database.db.delete(
      'extractions',
      where: 'attachment_id = ?',
      whereArgs: <Object?>[attachment.id],
    );
    await _database.db.delete(
      'processing_jobs',
      where: 'attachment_id = ?',
      whereArgs: <Object?>[attachment.id],
    );
    await _files.deleteRelative(attachment.relativePath);
    await _files.deleteRelative(attachment.thumbnailRelativePath);
    await _search.indexMemory(attachment.memoryId);
    _bump();
  }

  Future<Memory?> findById(String id) => _memories.findById(id);

  Future<List<Memory>> timeline({
    MemoryFilter filter = MemoryFilter.all,
    bool oldestFirst = false,
    int limit = 20,
    int offset = 0,
    String? collectionId,
    String? tagName,
    bool includeExtractions = false,
  }) => _memories.timeline(
    filter: filter,
    oldestFirst: oldestFirst,
    limit: limit,
    offset: offset,
    collectionId: collectionId,
    tagName: tagName,
    includeExtractions: includeExtractions,
  );

  Future<List<SearchHit>> search(String query) => _search.search(query);

  Future<String> absolutePath(String relativePath) =>
      _paths.absolute(relativePath);

  /// File size for an attachment, used in the storage breakdown.
  Future<int> totalBytes() => _memories.totalAttachmentBytes();

  /// Deletes orphaned files (e.g. an import killed between copy and insert).
  Future<int> sweepOrphans() async {
    final Set<String> referenced = await _memories.allStoredPaths();
    return _files.sweepOrphans(referenced);
  }

  Future<String?> exportableFileName(Attachment attachment) async {
    final String absolute = await _paths.absolute(attachment.relativePath);
    return p.basename(absolute) == attachment.storedName ? absolute : null;
  }

  /// Rebuilds every index entry, used by Settings and after manual recovery.
  Future<int> reindex() async {
    final int count = await _search.reindex();
    _bump();
    return count;
  }

  Future<List<TagCount>> tagCounts() => _memories.tagCounts();

  Future<List<Tag>> allTags() => _taxonomy.allTags();
}
