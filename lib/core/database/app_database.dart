import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'migrations/migration_v1.dart';
import 'migrations/migration_v2.dart';
import 'migrations/migration_v3.dart';

/// Owns the SQLite connection and the schema version.
///
/// Uses the isolate-backed `databaseFactoryFfi`, never the no-isolate variant:
/// sqflite_common_ffi dispatches open/SQL/close to its `SqfliteIsolate` worker.
/// Migration callbacks orchestrate here, but all SQLite migration work also
/// executes there. The factory serializes statements and transaction access.
/// Bundled SQLite supplies FTS5, unlike Android's system SQLite.
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;
  Future<void>? _closing;
  Database get db => _db;

  static const int schemaVersion = 3;
  static bool _ffiInitialised = false;

  /// Must be called once before opening any database.
  static void initialise() {
    if (_ffiInitialised) return;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _ffiInitialised = true;
  }

  /// Opens (and creates/upgrades) the database inside [directory].
  static Future<AppDatabase> openIn(
    String directory, {
    String fileName = 'mindpocket.db',
  }) async {
    initialise();
    final Database db = await databaseFactoryFfi.openDatabase(
      p.join(directory, fileName),
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: _configure,
        onCreate: _create,
        onUpgrade: _upgrade,
        onOpen: _optimize,
      ),
    );
    return AppDatabase._(db);
  }

  /// Opens a database at an arbitrary path (`:memory:` included for tests).
  static Future<AppDatabase> openAt(String path) async {
    initialise();
    final Database db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: _configure,
        onCreate: _create,
        onUpgrade: _upgrade,
        onOpen: _optimize,
      ),
    );
    return AppDatabase._(db);
  }

  static Future<void> _configure(Database db) async {
    await db.execute('PRAGMA busy_timeout = 5000');
    await db.execute('PRAGMA foreign_keys = ON');
    // WAL is disk-only; in-memory SQLite retains its memory journal. Configure
    // before the migration transaction because journal mode cannot change in it.
    if (db.path != inMemoryDatabasePath) {
      await db.rawQuery('PRAGMA journal_mode = WAL');
    }
    // Keep committed personal data durable through power loss. WAL still avoids
    // rollback-journal rewriting without NORMAL's weaker commit durability.
    await db.execute('PRAGMA synchronous = FULL');
  }

  static Future<void> _optimize(Database db) async {
    // Refresh bounded planner statistics after migrations. Without them SQLite
    // can prefer the old deleted_at index and sort instead of using the new
    // ordered timeline index, even when the latter matches the query exactly.
    await db.execute('PRAGMA optimize=0x10002');
  }

  static Future<void> _create(Database db, int version) async {
    await MigrationV1.up(db);
    if (version >= 2) await MigrationV2.up(db);
    if (version >= 3) await MigrationV3.up(db);
  }

  static Future<void> _upgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 1) await MigrationV1.up(db);
    if (oldVersion < 2) await MigrationV2.up(db);
    if (oldVersion < 3) await MigrationV3.up(db);
  }

  /// Close through sqflite's serialized connection queue. SQLite checkpoints
  /// WAL on the last connection close; do not kill the shared factory isolate.
  Future<void> close() => _closing ??= _db.close();

  /// Integrity check used by the settings screen.
  Future<bool> isHealthy() async {
    final List<Map<String, Object?>> result = await _db.rawQuery(
      'PRAGMA integrity_check',
    );
    return result.isNotEmpty && result.first.values.first == 'ok';
  }
}
