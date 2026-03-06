import 'dart:async';

class LogEntry {
  final DateTime time;
  final String level;
  final String message;

  LogEntry({required this.time, required this.level, required this.message});
}

class EventLog {
  static final EventLog _instance = EventLog._();
  factory EventLog() => _instance;
  EventLog._();

  final List<LogEntry> _entries = [];
  final _controller = StreamController<LogEntry>.broadcast();

  List<LogEntry> get entries => List.unmodifiable(_entries);
  Stream<LogEntry> get stream => _controller.stream;

  void add(String level, String message) {
    final entry = LogEntry(time: DateTime.now(), level: level, message: message);
    _entries.add(entry);
    _controller.add(entry);
  }

  void info(String message) => add('INFO', message);
  void error(String message) => add('ERROR', message);
  void debug(String message) => add('DEBUG', message);

  void clear() => _entries.clear();
}
