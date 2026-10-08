import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/database.dart';

/// Syncs the local Drift database with the `tasks` table in Supabase.
///
/// This is a simple single-device backup sync, not a multi-device merge:
/// local changes are pushed, and remote rows not present locally are pulled
/// down (useful for restoring after a reinstall). Any failure (e.g. no
/// network) is swallowed so the app keeps working fully offline.
class SyncService {
  SyncService(this._db);

  final AppDatabase _db;

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> sync() async {
    try {
      await _push();
      await _pull();
    } catch (e) {
      debugPrint('SyncService: sync failed, will retry later: $e');
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
}
