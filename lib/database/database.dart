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
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

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
        await m.addColumn(tasks, tasks.remoteId);
        await m.addColumn(tasks, tasks.updatedAt);
        await m.addColumn(tasks, tasks.dirty);
      }
    },
  );

  Stream<List<Task>> watchAllTasks() {
    return (select(tasks)..orderBy([(t) => OrderingTerm(expression: t.id)]))
        .watch();
  }

  Future<int> addTask(String name) {
    return into(tasks).insert(TasksCompanion.insert(name: name));
  }

  Future<void> toggleTask(Task task) {
    return update(tasks).replace(
      task.copyWith(
        done: !task.done,
        dirty: true,
        updatedAt: DateTime.now(),
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
}
