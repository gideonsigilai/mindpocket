import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mindpocket/core/models/enums.dart';
import 'package:mindpocket/core/models/memory.dart';

import 'support/harness.dart';

void main() {
  late Harness harness;

  setUp(() async {
    harness = await Harness.create(transcribeAuto: true);
  });

  tearDown(() async {
    harness.processing.onClose();
    await harness.dispose();
  });

  Future<Memory> queuedVoice() async {
    final Memory voice = await harness.memories.createVoiceMemory(
      title: 'Voice',
    );
    final File wav = File('${harness.tempDir.path}/voice.wav');
    await wav.writeAsBytes(testWav(seconds: 1));
    await harness.memories.attachRecording(
      memoryId: voice.id,
      tempPath: wav.path,
      duration: const Duration(seconds: 1),
    );
    return voice;
  }

  test('a missing speech model does not block new screenshot OCR', () async {
    final Memory voice = await queuedVoice();
    final image = await harness.memories.createFromImage(
      source: await harness.writePng('screenshot.png'),
    );
    await harness.processing.drain();
    expect(
      (await harness.jobs.jobsForMemory(voice.id)).single.status,
      JobStatus.queued,
    );
    expect(
      (await harness.jobs.jobsForMemory(image.memoryId)).single.status,
      JobStatus.completed,
    );
    expect(
      (await harness.memories.findById(image.memoryId))!.ocrText,
      'Travel Planner navigation',
    );
    harness.models.ready = true;
    await harness.processing.drain();
    expect(
      (await harness.jobs.jobsForMemory(voice.id)).single.status,
      JobStatus.completed,
    );
  });

  test(
    'disabling automatic transcription parks jobs without spinning',
    () async {
      final Memory voice = await queuedVoice();
      harness.models.ready = true;
      harness.settings.transcribeAuto = false;
      final image = await harness.memories.createFromImage(
        source: await harness.writePng('while-paused.png'),
      );
      await harness.processing.drain().timeout(const Duration(seconds: 5));
      expect(
        (await harness.jobs.jobsForMemory(voice.id)).single.status,
        JobStatus.queued,
      );
      expect(
        (await harness.jobs.jobsForMemory(image.memoryId)).single.status,
        JobStatus.completed,
      );
      harness.settings.transcribeAuto = true;
      await harness.processing.drain();
      expect(
        (await harness.jobs.jobsForMemory(voice.id)).single.status,
        JobStatus.completed,
      );
    },
  );
}
