import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'database/database.dart';
import 'sync/sync_service.dart';

Future<void> main() async {
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cup of Time',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
      ),
      home: const MyHomePage(title: 'Cup of Time'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final AppDatabase _db = AppDatabase();
  late final SyncService _syncService = SyncService(_db);
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _syncService.sync();
    _syncService.startRealtime();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        _syncService.sync();
      }
    });
  }

  @override
  void dispose() {
    _syncService.stopRealtime();
    _connectivitySubscription?.cancel();
    _textController.dispose();
    _db.close();
    super.dispose();
  }

  void toggleTask(Task task) {
    _db.toggleTask(task);
    _syncService.sync();
  }

  void addTask(String name) {
    _db.addTask(name);
    _syncService.sync();
  }

  void deleteTask(Task task) {
    _db.deleteTaskLocal(task.id);
    _syncService.deleteTask(task);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: StreamBuilder<List<Task>>(
          stream: _db.watchAllTasks(),
          builder: (context, snapshot) {
            final tasks = snapshot.data ?? [];
            return ListView.builder(
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final task = tasks[index];
                return Dismissible(
                  key: ValueKey(task.id),
                  background: Container(color: Colors.red),
                  onDismissed: (_) => deleteTask(task),
                  child: CheckboxListTile(
                    title: Text(task.name),
                    value: task.done,
                    onChanged: (_) => toggleTask(task),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final text = await showDialog<String>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: Text('Add Task'),
                content: TextField(
                  controller: _textController,
                  autofocus: true,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, _textController.text),
                    child: Text('Add'),
                  ),
                ],
              );
            },
          );
          if (text != null) {
            addTask(text);
          }
          _textController.clear();
        },
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
