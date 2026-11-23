import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_studio/app/data/model_downloader.dart';
import 'package:path/path.dart' as p;

void main() {
  test('removes stale app staging parts without deleting other files', () async {
    final root = await Directory.systemTemp.createTemp('loom-download-cleanup-');
    final staging = Directory(p.join(root.path, '.loom-downloads'));
    await staging.create();
    final stalePart = File(p.join(staging.path, '123456.part'));
    final unrelated = File(p.join(staging.path, 'notes.txt'));
    await stalePart.writeAsString('partial model data');
    await unrelated.writeAsString('keep');

    try {
      await ModelDownloader().cleanupStaleDownloads(root.path);

      expect(await stalePart.exists(), isFalse);
      expect(await unrelated.readAsString(), 'keep');
    } finally {
      await root.delete(recursive: true);
    }
  });
}
