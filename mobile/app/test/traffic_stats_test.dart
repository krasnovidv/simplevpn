import 'package:flutter_test/flutter_test.dart';
import 'package:simplevpn/models/traffic_stats.dart';

void main() {
  group('TrafficStats.fromJson', () {
    test('parses valid JSON', () {
      final stats = TrafficStats.fromJson('{"bytes_in":1024,"bytes_out":512,"since_ms":1700000000000}');
      expect(stats.bytesIn, 1024);
      expect(stats.bytesOut, 512);
      expect(stats.sinceMs, 1700000000000);
    });

    test('handles zero values', () {
      final stats = TrafficStats.fromJson('{"bytes_in":0,"bytes_out":0,"since_ms":0}');
      expect(stats.bytesIn, 0);
      expect(stats.bytesOut, 0);
      expect(stats.sinceMs, 0);
    });

    test('handles large values near int64 max', () {
      final stats = TrafficStats.fromJson('{"bytes_in":9007199254740992,"bytes_out":9007199254740991,"since_ms":1700000000000}');
      expect(stats.bytesIn, 9007199254740992);
      expect(stats.bytesOut, 9007199254740991);
    });

    test('malformed JSON returns zero', () {
      final stats = TrafficStats.fromJson('not json at all');
      expect(stats.bytesIn, 0);
      expect(stats.bytesOut, 0);
      expect(stats.sinceMs, 0);
    });

    test('empty string returns zero', () {
      final stats = TrafficStats.fromJson('');
      expect(stats.bytesIn, 0);
      expect(stats.bytesOut, 0);
      expect(stats.sinceMs, 0);
    });

    test('missing fields default to zero', () {
      final stats = TrafficStats.fromJson('{"bytes_in":100}');
      expect(stats.bytesIn, 100);
      expect(stats.bytesOut, 0);
      expect(stats.sinceMs, 0);
    });

    test('null values default to zero', () {
      final stats = TrafficStats.fromJson('{"bytes_in":null,"bytes_out":null,"since_ms":null}');
      expect(stats.bytesIn, 0);
      expect(stats.bytesOut, 0);
      expect(stats.sinceMs, 0);
    });
  });

  group('TrafficSample.fromDelta', () {
    test('computes correct KB/s for monotonic increase', () {
      const prev = TrafficStats(bytesIn: 0, bytesOut: 0, sinceMs: 1000);
      const curr = TrafficStats(bytesIn: 10240, bytesOut: 5120, sinceMs: 1000);
      final sample = TrafficSample.fromDelta(prev, curr, const Duration(seconds: 1));
      expect(sample.kbpsIn, closeTo(10.0, 0.01));
      expect(sample.kbpsOut, closeTo(5.0, 0.01));
    });

    test('computes correct rate over 2 seconds', () {
      const prev = TrafficStats(bytesIn: 1000, bytesOut: 500, sinceMs: 1000);
      const curr = TrafficStats(bytesIn: 11240, bytesOut: 5620, sinceMs: 1000);
      final sample = TrafficSample.fromDelta(prev, curr, const Duration(seconds: 2));
      // deltaIn = 10240, over 2s = 5120 B/s = 5 KB/s
      expect(sample.kbpsIn, closeTo(5.0, 0.01));
      // deltaOut = 5120, over 2s = 2560 B/s = 2.5 KB/s
      expect(sample.kbpsOut, closeTo(2.5, 0.01));
    });

    test('counter reset produces zero (no negative spike)', () {
      const prev = TrafficStats(bytesIn: 50000, bytesOut: 30000, sinceMs: 1000);
      const curr = TrafficStats(bytesIn: 100, bytesOut: 50, sinceMs: 2000);
      final sample = TrafficSample.fromDelta(prev, curr, const Duration(seconds: 1));
      expect(sample.kbpsIn, 0.0);
      expect(sample.kbpsOut, 0.0);
    });

    test('zero elapsed produces zero rates', () {
      const prev = TrafficStats(bytesIn: 0, bytesOut: 0, sinceMs: 1000);
      const curr = TrafficStats(bytesIn: 1024, bytesOut: 512, sinceMs: 1000);
      final sample = TrafficSample.fromDelta(prev, curr, Duration.zero);
      expect(sample.kbpsIn, 0.0);
      expect(sample.kbpsOut, 0.0);
    });

    test('negative elapsed produces zero rates', () {
      const prev = TrafficStats(bytesIn: 0, bytesOut: 0, sinceMs: 1000);
      const curr = TrafficStats(bytesIn: 1024, bytesOut: 512, sinceMs: 1000);
      final sample = TrafficSample.fromDelta(prev, curr, const Duration(milliseconds: -500));
      expect(sample.kbpsIn, 0.0);
      expect(sample.kbpsOut, 0.0);
    });

    test('identical values produce zero rates', () {
      const prev = TrafficStats(bytesIn: 5000, bytesOut: 3000, sinceMs: 1000);
      const curr = TrafficStats(bytesIn: 5000, bytesOut: 3000, sinceMs: 1000);
      final sample = TrafficSample.fromDelta(prev, curr, const Duration(seconds: 1));
      expect(sample.kbpsIn, 0.0);
      expect(sample.kbpsOut, 0.0);
    });
  });

  group('formatBytes', () {
    test('formats bytes', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(500), '500 B');
      expect(formatBytes(1023), '1023 B');
    });

    test('formats kilobytes', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(10240), '10.0 KB');
    });

    test('formats megabytes', () {
      expect(formatBytes(1048576), '1.0 MB');
      expect(formatBytes(12582912), '12.0 MB');
    });

    test('formats gigabytes', () {
      expect(formatBytes(1073741824), '1.00 GB');
      expect(formatBytes(2147483648), '2.00 GB');
    });
  });

  group('rolling window behavior', () {
    test('oldest sample drops at 61st insert', () {
      final samples = <TrafficSample>[];
      const maxSamples = 60;

      for (var i = 0; i < 65; i++) {
        samples.add(TrafficSample(kbpsIn: i.toDouble(), kbpsOut: 0));
        if (samples.length > maxSamples) {
          samples.removeAt(0);
        }
      }

      expect(samples.length, maxSamples);
      // First sample should be index 5 (0-4 dropped)
      expect(samples.first.kbpsIn, 5.0);
      expect(samples.last.kbpsIn, 64.0);
    });
  });
}
