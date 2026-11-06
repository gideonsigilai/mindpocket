/// Canonical FTS projection, executed by SQLite in the sqflite worker isolate.
/// Keeping FTS rowids equal to memory rowids makes replacement/deletion a
/// primary-key lookup instead of scanning the unindexed memory_id column.
abstract final class FtsIndex {
  static const String insert = '''
    INSERT INTO memory_fts(rowid, memory_id, title, note, tags, ocr, transcript)
    SELECT m.rowid, m.id, m.title, m.note,
      IFNULL((SELECT group_concat(name, ' ') FROM (
        SELECT t.name AS name FROM memory_tags mt
        JOIN tags t ON t.id = mt.tag_id WHERE mt.memory_id = m.id
        ORDER BY t.name COLLATE NOCASE
      )), ''),
      IFNULL((SELECT group_concat(text, char(10)) FROM (
        SELECT CASE WHEN trim(e.edited_text, char(9) || char(10) || char(13) || ' ') <> ''
          THEN e.edited_text ELSE e.raw_text END AS text
        FROM extractions e WHERE e.memory_id = m.id AND e.kind = 'ocr'
        ORDER BY e.id
      )), ''),
      IFNULL((SELECT group_concat(text, char(10)) FROM (
        SELECT CASE WHEN trim(e.edited_text, char(9) || char(10) || char(13) || ' ') <> ''
          THEN e.edited_text ELSE e.raw_text END AS text
        FROM extractions e WHERE e.memory_id = m.id AND e.kind = 'transcript'
        ORDER BY e.id
      )), '')
    FROM memories m WHERE m.deleted_at IS NULL
  ''';
}
