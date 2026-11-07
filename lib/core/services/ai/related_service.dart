import 'dart:isolate';
import 'dart:math' as math;

import 'package:get/get.dart';

import '../../database/app_database.dart';
import '../../database/search_dao.dart';
import '../../models/attachment.dart';
import '../../models/memory.dart';
import '../../utils/text_utils.dart';
import '../storage/memory_service.dart';

/// Local relatedness without a model download. Memory detail requires at least
/// 90% character similarity across titles, notes, OCR, and transcripts. Queries,
/// collections, and interests use lexical overlap (TF-IDF over local documents).
///
/// Scores describe text similarity or ranking, never calibrated confidence.
/// Suggestions name their reference and can be dismissed. Image pixels are not
/// compared.
class RelatedService extends GetxService {
  RelatedService(this._database, this._memoryService);

  final AppDatabase _database;
  final MemoryService _memoryService;

  /// Related memories for a query, based on shared distinctive terms.
  Future<List<RelatedSuggestion>> forQuery(
    String query, {
    String? excludeId,
    int limit = 4,
  }) async {
    if (query.trim().isEmpty) return const <RelatedSuggestion>[];
    final List<Memory> memories = await _memoryService.timeline(
      limit: 200,
      includeExtractions: true,
    );
    return _rank(
      memories: memories,
      referenceText: query,
      referenceLabel: query.trim(),
      referenceKind: RelatedReference.query,
      excludeId: excludeId,
      limit: limit,
    );
  }

  /// Related memories for a collection, using its name, description, and the
  /// text of its members as the reference.
  Future<List<RelatedSuggestion>> forCollection(
    Collection collection, {
    int limit = 4,
  }) async {
    final List<Memory> members = await _memoryService.timeline(
      collectionId: collection.id,
      limit: 100,
      includeExtractions: true,
    );
    final String referenceText =
        '${collection.name} ${collection.description} ${members.map((Memory m) => m.combinedText).join(' ')}';
    final Set<String> memberIds = members.map((Memory m) => m.id).toSet();
    final List<Memory> all = await _memoryService.timeline(
      limit: 200,
      includeExtractions: true,
    );
    return _rank(
      memories: all
          .where((Memory m) => !memberIds.contains(m.id))
          .toList(growable: false),
      referenceText: referenceText,
      maxReferenceTerms: 40,
      referenceLabel: collection.name,
      referenceKind: RelatedReference.collection,
      limit: limit,
    );
  }

  /// Only near-matching text (90% or more) is suggested on memory detail.
  Future<List<RelatedSuggestion>> forMemory(
    Memory memory, {
    int limit = 4,
  }) async {
    final String referenceText = memory.combinedText;
    if (referenceText.trim().isEmpty) return const <RelatedSuggestion>[];
    final List<Memory> all = await _memoryService.timeline(
      limit: 200,
      includeExtractions: true,
    );
    return Isolate.run(
      () => _matchingMemories(all, memory, limit),
      debugName: 'related-memory-text',
    );
  }

  /// Related memories for the interests the user picked in Settings.
  Future<List<RelatedSuggestion>> forInterests({int limit = 4}) async {
    final TaxonomyDao taxonomy = TaxonomyDao(_database);
    final List<String> interests = await taxonomy.interests();
    if (interests.isEmpty) return const <RelatedSuggestion>[];
    final List<Memory> all = await _memoryService.timeline(
      limit: 200,
      includeExtractions: true,
    );
    return _rank(
      memories: all,
      referenceText: interests.join(' '),
      referenceLabel: interests.join(', '),
      referenceKind: RelatedReference.interests,
      limit: limit,
    );
  }

  Future<void> dismiss(String memoryId, RelatedSuggestion suggestion) async {
    await EmbeddingDao(_database).dismissRelated(
      memoryId: memoryId,
      relatedId: suggestion.memory.id,
      referenceKind: suggestion.referenceKind.name,
      referenceLabel: suggestion.referenceLabel,
    );
  }

  Future<Set<String>> dismissedIds(String memoryId, RelatedReference kind) =>
      EmbeddingDao(_database).dismissedRelated(memoryId, kind.name);

  Future<List<RelatedSuggestion>> _rank({
    required List<Memory> memories,
    required String referenceText,
    required String referenceLabel,
    required RelatedReference referenceKind,
    String? excludeId,
    int? maxReferenceTerms,
    int limit = 4,
  }) => Isolate.run(
    () => _rankSync(
      memories: memories,
      referenceText: referenceText,
      referenceLabel: referenceLabel,
      referenceKind: referenceKind,
      excludeId: excludeId,
      maxReferenceTerms: maxReferenceTerms,
      limit: limit,
    ),
    debugName: 'related-search',
  );

  /// TF-IDF cosine over the reference terms. Deterministic and explainable:
  /// returns the exact shared terms that produced the suggestion.
  static List<RelatedSuggestion> _rankSync({
    required List<Memory> memories,
    required String referenceText,
    required String referenceLabel,
    required RelatedReference referenceKind,
    String? excludeId,
    int? maxReferenceTerms,
    int limit = 4,
  }) {
    final Set<String> terms = tokenize(referenceText).toSet();
    final Set<String> reference = maxReferenceTerms == null
        ? terms
        : terms.take(maxReferenceTerms).toSet();
    if (reference.isEmpty) return const <RelatedSuggestion>[];

    // Document frequency for inverse weighting.
    final Map<String, int> documentFrequency = <String, int>{};
    final Map<String, Set<String>> tokensById = <String, Set<String>>{};
    for (final Memory memory in memories) {
      final Set<String> tokens = tokenize(memory.combinedText).toSet();
      tokensById[memory.id] = tokens;
      for (final String token in tokens) {
        documentFrequency[token] = (documentFrequency[token] ?? 0) + 1;
      }
    }
    final int total = memories.length.clamp(1, 1 << 30);
    double weight(String token) {
      final int df = documentFrequency[token] ?? 0;
      return 1 + _log2(total / (1 + df));
    }

    final double referenceNorm = _sqrt(
      reference.fold<double>(
        0,
        (double sum, String term) => sum + weight(term),
      ),
    );

    final List<RelatedSuggestion> scored = <RelatedSuggestion>[];
    for (final Memory memory in memories) {
      if (memory.id == excludeId) continue;
      final Set<String> tokens = tokensById[memory.id] ?? const <String>{};
      if (tokens.isEmpty) continue;
      final List<String> shared = tokens
          .where(reference.contains)
          .toList(growable: false);
      if (shared.isEmpty) continue;

      double numerator = 0;
      for (final String term in shared) {
        numerator += weight(term) * 1.0;
      }
      final double docNorm = _sqrt(
        tokens.fold<double>(0, (double sum, String t) => sum + weight(t)),
      );
      final double score =
          numerator / (referenceNorm * docNorm).clamp(1e-9, double.infinity);

      scored.add(
        RelatedSuggestion(
          memory: memory,
          sharedTerms: shared.take(4).toList(growable: false),
          referenceLabel: referenceLabel,
          referenceKind: referenceKind,
          score: score,
        ),
      );
    }

    scored.sort((RelatedSuggestion a, RelatedSuggestion b) {
      final int byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final int byShared = b.sharedTerms.length.compareTo(a.sharedTerms.length);
      if (byShared != 0) return byShared;
      return b.memory.updatedAt.compareTo(a.memory.updatedAt);
    });
    return scored.take(limit).toList(growable: false);
  }

  static final RegExp _nonLetters = RegExp(r'[^\p{L}\p{N}]', unicode: true);

  static List<int> _letters(String text) => text
      .toLowerCase()
      .replaceAll(_nonLetters, '')
      .runes
      .toList(growable: false);

  static List<RelatedSuggestion> _matchingMemories(
    List<Memory> memories,
    Memory reference,
    int limit,
  ) {
    final List<int> letters = _letters(reference.combinedText);
    if (letters.isEmpty) return const <RelatedSuggestion>[];
    final Set<String> terms = tokenize(reference.combinedText).toSet();
    final List<RelatedSuggestion> matches = <RelatedSuggestion>[];
    for (final Memory memory in memories) {
      if (memory.id == reference.id) continue;
      final String text = memory.combinedText;
      final double? similarity = _letterSimilarity(letters, _letters(text));
      if (similarity == null) continue;
      matches.add(
        RelatedSuggestion(
          memory: memory,
          sharedTerms: tokenize(text)
              .toSet()
              .where(terms.contains)
              .take(4)
              .toList(growable: false),
          referenceLabel: reference.title.isEmpty
              ? 'this memory'
              : reference.title,
          referenceKind: RelatedReference.memory,
          score: similarity,
        ),
      );
    }
    matches.sort((RelatedSuggestion a, RelatedSuggestion b) {
      final int byScore = b.score.compareTo(a.score);
      return byScore != 0
          ? byScore
          : b.memory.updatedAt.compareTo(a.memory.updatedAt);
    });
    return matches.take(limit).toList(growable: false);
  }

  /// Normalized Levenshtein similarity; null below 90%. Strip equal ends, then
  /// compute only the edit band that could still meet the threshold.
  static double? _letterSimilarity(List<int> left, List<int> right) {
    if (right.isEmpty) return null;
    final int length = math.max(left.length, right.length);
    final int maxEdits = length ~/ 10;
    if ((left.length - right.length).abs() > maxEdits) return null;

    int start = 0;
    int leftEnd = left.length;
    int rightEnd = right.length;
    while (start < leftEnd && start < rightEnd && left[start] == right[start]) {
      start++;
    }
    while (leftEnd > start &&
        rightEnd > start &&
        left[leftEnd - 1] == right[rightEnd - 1]) {
      leftEnd--;
      rightEnd--;
    }
    final int rows = leftEnd - start;
    final int columns = rightEnd - start;
    if (rows == 0 || columns == 0) {
      final int edits = rows + columns;
      return edits <= maxEdits ? 1 - edits / length : null;
    }

    final int outside = maxEdits + 1;
    List<int> previous = List<int>.generate(
      columns + 1,
      (int column) => column <= maxEdits ? column : outside,
      growable: false,
    );
    List<int> current = List<int>.filled(columns + 1, outside);
    for (int row = 1; row <= rows; row++) {
      final int first = math.max(1, row - maxEdits);
      final int last = math.min(columns, row + maxEdits);
      current[0] = row <= maxEdits ? row : outside;
      if (first > 1) current[first - 1] = outside;
      if (last < columns) current[last + 1] = outside;
      int best = current[0];
      for (int column = first; column <= last; column++) {
        final int substitution =
            previous[column - 1] +
            (left[start + row - 1] == right[start + column - 1] ? 0 : 1);
        final int edits = math.min(
          substitution,
          math.min(previous[column] + 1, current[column - 1] + 1),
        );
        current[column] = edits;
        best = math.min(best, edits);
      }
      if (best > maxEdits) return null;
      final List<int> swap = previous;
      previous = current;
      current = swap;
    }
    final int edits = previous[columns];
    return edits <= maxEdits ? 1 - edits / length : null;
  }

  static double _sqrt(double value) => value <= 0 ? 1 : math.sqrt(value);

  static double _log2(double value) =>
      value <= 0 ? 0 : math.log(value) / math.ln2;
}
