import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mindpocket/core/models/enums.dart';
import 'package:mindpocket/core/models/memory.dart';
import 'package:mindpocket/core/services/processing/share_intake_service.dart';
import 'package:mindpocket/core/services/storage/share_import_service.dart';

import 'support/harness.dart';

void main() {
  late Harness harness;

  setUp(() async {
    harness = await Harness.create();
  });

  tearDown(() async {
    await harness.dispose();
  });

  ShareImportService importer() => ShareImportService(
    intake: ShareIntakeService(),
    memories: harness.memories,
    memoryDao: harness.memoryDao,
  );

  group('shared content', () {
    test('a shared image is saved through the same import path', () async {
      final File image = await harness.writePng('shared.png', size: 31);
      final ShareImportService service = importer();

      final String? memoryId = await service.import(
        IncomingShare(
          kind: IncomingShareKind.image,
          filePath: image.path,
          mimeType: 'image/png',
        ),
      );

      expect(memoryId, isNotNull);
      final Memory memory = (await harness.memoryDao.findById(memoryId!))!;
      expect(memory.source, MemorySource.share);
      expect(memory.attachments.single.relativePath, isNotEmpty);
      expect(service.lastMessage.value, contains('Saved'));
      expect(service.importedCount.value, 1);
    });

    test(
      'the same shared bytes are reported as a duplicate, not imported twice',
      () async {
        final File image = await harness.writePng('again.png', size: 32);
        final ShareImportService service = importer();
        final IncomingShare share = IncomingShare(
          kind: IncomingShareKind.image,
          filePath: image.path,
        );

        final String? first = await service.import(share);
        final String? second = await service.import(share);

        expect(second, first);
        expect(service.lastMessage.value, contains('already'));
        expect(await harness.memoryDao.attachmentCount(), 1);
      },
    );

    test('shared text keeps every word and gets a readable title', () async {
      final ShareImportService service = importer();

      final String? memoryId = await service.import(
        const IncomingShare(
          kind: IncomingShareKind.text,
          text: 'Travel Planner navigation\nUse five bottom tabs, sun accent on the active one.',
        ),
      );

      final Memory memory = (await harness.memoryDao.findById(memoryId!))!;
      expect(memory.title, 'Travel Planner navigation');
      expect(memory.note, contains('five bottom tabs'));
      expect(memory.source, MemorySource.share);
      expect(memory.kind, MemoryKind.note);
    });

    test(
      'long shared text is truncated in the title but kept in the note',
      () async {
        final String body = 'x' * 400;
        final ShareImportService service = importer();
        final String? memoryId = await service.import(
          IncomingShare(kind: IncomingShareKind.text, text: body),
        );

        final Memory memory = (await harness.memoryDao.findById(memoryId!))!;
        expect(memory.title.length, lessThanOrEqualTo(61));
        expect(memory.note.length, 400);
      },
    );

    test('an expired file is reported instead of silently dropped', () async {
      final ShareImportService service = importer();

      final String? memoryId = await service.import(
        const IncomingShare(
          kind: IncomingShareKind.image,
          filePath: '/nonexistent/cache/shared.png',
        ),
      );

      expect(memoryId, isNull);
      expect(service.lastMessage.value, contains('expired'));
      expect(await harness.memoryDao.timeline(limit: 5), isEmpty);
    });

    test('unsupported payloads say why nothing was saved', () async {
      final ShareImportService service = importer();

      final String? memoryId = await service.import(
        const IncomingShare(
          kind: IncomingShareKind.unsupported,
          filePath: '/tmp/a.pdf',
        ),
      );

      expect(memoryId, isNull);
      expect(service.lastMessage.value, contains('cannot be imported'));
    });

    test('empty shared text is refused', () async {
      final ShareImportService service = importer();
      final String? memoryId = await service.import(
        const IncomingShare(kind: IncomingShareKind.text, text: '   '),
      );

      expect(memoryId, isNull);
      expect(await harness.memoryDao.timeline(limit: 5), isEmpty);
    });
  });
}
