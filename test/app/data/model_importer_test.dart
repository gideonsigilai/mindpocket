import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_studio/app/data/model_importer.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory modelsDirectory;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('loom-model-import-');
    modelsDirectory = Directory(p.join(root.path, 'models'));
    await modelsDirectory.create();
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('copies a GGUF file into the managed library', () async {
    final source = File(p.join(root.path, 'model.gguf'));
    await source.writeAsBytes([0x47, 0x47, 0x55, 0x46, 1, 2, 3]);

    final imported = await ModelImporter().importFile(
      sourcePath: source.path,
      modelsDirectory: modelsDirectory.path,
    );

    expect(
      p.relative(imported.path, from: modelsDirectory.path),
      p.join('local', 'imported', 'model.gguf'),
    );
    expect(await imported.readAsBytes(), await source.readAsBytes());
  });

  test('rejects invalid GGUF data and duplicate filenames', () async {
    final invalid = File(p.join(root.path, 'invalid.gguf'));
    await invalid.writeAsBytes([0, 1, 2, 3]);
    final importer = ModelImporter();

    await expectLater(
      importer.importFile(
        sourcePath: invalid.path,
        modelsDirectory: modelsDirectory.path,
      ),
      throwsFormatException,
    );

    final source = File(p.join(root.path, 'model.gguf'));
    await source.writeAsBytes([0x47, 0x47, 0x55, 0x46, 1]);
    await importer.importFile(
      sourcePath: source.path,
      modelsDirectory: modelsDirectory.path,
    );

    await expectLater(
      importer.importFile(
        sourcePath: source.path,
        modelsDirectory: modelsDirectory.path,
      ),
      throwsStateError,
    );
  });
}
