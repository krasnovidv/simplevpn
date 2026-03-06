import 'dart:async';
import 'package:flutter/material.dart';
import '../services/event_log.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final _eventLog = EventLog();
  StreamSubscription<LogEntry>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = _eventLog.stream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final logs = _eventLog.entries;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connection Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear logs',
            onPressed: () {
              _eventLog.clear();
              setState(() {});
            },
          ),
        ],
      ),
      body: logs.isEmpty
          ? const Center(
              child: Text('No log entries', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(8),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[logs.length - 1 - index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '${_formatTime(log.time)} [${log.level}] ${log.message}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: log.level == 'ERROR'
                          ? colorScheme.error
                          : log.level == 'NATIVE'
                              ? Colors.cyan
                              : log.level == 'DEBUG'
                                  ? colorScheme.onSurface.withValues(alpha: 0.5)
                                  : colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
