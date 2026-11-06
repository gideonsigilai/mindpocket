import 'dart:convert';

import 'package:path/path.dart' as p;

import '../models/attachment.dart';
import '../models/enums.dart';
import '../models/memory.dart';
import 'app_database.dart';

/// Every SQL statement about memories lives here. Callers get models, never
/// rows, so schema details cannot leak into controllers.
class MemoryDao {
  MemoryDao(this._database);

  final AppDatabase _database;

  Future<List<Memory>> timeline({
    MemoryFilter filter = MemoryFilter.all,
    bool oldestFirst = false,
    int limit = 20,
    int offset = 0,
    String? collectionId,
    String? tagName,
    bool includeExtractions = false,
  }) async {
    final List<String> clauses = <String>['m.deleted_at IS NULL'];
    final List<Object?> args = <Object?>[];

    switch (filter) {
      case MemoryFilter.all:
        break;
      case MemoryFilter.images:
        clauses.add(
          "EXISTS (SELECT 1 FROM attachments a WHERE a.memory_id = m.id AND a.type = 'image')",
        );
      case MemoryFilter.voice:
        clauses.add(
          "EXISTS (SELECT 1 FROM attachments a WHERE a.memory_id = m.id AND a.type = 'audio')",
        );
      case MemoryFilter.notes:
        // Screenshots and voice memories carry generated titles, so matching on
        // title text would list almost everything. A note is what has no media.
        clauses.add(
          "NOT EXISTS (SELECT 1 FROM attachments a WHERE a.memory_id = m.id)",
        );
      case MemoryFilter.favorites:
        clauses.add('m.favorite = 1');
    }
    if (collectionId != null) {
      clauses.add(
        'EXISTS (SELECT 1 FROM collection_memories cm WHERE cm.memory_id = m.id AND cm.collection_id = ?)',
      );
      args.add(collectionId);
    }
    if (tagName != null) {
      clauses.add(
        'EXISTS (SELECT 1 FROM memory_tags mt JOIN tags t ON t.id = mt.tag_id WHERE mt.memory_id = m.id AND t.name = ? COLLATE NOCASE)',
      );
      args.add(tagName);
    }

    final String order = oldestFirst ? 'ASC' : 'DESC';
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT m.*
      FROM memories m
      WHERE ${clauses.join(' AND ')}
      ORDER BY m.created_at $order, m.id $order
      LIMIT ? OFFSET ?
      ''',
      <Object?>[...args, limit, offset],
    );

    if (rows.isEmpty) return const <Memory>[];

    final List<String> ids = rows
        .map((Map<String, Object?> row) => row['id']! as String)
        .toList();
    final Map<String, List<Attachment>> attachments = await _attachmentsFor(
      ids,
    );
    final Map<String, List<String>> tags = await _tagsFor(ids);
    final Map<String, List<String>> collections = await _collectionsFor(ids);
    final Map<String, List<ProcessingJob>> jobs = await jobsFor(ids);
    final Map<String, List<ExtractionRecord>> extractions = includeExtractions
        ? await _extractionsFor(ids)
        : const <String, List<ExtractionRecord>>{};

    return rows
        .map((Map<String, Object?> row) {
          final String id = row['id']! as String;
          final List<ProcessingJob> memoryJobs =
              jobs[id] ?? const <ProcessingJob>[];
          final String? failedType = memoryJobs
              .where((ProcessingJob job) => job.status == JobStatus.failed)
              .firstOrNull
              ?.type
              .name;
          return Memory.fromRow(
            row,
            attachments: attachments[id] ?? const <Attachment>[],
            tags: tags[id] ?? const <String>[],
            collections: collections[id] ?? const <String>[],
            extractions: extractions[id] ?? const <ExtractionRecord>[],
            processing: Memory.reduceJobs(memoryJobs),
            jobError: failedType == null
                ? null
                : '${JobType.fromName(failedType).label} failed',
          );
        })
        .toList(growable: false);
  }

  Future<int> count({MemoryFilter filter = MemoryFilter.all}) async {
    final List<String> clauses = <String>['deleted_at IS NULL'];
    switch (filter) {
      case MemoryFilter.all:
        break;
      case MemoryFilter.images:
        clauses.add(
          "EXISTS (SELECT 1 FROM attachments a WHERE a.memory_id = memories.id AND a.type = 'image')",
        );
      case MemoryFilter.voice:
        clauses.add(
          "EXISTS (SELECT 1 FROM attachments a WHERE a.memory_id = memories.id AND a.type = 'audio')",
        );
      case MemoryFilter.notes:
        clauses.add(
          'NOT EXISTS (SELECT 1 FROM attachments a WHERE a.memory_id = memories.id)',
        );
      case MemoryFilter.favorites:
        clauses.add('favorite = 1');
    }
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      'SELECT COUNT(*) AS c FROM memories WHERE ${clauses.join(' AND ')}',
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<Memory?> findById(String id) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'memories',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final List<Attachment> attachments = await attachmentsFor(id);
    final List<ExtractionRecord> extractions = await extractionsForMemory(id);
    final List<ProcessingJob> jobs = await jobsFor(<String>[id]).then(
      (Map<String, List<ProcessingJob>> map) =>
          map[id] ?? const <ProcessingJob>[],
    );
    final List<String> tags =
        (await tagsForIds(<String>[id]))[id] ?? const <String>[];
    final List<String> collections =
        (await collectionsForIds(<String>[id]))[id] ?? const <String>[];
    final String? failed = jobs
        .where((ProcessingJob job) => job.status == JobStatus.failed)
        .map((ProcessingJob job) => '${job.type.label} failed')
        .firstOrNull;
    return Memory.fromRow(
      rows.first,
      attachments: attachments,
      extractions: extractions,
      tags: tags,
      collections: collections,
      processing: Memory.reduceJobs(jobs),
      jobError: failed,
    );
  }

  Future<void> insert(Memory memory) async {
    await _database.db.insert('memories', memory.toRow());
  }

  Future<void> touch(String id, {DateTime? at}) async {
    await _database.db.update(
      'memories',
      <String, Object?>{
        'updated_at': (at ?? DateTime.now()).millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> setFavorite(String id, bool favorite) async {
    await _database.db.update(
      'memories',
      <String, Object?>{
        'favorite': favorite ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> updateText({
    required String id,
    required String title,
    required String note,
  }) async {
    await _database.db.update(
      'memories',
      <String, Object?>{
        'title': title,
        'note': note,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// Hides the memory and its search entry in one database write. The service
  /// separately removes files and purges the canonical row.
  Future<void> softDelete(String id) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    await _database.db.update(
      'memories',
      <String, Object?>{'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> hardDelete(String id) async {
    await _database.db.delete(
      'memories',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<List<Attachment>> attachmentsFor(String memoryId) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'attachments',
      where: 'memory_id = ?',
      whereArgs: <Object?>[memoryId],
      orderBy: 'created_at ASC',
    );
    return rows.map(Attachment.fromRow).toList(growable: false);
  }

  Future<Map<String, List<Attachment>>> _attachmentsFor(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return <String, List<Attachment>>{};
    final List<Map<String, Object?>> rows = await _database.db.query(
      'attachments',
      where: 'memory_id IN (SELECT value FROM json_each(?))',
      whereArgs: <Object?>[jsonEncode(ids)],
      orderBy: 'created_at ASC',
    );
    final Map<String, List<Attachment>> grouped = <String, List<Attachment>>{};
    for (final Map<String, Object?> row in rows) {
      final Attachment attachment = Attachment.fromRow(row);
      grouped
          .putIfAbsent(attachment.memoryId, () => <Attachment>[])
          .add(attachment);
    }
    return grouped;
  }

  Future<void> insertAttachment(Attachment attachment) async {
    await _database.db.insert('attachments', attachment.toRow());
  }

  Future<void> updateAttachment(Attachment attachment) async {
    await _database.db.update(
      'attachments',
      attachment.toRow(),
      where: 'id = ?',
      whereArgs: <Object?>[attachment.id],
    );
  }

  Future<void> deleteAttachment(String attachmentId) async {
    await _database.db.delete(
      'attachments',
      where: 'id = ?',
      whereArgs: <Object?>[attachmentId],
    );
  }

  /// Looks up an existing attachment with the same content hash so imports can
  /// surface "already in your pocket" instead of duplicating bytes.
  Future<Attachment?> findByHash(
    String sha256, {
    String? excludingMemoryId,
  }) async {
    if (sha256.isEmpty) return null;
    final List<Map<String, Object?>> rows = await _database.db.query(
      'attachments',
      where: excludingMemoryId == null
          ? "sha256 <> '' AND sha256 = ?"
          : "sha256 <> '' AND sha256 = ? AND memory_id <> ?",
      whereArgs: excludingMemoryId == null
          ? <Object?>[sha256]
          : <Object?>[sha256, excludingMemoryId],
      limit: 1,
    );
    return rows.isEmpty ? null : Attachment.fromRow(rows.first);
  }

  Future<List<ExtractionRecord>> extractionsForMemory(String memoryId) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'extractions',
      where: 'memory_id = ?',
      whereArgs: <Object?>[memoryId],
    );
    return rows.map(ExtractionRecord.fromRow).toList(growable: false);
  }

  Future<Map<String, List<String>>> tagsForIds(List<String> ids) async {
    if (ids.isEmpty) return <String, List<String>>{};
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT mt.memory_id AS memory_id, t.name AS name
      FROM memory_tags mt JOIN tags t ON t.id = mt.tag_id
      WHERE mt.memory_id IN (SELECT value FROM json_each(?))
      ORDER BY t.name COLLATE NOCASE
      ''',
      <Object?>[jsonEncode(ids)],
    );
    final Map<String, List<String>> grouped = <String, List<String>>{};
    for (final Map<String, Object?> row in rows) {
      grouped
          .putIfAbsent(row['memory_id']! as String, () => <String>[])
          .add(row['name']! as String);
    }
    return grouped;
  }

  Future<Map<String, List<String>>> _tagsFor(List<String> ids) =>
      tagsForIds(ids);

  Future<Map<String, List<String>>> collectionsForIds(List<String> ids) async {
    if (ids.isEmpty) return <String, List<String>>{};
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT cm.memory_id AS memory_id, c.name AS name
      FROM collection_memories cm JOIN collections c ON c.id = cm.collection_id
      WHERE cm.memory_id IN (SELECT value FROM json_each(?))
      ORDER BY c.name COLLATE NOCASE
      ''',
      <Object?>[jsonEncode(ids)],
    );
    final Map<String, List<String>> grouped = <String, List<String>>{};
    for (final Map<String, Object?> row in rows) {
      grouped
          .putIfAbsent(row['memory_id']! as String, () => <String>[])
          .add(row['name']! as String);
    }
    return grouped;
  }

  Future<Map<String, List<String>>> _collectionsFor(List<String> ids) =>
      collectionsForIds(ids);

  /// All memories with their effective text, used by the local relatedness
  /// matcher and embedding rebuilds.
  Future<List<Memory>> allWithText({int limit = 500}) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'memories',
      columns: <String>[
        'id',
        'title',
        'note',
        'kind',
        'source',
        'favorite',
        'created_at',
        'updated_at',
      ],
      where: 'deleted_at IS NULL',
      orderBy: 'updated_at DESC',
      limit: limit,
    );
    if (rows.isEmpty) return const <Memory>[];
    final List<String> ids = rows
        .map((Map<String, Object?> r) => r['id']! as String)
        .toList();
    final Map<String, List<ExtractionRecord>> extractions =
        await _extractionsFor(ids);
    final Map<String, List<String>> tags = await tagsForIds(ids);
    return rows
        .map((Map<String, Object?> row) {
          final String id = row['id']! as String;
          return Memory.fromRow(
            row,
            extractions: extractions[id] ?? const <ExtractionRecord>[],
            tags: tags[id] ?? const <String>[],
          );
        })
        .toList(growable: false);
  }

  Future<Map<String, List<ExtractionRecord>>> _extractionsFor(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return <String, List<ExtractionRecord>>{};
    final List<Map<String, Object?>> rows = await _database.db.query(
      'extractions',
      where: 'memory_id IN (SELECT value FROM json_each(?))',
      whereArgs: <Object?>[jsonEncode(ids)],
    );
    final Map<String, List<ExtractionRecord>> grouped =
        <String, List<ExtractionRecord>>{};
    for (final Map<String, Object?> row in rows) {
      final ExtractionRecord record = ExtractionRecord.fromRow(row);
      grouped
          .putIfAbsent(record.memoryId, () => <ExtractionRecord>[])
          .add(record);
    }
    return grouped;
  }

  Future<Map<String, List<ProcessingJob>>> jobsFor(List<String> ids) async {
    if (ids.isEmpty) return <String, List<ProcessingJob>>{};
    final List<Map<String, Object?>> rows = await _database.db.query(
      'processing_jobs',
      where: 'memory_id IN (SELECT value FROM json_each(?))',
      whereArgs: <Object?>[jsonEncode(ids)],
      orderBy: 'updated_at DESC, id DESC',
    );
    final Map<String, List<ProcessingJob>> grouped =
        <String, List<ProcessingJob>>{};
    for (final Map<String, Object?> row in rows) {
      final ProcessingJob job = ProcessingJob.fromRow(row);
      grouped.putIfAbsent(job.memoryId, () => <ProcessingJob>[]).add(job);
    }
    return grouped;
  }

  Future<List<Memory>> memoriesInCollection(
    String collectionId, {
    int limit = 500,
  }) async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT m.* FROM memories m
      JOIN collection_memories cm ON cm.memory_id = m.id
      WHERE cm.collection_id = ? AND m.deleted_at IS NULL
      ORDER BY cm.added_at DESC
      LIMIT ?
      ''',
      <Object?>[collectionId, limit],
    );
    if (rows.isEmpty) return const <Memory>[];
    final List<String> ids = rows
        .map((Map<String, Object?> r) => r['id']! as String)
        .toList();
    final Map<String, List<Attachment>> attachments = await _attachmentsFor(
      ids,
    );
    final Map<String, List<String>> tags = await tagsForIds(ids);
    return rows
        .map(
          (Map<String, Object?> row) => Memory.fromRow(
            row,
            attachments:
                attachments[row['id']! as String] ?? const <Attachment>[],
            tags: tags[row['id']! as String] ?? const <String>[],
          ),
        )
        .toList(growable: false);
  }

  Future<List<TagCount>> tagCounts() async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery('''
      SELECT t.name AS name, COUNT(mt.memory_id) AS c
      FROM tags t JOIN memory_tags mt ON mt.tag_id = t.id
      JOIN memories m ON m.id = mt.memory_id AND m.deleted_at IS NULL
      GROUP BY t.id
      ORDER BY c DESC, t.name COLLATE NOCASE
    ''');
    return rows
        .map(
          (Map<String, Object?> row) => TagCount(
            name: row['name']! as String,
            count: (row['c'] as int?) ?? 0,
          ),
        )
        .toList(growable: false);
  }

  Future<int> totalAttachmentBytes() async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      'SELECT IFNULL(SUM(byte_size), 0) AS total FROM attachments',
    );
    return (rows.first['total'] as int?) ?? 0;
  }

  Future<int> attachmentCount() async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      'SELECT COUNT(*) AS c FROM attachments',
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// All distinct file paths, used to compute orphaned files during cleanup.
  Future<Set<String>> allStoredPaths() async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'attachments',
      columns: <String>['relative_path', 'thumbnail_relative_path'],
    );
    final Set<String> paths = <String>{};
    for (final Map<String, Object?> row in rows) {
      final Object? path = row['relative_path'];
      final Object? thumb = row['thumbnail_relative_path'];
      if (path is String && path.isNotEmpty) paths.add(path);
      if (thumb is String && thumb.isNotEmpty) paths.add(thumb);
    }
    return paths;
  }
}

enum MemoryFilter {
  all('All'),
  images('Images'),
  voice('Voice'),
  notes('Notes'),
  favorites('Starred');

  const MemoryFilter(this.label);

  final String label;
}

String relativeMediaPath(String folder, String fileName) =>
    p.posix.join(folder, fileName);
