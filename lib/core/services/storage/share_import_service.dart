// Private fields are assigned from clearly named parameters.
// ignore_for_file: prefer_initializing_formals, unused_field

import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';

import '../../database/memory_dao.dart';
import '../../models/enums.dart';
import '../../models/memory.dart';
import '../../utils/logger.dart';
import '../processing/share_intake_service.dart';
import 'memory_service.dart';

/// Turns shared payloads into memories.
///
/// The share plugin only reports intents; saving them is this class's job, so
/// both the cold-start intent and warm deliveries end in the same path. A
/// failed import is reported, never swallowed.
class ShareImportService extends GetxService {
  ShareImportService({
    required ShareIntakeService intake,
    required MemoryService memories,
    required MemoryDao memoryDao,
  }) : _intake = intake,
       _memories = memories,
       _memoryDao = memoryDao;

  final ShareIntakeService _intake;
  final MemoryService _memories;
  // Retained for future duplicate heuristics on text; hash dedup lives in
  // MemoryService, which owns file identity.
  final MemoryDao _memoryDao;

  StreamSubscription<IncomingShare>? _subscription;
  bool _started = false;

  /// Latest outcome, surfaced by the timeline as a short banner.
  final RxString lastMessage = ''.obs;
  final RxInt importedCount = 0.obs;

  /// Subscribes and drains any intent that launched the app. Idempotent.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _subscription = _intake.shares.listen(
      (IncomingShare share) => unawaited(import(share)),
      onError: (Object error) => logWarn('Share stream error', error),
    );
    await _intake.start();
  }

  /// Imports one payload. Returns the memory id, or null when nothing was saved.
  Future<String?> import(IncomingShare share) async {
    switch (share.kind) {
      case IncomingShareKind.image:
        return _importImage(share);
      case IncomingShareKind.text:
        return _importText(share);
      case IncomingShareKind.unsupported:
        lastMessage.value =
            'That kind of file cannot be imported yet. '
            'Images and text are supported.';
        return null;
    }
  }

  Future<String?> _importImage(IncomingShare share) async {
    final String? path = share.filePath;
    if (path == null) {
      lastMessage.value = 'The shared image could not be read.';
      return null;
    }
    final File file = File(path);
    if (!await file.exists()) {
      // The plugin copies into a cache directory that the sender may clear.
      lastMessage.value = 'The shared image had already expired.';
      return null;
    }
    try {
      final ImportOutcome outcome = await _memories.createFromImage(
        source: file,
        // A shared image has no filename worth showing; name it for how it
        // arrived. OCR then supplies the real subject in the body.
        title: 'Shared image',
        memorySource: MemorySource.share,
        extensionHint: _extensionOf(path),
      );
      if (outcome.isDuplicate) {
        lastMessage.value = 'That image is already in your pocket.';
        return outcome.duplicateOf;
      }
      importedCount.value++;
      lastMessage.value = 'Saved the shared image.';
      return outcome.memoryId;
    } catch (error) {
      logWarn('Shared image import failed', error);
      lastMessage.value = 'The shared image could not be saved.';
      return null;
    }
  }

  Future<String?> _importText(IncomingShare share) async {
    final String text = (share.text ?? '').trim();
    if (text.isEmpty) {
      lastMessage.value = 'The shared text was empty.';
      return null;
    }
    try {
      // First line becomes the title when it reads like one; the whole payload
      // is kept verbatim as the note so nothing the user shared is lost.
      final List<String> lines = text.split('\n');
      final String firstLine = lines.first.trim();
      final bool hasHeadline =
          firstLine.isNotEmpty && firstLine.length <= 80 && lines.length > 1;
      final String title = hasHeadline ? firstLine : _titleFrom(text);
      final String note = hasHeadline ? lines.skip(1).join('\n').trim() : text;

      final Memory memory = await _memories.createNote(
        title: title,
        note: note.isEmpty ? text : note,
        source: MemorySource.share,
      );
      importedCount.value++;
      lastMessage.value = 'Saved the shared text.';
      return memory.id;
    } catch (error) {
      logWarn('Shared text import failed', error);
      lastMessage.value = 'The shared text could not be saved.';
      return null;
    }
  }

  /// A short, honest title: the first words of the payload, not a guess at its
  /// meaning.
  static String _titleFrom(String text) {
    final String flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= 60) return flat;
    final int cut = flat.lastIndexOf(' ', 60);
    return '${flat.substring(0, cut <= 0 ? 60 : cut).trim()}…';
  }

  static String? _extensionOf(String path) {
    final int dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return null;
    return path.substring(dot + 1).toLowerCase();
  }

  @override
  void onClose() {
    _subscription?.cancel();
    super.onClose();
  }
}
