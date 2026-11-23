import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:local_ai_studio/src/rust/api/resources.dart';

import 'data/hugging_face_repository.dart';
import 'data/model_downloader.dart';
import 'data/model_importer.dart';
import 'data/api_key_store.dart';
import 'data/openai_compatible_client.dart';
import 'data/openai_api_server.dart';
import 'data/settings_store.dart';
import 'models/app_settings.dart';
import 'models/chat_message.dart';
import 'models/installed_model.dart';
import 'models/model_info.dart';
import 'services/local_inference_service.dart';

class AppController extends ChangeNotifier {
  AppController._({
    required this._settingsStore,
    required this._catalog,
    required this._downloader,
    required this._apiKeyStore,
    required this._remoteApi,
    required this._localInference,
    required this._modelsDirectory,
    required this.settings,
    required List<ApiKeyMetadata> apiKeys,
  }) {
    _apiKeys.addAll(apiKeys);
    _apiServer = OpenAiApiServer(
      validateApiKey: _apiKeyStore.isValid,
      models: _apiModelIds,
      complete: _generateApiCompletion,
      stream: _generateApiStreamCompletion,
    );
  }

  static Future<AppController> bootstrap() async {
    final settingsStore = SettingsStore();
    final settings = await settingsStore.load();
    final apiKeyStore = ApiKeyStore();
    final apiKeys = await apiKeyStore.listKeys();
    final supportDirectory = await getApplicationSupportDirectory();
    final modelsDirectory = Directory(p.join(supportDirectory.path, 'models'));
    await modelsDirectory.create(recursive: true);
    final downloader = ModelDownloader();
    await downloader.cleanupStaleDownloads(modelsDirectory.path);

    final controller = AppController._(
      settingsStore: settingsStore,
      catalog: HuggingFaceRepository(),
      downloader: downloader,
      apiKeyStore: apiKeyStore,
      remoteApi: OpenAiCompatibleClient(),
      localInference: LocalInferenceService(),
      modelsDirectory: modelsDirectory,
      settings: settings,
      apiKeys: apiKeys,
    );
    await Future.wait([
      controller.refreshInstalledModels(),
      controller.refreshResources(),
    ]);
    return controller;
  }

  final SettingsStore _settingsStore;
  final HuggingFaceRepository _catalog;
  final ModelDownloader _downloader;
  final ModelImporter _modelImporter = ModelImporter();
  final ApiKeyStore _apiKeyStore;
  final OpenAiCompatibleClient _remoteApi;
  final LocalInferenceService _localInference;
  final Directory _modelsDirectory;
  final List<AvailableModel> _catalogModels = [];
  final List<InstalledModel> _installedModels = [];
  final List<ChatMessage> _messages = [];
  final List<ApiKeyMetadata> _apiKeys = [];
  late final OpenAiApiServer _apiServer;
  late final UnmodifiableListView<AvailableModel> _catalogModelsView =
      UnmodifiableListView(_catalogModels);
  late final UnmodifiableListView<InstalledModel> _installedModelsView =
      UnmodifiableListView(_installedModels);
  late final UnmodifiableListView<ChatMessage> _messagesView =
      UnmodifiableListView(_messages);

  AppSettings settings;
  HostResources? resources;
  String? resourceError;
  String? loadedModelPath;
  String? catalogError;
  String? libraryError;
  String? downloadError;
  String? settingsError;
  String? chatError;
  String? catalogNextCursor;
  String catalogQuery = '';
  double? downloadFraction;
  String? activeDownloadName;
  List<String> remoteModels = const [];
  ChatMode chatMode = ChatMode.local;
  bool isLoadingCatalog = false;
  bool isLoadingModel = false;
  bool isImportingModel = false;
  bool isTestingRemote = false;
  bool isGenerating = false;
  bool isDownloading = false;
  bool isApiServerRunning = false;
  String? apiServerError;
  CreatedApiKey? createdApiKey;

  ModelDownloadTask? _downloadTask;
  bool _downloadCancelRequested = false;
  StreamSubscription<ModelDownloadProgress>? _downloadProgressSubscription;
  int _catalogRequestId = 0;
  bool _cancelRequested = false;
  bool _disposed = false;

  UnmodifiableListView<AvailableModel> get catalogModels => _catalogModelsView;
  UnmodifiableListView<InstalledModel> get installedModels =>
      _installedModelsView;
  UnmodifiableListView<ChatMessage> get messages => _messagesView;
  List<ApiKeyMetadata> get apiKeys => List.unmodifiable(_apiKeys);
  List<String> get servedApiModels => List.unmodifiable(_apiModelIds());
  String get apiServerBaseUrl => _apiServer.baseUrl;
  int? get apiServerPort => _apiServer.port;
  String get modelsDirectory => _modelsDirectory.path;
  String? get localModelPath => _localInference.modelPath;

  Future<void> refreshResources() async {
    try {
      resources = await probeHostResources(
        modelDirectory: _modelsDirectory.path,
      );
      resourceError = null;
    } on Object catch (error) {
      resources = null;
      resourceError = 'Resource probe failed (${error.runtimeType}).';
    }
    _notify();
  }

  Future<void> refreshInstalledModels() async {
    try {
      final models = <InstalledModel>[];
      await for (final entity in _modelsDirectory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File ||
            p.extension(entity.path).toLowerCase() != '.gguf') {
          continue;
        }
        final relativePath = p.relative(
          entity.path,
          from: _modelsDirectory.path,
        );
        final segments = p.split(relativePath);
        if (segments.length < 3) continue;
        final entityType = await FileSystemEntity.type(
          entity.path,
          followLinks: false,
        );
        if (entityType != FileSystemEntityType.file) continue;

        models.add(
          InstalledModel(
            name: p.basename(entity.path),
            repository: p.posix.join(segments[0], segments[1]),
            filename: p.posix.joinAll(segments.skip(2)),
            path: entity.path,
            sizeBytes: await entity.length(),
          ),
        );
      }
      models.sort(
        (left, right) =>
            left.name.toLowerCase().compareTo(right.name.toLowerCase()),
      );
      _installedModels
        ..clear()
        ..addAll(models);
      libraryError = null;
    } on Object catch (error) {
      libraryError =
          'Could not read the local model library (${error.runtimeType}).';
    }
    _notify();
  }

  Future<void> searchModels({String? query, bool loadMore = false}) async {
    if (!settings.internetEnabled) {
      catalogError = 'Enable internet access to search Hugging Face.';
      _notify();
      return;
    }

    final requestedQuery = (query ?? catalogQuery).trim();
    if (loadMore && catalogNextCursor == null) return;
    final requestId = ++_catalogRequestId;
    catalogQuery = requestedQuery;
    catalogError = null;
    if (!loadMore) {
      _catalogModels.clear();
      catalogNextCursor = null;
    }
    isLoadingCatalog = true;
    _notify();

    try {
      final page = await _catalog.search(
        query: requestedQuery,
        cursor: loadMore ? catalogNextCursor : null,
        accessToken: settings.huggingFaceToken,
      );
      if (_disposed || requestId != _catalogRequestId) return;

      if (loadMore) {
        final existingIds = _catalogModels.map((model) => model.id).toSet();
        _catalogModels.addAll(
          page.models.where((model) => existingIds.add(model.id)),
        );
      } else {
        _catalogModels
          ..clear()
          ..addAll(page.models);
      }
      catalogNextCursor = page.nextCursor;
    } on Object catch (error) {
      if (!_disposed && requestId == _catalogRequestId) {
        catalogError = error.toString();
      }
    } finally {
      if (!_disposed && requestId == _catalogRequestId) {
        isLoadingCatalog = false;
        _notify();
      }
    }
  }

  Future<List<ModelArtifact>> listArtifacts(AvailableModel model) async {
    if (!settings.internetEnabled) {
      throw StateError('Enable internet access to view model files.');
    }
    return _catalog.listArtifacts(
      repository: model.id,
      accessToken: settings.huggingFaceToken,
    );
  }

  Future<File?> downloadArtifact(ModelArtifact artifact) async {
    if (!settings.internetEnabled) {
      downloadError = 'Enable internet access to download models.';
      _notify();
      return null;
    }
    if (isDownloading) {
      downloadError = 'Wait for the current model download to finish.';
      _notify();
      return null;
    }

    downloadError = null;
    downloadFraction = null;
    _downloadCancelRequested = false;
    activeDownloadName = '${artifact.repository}/${artifact.filename}';
    isDownloading = true;
    _notify();

    try {
      await refreshResources();
      if (!settings.internetEnabled) {
        throw StateError(
          'Internet access was turned off before the download started.',
        );
      }
      if (_downloadCancelRequested) {
        throw const ModelDownloadException('Download cancelled.');
      }
      final freeBytes = resources?.modelDiskAvailableBytes;
      if (artifact.sizeBytes > 0 &&
          freeBytes != null &&
          freeBytes > BigInt.zero) {
        if (BigInt.from(artifact.sizeBytes) > freeBytes) {
          throw StateError(
            'Not enough free space. The model needs ${formatByteSize(artifact.sizeBytes)}.',
          );
        }
      }

      final task = await _downloader.start(
        artifact: artifact,
        modelsDirectory: _modelsDirectory.path,
        accessToken: settings.huggingFaceToken,
      );
      _downloadTask = task;
      if (_downloadCancelRequested || !settings.internetEnabled) task.cancel();
      _downloadProgressSubscription = task.progress.listen((progress) {
        downloadFraction = progress.fraction;
        _notify();
      });
      final file = await task.result;
      await refreshInstalledModels();
      await refreshResources();
      return file;
    } on Object catch (error) {
      if (!_downloadCancelRequested) {
        downloadError = error.toString();
        _notify();
      }
      return null;
    } finally {
      await _downloadProgressSubscription?.cancel();
      _downloadProgressSubscription = null;
      _downloadTask = null;
      isDownloading = false;
      activeDownloadName = null;
      _downloadCancelRequested = false;
      _notify();
    }
  }

  void cancelDownload() {
    if (!isDownloading) return;
    _downloadCancelRequested = true;
    _downloadTask?.cancel();
  }

  Future<bool> loadModel(InstalledModel model) async {
    if (isGenerating || isLoadingModel || isImportingModel) return false;
    isLoadingModel = true;
    loadedModelPath = null;
    libraryError = null;
    _notify();

    try {
      await _localInference.load(model.path);
      loadedModelPath = model.path;
      chatMode = ChatMode.local;
      _messages.clear();
      chatError = null;
      return true;
    } on Object catch (error) {
      loadedModelPath = _localInference.modelPath;
      libraryError = 'Could not load ${model.name}: $error';
      return false;
    } finally {
      isLoadingModel = false;
      _notify();
    }
  }

  Future<bool> importAndLoadModel(String sourcePath) async {
    if (isGenerating || isLoadingModel || isImportingModel || isDownloading) {
      return false;
    }
    isImportingModel = true;
    libraryError = null;
    _notify();

    try {
      final file = await _modelImporter.importFile(
        sourcePath: sourcePath,
        modelsDirectory: _modelsDirectory.path,
      );
      await refreshInstalledModels();
      final model = _installedModels.firstWhere(
        (installed) =>
            installed.repository == 'local/imported' &&
            installed.filename == p.basename(file.path),
        orElse: () => throw StateError(
          'The imported model could not be found in your library.',
        ),
      );
      isImportingModel = false;
      _notify();
      return await loadModel(model);
    } on Object catch (error) {
      libraryError = 'Could not import the selected model: $error';
      return false;
    } finally {
      isImportingModel = false;
      _notify();
    }
  }

  Future<void> unloadModel() async {
    if (isGenerating) {
      throw StateError('Stop generation before unloading the model.');
    }
    await _localInference.unload();
    loadedModelPath = null;
    _messages.clear();
    _notify();
  }

  Future<void> deleteModel(InstalledModel model) async {
    if (isGenerating || isDownloading || isLoadingModel || isImportingModel) {
      throw StateError('Stop active work before removing a model.');
    }
    final isKnownModel = _installedModels.any(
      (installed) =>
          installed.path == model.path &&
          installed.sizeBytes == model.sizeBytes,
    );
    if (!isKnownModel)
      throw StateError('Refresh the library before removing this model.');

    final sourceType = await FileSystemEntity.type(
      model.path,
      followLinks: false,
    );
    if (sourceType != FileSystemEntityType.file) {
      throw StateError('The selected model is no longer a regular file.');
    }
    final root = await Directory(_modelsDirectory.path).resolveSymbolicLinks();
    final target = await File(model.path).resolveSymbolicLinks();
    final relative = p.relative(target, from: root);
    if (!p.isWithin(root, target) || p.split(relative).length < 3) {
      throw StateError('The model file is outside app storage.');
    }
    final file = File(target);
    if (await file.length() != model.sizeBytes) {
      throw StateError(
        'The model file changed. Refresh the library and try again.',
      );
    }

    if (loadedModelPath == model.path) await unloadModel();
    await file.delete();
    await refreshInstalledModels();
    await refreshResources();
  }

  Future<void> setInternetEnabled(bool enabled) async {
    final previous = settings.internetEnabled;
    settings = settings.copyWith(internetEnabled: enabled);
    settingsError = null;
    if (!enabled) {
      _catalogRequestId++;
      isLoadingCatalog = false;
      cancelDownload();
    }
    _notify();

    try {
      await _settingsStore.saveInternetAccess(enabled);
    } on Object catch (_) {
      if (settings.internetEnabled == enabled) {
        settings = settings.copyWith(internetEnabled: previous);
      }
      settingsError = 'Could not save the internet access setting.';
      _notify();
    }
  }

  Future<void> saveApiSettings({
    required String baseUrl,
    required String model,
    required String apiToken,
    required String huggingFaceToken,
  }) async {
    apiResourceUri(baseUrl, 'models');
    if (model.trim().length > 256) {
      throw const FormatException('The API model name is too long.');
    }
    final remoteBaseUrl = baseUrl.trim();
    final remoteModel = model.trim();
    final remoteApiToken = apiToken.trim();
    final normalizedHuggingFaceToken = huggingFaceToken.trim();
    try {
      await _settingsStore.saveApiSettings(
        remoteBaseUrl: remoteBaseUrl,
        remoteModel: remoteModel,
        remoteApiToken: remoteApiToken,
        huggingFaceToken: normalizedHuggingFaceToken,
      );
      settings = settings.copyWith(
        remoteBaseUrl: remoteBaseUrl,
        remoteModel: remoteModel,
        remoteApiToken: remoteApiToken,
        huggingFaceToken: normalizedHuggingFaceToken,
      );
      settingsError = null;
    } on Object catch (error) {
      settingsError =
          'Could not securely save the API settings (${error.runtimeType}).';
      rethrow;
    } finally {
      _notify();
    }
  }

  Future<void> createServedApiKey(String name) async {
    final created = await _apiKeyStore.createKey(name);
    createdApiKey = created;
    await refreshServedApiKeys();
    _notify();
  }

  void dismissCreatedApiKey() {
    createdApiKey = null;
    _notify();
  }

  Future<void> refreshServedApiKeys() async {
    final keys = await _apiKeyStore.listKeys();
    _apiKeys
      ..clear()
      ..addAll(keys);
    _notify();
  }

  Future<void> revokeServedApiKey(String id) async {
    await _apiKeyStore.revokeKey(id);
    if (createdApiKey?.metadata.id == id) createdApiKey = null;
    await refreshServedApiKeys();
  }

  Future<void> startApiServer({int port = OpenAiApiServer.defaultPort}) async {
    if (_apiKeys.isEmpty) {
      throw StateError('Create an API key before starting the API server.');
    }
    apiServerError = null;
    try {
      await _apiServer.start(port: port);
      isApiServerRunning = true;
    } on Object catch (error) {
      apiServerError = 'Could not start the API server (${error.runtimeType}).';
      rethrow;
    } finally {
      _notify();
    }
  }

  Future<void> stopApiServer() async {
    await _apiServer.stop();
    isApiServerRunning = false;
    apiServerError = null;
    _notify();
  }

  List<String> _apiModelIds() {
    if (chatMode == ChatMode.remote) {
      return settings.remoteModel.isEmpty || !settings.internetEnabled
          ? const []
          : [settings.remoteModel];
    }
    final path = loadedModelPath;
    if (path == null) return const [];
    final fileName = p.basename(path);
    final stem = p.basenameWithoutExtension(path);
    return fileName == stem ? [stem] : [stem, fileName];
  }

  Future<String> _generateApiCompletion(
    String model,
    List<ApiMessage> messages,
  ) async {
    if (isGenerating) {
      throw const ApiRequestException(
        HttpStatus.conflict,
        'generation_in_progress',
        'Another generation is already in progress.',
      );
    }
    if (!_apiModelIds().contains(model)) {
      throw const ApiRequestException(
        HttpStatus.serviceUnavailable,
        'model_unavailable',
        'Load a model or configure an available remote model first.',
      );
    }

    isGenerating = true;
    _notify();
    try {
      if (chatMode == ChatMode.local) {
        return await _localInference.complete(messages);
      }
      if (!settings.internetEnabled) {
        throw const ApiRequestException(
          HttpStatus.serviceUnavailable,
          'internet_disabled',
          'Enable internet access before using the configured remote model.',
        );
      }
      final systemPrompt = messages
          .where((message) => message.role == 'system')
          .map((message) => message.content)
          .where((content) => content.isNotEmpty)
          .join('\n\n');
      final conversation = <ChatMessage>[
        if (systemPrompt.isNotEmpty)
          ChatMessage(
            role: MessageRole.user,
            content: 'System instructions:\n$systemPrompt',
          ),
        for (final message in messages.where(
          (message) => message.role != 'system',
        ))
          ChatMessage(
            role: message.role == 'assistant'
                ? MessageRole.assistant
                : MessageRole.user,
            content: message.content,
          ),
      ];
      return await _remoteApi.complete(
        baseUrl: settings.remoteBaseUrl,
        apiToken: settings.remoteApiToken,
        model: model,
        messages: conversation,
      );
    } finally {
      isGenerating = false;
      _notify();
    }
  }

  Future<Stream<String>> _generateApiStreamCompletion(
    String model,
    List<ApiMessage> messages,
  ) async {
    if (isGenerating) {
      throw const ApiRequestException(
        HttpStatus.conflict,
        'generation_in_progress',
        'Another generation is already in progress.',
      );
    }
    if (!_apiModelIds().contains(model)) {
      throw const ApiRequestException(
        HttpStatus.serviceUnavailable,
        'model_unavailable',
        'Load a model or configure an available remote model first.',
      );
    }

    isGenerating = true;
    _notify();
    return () async* {
      try {
        if (chatMode == ChatMode.local) {
          yield* _localInference.streamComplete(messages);
        } else {
          if (!settings.internetEnabled) {
            throw const ApiRequestException(
              HttpStatus.serviceUnavailable,
              'internet_disabled',
              'Enable internet access before using the configured remote model.',
            );
          }
          final systemPrompt = messages
              .where((message) => message.role == 'system')
              .map((message) => message.content)
              .where((content) => content.isNotEmpty)
              .join('\n\n');
          final conversation = <ChatMessage>[
            if (systemPrompt.isNotEmpty)
              ChatMessage(
                role: MessageRole.user,
                content: 'System instructions:\n$systemPrompt',
              ),
            for (final message in messages.where(
              (message) => message.role != 'system',
            ))
              ChatMessage(
                role: message.role == 'assistant'
                    ? MessageRole.assistant
                    : MessageRole.user,
                content: message.content,
              ),
          ];
          final reply = await _remoteApi.complete(
            baseUrl: settings.remoteBaseUrl,
            apiToken: settings.remoteApiToken,
            model: model,
            messages: conversation,
          );
          if (reply.isNotEmpty) yield reply;
        }
      } finally {
        isGenerating = false;
        _notify();
      }
    }();
  }

  Future<bool> testRemoteConnection() async {
    if (!settings.internetEnabled) {
      settingsError = 'Enable internet access before testing the API.';
      _notify();
      return false;
    }
    isTestingRemote = true;
    settingsError = null;
    _notify();

    try {
      final models = await _remoteApi.listModels(
        baseUrl: settings.remoteBaseUrl,
        apiToken: settings.remoteApiToken,
      );
      remoteModels = models;
      if (models.isEmpty) {
        settingsError = 'The API is reachable but returned no models.';
        return false;
      }
      if (!models.contains(settings.remoteModel)) {
        final selectedModel = models.first;
        await _settingsStore.saveRemoteModel(selectedModel);
        settings = settings.copyWith(remoteModel: selectedModel);
      }
      return true;
    } on Object catch (error) {
      settingsError = error.toString();
      return false;
    } finally {
      isTestingRemote = false;
      _notify();
    }
  }

  Future<void> selectRemoteModel(String model) async {
    if (!remoteModels.contains(model)) {
      throw ArgumentError.value(model, 'model');
    }
    await _settingsStore.saveRemoteModel(model);
    settings = settings.copyWith(remoteModel: model);
    _notify();
  }

  void setChatMode(ChatMode mode) {
    if (mode == chatMode || isGenerating) return;
    chatMode = mode;
    _messages.clear();
    _localInference.resetConversation();
    chatError = null;
    _notify();
  }

  Future<void> sendPrompt(String value) async {
    final prompt = value.trim();
    if (prompt.isEmpty || isGenerating) return;
    if (prompt.length > 32768) {
      chatError = 'Keep each message below 32,768 characters.';
      _notify();
      return;
    }
    if (chatMode == ChatMode.local && !_localInference.isLoaded) {
      chatError = 'Load a local model from the library before chatting.';
      _notify();
      return;
    }
    if (chatMode == ChatMode.remote && !settings.internetEnabled) {
      chatError = 'Enable internet access before using a remote API.';
      _notify();
      return;
    }
    if (chatMode == ChatMode.remote && settings.remoteModel.isEmpty) {
      chatError = 'Choose a remote model in API settings first.';
      _notify();
      return;
    }

    _messages.add(ChatMessage(role: MessageRole.user, content: prompt));
    final assistantIndex = _messages.length;
    _messages.add(const ChatMessage(role: MessageRole.assistant, content: ''));
    isGenerating = true;
    _cancelRequested = false;
    chatError = null;
    _notify();

    try {
      if (chatMode == ChatMode.local) {
        final buffer = StringBuffer();
        var lastUpdate = DateTime.now();
        await for (final delta in _localInference.reply(prompt)) {
          buffer.write(delta);
          final now = DateTime.now();
          if (now.difference(lastUpdate) >= const Duration(milliseconds: 90)) {
            _messages[assistantIndex] = ChatMessage(
              role: MessageRole.assistant,
              content: buffer.toString(),
            );
            lastUpdate = now;
            _notify();
          }
        }
        _messages[assistantIndex] = ChatMessage(
          role: MessageRole.assistant,
          content: buffer.toString(),
        );
      } else {
        final reply = await _remoteApi.complete(
          baseUrl: settings.remoteBaseUrl,
          apiToken: settings.remoteApiToken,
          model: settings.remoteModel,
          messages: _messages
              .where((message) => message.content.isNotEmpty)
              .toList(),
        );
        _messages[assistantIndex] = ChatMessage(
          role: MessageRole.assistant,
          content: reply,
        );
      }
    } on Object catch (error) {
      if (!_cancelRequested) chatError = error.toString();
      if (_messages[assistantIndex].content.isEmpty)
        _messages.removeAt(assistantIndex);
    } finally {
      isGenerating = false;
      _cancelRequested = false;
      _notify();
    }
  }

  void cancelGeneration() {
    if (!isGenerating || chatMode != ChatMode.local) return;
    _cancelRequested = true;
    _localInference.cancelGeneration();
  }

  void clearConversation() {
    if (isGenerating) return;
    _messages.clear();
    _localInference.resetConversation();
    chatError = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _catalogRequestId++;
    cancelDownload();
    unawaited(_downloadProgressSubscription?.cancel());
    _catalog.close();
    _remoteApi.close();
    unawaited(_apiServer.stop());
    if (isGenerating && chatMode == ChatMode.local) {
      _localInference.cancelGeneration();
    }
    unawaited(_localInference.unload());
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
