import 'attachment.dart';
import 'enums.dart';

/// A memory and everything needed to render it in the timeline. Detail screens
/// load full attachment/extraction sets separately.
class Memory {
  const Memory({
    required this.id,
    required this.title,
    required this.note,
    required this.kind,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.favorite = false,
    this.archived = false,
    this.deletedAt,
    this.attachments = const <Attachment>[],
    this.tags = const <String>[],
    this.collections = const <String>[],
    this.extractions = const <ExtractionRecord>[],
    this.imageCount = 0,
    this.audioCount = 0,
    this.totalAudioMs = 0,
    this.processing = MemoryProcessing.none,
    this.jobError,
    this.thumbnailHint,
  });

  final String id;
  final String title;
  final String note;
  final MemoryKind kind;
  final MemorySource source;
  final bool favorite;
  final bool archived;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Attachment> attachments;
  final List<String> tags;
  final List<String> collections;
  final List<ExtractionRecord> extractions;
  final int imageCount;
  final int audioCount;
  final int totalAudioMs;
  final MemoryProcessing processing;
  final String? jobError;

  /// Only populated by search rows, where loading every attachment would be
  /// wasteful. Null for fully hydrated memories.
  final String? thumbnailHint;

  bool get hasImages => imageCount > 0;
  bool get hasAudio => audioCount > 0;
  bool get hasText => title.trim().isNotEmpty || note.trim().isNotEmpty;

  /// Coalesced text for lexical relatedness and previews.
  String get combinedText => <String>[
    title,
    note,
    ...extractions.map((ExtractionRecord e) => e.effectiveText),
  ].where((String part) => part.trim().isNotEmpty).join('\n');

  String get ocrText => extractions
      .where((ExtractionRecord e) => e.kind == 'ocr')
      .map((ExtractionRecord e) => e.effectiveText)
      .join('\n');

  String get transcriptText => extractions
      .where((ExtractionRecord e) => e.kind == 'transcript')
      .map((ExtractionRecord e) => e.effectiveText)
      .join('\n');

  Duration get audioDuration => Duration(milliseconds: totalAudioMs);

  /// First image that can back a thumbnail, preferring pre-generated previews.
  String? get primaryThumbnailPath {
    for (final Attachment attachment in attachments) {
      if (!attachment.isImage) continue;
      return attachment.thumbnailRelativePath ?? attachment.relativePath;
    }
    return null;
  }

  Attachment? get primaryImage {
    for (final Attachment attachment in attachments) {
      if (attachment.isImage) return attachment;
    }
    return null;
  }

  Attachment? get primaryAudio {
    for (final Attachment attachment in attachments) {
      if (attachment.isAudio) return attachment;
    }
    return null;
  }

  Memory copyWith({
    String? title,
    String? note,
    bool? favorite,
    bool? archived,
    DateTime? updatedAt,
    List<Attachment>? attachments,
    List<String>? tags,
    List<String>? collections,
    List<ExtractionRecord>? extractions,
    int? imageCount,
    int? audioCount,
    int? totalAudioMs,
    MemoryProcessing? processing,
    String? jobError,
    bool clearJobError = false,
  }) {
    return Memory(
      id: id,
      title: title ?? this.title,
      note: note ?? this.note,
      kind: kind,
      source: source,
      favorite: favorite ?? this.favorite,
      archived: archived ?? this.archived,
      deletedAt: deletedAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      attachments: attachments ?? this.attachments,
      tags: tags ?? this.tags,
      collections: collections ?? this.collections,
      extractions: extractions ?? this.extractions,
      imageCount: imageCount ?? this.imageCount,
      audioCount: audioCount ?? this.audioCount,
      totalAudioMs: totalAudioMs ?? this.totalAudioMs,
      processing: processing ?? this.processing,
      jobError: clearJobError ? null : (jobError ?? this.jobError),
    );
  }

  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'title': title,
    'note': note,
    'kind': kind.name,
    'source': source.name,
    'favorite': favorite ? 1 : 0,
    'archived': archived ? 1 : 0,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  factory Memory.fromRow(
    Map<String, Object?> row, {
    List<Attachment> attachments = const <Attachment>[],
    List<String> tags = const <String>[],
    List<String> collections = const <String>[],
    List<ExtractionRecord> extractions = const <ExtractionRecord>[],
    MemoryProcessing processing = MemoryProcessing.none,
    String? jobError,
  }) {
    final int createdAt = (row['created_at'] as int?) ?? 0;
    final int updatedAt = (row['updated_at'] as int?) ?? createdAt;
    return Memory(
      id: row['id']! as String,
      title: (row['title'] as String?) ?? '',
      note: (row['note'] as String?) ?? '',
      kind: MemoryKind.fromName(row['kind'] as String?),
      source: MemorySource.fromName(row['source'] as String?),
      favorite: (row['favorite'] as int?) == 1,
      archived: (row['archived'] as int?) == 1,
      deletedAt: row['deleted_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['deleted_at']! as int),
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt),
      attachments: attachments,
      tags: tags,
      collections: collections,
      extractions: extractions,
      imageCount: attachments.where((Attachment a) => a.isImage).length,
      audioCount: attachments.where((Attachment a) => a.isAudio).length,
      totalAudioMs: attachments
          .where((Attachment a) => a.isAudio)
          .fold<int>(0, (int sum, Attachment a) => sum + (a.durationMs ?? 0)),
      processing: processing,
      jobError: jobError,
    );
  }

  /// Lightweight representation used by FTS search results.
  factory Memory.fromSearchRow(Map<String, Object?> row) {
    final int createdAt = (row['created_at'] as int?) ?? 0;
    final int updatedAt = (row['updated_at'] as int?) ?? createdAt;
    return Memory(
      id: row['id']! as String,
      title: (row['title'] as String?) ?? '',
      note: (row['note'] as String?) ?? '',
      kind: MemoryKind.fromName(row['kind'] as String?),
      source: MemorySource.fromName(row['source'] as String?),
      favorite: (row['favorite'] as int?) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt),
      imageCount: (row['image_count'] as int?) ?? 0,
      audioCount: (row['audio_count'] as int?) ?? 0,
      totalAudioMs: (row['audio_ms'] as int?) ?? 0,
      thumbnailHint: (row['thumb_hint'] as String?) ?? '',
    );
  }

  /// Derived, never stored: some jobs are pending or failed.
  static MemoryProcessing reduceJobs(List<ProcessingJob> jobs) {
    if (jobs.isEmpty) return MemoryProcessing.none;
    if (jobs.any((ProcessingJob job) => job.status == JobStatus.running)) {
      return MemoryProcessing.running;
    }
    if (jobs.any((ProcessingJob job) => job.status == JobStatus.queued)) {
      return MemoryProcessing.queued;
    }
    if (jobs.any((ProcessingJob job) => job.status == JobStatus.failed)) {
      return MemoryProcessing.failed;
    }
    return MemoryProcessing.done;
  }

  @override
  String toString() => 'Memory($id, "$title", ${attachments.length} files)';
}

enum MemoryProcessing { none, queued, running, done, failed }

/// Result of a full text search, with the highlighted snippet.
class SearchHit {
  const SearchHit({
    required this.memory,
    required this.snippet,
    required this.score,
  });

  final Memory memory;

  /// Snippet built from FTS5 `snippet()` with `[`/`]` markers stripped into
  /// spans by the UI.
  final String snippet;
  final double score;
}

/// A "possibly related" suggestion. Always stated as a suggestion tied to an
/// explicit reference (query / collection / memory), never as confidence.
class RelatedSuggestion {
  const RelatedSuggestion({
    required this.memory,
    required this.sharedTerms,
    required this.referenceLabel,
    required this.referenceKind,
    this.score = 0,
    this.dismissed = false,
  });

  final Memory memory;
  final List<String> sharedTerms;
  final String referenceLabel;
  final RelatedReference referenceKind;
  final double score;
  final bool dismissed;
}

enum RelatedReference { query, collection, memory, interests }

class TagCount {
  const TagCount({required this.name, required this.count});

  final String name;
  final int count;
}
