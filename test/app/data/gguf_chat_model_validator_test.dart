import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_studio/app/data/gguf_chat_model_validator.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late File model;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('loom-gguf-validator-');
    model = File(p.join(directory.path, 'model.gguf'));
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'rejects a Qwen3.5 draft file without base transformer weights',
    () async {
      await model.writeAsBytes(
        _gguf(blockCount: 65, tensorNames: const ['blk.64.attn_q.weight']),
      );

      await expectLater(
        validateStandaloneChatModel(model.path),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('speculative draft weights'),
          ),
        ),
      );
    },
  );

  test('allows a full Qwen3.5 model and other architectures', () async {
    await model.writeAsBytes(
      _gguf(
        blockCount: 65,
        tensorNames: const ['blk.0.attn_q.weight', 'blk.64.attn_q.weight'],
        includeTokenizerArray: true,
      ),
    );
    await expectLater(validateStandaloneChatModel(model.path), completes);

    await model.writeAsBytes(
      _gguf(
        architecture: 'llama',
        blockCount: 2,
        tensorNames: const ['blk.1.attn_q.weight'],
      ),
    );
    await expectLater(validateStandaloneChatModel(model.path), completes);
  });
}

Uint8List _gguf({
  String architecture = 'qwen35',
  required int blockCount,
  required List<String> tensorNames,
  bool includeTokenizerArray = false,
}) {
  final output = BytesBuilder(copy: false);

  void addUint32(int value) {
    final bytes = ByteData(4)..setUint32(0, value, Endian.little);
    output.add(bytes.buffer.asUint8List());
  }

  void addUint64(int value) {
    final bytes = ByteData(8)..setUint64(0, value, Endian.little);
    output.add(bytes.buffer.asUint8List());
  }

  void addString(String value) {
    final bytes = utf8.encode(value);
    addUint64(bytes.length);
    output.add(bytes);
  }

  void addStringMetadata(String key, String value) {
    addString(key);
    addUint32(8);
    addString(value);
  }

  void addIntegerMetadata(String key, int value) {
    addString(key);
    addUint32(4);
    addUint32(value);
  }

  final metadataCount = includeTokenizerArray ? 4 : 3;
  output.add(const [0x47, 0x47, 0x55, 0x46]);
  addUint32(3);
  addUint64(tensorNames.length);
  addUint64(metadataCount);
  addStringMetadata('general.architecture', architecture);
  addIntegerMetadata('$architecture.block_count', blockCount);
  addIntegerMetadata('$architecture.nextn_predict_layers', 1);
  if (includeTokenizerArray) {
    addString('tokenizer.ggml.tokens');
    addUint32(9);
    addUint32(8);
    addUint64(2);
    addString('one');
    addString('two');
  }

  for (final name in tensorNames) {
    addString(name);
    addUint32(1);
    addUint64(1);
    addUint32(8);
    addUint64(0);
  }
  return output.takeBytes();
}
