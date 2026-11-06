import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mindpocket/core/database/app_database.dart';
import 'package:mindpocket/core/database/job_dao.dart';
import 'package:mindpocket/core/database/memory_dao.dart';
import 'package:mindpocket/core/database/search_dao.dart';
import 'package:mindpocket/core/models/attachment.dart';
import 'package:mindpocket/core/models/enums.dart';
import 'package:mindpocket/core/models/memory.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late AppDatabase database;
  late MemoryDao memories;
  late SearchDao search;
  late TaxonomyDao taxonomy;
  late JobDao jobs;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mindpocket_database_');
    database = await AppDatabase.openIn(directory.path);
    memories = MemoryDao(database);
    search = SearchDao(database);
    taxonomy = TaxonomyDao(database);
    jobs = JobDao(database);
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  Memory note(String id, {String title = 'Original itinerary'}) => Memory(
    id: id,
    title: title,
    note: 'Personal travel journal',
    kind: MemoryKind.note,
    source: MemorySource.typed,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  Future<void> image(String memoryId, String id, {String hash = ''}) async {
    await database.db.insert('attachments', <String, Object?>{
      'id': id,
      'memory_id': memoryId,
      'type': 'image',
      'relative_path': 'images/$id.png',
      'sha256': hash,
      'created_at': 1,
    });
  }

  test(
    'canonical edits and cascades update search without service repair',
    () async {
      await memories.insert(note('memory'));
      expect((await search.search('itinerary')).single.memory.id, 'memory');
      await taxonomy.setTags('memory', <String>['holiday', 'HOLIDAY']);
      expect((await memories.findById('memory'))!.tags, <String>['holiday']);
      expect((await search.search('holiday')).single.memory.id, 'memory');

      await image('memory', 'image');
      await database.db.insert('extractions', <String, Object?>{
        'id': 'extraction',
        'attachment_id': 'image',
        'memory_id': 'memory',
        'kind': 'ocr',
        'raw_text': 'machine draft',
        'edited_text': 'corrected reservation',
        'updated_at': 1,
      });
      expect((await search.search('reservation')).single.memory.id, 'memory');
      expect(await search.search('machine'), isEmpty);

      await database.db.update(
        'extractions',
        <String, Object?>{'edited_text': ' \t\n '},
        where: 'id = ?',
        whereArgs: <Object?>['extraction'],
      );
      expect((await search.search('machine draft')).single.memory.id, 'memory');
      expect(await search.search('reservation'), isEmpty);
      await memories.deleteAttachment('image');
      expect(await search.search('machine'), isEmpty);
      expect(await database.db.query('extractions'), isEmpty);

      await memories.updateText(
        id: 'memory',
        title: 'Revised tickets',
        note: '',
      );
      expect(await search.search('itinerary'), isEmpty);
      expect((await search.search('tickets')).single.memory.id, 'memory');
      await memories.softDelete('memory');
      expect(await search.search('tickets'), isEmpty);
      await memories.hardDelete('memory');
      expect(await database.db.query('memory_fts'), isEmpty);
      expect(await database.db.query('memory_tags'), isEmpty);
    },
  );

  test('failed FTS rebuild rolls back the cleared index', () async {
    await memories.insert(note('memory'));
    // A real SQL projection failure after DELETE must not leave search empty.
    await database.db.execute(
      'ALTER TABLE extractions RENAME COLUMN raw_text TO unavailable_raw_text',
    );
    await expectLater(search.reindex(), throwsA(isA<DatabaseException>()));
    expect((await search.search('itinerary')).single.memory.id, 'memory');
    await database.db.execute(
      'ALTER TABLE extractions RENAME COLUMN unavailable_raw_text TO raw_text',
    );
    expect(await search.reindex(), 1);
    expect((await search.search('itinerary')).single.memory.id, 'memory');
  });

  test('failed tag replacement preserves relationships and search', () async {
    await memories.insert(note('memory'));
    await taxonomy.setTags('memory', <String>['originaltag']);
    await database.db.execute('''
      CREATE TRIGGER reject_blocked_tag BEFORE INSERT ON memory_tags
      WHEN EXISTS (SELECT 1 FROM tags WHERE id = NEW.tag_id AND name = 'blocked')
      BEGIN SELECT RAISE(ABORT, 'blocked test tag'); END
    ''');
    await expectLater(
      taxonomy.setTags('memory', <String>['newtag', 'blocked']),
      throwsA(isA<DatabaseException>()),
    );
    expect((await memories.findById('memory'))!.tags, <String>['originaltag']);
    expect((await search.search('originaltag')).single.memory.id, 'memory');
    expect(await search.search('newtag'), isEmpty);
    expect((await taxonomy.allTags()).map((Tag tag) => tag.name), <String>[
      'originaltag',
    ]);
  });

  test(
    'failed collection replacement preserves previous memberships',
    () async {
      await memories.insert(note('memory'));
      final Collection original = await taxonomy.createCollection('Original');
      final Collection replacement = await taxonomy.createCollection(
        'Replacement',
      );
      await taxonomy.setCollections('memory', <String>{original.id});
      await expectLater(
        taxonomy.setCollections('memory', <String>{replacement.id, 'missing'}),
        throwsA(isA<DatabaseException>()),
      );
      expect(await taxonomy.collectionIdsFor('memory'), <String>{original.id});
    },
  );

  test(
    'failed interest replacement does not discard existing preferences',
    () async {
      await taxonomy.setInterests(<String>['travel']);
      await database.db.execute('''
      CREATE TRIGGER reject_blocked_interest BEFORE INSERT ON interests
      WHEN NEW.name = 'blocked'
      BEGIN SELECT RAISE(ABORT, 'blocked test interest'); END
    ''');
      await expectLater(
        taxonomy.setInterests(<String>['photography', 'blocked']),
        throwsA(isA<DatabaseException>()),
      );
      expect(await taxonomy.interests(), <String>['travel']);
    },
  );

  test(
    'parallel enqueue returns one persisted job and reset matches disk',
    () async {
      await memories.insert(note('memory'));
      final List<ProcessingJob?> enqueued = await Future.wait(
        List<Future<ProcessingJob?>>.generate(
          20,
          (_) => jobs.enqueue(
            memoryId: 'memory',
            attachmentId: null,
            type: JobType.ocr,
          ),
        ),
      );
      final String id = enqueued.first!.id;
      expect(enqueued.map((ProcessingJob? job) => job!.id).toSet(), <String>{
        id,
      });
      expect(await jobs.jobsForMemory('memory'), hasLength(1));
      await jobs.markRunning(id);
      await jobs.markCompleted(id);
      final ProcessingJob reset = (await jobs.enqueue(
        memoryId: 'memory',
        attachmentId: null,
        type: JobType.ocr,
        force: true,
      ))!;
      final ProcessingJob persisted = (await jobs.jobsForMemory('memory'))
          .single;
      expect(reset.toRow(), persisted.toRow());
      expect(reset.startedAt, isNull);
      expect(reset.finishedAt, isNull);
    },
  );

  test('queued OCR can bypass an older parked transcription', () async {
    await memories.insert(note('memory'));
    await jobs.enqueue(
      memoryId: 'memory',
      attachmentId: null,
      type: JobType.transcription,
    );
    final ProcessingJob ocr = (await jobs.enqueue(
      memoryId: 'memory',
      attachmentId: null,
      type: JobType.ocr,
    ))!;
    final List<ProcessingJob> runnable = await jobs.nextQueued(
      excludeTypes: <JobType>[JobType.transcription],
    );
    expect(runnable.single.id, ocr.id);
    expect(await jobs.pendingCount(), 2);
  });

  test('large hydration binds ids without a SQL variable per memory', () async {
    final List<String> ids = List<String>.generate(
      1200,
      (int i) => 'memory_$i',
    );
    final Batch batch = database.db.batch();
    for (final String id in ids) {
      batch.insert('memories', note(id).toRow());
    }
    await batch.commit(noResult: true);
    await taxonomy.setTags(ids.last, <String>['lasttag']);
    final Collection collection = await taxonomy.createCollection(
      'Large collection',
    );
    await taxonomy.addToCollection(collection.id, ids.last);
    await image(ids.last, 'last_image', hash: 'last_hash');
    await database.db.insert('extractions', <String, Object?>{
      'id': 'last_extraction',
      'attachment_id': 'last_image',
      'memory_id': ids.last,
      'kind': 'ocr',
      'raw_text': 'destination photograph',
      'updated_at': 1,
    });
    await jobs.enqueue(
      memoryId: ids.last,
      attachmentId: 'last_image',
      type: JobType.ocr,
    );
    expect((await memories.tagsForIds(ids))[ids.last], <String>['lasttag']);
    expect((await memories.collectionsForIds(ids))[ids.last], <String>[
      'Large collection',
    ]);
    expect((await memories.jobsFor(ids))[ids.last], hasLength(1));
    expect((await memories.findByHash('last_hash'))!.memoryId, ids.last);
    final List<Memory> timeline = await memories.timeline(
      limit: 1200,
      includeExtractions: true,
    );
    expect(timeline, hasLength(1200));
    expect(
      timeline
          .singleWhere((Memory memory) => memory.id == ids.last)
          .attachments,
      hasLength(1),
    );
    expect(
      timeline.singleWhere((Memory memory) => memory.id == ids.last).ocrText,
      'destination photograph',
    );
    expect(await memories.allWithText(limit: 1200), hasLength(1200));
  });

  test(
    'conflicting memory insert cannot cascade-delete existing user content',
    () async {
      await memories.insert(note('memory'));
      await image('memory', 'image', hash: 'unique_hash');
      await taxonomy.setTags('memory', <String>['preserved']);
      await expectLater(
        memories.insert(note('memory', title: 'Replacement')),
        throwsA(isA<DatabaseException>()),
      );
      expect((await memories.findById('memory'))!.title, 'Original itinerary');
      expect(await memories.attachmentsFor('memory'), hasLength(1));
      expect((await search.search('preserved')).single.memory.id, 'memory');
    },
  );

  test(
    'disk close is idempotent and reopening preserves searchable content',
    () async {
      await memories.insert(note('memory'));
      await database.close();
      await database.close();
      database = await AppDatabase.openAt(
        p.join(directory.path, 'mindpocket.db'),
      );
      expect(
        (await MemoryDao(database).findById('memory'))!.title,
        'Original itinerary',
      );
      expect(
        (await SearchDao(database).search('itinerary')).single.memory.id,
        'memory',
      );
      expect(await database.isHealthy(), isTrue);
    },
  );
}
