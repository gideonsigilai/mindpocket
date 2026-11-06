import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/app_database.dart';
import 'fts_index.dart';
import '../models/attachment.dart';
import '../models/memory.dart';
import '../utils/ids.dart';
import '../utils/text_utils.dart';

/// Owns search and explicit repair of the FTS5 projection. Canonical writes are
/// indexed by SQLite triggers in the same transaction; rebuilds are atomic too.
class SearchDao {
  SearchDao(this._database);

  final AppDatabase _database;

  /// Repairs one index row from a consistent canonical snapshot.
  Future<void> indexMemory(String memoryId) async {
    await _database.db.transaction((Transaction txn) async {
      await txn.rawDelete(
        'DELETE FROM memory_fts WHERE rowid = (SELECT rowid FROM memories WHERE id = ?)',
        <Object?>[memoryId],
      );
      await txn.execute('${FtsIndex.insert} AND m.id = ?', <Object?>[memoryId]);
    });
  }

  /// Rebuild entirely inside SQLite, without one read/write RPC per memory or
  /// copying all extracted text through the UI isolate. Readers see either the
  /// old index or the committed replacement, never a partially rebuilt index.
  Future<int> reindex() => _database.db.transaction((Transaction txn) async {
    await txn.delete('memory_fts');
    await txn.execute(FtsIndex.insert);
    final List<Map<String, Object?>> rows = await txn.rawQuery(
      'SELECT COUNT(*) AS c FROM memory_fts',
    );
    return rows.single['c']! as int;
  });

  Future<void> removeMemory(String memoryId) async {
    await _database.db.delete(
      'memory_fts',
      where: 'rowid = (SELECT rowid FROM memories WHERE id = ?)',
      whereArgs: <Object?>[memoryId],
    );
  }

  /// FTS search with BM25 ranking and a highlighted snippet.
  Future<List<SearchHit>> search(String rawQuery, {int limit = 40}) async {
    final String match = buildFtsQuery(rawQuery);
    if (match.isEmpty) return const <SearchHit>[];

    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT m.*,
        snippet(memory_fts, -1, '⟦', '⟧', ' … ', 24) AS snippet,
        bm25(memory_fts, 6.0, 2.0, 4.0, 1.0, 1.5) AS rank,
        (SELECT COUNT(*) FROM attachments a WHERE a.memory_id = m.id AND a.type='image') AS image_count,
        (SELECT COUNT(*) FROM attachments a WHERE a.memory_id = m.id AND a.type='audio') AS audio_count,
        (SELECT IFNULL(SUM(a.duration_ms),0) FROM attachments a WHERE a.memory_id = m.id AND a.type='audio') AS audio_ms,
        (SELECT IFNULL(a.thumbnail_relative_path, a.relative_path) FROM attachments a
          WHERE a.memory_id = m.id AND a.type='image' ORDER BY a.created_at LIMIT 1) AS thumb_hint
      FROM memory_fts
      JOIN memories m ON m.id = memory_fts.memory_id
      WHERE memory_fts MATCH ? AND m.deleted_at IS NULL
      ORDER BY rank
      LIMIT ?
      ''',
      <Object?>[match, limit],
    );

    return rows
        .map((Map<String, Object?> row) {
          final double rank = ((row['rank'] as num?) ?? 0).toDouble();
          return SearchHit(
            memory: Memory.fromSearchRow(row),
            snippet: ((row['snippet'] as String?) ?? '').trim(),
            score: rank.abs(),
          );
        })
        .toList(growable: false);
  }

  /// Direct tag search, used by the search suggestions under the field.
  Future<List<TagCount>> matchingTags(String prefix, {int limit = 8}) async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT t.name AS name, COUNT(mt.memory_id) AS c
      FROM tags t JOIN memory_tags mt ON mt.tag_id = t.id
      JOIN memories m ON m.id = mt.memory_id AND m.deleted_at IS NULL
      WHERE t.name LIKE ? ESCAPE '\\'
      GROUP BY t.id ORDER BY c DESC, t.name LIMIT ?
      ''',
      <Object?>[
        '${prefix.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%',
        limit,
      ],
    );
    return rows
        .map(
          (Map<String, Object?> row) => TagCount(
            name: row['name']! as String,
            count: (row['c'] as int?) ?? 0,
          ),
        )
        .toList(growable: false);
  }
}

/// Tag and collection relationships.
class TaxonomyDao {
  TaxonomyDao(this._database);

  final AppDatabase _database;

  Future<void> setTags(String memoryId, List<String> names) async {
    final Database db = _database.db;
    final List<String> cleaned = names
        .map((String name) => name.trim())
        .where((String name) => name.isNotEmpty)
        .map((String name) => name.length > 40 ? name.substring(0, 40) : name)
        .toSet()
        .toList(growable: false);

    await db.transaction((Transaction txn) async {
      final Batch batch = txn.batch();
      batch.delete(
        'memory_tags',
        where: 'memory_id = ?',
        whereArgs: <Object?>[memoryId],
      );
      for (final String name in cleaned) {
        batch.insert(
          'tags',
          Tag(id: Ids.newId('tag'), name: name).toRow(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        // Resolve the actual id even when a differently-cased tag already
        // exists. No per-tag query or stale generated id can lose the link.
        batch.rawInsert(
          'INSERT OR IGNORE INTO memory_tags(memory_id, tag_id) '
          'SELECT ?, id FROM tags WHERE name = ? COLLATE NOCASE',
          <Object?>[memoryId, name],
        );
      }
      batch.rawDelete(
        'DELETE FROM tags WHERE NOT EXISTS '
        '(SELECT 1 FROM memory_tags mt WHERE mt.tag_id = tags.id)',
      );
      await batch.commit(noResult: true);
    });
  }

  Future<List<Tag>> allTags() async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'tags',
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(Tag.fromRow).toList(growable: false);
  }

  Future<List<Collection>> collections() async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery('''
      SELECT c.*, (SELECT COUNT(*) FROM collection_memories cm
        JOIN memories m ON m.id = cm.memory_id AND m.deleted_at IS NULL
        WHERE cm.collection_id = c.id) AS memory_count
      FROM collections c
      ORDER BY c.updated_at DESC
    ''');
    return rows.map(Collection.fromRow).toList(growable: false);
  }

  Future<Collection> createCollection(
    String name, {
    String description = '',
  }) async {
    final Collection collection = Collection(
      id: Ids.newId('col'),
      name: name.trim(),
      description: description.trim(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _database.db.insert('collections', collection.toRow());
    return collection;
  }

  Future<void> updateCollection(Collection collection) async {
    await _database.db.update(
      'collections',
      <String, Object?>{
        'name': collection.name,
        'description': collection.description,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[collection.id],
    );
  }

  Future<void> deleteCollection(String id) async {
    await _database.db.delete(
      'collections',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> setCollections(
    String memoryId,
    Set<String> collectionIds,
  ) async {
    final Database db = _database.db;
    await db.transaction((Transaction txn) async {
      final Batch batch = txn.batch();
      batch.delete(
        'collection_memories',
        where: 'memory_id = ?',
        whereArgs: <Object?>[memoryId],
      );
      final int now = DateTime.now().millisecondsSinceEpoch;
      for (final String collectionId in collectionIds) {
        batch.insert('collection_memories', <String, Object?>{
          'collection_id': collectionId,
          'memory_id': memoryId,
          'added_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<Set<String>> collectionIdsFor(String memoryId) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'collection_memories',
      columns: <String>['collection_id'],
      where: 'memory_id = ?',
      whereArgs: <Object?>[memoryId],
    );
    return rows
        .map((Map<String, Object?> row) => row['collection_id']! as String)
        .toSet();
  }

  Future<void> addToCollection(String collectionId, String memoryId) async {
    await _database.db.insert('collection_memories', <String, Object?>{
      'collection_id': collectionId,
      'memory_id': memoryId,
      'added_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> removeFromCollection(
    String collectionId,
    String memoryId,
  ) async {
    await _database.db.delete(
      'collection_memories',
      where: 'collection_id = ? AND memory_id = ?',
      whereArgs: <Object?>[collectionId, memoryId],
    );
  }

  Future<List<String>> interests() async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'interests',
      orderBy: 'name COLLATE NOCASE',
    );
    return rows
        .map((Map<String, Object?> row) => row['name']! as String)
        .toList(growable: false);
  }

  Future<void> setInterests(List<String> names) async {
    await _database.db.transaction((Transaction txn) async {
      final Batch batch = txn.batch()..delete('interests');
      final int now = DateTime.now().millisecondsSinceEpoch;
      for (final String name
          in names
              .map((String value) => value.trim())
              .where((String value) => value.isNotEmpty)
              .toSet()) {
        batch.insert('interests', <String, Object?>{
          'name': name,
          'created_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
    });
  }
}

/// Vector store for the optional local semantic layer. Vectors are little
/// endian float32 blobs; model id + version are part of the key so switching
/// models cannot mix incompatible spaces.
class EmbeddingDao {
  EmbeddingDao(this._database);

  final AppDatabase _database;

  Future<void> upsert({
    required String memoryId,
    required String modelId,
    required String modelVersion,
    required List<double> vector,
    required String sourceHash,
  }) async {
    final Float32List floats = Float32List.fromList(vector);
    await _database.db.insert('embeddings', <String, Object?>{
      'memory_id': memoryId,
      'model_id': modelId,
      'model_version': modelVersion,
      'dim': vector.length,
      'vector': floats.buffer.asUint8List(),
      'source_hash': sourceHash,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, List<double>>> vectors(String modelId) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'embeddings',
      where: 'model_id = ?',
      whereArgs: <Object?>[modelId],
    );
    final Map<String, List<double>> result = <String, List<double>>{};
    for (final Map<String, Object?> row in rows) {
      final Object? blob = row['vector'];
      if (blob is! Uint8List) continue;
      final Float32List floats = Float32List.view(
        blob.buffer,
        blob.offsetInBytes,
        blob.lengthInBytes ~/ 4,
      );
      result[row['memory_id']! as String] = floats.toList(growable: false);
    }
    return result;
  }

  Future<int> count(String modelId) async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      'SELECT COUNT(*) AS c FROM embeddings WHERE model_id = ?',
      <Object?>[modelId],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<void> clear({String? modelId}) async {
    if (modelId == null) {
      await _database.db.delete('embeddings');
    } else {
      await _database.db.delete(
        'embeddings',
        where: 'model_id = ?',
        whereArgs: <Object?>[modelId],
      );
    }
  }

  Future<Set<String>> dismissedRelated(
    String memoryId,
    String referenceKind,
  ) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'related_dismissals',
      columns: <String>['related_id'],
      where: 'memory_id = ? AND reference_kind = ?',
      whereArgs: <Object?>[memoryId, referenceKind],
    );
    return rows
        .map((Map<String, Object?> row) => row['related_id']! as String)
        .toSet();
  }

  Future<void> dismissRelated({
    required String memoryId,
    required String relatedId,
    required String referenceKind,
    required String referenceLabel,
  }) async {
    await _database.db.insert('related_dismissals', <String, Object?>{
      'memory_id': memoryId,
      'related_id': relatedId,
      'reference_kind': referenceKind,
      'reference_label': referenceLabel,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Hash of the text a vector was built from, so staleness is checkable
  /// without re-running inference.
  Future<Map<String, String>> sourceHashes(String modelId) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'embeddings',
      columns: <String>['memory_id', 'source_hash'],
      where: 'model_id = ?',
      whereArgs: <Object?>[modelId],
    );
    return <String, String>{
      for (final Map<String, Object?> row in rows)
        row['memory_id']! as String: (row['source_hash'] as String?) ?? '',
    };
  }
}

/// AI suggestion persistence. Suggestions are inert data until accepted.
class SuggestionDao {
  SuggestionDao(this._database);

  final AppDatabase _database;

  Future<void> insert(AiSuggestion suggestion) async {
    await _database.db.insert(
      'ai_suggestions',
      suggestion.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<AiSuggestion?> latestFor(String memoryId) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'ai_suggestions',
      where: 'memory_id = ? AND status = ?',
      whereArgs: <Object?>[memoryId, AiSuggestionStatus.pending.name],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : AiSuggestion.fromRow(rows.first);
  }

  Future<void> updateStatus(
    String id,
    AiSuggestionStatus status,
    Set<String> accepted,
  ) async {
    await _database.db.update(
      'ai_suggestions',
      <String, Object?>{
        'status': status.name,
        'accepted_fields_json': jsonEncode(accepted.toList()),
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> deleteForMemory(String memoryId) async {
    await _database.db.delete(
      'ai_suggestions',
      where: 'memory_id = ?',
      whereArgs: <Object?>[memoryId],
    );
  }
}
