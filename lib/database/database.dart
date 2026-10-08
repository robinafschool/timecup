import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();

  /// The row's id in the Supabase `tasks` table, once it has been pushed
  /// there. Null means this row has never been synced.
  TextColumn get remoteId => text().nullable()();

  /// Last time this row was changed locally. Mirrors `updated_at` in
  /// Supabase so pulled rows can be compared against local ones.
  ///
  /// Nullable (rather than using a SQL-level default) because SQLite's
  /// `ALTER TABLE ... ADD COLUMN` only accepts constant defaults (`NULL`,
  /// literals, or bare `CURRENT_TIMESTAMP`) -- a `strftime(...)` expression
  /// like `currentDateAndTime` produces is rejected during migration. The
  /// app always supplies a value on insert/update instead.
  DateTimeColumn get updatedAt => dateTime().nullable()();

  /// True when this row has local changes that haven't been pushed yet.
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();
}

@DriftDatabase(tables: [Tasks])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'cup_of_time'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // A previous version of this migration failed partway through
        // (SQLite rejected a non-constant column default), which can leave
        // some of these columns already added. Check what's actually
        // present before adding, so re-running the migration on an
        // already-partially-migrated database doesn't blow up with
        // "duplicate column name".
        final existingColumns = await customSelect(
          "SELECT name FROM pragma_table_info('tasks')",
        ).map((row) => row.read<String>('name')).get();

        if (!existingColumns.contains('remote_id')) {
          await m.addColumn(tasks, tasks.remoteId);
        }
        if (!existingColumns.contains('updated_at')) {
          await m.addColumn(tasks, tasks.updatedAt);
        }
        if (!existingColumns.contains('dirty')) {
          await m.addColumn(tasks, tasks.dirty);
        }
      }
    },
  );

  Stream<List<Task>> watchAllTasks() {
    return (select(tasks)..orderBy([(t) => OrderingTerm(expression: t.id)]))
        .watch();
  }

  Future<int> addTask(String name) {
    return into(tasks).insert(
      TasksCompanion.insert(name: name, updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> toggleTask(Task task) {
    return update(tasks).replace(
      task.copyWith(
        done: !task.done,
        dirty: true,
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Rows with local changes that still need to be pushed to Supabase.
  Future<List<Task>> getDirtyTasks() {
    return (select(tasks)..where((t) => t.dirty.equals(true))).get();
  }

  /// Marks a freshly-pushed (newly inserted remote) row as synced.
  Future<void> markSynced(int localId, String remoteId) {
    return (update(tasks)..where((t) => t.id.equals(localId))).write(
      TasksCompanion(
        remoteId: Value(remoteId),
        dirty: const Value(false),
      ),
    );
  }

  /// Marks a row that was pushed as an update (already had a remoteId) as
  /// synced.
  Future<void> clearDirty(int localId) {
    return (update(tasks)..where((t) => t.id.equals(localId))).write(
      const TasksCompanion(dirty: Value(false)),
    );
  }

  Future<bool> existsByRemoteId(String remoteId) async {
    final row = await (select(
      tasks,
    )..where((t) => t.remoteId.equals(remoteId))).getSingleOrNull();
    return row != null;
  }

  /// Inserts a row pulled down from Supabase. Marked as not dirty since it
  /// already matches the remote state.
  Future<void> insertFromRemote({
    required String remoteId,
    required String name,
    required bool done,
    required DateTime updatedAt,
  }) {
    return into(tasks).insert(
      TasksCompanion.insert(
        name: name,
        done: Value(done),
        remoteId: Value(remoteId),
        updatedAt: Value(updatedAt),
        dirty: const Value(false),
      ),
    );
  }

  /// Applies a remote update (e.g. from a Realtime event) to the matching
  /// local row, identified by [remoteId]. Skipped if the local row has
  /// unpushed local changes (`dirty`), so an in-flight local edit always
  /// wins over a remote one we haven't pushed yet.
  Future<void> updateFromRemote({
    required String remoteId,
    required String name,
    required bool done,
    required DateTime updatedAt,
  }) {
    return (update(tasks)..where(
          (t) => t.remoteId.equals(remoteId) & t.dirty.equals(false),
        ))
        .write(
          TasksCompanion(
            name: Value(name),
            done: Value(done),
            updatedAt: Value(updatedAt),
          ),
        );
  }

  /// Deletes the local row with the given local [id]. Used after a local
  /// delete has already been (or doesn't need to be) pushed to Supabase.
  Future<void> deleteTaskLocal(int id) {
    return (delete(tasks)..where((t) => t.id.equals(id))).go();
  }

  /// Deletes the local row matching a given Supabase row id. Used when a
  /// Realtime DELETE event arrives for a row that still exists locally.
  Future<void> deleteByRemoteId(String remoteId) {
    return (delete(tasks)..where((t) => t.remoteId.equals(remoteId))).go();
  }
}
