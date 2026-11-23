import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_ai_studio/app/data/hugging_face_repository.dart';
import 'package:local_ai_studio/app/data/model_downloader.dart';
import 'package:local_ai_studio/app/services/local_inference_service.dart';
import 'package:local_ai_studio/src/rust/frb_generated.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('searches, downloads, and chats with a GGUF model', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));

    final reply = await tester.runAsync(() async {
      await RustLib.init();
      const repositoryId = 'bartowski/SmolLM2-135M-Instruct-GGUF';
      final directory = await Directory.systemTemp.createTemp('loom-model-smoke-');
      final catalog = HuggingFaceRepository();
      final runtime = LocalInferenceService();

      try {
        final search = await catalog.search(query: 'SmolLM2-135M-Instruct');
        if (!search.models.any((model) => model.id == repositoryId)) {
          throw StateError('The smoke model was not returned by catalog search.');
        }

        final artifacts = await catalog.listArtifacts(repository: repositoryId);
        final model = artifacts.firstWhere(
          (artifact) => artifact.name == 'SmolLM2-135M-Instruct-Q2_K.gguf',
        );
        final download = await ModelDownloader().start(
          artifact: model,
          modelsDirectory: directory.path,
        );
        final file = await download.result.timeout(const Duration(minutes: 5));
        await runtime.load(file.path);

        final response = StringBuffer();
        await for (final token in runtime.reply('Reply with one short greeting.')) {
          response.write(token);
        }
        return response.toString();
      } finally {
        await runtime.unload();
        catalog.close();
        await directory.delete(recursive: true);
      }
    });

    expect(reply?.trim(), isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
