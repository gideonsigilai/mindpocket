import 'package:flutter_test/flutter_test.dart';
import 'package:mindpocket/core/models/memory.dart';
import 'package:mindpocket/core/services/ai/related_service.dart';

import 'support/harness.dart';

void main() {
  test(
    'related screenshots compare OCR and retain their image previews',
    () async {
      final Harness harness = await Harness.create();
      addTearDown(harness.dispose);

      Future<Memory> screenshot(String title, String text, int color) async {
        harness.ocr.text = text;
        final outcome = await harness.memories.createFromImage(
          source: await harness.writePng('$color.png', size: color),
          title: title,
        );
        await harness.processing.drain();
        return (await harness.memories.findById(outcome.memoryId))!;
      }

      final Memory reference = await screenshot(
        'City itinerary',
        'coast train tickets museum',
        3,
      );
      final Memory related = await screenshot(
        'City itinerary',
        'coast train tickets museums',
        5,
      );
      final Memory unrelated = await screenshot(
        'City itinerary',
        'coast train camera notebook',
        7,
      );

      final List<RelatedSuggestion> suggestions = await RelatedService(
        harness.database,
        harness.memories,
      ).forMemory(reference);
      expect(
        suggestions.map((RelatedSuggestion item) => item.memory.id),
        contains(related.id),
      );
      expect(
        suggestions.map((RelatedSuggestion item) => item.memory.id),
        isNot(contains(unrelated.id)),
      );
      final RelatedSuggestion match = suggestions.firstWhere(
        (RelatedSuggestion item) => item.memory.id == related.id,
      );
      expect(match.sharedTerms, containsAll(<String>['coast', 'train']));
      expect(match.memory.primaryThumbnailPath, related.primaryThumbnailPath);
    },
  );

  test('detail matches include exactly 90% and reject weaker overlap', () async {
    final Harness harness = await Harness.create();
    addTearDown(harness.dispose);
    Future<Memory> note(String text) =>
        harness.memories.createNote(title: '', note: text);
    final Memory reference = await note('abcde fghij');
    final Memory substitution = await note('abcde fghiz');
    final Memory deletion = await note('abcde fghi');
    final Memory insertion = await note('abcde fghijz');
    final Memory below = await note('abcde fghyz');
    final Memory longer = await note('abcde fghijzz');
    final RelatedService service = RelatedService(
      harness.database,
      harness.memories,
    );
    final List<RelatedSuggestion> suggestions = await service.forMemory(
      reference,
      limit: 10,
    );

    expect(
      suggestions.map((RelatedSuggestion item) => item.memory.id),
      unorderedEquals(<String>[substitution.id, deletion.id, insertion.id]),
    );
    expect(
      suggestions
          .firstWhere(
            (RelatedSuggestion item) => item.memory.id == substitution.id,
          )
          .score,
      closeTo(.9, 1e-9),
    );
    // Search stays lexical: the detail-only threshold must not hide word hits.
    final List<RelatedSuggestion> query = await service.forQuery('abcde');
    expect(
      query.map((RelatedSuggestion item) => item.memory.id),
      containsAll(<String>[below.id, longer.id]),
    );
  });

  test(
    'detail compares Unicode text without case or formatting noise',
    () async {
      final Harness harness = await Harness.create();
      addTearDown(harness.dispose);
      final Memory reference = await harness.memories.createNote(
        title: '',
        note: 'École: 東京, café!',
      );
      final Memory formatted = await harness.memories.createNote(
        title: '',
        note: '  ÉCOLE\n東京 — CAFÉ. ',
      );
      final RelatedService service = RelatedService(
        harness.database,
        harness.memories,
      );
      final List<RelatedSuggestion> suggestions = await service.forMemory(
        reference,
      );
      expect(
        suggestions.map((RelatedSuggestion item) => item.memory.id),
        <String>[formatted.id],
      );
      expect(suggestions.single.score, 1);

      final Memory blank = await harness.memories.createNote(
        title: '...',
        note: '! — ?',
      );
      expect(await service.forMemory(blank), isEmpty);
    },
  );

  test(
    '90% applies to the whole text, including scattered letter edits',
    () async {
      final Harness harness = await Harness.create();
      addTearDown(harness.dispose);
      final String text = List<String>.filled(10, 'abcdefghij').join();
      final List<String> changed = text.split('');
      for (int index = 0; index < changed.length; index += 10) {
        changed[index] = 'z';
      }
      final Memory reference = await harness.memories.createNote(
        title: '',
        note: text,
      );
      final Memory threshold = await harness.memories.createNote(
        title: '',
        note: changed.join(),
      );
      changed[5] = 'z';
      await harness.memories.createNote(title: '', note: changed.join());
      final List<RelatedSuggestion> suggestions = await RelatedService(
        harness.database,
        harness.memories,
      ).forMemory(reference);
      expect(
        suggestions.map((RelatedSuggestion item) => item.memory.id),
        <String>[threshold.id],
      );
      expect(suggestions.single.score, closeTo(.9, 1e-9));
    },
  );
}
