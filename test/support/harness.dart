import 'dart:async';
import 'dart:io';

import 'package:mindpocket/core/database/app_database.dart';
import 'package:mindpocket/core/database/job_dao.dart';
import 'package:mindpocket/core/database/memory_dao.dart';
import 'package:mindpocket/core/database/search_dao.dart';
import 'package:mindpocket/core/models/attachment.dart';
import 'package:mindpocket/core/models/enums.dart';
import 'package:mindpocket/core/services/ai/model_catalog.dart';
import 'package:mindpocket/core/services/ai/model_manager.dart';
import 'package:mindpocket/core/services/processing/ocr_service.dart';
import 'package:mindpocket/core/services/processing/processing_contracts.dart';
import 'package:mindpocket/core/services/processing/processing_service.dart';
import 'package:mindpocket/core/services/storage/file_store.dart';
import 'package:mindpocket/core/services/storage/memory_service.dart';
import 'package:mindpocket/core/services/storage/preferences_service.dart';
import 'package:mindpocket/core/services/storage/path_service.dart';
import 'package:path/path.dart' as p;

/// Everything a persistence test needs, wired the way the app wires it but
/// pointed at a throwaway directory and with deterministic processing fakes.
class Harness {
  Harness._({
    required this.database,
    required this.tempDir,
    required this.paths,
    required this.files,
    required this.memories,
    required this.memoryDao,
    required this.jobs,
    required this.search,
    required this.taxonomy,
    required this.processing,
    required this.settings,
    required this.ocr,
    required this.models,
    required this.prefs,
  });

  static Future<Harness> create({
    bool ocrAuto = true,
    bool transcribeAuto = false,
  }) async {
    AppDatabase.initialise();
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'mindpocket_test_',
    );
    final PathService paths = PathService(
      documentsDirectory: () async => tempDir,
      temporaryDirectory: () async => tempDir,
    );
    final AppDatabase database = await AppDatabase.openAt(
      p.join(tempDir.path, 'mindpocket.db'),
    );
    final MemoryDao memoryDao = MemoryDao(database);
    final JobDao jobs = JobDao(database);
    final SearchDao search = SearchDao(database);
    final TaxonomyDao taxonomy = TaxonomyDao(database);
    final FileStore files = FileStore(paths);
    final FakeSettings settings = FakeSettings(
      ocrAuto: ocrAuto,
      transcribeAuto: transcribeAuto,
    );
    final MemoryService memories = MemoryService(
      database: database,
      memories: memoryDao,
      jobs: jobs,
      search: search,
      taxonomy: taxonomy,
      files: files,
      paths: paths,
      settings: settings,
    );
    final FakeOcr ocr = FakeOcr();
    final FakeModels models = FakeModels();
    final ProcessingService processing = ProcessingService(
      database: database,
      memories: memoryDao,
      jobs: jobs,
      search: search,
      ocr: ocr,
      models: models,
      paths: PathResolverAdapter(paths),
      settings: settings,
      transcripts: FakeTranscripts(),
    );
    return Harness._(
      database: database,
      tempDir: tempDir,
      paths: paths,
      files: files,
      memories: memories,
      memoryDao: memoryDao,
      jobs: jobs,
      search: search,
      taxonomy: taxonomy,
      processing: processing,
      settings: settings,
      ocr: ocr,
      models: models,
      prefs: FakePreferences(),
    );
  }

  final AppDatabase database;
  final Directory tempDir;
  final PathService paths;
  final FileStore files;
  final MemoryService memories;
  final MemoryDao memoryDao;
  final JobDao jobs;
  final SearchDao search;
  final TaxonomyDao taxonomy;
  final ProcessingService processing;
  final FakeOcr ocr;
  final FakeModels models;
  final FakeSettings settings;
  final FakePreferences prefs;

  /// Writes a tiny but valid PNG so imports exercise the real codec path.
  Future<File> writePng(String name, {int size = 4, List<int>? bytes}) async {
    final File file = File(p.join(tempDir.path, name));
    await file.writeAsBytes(bytes ?? _pngBytes(size), flush: true);
    return file;
  }

  Future<void> dispose() async {
    await database.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  }
}

/// In-memory preference surface covering every getter that would otherwise
/// touch GetStorage on disk, so screens can be rendered headlessly.
class FakePreferences extends PreferencesService {
  final Map<String, Object?> _values = <String, Object?>{};

  @override
  bool sortOldest = false;

  @override
  bool semanticEnabled = true;

  @override
  bool onboardingDone = false;

  @override
  String themeModeName = 'system';

  @override
  bool ocrAuto = true;

  @override
  bool transcribeAuto = false;

  @override
  bool cloudEnabled = false;

  @override
  String cloudBaseUrl = '';

  @override
  bool? reducedMotionOverride;

  @override
  bool interestsHintDismissed = false;

  @override
  Future<PreferencesService> init() async => this;

  @override
  bool readBool(String key, bool fallback) {
    final Object? value = _values[key];
    return value is bool ? value : fallback;
  }

  @override
  String readString(String key, String fallback) {
    final Object? value = _values[key];
    return value is String ? value : fallback;
  }

  @override
  Future<void> write(String key, Object? value) async => _values[key] = value;

  @override
  Future<void> completeOnboarding() =>
      write(PreferencesService.kOnboardingDone, true);

  @override
  Future<void> setThemeModeName(String value) =>
      write(PreferencesService.kThemeMode, value);

  @override
  Future<void> setOcrAuto(bool value) =>
      write(PreferencesService.kOcrAuto, value);

  @override
  Future<void> setTranscribeAuto(bool value) =>
      write(PreferencesService.kTranscribeAuto, value);

  @override
  Future<void> setCloudEnabled(bool value) =>
      write(PreferencesService.kCloudEnabled, value);

  @override
  Future<void> setCloudBaseUrl(String value) =>
      write(PreferencesService.kCloudBaseUrl, value.trim());

  @override
  Future<void> setSortOldest(bool value) =>
      write(PreferencesService.kSortOldest, value);

  @override
  Future<void> setSemanticEnabled(bool value) =>
      write(PreferencesService.kSemanticEnabled, value);

  @override
  Future<void> setReducedMotionOverride(bool? value) async {
    if (value == null) {
      _values.remove(PreferencesService.kReducedMotion);
    } else {
      await write(PreferencesService.kReducedMotion, value);
    }
  }

  @override
  Future<void> dismissInterestsHint() =>
      write(PreferencesService.kInterestsDismissedHint, true);

  @override
  bool get screenshotAutoImport =>
      readBool(PreferencesService.kScreenshotAutoImport, true);

  @override
  Future<void> setScreenshotAutoImport(bool value) =>
      write(PreferencesService.kScreenshotAutoImport, value);

  @override
  bool get screenshotFirstRunDone =>
      readBool(PreferencesService.kScreenshotFirstRunDone, false);

  @override
  Future<void> markScreenshotFirstRunDone() =>
      write(PreferencesService.kScreenshotFirstRunDone, true);
}

class FakeSettings implements ProcessingSettings {
  FakeSettings({required this.ocrAuto, required this.transcribeAuto});

  @override
  bool ocrAuto;

  @override
  bool transcribeAuto;
}

class FakeOcr implements TextExtractor {
  FakeOcr({this.text = 'Travel Planner navigation', this.failure});

  String text;
  OcrException? failure;
  final List<String> calls = <String>[];

  @override
  Future<OcrResult> recognize(File imageFile) async {
    calls.add(imageFile.path);
    if (failure != null) throw failure!;
    return OcrResult(
      text: text,
      engine: 'fake-ocr',
      language: 'en',
      hasText: text.trim().isNotEmpty,
    );
  }
}

class FakeModels implements SpeechModelProvider {
  bool ready = false;
  ModelSpec? spec = whisperTinyEn;

  @override
  ModelSpec? get activeModel => spec;

  @override
  bool isReady(String modelId) => ready;

  @override
  Future<ModelPaths> pathsFor(ModelSpec spec) async => const ModelPaths(
    directory: 'models/fake',
    encoder: 'models/fake/encoder.onnx',
    decoder: 'models/fake/decoder.onnx',
    tokens: 'models/fake/tokens.txt',
  );
}

class FakeTranscripts implements TranscriptEngine {
  @override
  Future<TranscriptionOutput> transcribe({
    required String wavPath,
    required ModelSpec spec,
    required ModelPaths paths,
  }) async => const TranscriptionOutput(
    text: 'use this navigation style for travel planner',
    engine: 'fake-asr',
    language: 'en',
  );
}

class FakeAttachmentLookup implements AttachmentLookup {
  @override
  Future<List<Attachment>> attachmentsFor(String memoryId) async =>
      const <Attachment>[];
}

/// Encodes a real, decodable RGBA PNG. [color] varies the pixel data so tests
/// can produce distinct-but-valid images for duplicate detection.
List<int> _pngBytes(int color) {
  const int width = 2;
  const int height = 2;
  final List<int> raw = <int>[];
  for (int y = 0; y < height; y++) {
    raw.add(0); // filter: none
    for (int x = 0; x < width; x++) {
      raw.addAll(<int>[color & 0xFF, (color >> 8) & 0xFF, 0x80, 0xFF]);
    }
  }
  final List<int> out = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  out.addAll(
    _chunk('IHDR', <int>[
      0, 0, 0, width, // width
      0, 0, 0, height, // height
      8, 6, 0, 0, 0, // 8-bit RGBA, deflate, no filter, no interlace
    ]),
  );
  out.addAll(_chunk('IDAT', _zlibStored(raw)));
  out.addAll(_chunk('IEND', const <int>[]));
  return out;
}

/// zlib stream using stored (uncompressed) deflate blocks: valid, and it needs
/// no compressor dependency.
List<int> _zlibStored(List<int> data) {
  final List<int> out = <int>[0x78, 0x01];
  int offset = 0;
  while (offset < data.length) {
    final int take = data.length - offset > 65535
        ? 65535
        : data.length - offset;
    final bool last = offset + take >= data.length;
    out.add(last ? 1 : 0);
    out.addAll(<int>[
      take & 0xFF,
      (take >> 8) & 0xFF,
      (~take) & 0xFF,
      ((~take) >> 8) & 0xFF,
    ]);
    out.addAll(data.sublist(offset, offset + take));
    offset += take;
  }
  out.addAll(_adler32(data));
  return out;
}

List<int> _chunk(String type, List<int> data) {
  final List<int> typeBytes = type.codeUnits;
  final List<int> crcInput = <int>[...typeBytes, ...data];
  return <int>[
    (data.length >> 24) & 0xFF,
    (data.length >> 16) & 0xFF,
    (data.length >> 8) & 0xFF,
    data.length & 0xFF,
    ...crcInput,
    ..._crc32(crcInput),
  ];
}

List<int> _crc32(List<int> bytes) {
  int crc = 0xFFFFFFFF;
  for (final int byte in bytes) {
    crc ^= byte;
    for (int bit = 0; bit < 8; bit++) {
      crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  crc ^= 0xFFFFFFFF;
  return <int>[
    (crc >> 24) & 0xFF,
    (crc >> 16) & 0xFF,
    (crc >> 8) & 0xFF,
    crc & 0xFF,
  ];
}

List<int> _adler32(List<int> bytes) {
  int a = 1;
  int b = 0;
  for (final int byte in bytes) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  return <int>[(b >> 8) & 0xFF, b & 0xFF, (a >> 8) & 0xFF, a & 0xFF];
}

/// Job status lookup used by assertions without reaching into SQL.
Future<JobStatus?> jobStatus(
  Harness harness,
  String memoryId,
  JobType type,
) async {
  final ProcessingJob? job = await harness.jobs.jobFor(
    memoryId: memoryId,
    attachmentId: null,
    type: type,
  );
  return job?.status;
}

/// Minimal 16-bit PCM WAV so audio paths run end to end without a device.
List<int> testWav({required int seconds, int sampleRate = 16000}) {
  final int samples = sampleRate * seconds;
  final int dataBytes = samples * 2;
  final List<int> out = <int>[];
  void ascii(String text) => out.addAll(text.codeUnits);
  void u32(int value) => out.addAll(<int>[
    value & 0xFF,
    (value >> 8) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 24) & 0xFF,
  ]);
  void u16(int value) => out.addAll(<int>[value & 0xFF, (value >> 8) & 0xFF]);

  ascii('RIFF');
  u32(36 + dataBytes);
  ascii('WAVE');
  ascii('fmt ');
  u32(16);
  u16(1);
  u16(1);
  u32(sampleRate);
  u32(sampleRate * 2);
  u16(2);
  u16(16);
  ascii('data');
  u32(dataBytes);
  out.addAll(List<int>.filled(dataBytes, 0));
  return out;
}
