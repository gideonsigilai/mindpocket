import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Version 1: core records, relationships, jobs, and the full-text index.
abstract final class MigrationV1 {
  static const int version = 1;

  static Future<void> up(Database db) async {
    await db.execute('''
      CREATE TABLE memories (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        kind TEXT NOT NULL DEFAULT 'note',
        source TEXT NOT NULL DEFAULT 'typed',
        favorite INTEGER NOT NULL DEFAULT 0,
        archived INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_memories_updated ON memories(deleted_at, updated_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_memories_favorite ON memories(favorite, updated_at DESC)',
    );

    await db.execute('''
      CREATE TABLE attachments (
        id TEXT PRIMARY KEY,
        memory_id TEXT NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
        type TEXT NOT NULL,
        relative_path TEXT NOT NULL,
        stored_name TEXT NOT NULL DEFAULT '',
        mime_type TEXT,
        byte_size INTEGER NOT NULL DEFAULT 0,
        sha256 TEXT NOT NULL DEFAULT '',
        width INTEGER,
        height INTEGER,
        duration_ms INTEGER,
        thumbnail_relative_path TEXT,
        source_uri TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_attachments_memory ON attachments(memory_id, created_at)',
    );
    // Exact duplicate detection for imports. Empty hashes are excluded by the
    // partial index so failures can never collide with real content.
    await db.execute('''
      CREATE UNIQUE INDEX idx_attachments_hash ON attachments(sha256)
      WHERE sha256 <> ''
    ''');

    await db.execute('''
      CREATE TABLE extractions (
        id TEXT PRIMARY KEY,
        attachment_id TEXT NOT NULL REFERENCES attachments(id) ON DELETE CASCADE,
        memory_id TEXT NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
        kind TEXT NOT NULL,
        raw_text TEXT NOT NULL DEFAULT '',
        edited_text TEXT NOT NULL DEFAULT '',
        engine TEXT NOT NULL DEFAULT '',
        language TEXT,
        confidence REAL,
        updated_at INTEGER NOT NULL,
        UNIQUE(attachment_id, kind)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_extractions_memory ON extractions(memory_id, kind)',
    );

    await db.execute('''
      CREATE TABLE tags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_tags_name ON tags(name COLLATE NOCASE)',
    );

    await db.execute('''
      CREATE TABLE memory_tags (
        memory_id TEXT NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
        tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
        PRIMARY KEY (memory_id, tag_id)
      )
    ''');
    await db.execute('CREATE INDEX idx_memory_tags_tag ON memory_tags(tag_id)');

    await db.execute('''
      CREATE TABLE collections (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_collections_name ON collections(name COLLATE NOCASE)',
    );

    await db.execute('''
      CREATE TABLE collection_memories (
        collection_id TEXT NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
        memory_id TEXT NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
        added_at INTEGER NOT NULL,
        PRIMARY KEY (collection_id, memory_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_collection_memories_memory ON collection_memories(memory_id)',
    );

    await db.execute('''
      CREATE TABLE processing_jobs (
        id TEXT PRIMARY KEY,
        memory_id TEXT NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
        attachment_id TEXT,
        type TEXT NOT NULL,
        status TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        error TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        started_at INTEGER,
        finished_at INTEGER
      )
    ''');
    // Idempotency: at most one job per (attachment, type). COALESCE keeps the
    // constraint effective for memory-scoped jobs with no attachment.
    await db.execute('''
      CREATE UNIQUE INDEX idx_jobs_unique
      ON processing_jobs(memory_id, IFNULL(attachment_id, ''), type)
    ''');
    await db.execute(
      'CREATE INDEX idx_jobs_status ON processing_jobs(status, created_at)',
    );

    await db.execute('''
      CREATE TABLE ai_suggestions (
        id TEXT PRIMARY KEY,
        memory_id TEXT NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
        provider TEXT NOT NULL DEFAULT '',
        title TEXT NOT NULL DEFAULT '',
        summary TEXT NOT NULL DEFAULT '',
        category TEXT NOT NULL DEFAULT '',
        tags_json TEXT NOT NULL DEFAULT '[]',
        collection_name TEXT NOT NULL DEFAULT '',
        tasks_json TEXT NOT NULL DEFAULT '[]',
        status TEXT NOT NULL DEFAULT 'pending',
        accepted_fields_json TEXT NOT NULL DEFAULT '[]',
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_ai_suggestions_memory ON ai_suggestions(memory_id, created_at DESC)',
    );

    // Full text index. Content is duplicated on purpose: snippet() and
    // highlight() require a contentful FTS5 table.
    await db.execute('''
      CREATE VIRTUAL TABLE memory_fts USING fts5(
        memory_id UNINDEXED,
        title,
        note,
        tags,
        ocr,
        transcript,
        tokenize = 'unicode61 remove_diacritics 2'
      )
    ''');
  }
}
