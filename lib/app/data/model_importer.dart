import 'dart:io';

import 'package:path/path.dart' as p;

class ModelImporter {
  Future<File> importFile({
    required String sourcePath,
    required String modelsDirectory,
  }) async {
    if (p.extension(sourcePath).toLowerCase() != '.gguf') {
      throw const FormatException('Choose a GGUF model file.');
    }

    final source = File(sourcePath);
    final sourceStat = await source.stat();
    if (sourceStat.type != FileSystemEntityType.file || sourceStat.size < 4) {
      throw const FormatException(
        'The selected file is not a valid GGUF model.',
      );
    }
    if (!await _hasGgufSignature(source)) {
      throw const FormatException(
        'The selected file is not a valid GGUF model.',
      );
    }

    final root = await Directory(modelsDirectory).resolveSymbolicLinks();
    final importDirectory = Directory(p.join(root, 'local', 'imported'));
    await importDirectory.create(recursive: true);
    final canonicalImportDirectory = await importDirectory
        .resolveSymbolicLinks();
    if (!p.isWithin(root, canonicalImportDirectory)) {
      throw const FormatException(
        'The model folder resolves outside app storage.',
      );
    }

    final destination = File(
      p.join(canonicalImportDirectory, p.basename(source.path)),
    );
    if (await destination.exists()) {
      throw StateError(
        'A model with that filename is already in your library.',
      );
    }

    final temporary = File(
      p.join(
        canonicalImportDirectory,
        '.${p.basename(source.path)}.$pid.${DateTime.now().microsecondsSinceEpoch}.part',
      ),
    );
    try {
      await source.copy(temporary.path);
      if (await temporary.length() != sourceStat.size ||
          !await _hasGgufSignature(temporary)) {
        throw const FormatException(
          'The selected file changed while importing.',
        );
      }
      if (await destination.exists()) {
        throw StateError(
          'A model with that filename is already in your library.',
        );
      }
      return await temporary.rename(destination.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<bool> _hasGgufSignature(File file) async {
    final handle = await file.open();
    try {
      final signature = await handle.read(4);
      return signature.length == 4 &&
          signature[0] == 0x47 &&
          signature[1] == 0x47 &&
          signature[2] == 0x55 &&
          signature[3] == 0x46;
    } finally {
      await handle.close();
    }
  }
}
