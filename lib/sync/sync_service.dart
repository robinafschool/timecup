import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/database.dart';

/// Syncs the local Drift database with the `tasks` table in Supabase.
///
/// This is a simple single-device backup sync, not a multi-device merge:
/// local changes are pushed, and remote rows not present locally are pulled
/// down (useful for restoring after a reinstall). Any failure (e.g. no
/// network) is swallowed so the app keeps working fully offline.
///
/// On top of that poll-style push/pull, [startRealtime] opens a Supabase
/// Realtime subscription so changes made directly on the server (by another
/// client, or in the Supabase dashboard) show up locally immediately instead
/// of waiting for the next `sync()` trigger. Requires Realtime to be enabled
/// for the `tasks` table (Database > Replication in the Supabase dashboard).
class SyncService {
  SyncService(this._db);

  final AppDatabase _db;

  RealtimeChannel? _channel;
  bool _syncing = false;

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> sync() async {
    if (_syncing) return;
    _syncing = true;
    try {
      await _push();
      await _pull();
    } catch (e) {
      debugPrint('SyncService: sync failed, will retry later: $e');
    } finally {
      _syncing = false;
    }
  }

  Future<void> _push() async {
    final dirtyTasks = await _db.getDirtyTasks();
    for (final task in dirtyTasks) {
      final updatedAt = task.updatedAt ?? DateTime.now();
      if (task.remoteId == null) {
        final inserted = await _client
            .from('tasks')
            .insert({
              'name': task.name,
              'done': task.done,
              'updated_at': updatedAt.toIso8601String(),
            })
            .select()
            .single();
        await _db.markSynced(task.id, inserted['id'] as String);
      } else {
        await _client
            .from('tasks')
            .update({
              'name': task.name,
              'done': task.done,
              'updated_at': updatedAt.toIso8601String(),
            })
            .eq('id', task.remoteId!);
        await _db.clearDirty(task.id);
      }
    }
  }

  Future<void> _pull() async {
    final remoteRows = await _client.from('tasks').select();
    for (final row in remoteRows) {
      final remoteId = row['id'] as String;
      if (await _db.existsByRemoteId(remoteId)) continue;
      await _db.insertFromRemote(
        remoteId: remoteId,
        name: row['name'] as String,
        done: row['done'] as bool,
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );
    }
  }

  /// Deletes a task both locally (caller's responsibility, before or after
  /// calling this) and on Supabase, if it had ever been synced there.
  /// Best-effort: if this fails (e.g. offline), the row simply stays deleted
  /// locally and orphaned remotely, consistent with how push/pull failures
  /// are handled elsewhere in this class.
  Future<void> deleteTask(Task task) async {
    if (task.remoteId == null) return;
    try {
      await _client.from('tasks').delete().eq('id', task.remoteId!);
    } catch (e) {
      debugPrint('SyncService: remote delete failed: $e');
    }
  }

  /// Subscribes to Postgres Changes on the `tasks` table so remote
  /// inserts/updates/deletes are applied locally as they happen.
  void startRealtime() {
    _channel = _client
        .channel('tasks-changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tasks',
          callback: _handleRealtimeChange,
        )
        .subscribe();
  }

  void stopRealtime() {
    final channel = _channel;
    if (channel != null) {
      _client.removeChannel(channel);
      _channel = null;
    }
  }

  Future<void> _handleRealtimeChange(PostgresChangePayload payload) async {
    try {
      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
          final row = payload.newRecord;
          final remoteId = row['id'] as String;
          if (await _db.existsByRemoteId(remoteId)) return;
          await _db.insertFromRemote(
            remoteId: remoteId,
            name: row['name'] as String,
            done: row['done'] as bool,
            updatedAt: DateTime.parse(row['updated_at'] as String),
          );
        case PostgresChangeEvent.update:
          final row = payload.newRecord;
          await _db.updateFromRemote(
            remoteId: row['id'] as String,
            name: row['name'] as String,
            done: row['done'] as bool,
            updatedAt: DateTime.parse(row['updated_at'] as String),
          );
        case PostgresChangeEvent.delete:
          final remoteId = payload.oldRecord['id'] as String?;
          if (remoteId != null) {
            await _db.deleteByRemoteId(remoteId);
          }
        case PostgresChangeEvent.all:
          // Never actually delivered; onPostgresChanges always resolves to
          // a concrete event type above.
          break;
      }
    } catch (e) {
      debugPrint('SyncService: realtime event handling failed: $e');
    }
  }
}
