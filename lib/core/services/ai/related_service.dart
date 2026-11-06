import 'dart:isolate';
import 'dart:math' as math;

import 'package:get/get.dart';

import '../../database/app_database.dart';
import '../../database/search_dao.dart';
import '../../models/attachment.dart';
import '../../models/memory.dart';
import '../../utils/text_utils.dart';
import '../storage/memory_service.dart';

/// Local, explicit relatedness. Two references are supported without any model
/// download:
///
/// * lexical overlap with the user's query (TF-IDF over local documents);
/// * token overlap with a named collection, another memory, or the interests the
///   user selected.
///
/// Scores are *ranks*, not calibrated confidence. The UI always words results as
/// "Possibly related", ties them to a named reference, and lets the user dismiss
/// them. This works on text only; it does not understand image content.
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

  /// Related memories for one memory.
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
    return _rank(
      memories: all,
      referenceText: referenceText,
      maxReferenceTerms: 40,
      referenceLabel: memory.title.isEmpty ? 'this memory' : memory.title,
      referenceKind: RelatedReference.memory,
      excludeId: memory.id,
      limit: limit,
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

  static double _sqrt(double value) => value <= 0 ? 1 : math.sqrt(value);

  static double _log2(double value) =>
      value <= 0 ? 0 : math.log(value) / math.ln2;
}
