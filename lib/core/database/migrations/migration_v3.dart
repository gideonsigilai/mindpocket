import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../fts_index.dart';

/// Version 3 preserves canonical user rows and makes FTS a transactional
/// projection. sqflite wraps this migration and user_version in one transaction.
abstract final class MigrationV3 {
  static const int version = 3;

  static Future<void> up(Database db) async {
    // The timeline orders by created_at, not the existing updated_at index.
    await db.execute('''
      CREATE INDEX idx_memories_timeline
      ON memories(created_at DESC, id DESC) WHERE deleted_at IS NULL
    ''');
    // Collection membership already has a collection_id prefix index, but not
    // its added_at ordering. This avoids sorting an entire large collection.
    await db.execute('''
      CREATE INDEX idx_collection_memories_added
      ON collection_memories(collection_id, added_at DESC)
    ''');

    // Discard only the derived index: repair missing, duplicate, and stale rows
    // from older non-transactional rebuilds, without modifying any user text.
    await db.delete('memory_fts');
    await db.execute(FtsIndex.insert);

    await db.execute('''
      CREATE TRIGGER memories_fts_insert AFTER INSERT ON memories BEGIN
        ${FtsIndex.insert} AND m.rowid = NEW.rowid;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER memories_fts_update
      AFTER UPDATE OF title, note, deleted_at, id ON memories BEGIN
        DELETE FROM memory_fts WHERE rowid = OLD.rowid;
        ${FtsIndex.insert} AND m.rowid = NEW.rowid;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER memories_fts_delete AFTER DELETE ON memories BEGIN
        DELETE FROM memory_fts WHERE rowid = OLD.rowid;
      END
    ''');

    // Identifiers below are fixed schema names, never user input. Trigger work
    // runs in the same SQLite statement/transaction as the canonical mutation.
    for (final String table in <String>['extractions', 'memory_tags']) {
      for (final String event in <String>['INSERT', 'UPDATE', 'DELETE']) {
        final String ids = switch (event) {
          'INSERT' => 'NEW.memory_id',
          'DELETE' => 'OLD.memory_id',
          _ => 'OLD.memory_id, NEW.memory_id',
        };
        await db.execute('''
          CREATE TRIGGER ${table}_fts_${event.toLowerCase()}
          AFTER $event ON $table BEGIN
            DELETE FROM memory_fts WHERE rowid IN (
              SELECT rowid FROM memories WHERE id IN ($ids)
            );
            ${FtsIndex.insert} AND m.id IN ($ids);
          END
        ''');
      }
    }
    await db.execute('''
      CREATE TRIGGER tags_fts_update AFTER UPDATE OF name ON tags BEGIN
        DELETE FROM memory_fts WHERE rowid IN (
          SELECT m.rowid FROM memories m JOIN memory_tags mt ON mt.memory_id = m.id
          WHERE mt.tag_id = NEW.id
        );
        ${FtsIndex.insert} AND m.id IN (
          SELECT memory_id FROM memory_tags WHERE tag_id = NEW.id
        );
      END
    ''');
  }
}
