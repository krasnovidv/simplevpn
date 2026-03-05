import 'package:flutter/material.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final List<LogEntry> _logs = [];

  @override
  void initState() {
    super.initState();
    // Add some sample log entries for demo
    _logs.addAll([
      LogEntry(time: DateTime.now(), level: 'INFO', message: 'App started'),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connection Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear logs',
            onPressed: () => setState(() => _logs.clear()),
          ),
        ],
      ),
      body: _logs.isEmpty
          ? const Center(
              child: Text('No log entries', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(8),
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                final log = _logs[_logs.length - 1 - index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '${_formatTime(log.time)} [${log.level}] ${log.message}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: log.level == 'ERROR'
                          ? colorScheme.error
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

  void addLog(String level, String message) {
    setState(() {
      _logs.add(LogEntry(time: DateTime.now(), level: level, message: message));
    });
  }
}

class LogEntry {
  final DateTime time;
  final String level;
  final String message;

  LogEntry({required this.time, required this.level, required this.message});
}
