import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_studio/src/rust/api/resources.dart';
import 'package:local_ai_studio/src/rust/frb_generated.dart';

void main() {
  setUpAll(() => RustLib.init());

  test('reports memory, processor, and model-volume resources on Windows', () async {
    final directory = await Directory.systemTemp.createTemp('loom-models-');
    try {
      final resources = await probeHostResources(modelDirectory: directory.path);

      expect(resources.totalMemoryBytes, greaterThan(BigInt.zero));
      expect(resources.availableMemoryBytes, greaterThan(BigInt.zero));
      expect(resources.modelDiskAvailableBytes, greaterThan(BigInt.zero));
      expect(resources.logicalProcessors, greaterThan(0));
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
