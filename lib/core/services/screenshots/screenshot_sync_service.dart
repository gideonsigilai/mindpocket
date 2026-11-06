import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

// ignore_for_file: prefer_initializing_formals

import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../../database/search_dao.dart';
import '../../database/memory_dao.dart';
import '../../models/attachment.dart';
import '../../models/enums.dart';
import '../../models/memory.dart';
import '../../utils/logger.dart';
import '../ai/nim_grouping_provider.dart';
import '../storage/memory_service.dart';
import '../storage/path_service.dart';
import 'screenshot_source.dart';

/// Outcome of one sync pass, so the UI can report exactly what happened.
class ScreenshotSyncResult {
  const ScreenshotSyncResult({
    required this.found,
    required this.imported,
    required this.duplicates,
    required this.skipped,
    required this.grouped,
    required this.collectionsCreated,
    this.groupingError = '',
    this.completed = true,
  });

  final int found;
  final int imported;
  final int duplicates;
  final int skipped;
  final int grouped;
  final int collectionsCreated;
  final String groupingError;

  /// False when access, enumeration, or any import failed. Only a completed
  /// pass may advance first-run and last-successful-import state.
  final bool completed;

  String summary({bool fullScan = false}) {
    if (found == 0) {
      if (!completed) {
        return groupingError.isNotEmpty
            ? groupingError
            : 'Screenshot import did not complete. It will retry next time.';
      }
      // Distinguish "nothing new" from "this device has no screenshots": the
      // first is the normal steady state, the second is worth knowing.
      return fullScan
          ? 'No screenshots found on this device.'
          : 'No new screenshots since the last import.';
    }
    final String noun = found == 1 ? 'screenshot' : 'screenshots';
    final StringBuffer buffer = StringBuffer(
      'Imported $imported of $found $noun',
    );
    if (duplicates > 0) buffer.write(', $duplicates already saved');
    if (skipped > 0) buffer.write(', $skipped skipped');
    if (grouped > 0) {
      buffer.write(
        '. Sorted into $grouped collection${grouped == 1 ? '' : 's'}',
      );
    }
    if (groupingError.isNotEmpty) buffer.write('. $groupingError');
    return '$buffer.';
  }
}

/// Imports the device's screenshots and organises them into collections.
///
/// Each successful import is durably receipted before moving on. Later passes
/// enumerate bounded metadata pages but copy/process only unseen screenshots.
/// No capture-time watermark can hide equal timestamps, interrupted pages, old
/// screenshots saved later, or images newly exposed by limited Photos access.
class ScreenshotSyncService extends GetxService {
  ScreenshotSyncService({
    required ScreenshotSource source,
    required MemoryService memories,
    required TaxonomyDao taxonomy,
    required PathService paths,
  }) : _source = source,
       _memories = memories,
       _taxonomy = taxonomy,
       _paths = paths;

  final ScreenshotSource _source;
  final MemoryService _memories;
  final TaxonomyDao _taxonomy;
  final PathService _paths;

  final RxBool running = false.obs;
  final RxString phase = ''.obs;
  final RxInt progress = 0.obs;
  final RxInt total = 0.obs;

  Future<ScreenshotSyncResult>? _active;

  Future<File> get _receiptFile async => File(
    p.join((await _paths.documents).path, 'screenshot_import_receipts.jsonl'),
  );

  /// Run time, not capture time; only advanced after a fully successful scan.
  Future<File> get _lastRunFile async =>
      File(p.join((await _paths.documents).path, 'screenshots_last_import'));

  Future<bool> hasPermission() => _source.hasPermission();

  Future<bool> requestPermission() => _source.requestPermission();

  Future<DateTime?> lastSyncedAt() async {
    final String path = (await _lastRunFile).path;
    return Isolate.run(() async {
      final File file = File(path);
      if (!await file.exists()) return null;
      final int? millis = int.tryParse((await file.readAsString()).trim());
      return millis == null || millis <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis);
    });
  }

  Future<void> _markRan() async {
    final String path = (await _lastRunFile).path;
    final int millis = DateTime.now().millisecondsSinceEpoch;
    await Isolate.run(() async {
      final File pending = File('$path.pending');
      await pending.writeAsString('$millis', flush: true);
      await pending.rename(path);
    });
  }

  /// [full] includes already-receipted items in the reported scan totals, without
  /// copying or scheduling them again. Failed items remain unseen and retryable.
  Future<ScreenshotSyncResult> sync({
    required bool full,
    GroupingProvider? grouping,
  }) async {
    final Future<ScreenshotSyncResult>? active = _active;
    if (active != null) {
      try {
        await active;
      } catch (_) {
        // A queued pass can still retry after the previous scan failed.
      }
      return sync(full: full, grouping: grouping);
    }
    final Future<ScreenshotSyncResult> operation = _sync(
      full: full,
      grouping: grouping,
    );
    _active = operation;
    try {
      return await operation;
    } finally {
      if (identical(_active, operation)) _active = null;
    }
  }

  Future<ScreenshotSyncResult> _sync({
    required bool full,
    GroupingProvider? grouping,
  }) async {
    running.value = true;
    progress.value = 0;
    total.value = 0;
    try {
      if (!await _source.hasPermission()) {
        return const ScreenshotSyncResult(
          found: 0,
          imported: 0,
          duplicates: 0,
          skipped: 0,
          grouped: 0,
          collectionsCreated: 0,
          completed: false,
          groupingError: 'Screenshot access was not granted.',
        );
      }

      phase.value = 'Looking for screenshots';
      final File receiptFile = await _receiptFile;
      final String receiptPath = receiptFile.path;
      // Receipt parsing grows with the library, so keep it off the UI isolate.
      final Set<String> receipts = await Isolate.run(
        () => _readReceipts(receiptPath),
      );
      final String stagingPath = p.join(
        (await _paths.temporary).path,
        'screenshot_sync',
      );
      await Isolate.run(() async {
        await Directory(stagingPath).create(recursive: true);
      });
      int found = 0;
      int imported = 0;
      int duplicates = 0;
      int skipped = 0;
      final List<String> importedIds = <String>[];
      final Set<String> pageCursors = <String>{};
      String? afterId;

      while (true) {
        final List<DeviceScreenshot> shots = await _source.list(
          afterId: afterId,
        );
        if (shots.isEmpty) break;
        final String nextCursor = shots.last.id;
        if (nextCursor.isEmpty || !pageCursors.add(nextCursor)) {
          throw const FormatException('Screenshot pagination did not advance.');
        }
        for (final DeviceScreenshot shot in shots) {
          if (shot.id.isEmpty || shot.contentUri.isEmpty) {
            throw const FormatException('Screenshot metadata is incomplete.');
          }
          if (receipts.contains(shot.key)) {
            if (full) {
              found++;
              duplicates++;
              total.value++;
              progress.value++;
            }
            continue;
          }
          found++;
          total.value++;
          phase.value = 'Importing screenshots';
          if (shot.byteSize > 25 * 1024 * 1024) {
            skipped++;
            progress.value++;
            continue;
          }
          // Native IDs can contain slashes (PhotoKit local identifiers).
          final File staged = File(
            p.join(stagingPath, 'staged${_suffix(shot.mimeType)}'),
          );
          try {
            await _source.copyTo(shot.contentUri, staged.path);
            final String stagedPath = staged.path;
            final bool readable = await Isolate.run(() async {
              final File file = File(stagedPath);
              return await file.exists() && await file.length() > 0;
            });
            if (!readable) {
              throw const FileSystemException('Screenshot copy is empty.');
            }
            final ImportOutcome outcome = await _memories.createFromImage(
              source: staged,
              title: _titleFor(shot),
              memorySource: MemorySource.gallery,
              capturedAt: shot.takenAt,
            );
            if (outcome.isDuplicate) {
              duplicates++;
            } else {
              imported++;
              importedIds.add(outcome.memoryId);
            }
            // A leading newline also isolates a torn write from the next
            // receipt after a process interruption. Never receipt a failed copy.
            final String key = shot.key;
            await Isolate.run(() async {
              await File(receiptPath).writeAsString(
                '${String.fromCharCode(10)}${jsonEncode(key)}',
                mode: FileMode.append,
                flush: true,
              );
            });
            receipts.add(shot.key);
          } catch (error) {
            logWarn('Screenshot import failed for ${shot.id}', error);
            skipped++;
          } finally {
            progress.value++;
            final String stagedPath = staged.path;
            await Isolate.run(() async {
              final File file = File(stagedPath);
              if (await file.exists()) await file.delete();
            });
          }
        }
        afterId = nextCursor;
      }

      // Revocation during a scan must not mark an empty final page successful.
      final bool completed = skipped == 0 && await _source.hasPermission();
      int grouped = 0;
      int created = 0;
      String groupingError = '';
      if (grouping != null && importedIds.isNotEmpty) {
        phase.value = 'Sorting into collections';
        try {
          final GroupOutcome outcome = await organise(
            memoryIds: importedIds,
            provider: grouping,
          );
          grouped = outcome.collections;
          created = outcome.created;
        } on GroupingException catch (error) {
          groupingError = error.message;
        }
      }
      if (completed) {
        // The old capture-time cursor was unsafe; receipts replace it.
        final String oldMarkerPath = p.join(
          (await _paths.documents).path,
          'screenshots_synced_at',
        );
        await Isolate.run(() async {
          final File oldMarker = File(oldMarkerPath);
          if (await oldMarker.exists()) await oldMarker.delete();
        });
        await _markRan();
      }
      return ScreenshotSyncResult(
        found: found,
        imported: imported,
        duplicates: duplicates,
        skipped: skipped,
        grouped: grouped,
        collectionsCreated: created,
        groupingError: groupingError,
        completed: completed,
      );
    } finally {
      running.value = false;
      phase.value = '';
    }
  }

  static Future<Set<String>> _readReceipts(String path) async {
    final File file = File(path);
    if (!await file.exists()) return <String>{};
    final Set<String> receipts = <String>{};
    await for (final String line
        in file
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.isEmpty) continue;
      try {
        final Object? key = jsonDecode(line);
        if (key is String) receipts.add(key);
      } on FormatException {
        // A torn final append is retryable; image hashing still deduplicates it.
      }
    }
    return receipts;
  }

  /// Groups every image memory that has extracted text. Used when a key is
  /// added after imports already happened, so nothing is left unsorted.
  Future<GroupOutcome> organiseExisting({
    required GroupingProvider provider,
  }) async {
    final List<Memory> images = await _memories.timeline(
      filter: MemoryFilter.images,
      limit: 500,
    );
    if (images.isEmpty) return const GroupOutcome(collections: 0, created: 0);
    return organise(
      memoryIds: images
          .map((Memory memory) => memory.id)
          .toList(growable: false),
      provider: provider,
    );
  }

  /// Groups the given memories into collections using extracted text.
  ///
  /// Batched (the request stays small) and tolerant: an item the model omits
  /// keeps its current collections instead of being silently dropped.
  Future<GroupOutcome> organise({
    required List<String> memoryIds,
    required GroupingProvider provider,
    int batchSize = 25,
  }) async {
    final List<Memory> memories = <Memory>[];
    for (final String id in memoryIds) {
      final Memory? memory = await _memories.findById(id);
      if (memory != null) memories.add(memory);
    }
    if (memories.isEmpty) return const GroupOutcome(collections: 0, created: 0);

    final List<Collection> existing = await _taxonomy.collections();
    final Map<String, String> byName = <String, String>{
      for (final Collection collection in existing)
        collection.name.toLowerCase(): collection.id,
    };

    int created = 0;
    int groupedCount = 0;
    bool changed = false;

    for (int start = 0; start < memories.length; start += batchSize) {
      final List<Memory> batch = memories.sublist(
        start,
        (start + batchSize).clamp(0, memories.length),
      );
      final List<GroupingItem> items = batch
          .map(
            (Memory memory) =>
                GroupingItem(id: memory.id, text: _describe(memory)),
          )
          .toList(growable: false);

      final List<GroupingAssignment> assignments = await provider.group(
        items: items,
        knownCollections: byName.keys.toList(growable: false),
      );

      for (final GroupingAssignment assignment in assignments) {
        final String key = assignment.collection.toLowerCase();
        String collectionId;
        final String? existingId = byName[key];
        if (existingId != null) {
          collectionId = existingId;
        } else {
          final Collection collection = await _taxonomy.createCollection(
            assignment.collection,
          );
          collectionId = collection.id;
          byName[key] = collectionId;
          created++;
        }
        final Set<String> current = await _taxonomy.collectionIdsFor(
          assignment.id,
        );
        if (current.contains(collectionId)) continue;
        await _taxonomy.setCollections(assignment.id, <String>{
          ...current,
          collectionId,
        });
        if (assignment.title.isNotEmpty) {
          final Memory? memory = await _memories.findById(assignment.id);
          if (memory != null && memory.title.trim().isEmpty) {
            await _memories.renameMemory(assignment.id, assignment.title);
          }
        }
        groupedCount++;
        changed = true;
      }
    }

    if (changed) await _memories.notifyCollectionChange();
    return GroupOutcome(collections: groupedCount, created: created);
  }

  /// What the model sees: extracted text first, then the user's own words. No
  /// image bytes leave the device for grouping.
  static String _describe(Memory memory) {
    final String ocr = memory.ocrText.replaceAll(RegExp(r'\s+'), ' ').trim();
    final String note = memory.note.replaceAll(RegExp(r'\s+'), ' ').trim();
    final String title = memory.title.trim();
    final StringBuffer buffer = StringBuffer();
    if (title.isNotEmpty) buffer.write('title: $title; ');
    if (ocr.isNotEmpty) {
      buffer.write('text: ${ocr.length > 400 ? ocr.substring(0, 400) : ocr}');
    } else if (note.isNotEmpty) {
      buffer.write(
        'note: ${note.length > 200 ? note.substring(0, 200) : note}',
      );
    } else {
      buffer.write('content: image with no readable text');
    }
    return buffer.toString().trim();
  }

  /// File extension implied by the media mime type.
  static String _suffix(String mimeType) {
    final String type = mimeType.toLowerCase();
    if (type.contains('jpeg') || type.contains('jpg')) return '.jpg';
    if (type.contains('webp')) return '.webp';
    if (type.contains('heic')) return '.heic';
    if (type.contains('heif')) return '.heif';
    if (type.contains('gif')) return '.gif';
    return '.png';
  }

  /// A concrete default title; OCR refines the body afterwards.
  static String _titleFor(DeviceScreenshot shot) {
    final String stamp =
        '${shot.takenAt.day}/${shot.takenAt.month} '
        '${shot.takenAt.hour.toString().padLeft(2, '0')}:'
        '${shot.takenAt.minute.toString().padLeft(2, '0')}';
    return 'Screenshot $stamp';
  }
}

/// How much a grouping pass changed.
class GroupOutcome {
  const GroupOutcome({required this.collections, required this.created});

  final int collections;
  final int created;
}
