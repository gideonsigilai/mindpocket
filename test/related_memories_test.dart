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
        'Packing checklist',
        'coast train camera notebook',
        5,
      );
      final Memory unrelated = await screenshot(
        'Dinner recipe',
        'basil pasta tomatoes',
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
}
