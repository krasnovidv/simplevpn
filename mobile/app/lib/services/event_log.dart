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

  // Bound the in-memory log so long-lived connected sessions (native logs are
  // appended on every status poll) can't grow it without limit.
  static const _maxEntries = 500;

  final List<LogEntry> _entries = [];
  final _controller = StreamController<LogEntry>.broadcast();

  List<LogEntry> get entries => List.unmodifiable(_entries);
  Stream<LogEntry> get stream => _controller.stream;

  void add(String level, String message) {
    final entry = LogEntry(time: DateTime.now(), level: level, message: message);
    _entries.add(entry);
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    _controller.add(entry);
  }

  void info(String message) => add('INFO', message);
  void error(String message) => add('ERROR', message);
  void debug(String message) => add('DEBUG', message);
  void native(String message) => add('NATIVE', message);

  void clear() => _entries.clear();
}
