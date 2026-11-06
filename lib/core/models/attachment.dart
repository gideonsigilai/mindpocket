import 'dart:convert';

import 'enums.dart';

/// A single image or recording owned by a memory. Files live in app-private
/// storage; only relative paths are persisted so backups/moves stay valid.
class Attachment {
  const Attachment({
    required this.id,
    required this.memoryId,
    required this.type,
    required this.relativePath,
    required this.createdAt,
    this.storedName = '',
    this.mimeType,
    this.byteSize = 0,
    this.sha256 = '',
    this.width,
    this.height,
    this.durationMs,
    this.thumbnailRelativePath,
    this.sourceUri,
  });

  final String id;
  final String memoryId;
  final AttachmentType type;

  /// Path relative to the app documents directory, e.g. `images/ab12.jpg`.
  final String relativePath;
  final String storedName;
  final String? mimeType;

  /// Original size in bytes (post-copy), used for storage accounting.
  final int byteSize;

  /// Hex SHA-256 of the copied file, used to detect exact duplicate imports.
  final String sha256;
  final int? width;
  final int? height;
  final int? durationMs;

  /// Downscaled preview for the timeline; null until generated.
  final String? thumbnailRelativePath;

  /// Original picker/share URI, kept only as diagnostics.
  final String? sourceUri;
  final DateTime createdAt;

  bool get isImage => type == AttachmentType.image;
  bool get isAudio => type == AttachmentType.audio;
  Duration? get duration =>
      durationMs == null ? null : Duration(milliseconds: durationMs!);

  Attachment copyWith({
    String? relativePath,
    String? storedName,
    String? mimeType,
    int? byteSize,
    String? sha256,
    int? width,
    int? height,
    int? durationMs,
    String? thumbnailRelativePath,
  }) {
    return Attachment(
      id: id,
      memoryId: memoryId,
      type: type,
      relativePath: relativePath ?? this.relativePath,
      storedName: storedName ?? this.storedName,
      mimeType: mimeType ?? this.mimeType,
      byteSize: byteSize ?? this.byteSize,
      sha256: sha256 ?? this.sha256,
      width: width ?? this.width,
      height: height ?? this.height,
      durationMs: durationMs ?? this.durationMs,
      thumbnailRelativePath:
          thumbnailRelativePath ?? this.thumbnailRelativePath,
      sourceUri: sourceUri,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'memory_id': memoryId,
    'type': type.name,
    'relative_path': relativePath,
    'stored_name': storedName,
    'mime_type': mimeType,
    'byte_size': byteSize,
    'sha256': sha256,
    'width': width,
    'height': height,
    'duration_ms': durationMs,
    'thumbnail_relative_path': thumbnailRelativePath,
    'source_uri': sourceUri,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory Attachment.fromRow(Map<String, Object?> row) => Attachment(
    id: row['id']! as String,
    memoryId: row['memory_id']! as String,
    type: AttachmentType.fromName(row['type'] as String?),
    relativePath: row['relative_path']! as String,
    storedName: (row['stored_name'] as String?) ?? '',
    mimeType: row['mime_type'] as String?,
    byteSize: (row['byte_size'] as int?) ?? 0,
    sha256: (row['sha256'] as String?) ?? '',
    width: row['width'] as int?,
    height: row['height'] as int?,
    durationMs: row['duration_ms'] as int?,
    thumbnailRelativePath: row['thumbnail_relative_path'] as String?,
    sourceUri: row['source_uri'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
  );

  @override
  String toString() => 'Attachment($id, ${type.name}, $relativePath)';
}

/// Extracted text for one attachment, split into the immutable engine output
/// and the user's edited version. Reprocessing only ever replaces [rawText].
class ExtractionRecord {
  const ExtractionRecord({
    required this.id,
    required this.attachmentId,
    required this.memoryId,
    required this.kind,
    required this.rawText,
    required this.editedText,
    required this.engine,
    required this.updatedAt,
    this.language,
    this.confidence,
  });

  final String id;
  final String attachmentId;
  final String memoryId;

  /// `ocr` or `transcript`.
  final String kind;

  /// Untouched machine output. Never overwritten by user edits.
  final String rawText;

  /// What the user sees and searches. Starts equal to [rawText].
  final String editedText;
  final String engine;
  final String? language;
  final double? confidence;
  final DateTime updatedAt;

  bool get isEdited => editedText.trim() != rawText.trim();
  String get effectiveText => editedText.trim().isEmpty ? rawText : editedText;

  ExtractionRecord copyWith({
    String? rawText,
    String? editedText,
    String? engine,
    String? language,
    double? confidence,
    DateTime? updatedAt,
  }) {
    return ExtractionRecord(
      id: id,
      attachmentId: attachmentId,
      memoryId: memoryId,
      kind: kind,
      rawText: rawText ?? this.rawText,
      editedText: editedText ?? this.editedText,
      engine: engine ?? this.engine,
      language: language ?? this.language,
      confidence: confidence ?? this.confidence,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'attachment_id': attachmentId,
    'memory_id': memoryId,
    'kind': kind,
    'raw_text': rawText,
    'edited_text': editedText,
    'engine': engine,
    'language': language,
    'confidence': confidence,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  factory ExtractionRecord.fromRow(Map<String, Object?> row) =>
      ExtractionRecord(
        id: row['id']! as String,
        attachmentId: row['attachment_id']! as String,
        memoryId: row['memory_id']! as String,
        kind: row['kind']! as String,
        rawText: (row['raw_text'] as String?) ?? '',
        editedText: (row['edited_text'] as String?) ?? '',
        engine: (row['engine'] as String?) ?? '',
        language: row['language'] as String?,
        confidence: (row['confidence'] as num?)?.toDouble(),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (row['updated_at'] as int?) ?? 0,
        ),
      );
}

class Tag {
  const Tag({required this.id, required this.name, this.createdAt});

  final String id;
  final String name;
  final DateTime? createdAt;

  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'name': name,
    'created_at': (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
  };

  factory Tag.fromRow(Map<String, Object?> row) => Tag(
    id: row['id']! as String,
    name: row['name']! as String,
    createdAt: row['created_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
  );
}

class Collection {
  const Collection({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
    this.memoryCount = 0,
  });

  final String id;
  final String name;
  final String description;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Populated by list queries; not a stored column.
  final int memoryCount;

  Collection copyWith({String? name, String? description, int? memoryCount}) =>
      Collection(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        memoryCount: memoryCount ?? this.memoryCount,
      );

  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'name': name,
    'description': description,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  factory Collection.fromRow(Map<String, Object?> row) => Collection(
    id: row['id']! as String,
    name: row['name']! as String,
    description: (row['description'] as String?) ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
    memoryCount: (row['memory_count'] as int?) ?? 0,
  );
}

/// A persisted unit of heavy work. Jobs are idempotent: (memory, attachment,
/// type) is unique, so resuming can never duplicate extraction.
class ProcessingJob {
  const ProcessingJob({
    required this.id,
    required this.memoryId,
    required this.type,
    required this.status,
    required this.attempts,
    required this.createdAt,
    required this.updatedAt,
    this.attachmentId,
    this.error,
    this.startedAt,
    this.finishedAt,
  });

  final String id;
  final String memoryId;
  final String? attachmentId;
  final JobType type;
  final JobStatus status;
  final int attempts;
  final String? error;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  ProcessingJob copyWith({
    JobStatus? status,
    int? attempts,
    String? error,
    DateTime? startedAt,
    DateTime? finishedAt,
    DateTime? updatedAt,
  }) {
    return ProcessingJob(
      id: id,
      memoryId: memoryId,
      attachmentId: attachmentId,
      type: type,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      error: error,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
    );
  }

  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'memory_id': memoryId,
    'attachment_id': attachmentId,
    'type': type.name,
    'status': status.name,
    'attempts': attempts,
    'error': error,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'started_at': startedAt?.millisecondsSinceEpoch,
    'finished_at': finishedAt?.millisecondsSinceEpoch,
  };

  factory ProcessingJob.fromRow(Map<String, Object?> row) => ProcessingJob(
    id: row['id']! as String,
    memoryId: row['memory_id']! as String,
    attachmentId: row['attachment_id'] as String?,
    type: JobType.fromName(row['type'] as String?),
    status: JobStatus.fromName(row['status'] as String?),
    attempts: (row['attempts'] as int?) ?? 0,
    error: row['error'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
    startedAt: row['started_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['started_at']! as int),
    finishedAt: row['finished_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['finished_at']! as int),
  );
}

/// Structured cloud output. Never persisted until validated and accepted.
class AiSuggestion {
  const AiSuggestion({
    required this.id,
    required this.memoryId,
    required this.provider,
    required this.createdAt,
    this.title = '',
    this.summary = '',
    this.category = '',
    this.tags = const <String>[],
    this.collectionName = '',
    this.tasks = const <AiTask>[],
    this.status = AiSuggestionStatus.pending,
    this.acceptedFields = const <String>{},
  });

  final String id;
  final String memoryId;
  final String provider;
  final String title;
  final String summary;
  final String category;
  final List<String> tags;
  final String collectionName;
  final List<AiTask> tasks;
  final AiSuggestionStatus status;
  final Set<String> acceptedFields;
  final DateTime createdAt;

  AiSuggestion copyWith({
    AiSuggestionStatus? status,
    Set<String>? acceptedFields,
  }) => AiSuggestion(
    id: id,
    memoryId: memoryId,
    provider: provider,
    title: title,
    summary: summary,
    category: category,
    tags: tags,
    collectionName: collectionName,
    tasks: tasks,
    status: status ?? this.status,
    acceptedFields: acceptedFields ?? this.acceptedFields,
    createdAt: createdAt,
  );

  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'memory_id': memoryId,
    'provider': provider,
    'title': title,
    'summary': summary,
    'category': category,
    'tags_json': jsonEncode(tags),
    'collection_name': collectionName,
    'tasks_json': jsonEncode(tasks.map((AiTask t) => t.toJson()).toList()),
    'status': status.name,
    'accepted_fields_json': acceptedFields.toList(),
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory AiSuggestion.fromRow(Map<String, Object?> row) => AiSuggestion(
    id: row['id']! as String,
    memoryId: row['memory_id']! as String,
    provider: (row['provider'] as String?) ?? '',
    title: (row['title'] as String?) ?? '',
    summary: (row['summary'] as String?) ?? '',
    category: (row['category'] as String?) ?? '',
    tags: _stringList(row['tags_json']),
    collectionName: (row['collection_name'] as String?) ?? '',
    tasks: _taskList(row['tasks_json']),
    status: AiSuggestionStatus.values.firstWhere(
      (AiSuggestionStatus value) => value.name == row['status'],
      orElse: () => AiSuggestionStatus.pending,
    ),
    acceptedFields: _stringList(row['accepted_fields_json']).toSet(),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (row['created_at'] as int?) ?? 0,
    ),
  );

  static List<String> _stringList(Object? raw) {
    if (raw is! String || raw.isEmpty) return const <String>[];
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List) return const <String>[];
    return decoded.whereType<String>().toList(growable: false);
  }

  static List<AiTask> _taskList(Object? raw) {
    if (raw is! String || raw.isEmpty) return const <AiTask>[];
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List) return const <AiTask>[];
    return decoded
        .whereType<Map<Object?, Object?>>()
        .map(AiTask.fromJson)
        .toList(growable: false);
  }
}

class AiTask {
  const AiTask({required this.title});

  final String title;

  Map<String, Object?> toJson() => <String, Object?>{'title': title};

  factory AiTask.fromJson(Map<Object?, Object?> json) =>
      AiTask(title: (json['title'] as String?)?.trim() ?? '');
}

enum AiSuggestionStatus {
  pending,
  accepted,
  dismissed;

  static AiSuggestionStatus fromName(String? name) =>
      AiSuggestionStatus.values.firstWhere(
        (AiSuggestionStatus value) => value.name == name,
        orElse: () => AiSuggestionStatus.pending,
      );
}
