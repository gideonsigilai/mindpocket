import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Version 2 adds the local semantic layer:
/// * `embeddings` — one vector row per memory, keyed by model id/version so a
///   model change can trigger a clean rebuild.
/// * `related_dismissals` — remembered "not related" decisions so a suggestion
///   the user dismissed never nags again.
/// * `interests` — topics the user deliberately picked, used as an explicit
///   relevance reference.
abstract final class MigrationV2 {
  static const int version = 2;

  static Future<void> up(Database db) async {
    await db.execute('''
      CREATE TABLE embeddings (
        memory_id TEXT NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
        model_id TEXT NOT NULL,
        model_version TEXT NOT NULL,
        dim INTEGER NOT NULL,
        vector BLOB NOT NULL,
        source_hash TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        PRIMARY KEY (memory_id, model_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_embeddings_model ON embeddings(model_id, model_version)',
    );

    await db.execute('''
      CREATE TABLE related_dismissals (
        memory_id TEXT NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
        related_id TEXT NOT NULL,
        reference_kind TEXT NOT NULL,
        reference_label TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (memory_id, related_id, reference_kind, reference_label)
      )
    ''');

    await db.execute('''
      CREATE TABLE interests (
        name TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL
      )
    ''');
  }
}
