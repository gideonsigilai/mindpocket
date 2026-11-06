import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mindpocket/core/database/app_database.dart';
import 'package:mindpocket/core/database/memory_dao.dart';
import 'package:mindpocket/core/database/search_dao.dart';
import 'package:mindpocket/core/database/migrations/migration_v1.dart';
import 'package:mindpocket/core/database/migrations/migration_v2.dart';
import 'package:mindpocket/core/models/enums.dart';
import 'package:mindpocket/core/models/memory.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A populated version-1 database must survive the upgrade to the current
/// schema: recollections, attachments, tags, and their search entries are the
/// user's only copy of that content.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    AppDatabase.initialise();
    tempDir = await Directory.systemTemp.createTemp('mindpocket_migration_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('a populated version-1 database upgrades without losing records', () async {
    final String path = p.join(tempDir.path, 'mindpocket.db');

    // Build and populate a real version-1 database, not a mock.
    final Database legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: MigrationV1.version,
        onCreate: (Database db, int version) => MigrationV1.up(db),
      ),
    );
    const String memoryId = 'mem_legacy';
    final int now = DateTime(2026, 1, 1).millisecondsSinceEpoch;
    await legacy.insert('memories', <String, Object?>{
      'id': memoryId,
      'title': 'Legacy note',
      'note': 'Written before the semantic layer existed',
      'kind': 'note',
      'source': 'typed',
      'favorite': 1,
      'archived': 0,
      'created_at': now,
      'updated_at': now,
    });
    await legacy.insert('attachments', <String, Object?>{
      'id': 'att_legacy',
      'memory_id': memoryId,
      'type': 'image',
      'relative_path': 'images/legacy.png',
      'stored_name': 'legacy.png',
      'mime_type': 'image/png',
      'byte_size': 42,
      'sha256': 'deadbeef',
      'created_at': now,
    });
    await legacy.insert('tags', <String, Object?>{
      'id': 'tag_legacy',
      'name': 'travel',
      'created_at': now,
    });
    await legacy.insert('memory_tags', <String, Object?>{
      'memory_id': memoryId,
      'tag_id': 'tag_legacy',
    });
    await legacy.insert('extractions', <String, Object?>{
      'id': 'ext_legacy',
      'attachment_id': 'att_legacy',
      'memory_id': memoryId,
      'kind': 'ocr',
      'raw_text': 'machine original',
      'edited_text': 'corrected itinerary',
      'updated_at': now,
    });
    await legacy.insert('memory_fts', <String, Object?>{
      'memory_id': memoryId,
      'title': 'Legacy note',
      'note': 'Written before the semantic layer existed',
      'tags': '',
      'ocr': '',
      'transcript': '',
    });
    await legacy.close();

    // Opening through the app's own opener runs the real upgrade path.
    final AppDatabase upgraded = await AppDatabase.openIn(tempDir.path);
    addTearDown(upgraded.close);

    final List<Map<String, Object?>> tables = await upgraded.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final Set<String> names = tables
        .map((Map<String, Object?> row) => '${row['name']}')
        .toSet();
    expect(
      names,
      containsAll(<String>['embeddings', 'related_dismissals', 'interests']),
    );

    final MemoryDao memories = MemoryDao(upgraded);
    final Memory? restored = await memories.findById(memoryId);
    expect(restored, isNotNull);
    expect(restored!.title, 'Legacy note');
    expect(restored.note, 'Written before the semantic layer existed');
    expect(restored.favorite, isTrue);
    expect(restored.kind, MemoryKind.note);
    expect(restored.tags, <String>['travel']);
    expect(restored.extractions.single.rawText, 'machine original');
    expect(restored.extractions.single.editedText, 'corrected itinerary');

    final List<Map<String, Object?>> attachments = await upgraded.db.query(
      'attachments',
      where: 'memory_id = ?',
      whereArgs: <Object?>[memoryId],
    );
    expect(attachments, hasLength(1));
    expect(attachments.single['relative_path'], 'images/legacy.png');

    // The full-text index still answers queries and keeps its snippet.
    final List<SearchHit> hits = await SearchDao(upgraded).search('legacy');
    expect(hits.map((SearchHit hit) => hit.memory.id), contains(memoryId));
    expect(
      (await SearchDao(upgraded).search('corrected itinerary'))
          .single
          .memory
          .id,
      memoryId,
    );
    expect(await SearchDao(upgraded).search('machine original'), isEmpty);

    // Foreign keys survive the upgrade, so derived rows stay tied to memories.
    await upgraded.db.insert('interests', <String, Object?>{
      'name': 'travel',
      'created_at': now,
    });
    await upgraded.db.insert('embeddings', <String, Object?>{
      'memory_id': memoryId,
      'model_id': 'test',
      'model_version': '1',
      'dim': 1,
      'vector': Uint8List.fromList(<int>[0, 0, 128, 63]),
      'created_at': now,
    });
    await upgraded.db.delete(
      'memories',
      where: 'id = ?',
      whereArgs: <Object?>[memoryId],
    );
    expect(
      await upgraded.db.query(
        'attachments',
        where: 'memory_id = ?',
        whereArgs: <Object?>[memoryId],
      ),
      isEmpty,
    );
    expect(await upgraded.db.query('embeddings'), isEmpty);
    expect(await upgraded.db.query('extractions'), isEmpty);
    expect(await upgraded.db.query('memory_tags'), isEmpty);
    expect(await upgraded.db.query('memory_fts'), isEmpty);
    expect((await upgraded.db.query('tags')).single['name'], 'travel');
    expect((await upgraded.db.query('interests')).single['name'], 'travel');
  });

  test('version-2 upgrade repairs FTS without changing canonical data', () async {
    final String path = p.join(tempDir.path, 'version2.db');
    final Database legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: MigrationV2.version,
        onCreate: (Database db, int version) async {
          await MigrationV1.up(db);
          await MigrationV2.up(db);
        },
      ),
    );
    final Memory memory = Memory(
      id: 'mem_v2',
      title: 'Preserved itinerary',
      note: 'Personal travel journal',
      kind: MemoryKind.note,
      source: MemorySource.typed,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await legacy.insert('memories', memory.toRow());
    await legacy.insert('interests', <String, Object?>{
      'name': 'travel',
      'created_at': 1,
    });
    // Older rebuilds could leave duplicates or index entries for deleted rows.
    for (final String id in <String>[memory.id, memory.id, 'no_such_memory']) {
      await legacy.insert('memory_fts', <String, Object?>{
        'memory_id': id,
        'title': 'obsolete index',
      });
    }
    await legacy.close();

    final AppDatabase upgraded = await AppDatabase.openAt(path);
    addTearDown(upgraded.close);
    expect(await upgraded.db.getVersion(), AppDatabase.schemaVersion);
    expect(await upgraded.db.query('memory_fts'), hasLength(1));
    final Memory? restored = await MemoryDao(upgraded).findById(memory.id);
    expect(restored!.toRow(), memory.toRow());
    expect(await TaxonomyDao(upgraded).interests(), <String>['travel']);
    expect(
      (await SearchDao(upgraded).search('itinerary')).single.memory.id,
      memory.id,
    );
    expect(await SearchDao(upgraded).search('obsolete'), isEmpty);
  });
}
