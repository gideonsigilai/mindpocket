import '../../models/attachment.dart';
import '../../utils/isolates.dart';
import '../ai/model_catalog.dart';
import '../ai/model_manager.dart';
import '../ai/sherpa_transcriber.dart';
import '../storage/path_service.dart';
import '../storage/preferences_service.dart';

/// Narrow contracts the processing queue needs.
///
/// They exist so job transitions, retries, and recovery can be tested with
/// deterministic fakes (no native OCR, no FFI inference, no filesystem), while
/// production code still gets the real implementations.

/// Preferences the queue consults before doing work.
abstract interface class ProcessingSettings {
  bool get transcribeAuto;
  bool get ocrAuto;
}

/// Installed-model lookup without the download manager's network concerns.
abstract interface class SpeechModelProvider {
  ModelSpec? get activeModel;
  bool isReady(String modelId);
  Future<ModelPaths> pathsFor(ModelSpec spec);
}

/// Resolves app-relative paths to absolute file paths.
abstract interface class MediaPathResolver {
  Future<String> absolute(String relativePath);
}

/// Runs inference for one recording. The production implementation hands the
/// work to a background isolate.
abstract interface class TranscriptEngine {
  Future<TranscriptionOutput> transcribe({
    required String wavPath,
    required ModelSpec spec,
    required ModelPaths paths,
  });
}

class TranscriptionOutput {
  const TranscriptionOutput({
    required this.text,
    required this.engine,
    required this.language,
  });

  final String text;
  final String engine;
  final String language;
}

/// Attachment lookup used to resolve a job's target file.
abstract interface class AttachmentLookup {
  Future<List<Attachment>> attachmentsFor(String memoryId);
}

/// Adapters ------------------------------------------------------------------

/// `ModelManager` already exposes exactly these members.
class ModelManagerProvider implements SpeechModelProvider {
  ModelManagerProvider(this._manager);

  final ModelManager _manager;

  @override
  ModelSpec? get activeModel => _manager.activeModel;

  @override
  bool isReady(String modelId) => _manager.isReady(modelId);

  @override
  Future<ModelPaths> pathsFor(ModelSpec spec) => _manager.pathsFor(spec);
}

/// Wraps [PreferencesService] so the queue only sees the two flags it needs.
class ProcessingSettingsAdapter implements ProcessingSettings {
  ProcessingSettingsAdapter(this._preferences);

  final PreferencesService _preferences;

  @override
  bool get transcribeAuto => _preferences.transcribeAuto;

  @override
  bool get ocrAuto => _preferences.ocrAuto;
}

/// Adapter from [PathService].
class PathResolverAdapter implements MediaPathResolver {
  PathResolverAdapter(this._paths);

  final PathService _paths;

  @override
  Future<String> absolute(String relativePath) => _paths.absolute(relativePath);
}

/// Adapter that runs the real sherpa-onnx worker isolate.
class SherpaTranscriptEngine implements TranscriptEngine {
  @override
  Future<TranscriptionOutput> transcribe({
    required String wavPath,
    required ModelSpec spec,
    required ModelPaths paths,
  }) async {
    final TranscriptionRequest request = buildTranscriptionRequest(
      wavPath: wavPath,
      spec: spec,
      paths: paths,
    );
    final TranscriptResult result = await computeOnBackground(
      transcribeInIsolate,
      request,
    );
    return TranscriptionOutput(
      text: result.text,
      engine: result.engine,
      language: result.language,
    );
  }
}
