/// A memory is the unit a user keeps in the pocket. It can hold several
/// images, recordings, and a typed note, and is always described by exactly one
/// row in `memories`.
enum MemoryKind {
  /// Created by typing.
  note,

  /// Created from one or more imported screenshots.
  image,

  /// Created by recording audio.
  voice,

  /// Created through a share intent.
  shared;

  static MemoryKind fromName(String? value) => MemoryKind.values.firstWhere(
    (MemoryKind kind) => kind.name == value,
    orElse: () => MemoryKind.note,
  );
}

/// Processing state for OCR and transcription jobs. Stored per job, and
/// derived per memory for the timeline badge.
enum JobStatus {
  queued,
  running,
  completed,
  failed,
  canceled;

  bool get isTerminal =>
      this == completed || this == failed || this == canceled;
  bool get isActive => this == queued || this == running;

  static JobStatus fromName(String? value) => JobStatus.values.firstWhere(
    (JobStatus status) => status.name == value,
    orElse: () => JobStatus.queued,
  );
}

enum JobType {
  ocr,
  transcription;

  static JobType fromName(String? value) => JobType.values.firstWhere(
    (JobType type) => type.name == value,
    orElse: () => JobType.ocr,
  );

  String get label => switch (this) {
    JobType.ocr => 'Text extraction',
    JobType.transcription => 'Transcription',
  };
}

/// Where a creation came from.
enum MemorySource {
  typed,

  /// Chosen one at a time through the system photo picker.
  picker,

  /// Received through a share intent.
  share,

  /// Imported from the device's own screenshot gallery.
  gallery;

  static MemorySource fromName(String? value) => MemorySource.values.firstWhere(
    (MemorySource source) => source.name == value,
    orElse: () => MemorySource.typed,
  );
}

enum AttachmentType {
  image,
  audio;

  static AttachmentType fromName(String? value) =>
      AttachmentType.values.firstWhere(
        (AttachmentType type) => type.name == value,
        orElse: () => AttachmentType.image,
      );
}
