import 'package:llamadart/llamadart.dart';

import '../data/gguf_chat_model_validator.dart';
import '../data/openai_api_server.dart';

class LocalInferenceService {
  LlamaEngine? _engine;
  ChatSession? _session;
  String? _modelPath;

  static String _truncateFromStart(String value, int maxCharacters) {
    if (value.length <= maxCharacters) return value;
    return '${value.substring(0, maxCharacters)}\n';
  }

  static String _truncateFromEnd(String value, int maxCharacters) {
    if (value.length <= maxCharacters) return value;
    return '${value.substring(value.length - maxCharacters)}\n';
  }

  String? get modelPath => _modelPath;
  bool get isLoaded => _engine != null;

  Future<void> load(String modelPath) async {
    await validateStandaloneChatModel(modelPath);
    await unload();

    final engine = await LlamaEngine.load(
      LlamaModel(ModelSource.path(modelPath)),
    );
    _engine = engine;
    _session = ChatSession(
      engine,
      systemPrompt:
          'You are a clear, helpful assistant running on this device.',
    );
    _modelPath = modelPath;
  }

  Stream<String> reply(String prompt) async* {
    final session = _session;
    if (session == null) {
      throw StateError('Load a local model before chatting.');
    }

    await for (final chunk in session.create([
      LlamaTextContent(prompt),
    ], params: const GenerationParams(maxTokens: 512))) {
      if (chunk.text.isNotEmpty) yield chunk.text;
    }
  }

  Future<String> complete(List<ApiMessage> messages) async {
    final engine = _engine;
    if (engine == null) throw StateError('Load a local model before chatting.');

    final systemPrompt = _truncateFromStart(
      messages
          .where((message) => message.role == 'system')
          .map((message) => message.content)
          .where((content) => content.isNotEmpty)
          .join('\n\n'),
      2000,
    );
    final conversation = _truncateFromEnd(
      messages
          .where((message) => message.role != 'system')
          .map((message) {
            final role = message.role == 'assistant' ? 'Assistant' : 'User';
            return '$role: ${message.content}';
          })
          .join('\n'),
      3000,
    );
    final session = ChatSession(
      engine,
      systemPrompt: systemPrompt.isEmpty
          ? 'You are a clear, helpful assistant running on this device.'
          : systemPrompt,
    );
    final response = StringBuffer();
    await for (final chunk in session.create([
      LlamaTextContent(conversation),
    ], params: const GenerationParams(maxTokens: 512))) {
      response.write(chunk.text);
    }
    return response.toString();
  }

  Stream<String> streamComplete(List<ApiMessage> messages) async* {
    final engine = _engine;
    if (engine == null) throw StateError('Load a local model before chatting.');

    final systemPrompt = _truncateFromStart(
      messages
          .where((message) => message.role == 'system')
          .map((message) => message.content)
          .where((content) => content.isNotEmpty)
          .join('\n\n'),
      2000,
    );
    final conversation = _truncateFromEnd(
      messages
          .where((message) => message.role != 'system')
          .map((message) {
            final role = message.role == 'assistant' ? 'Assistant' : 'User';
            return '$role: ${message.content}';
          })
          .join('\n'),
      3000,
    );
    final session = ChatSession(
      engine,
      systemPrompt: systemPrompt.isEmpty
          ? 'You are a clear, helpful assistant running on this device.'
          : systemPrompt,
    );
    await for (final chunk in session.create([
      LlamaTextContent(conversation),
    ], params: const GenerationParams(maxTokens: 512))) {
      if (chunk.text.isNotEmpty) yield chunk.text;
    }
  }

  void cancelGeneration() => _engine?.cancelGeneration();

  void resetConversation() => _session?.reset();

  Future<void> unload() async {
    final engine = _engine;
    _engine = null;
    _session = null;
    _modelPath = null;
    if (engine != null) await engine.dispose();
  }
}
