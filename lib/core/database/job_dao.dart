import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/app_database.dart';
import '../models/attachment.dart';
import '../models/enums.dart';
import '../utils/ids.dart';

/// Job persistence. Every state transition goes through here so retries,
/// cancellations, and crash recovery stay consistent.
class JobDao {
  JobDao(this._database);

  final AppDatabase _database;

  /// Enqueues an idempotent job. If a job for the same (attachment, type)
  /// already exists in a non-terminal state it is reused; completed jobs are
  /// only re-queued when [force] is set (user-initiated retry/reprocess).
  Future<ProcessingJob?> enqueue({
    required String memoryId,
    required String? attachmentId,
    required JobType type,
    bool force = false,
  }) => _database.db.transaction((Transaction txn) async {
    final List<Map<String, Object?>> existing = await txn.rawQuery(
      '''
      SELECT * FROM processing_jobs
      WHERE memory_id = ? AND IFNULL(attachment_id, '') = ? AND type = ?
      LIMIT 1
      ''',
      <Object?>[memoryId, attachmentId ?? '', type.name],
    );

    if (existing.isNotEmpty) {
      final ProcessingJob job = ProcessingJob.fromRow(existing.first);
      if (!force &&
          (job.status.isActive || job.status == JobStatus.completed)) {
        return job;
      }
      final Map<String, Object?> changes = <String, Object?>{
        'status': JobStatus.queued.name,
        'attempts': 0,
        'error': null,
        'started_at': null,
        'finished_at': null,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };
      await txn.update(
        'processing_jobs',
        changes,
        where: 'id = ?',
        whereArgs: <Object?>[job.id],
      );
      return ProcessingJob.fromRow(<String, Object?>{
        ...existing.first,
        ...changes,
      });
    }

    final DateTime now = DateTime.now();
    final ProcessingJob job = ProcessingJob(
      id: Ids.newId('job'),
      memoryId: memoryId,
      attachmentId: attachmentId,
      type: type,
      status: JobStatus.queued,
      attempts: 0,
      createdAt: now,
      updatedAt: now,
    );
    // The lookup + write are serialized together. Do not return a synthetic
    // job after an ignored unique constraint from a concurrent enqueue.
    await txn.insert('processing_jobs', job.toRow());
    return job;
  });

  Future<void> markRunning(String jobId) async {
    await _database.db.update(
      'processing_jobs',
      <String, Object?>{
        'status': JobStatus.running.name,
        'started_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'error': null,
      },
      where: 'id = ? AND status IN (?, ?)',
      whereArgs: <Object?>[jobId, JobStatus.queued.name, JobStatus.failed.name],
    );
  }

  Future<void> markCompleted(String jobId) async {
    await _database.db.update(
      'processing_jobs',
      <String, Object?>{
        'status': JobStatus.completed.name,
        'finished_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'error': null,
      },
      where: 'id = ?',
      whereArgs: <Object?>[jobId],
    );
  }

  Future<void> markFailed(String jobId, String message) async {
    await _database.db.rawUpdate(
      '''
      UPDATE processing_jobs
      SET status = ?, error = ?, attempts = attempts + 1,
          finished_at = ?, updated_at = ?
      WHERE id = ?
      ''',
      <Object?>[
        JobStatus.failed.name,
        message,
        DateTime.now().millisecondsSinceEpoch,
        DateTime.now().millisecondsSinceEpoch,
        jobId,
      ],
    );
  }

  Future<void> markCanceled(String jobId) async {
    await _database.db.update(
      'processing_jobs',
      <String, Object?>{
        'status': JobStatus.canceled.name,
        'finished_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ? AND status IN (?, ?)',
      whereArgs: <Object?>[
        jobId,
        JobStatus.queued.name,
        JobStatus.running.name,
      ],
    );
  }

  /// On startup, jobs left in `running` were interrupted by a process death.
  /// They go back to `queued` so no work is lost and nothing is duplicated.
  Future<int> recoverInterrupted() async {
    final int count = await _database.db.update(
      'processing_jobs',
      <String, Object?>{
        'status': JobStatus.queued.name,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'status = ?',
      whereArgs: <Object?>[JobStatus.running.name],
    );
    return count;
  }

  Future<List<ProcessingJob>> nextQueued({
    int limit = 1,
    List<JobType> excludeTypes = const <JobType>[],
  }) async {
    final String excluded = excludeTypes.isEmpty
        ? ''
        : ' AND type NOT IN (${List<String>.filled(excludeTypes.length, '?').join(',')})';
    final List<Map<String, Object?>> rows = await _database.db.query(
      'processing_jobs',
      where: 'status = ?$excluded',
      whereArgs: <Object?>[
        JobStatus.queued.name,
        ...excludeTypes.map((JobType type) => type.name),
      ],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(ProcessingJob.fromRow).toList(growable: false);
  }

  Future<List<ProcessingJob>> jobsForMemory(String memoryId) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'processing_jobs',
      where: 'memory_id = ?',
      whereArgs: <Object?>[memoryId],
      orderBy: 'created_at ASC',
    );
    return rows.map(ProcessingJob.fromRow).toList(growable: false);
  }

  Future<ProcessingJob?> jobFor({
    required String memoryId,
    required String? attachmentId,
    required JobType type,
  }) async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT * FROM processing_jobs
      WHERE memory_id = ? AND IFNULL(attachment_id, '') = ? AND type = ?
      LIMIT 1
      ''',
      <Object?>[memoryId, attachmentId ?? '', type.name],
    );
    return rows.isEmpty ? null : ProcessingJob.fromRow(rows.first);
  }

  Future<int> pendingCount() async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      'SELECT COUNT(*) AS c FROM processing_jobs WHERE status IN (?, ?)',
      <Object?>[JobStatus.queued.name, JobStatus.running.name],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<void> deleteForMemory(String memoryId) async {
    await _database.db.delete(
      'processing_jobs',
      where: 'memory_id = ?',
      whereArgs: <Object?>[memoryId],
    );
  }
}
