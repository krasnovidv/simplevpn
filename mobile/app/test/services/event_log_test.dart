import 'package:flutter_test/flutter_test.dart';
import 'package:simplevpn/services/event_log.dart';

void main() {
  group('EventLog', () {
    late EventLog log;

    setUp(() {
      log = EventLog();
      log.clear();
    });

    test('info adds INFO entry', () {
      log.info('test message');

      expect(log.entries.length, 1);
      expect(log.entries.first.level, 'INFO');
      expect(log.entries.first.message, 'test message');
    });

    test('error adds ERROR entry', () {
      log.error('something broke');

      expect(log.entries.first.level, 'ERROR');
    });

    test('debug adds DEBUG entry', () {
      log.debug('debug info');

      expect(log.entries.first.level, 'DEBUG');
    });

    test('clear removes all entries', () {
      log.info('one');
      log.info('two');
      log.clear();

      expect(log.entries, isEmpty);
    });

    test('stream emits new entries', () async {
      final future = log.stream.first;
      log.info('streamed');

      final entry = await future;
      expect(entry.message, 'streamed');
    });

    test('entries are unmodifiable', () {
      log.info('test');
      expect(() => log.entries.add(LogEntry(
        time: DateTime.now(),
        level: 'X',
        message: 'y',
      )), throwsA(isA<UnsupportedError>()));
    });
  });
}
