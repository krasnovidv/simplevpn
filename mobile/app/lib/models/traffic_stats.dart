import 'dart:convert';

class TrafficStats {
  final int bytesIn;
  final int bytesOut;
  final int sinceMs;

  const TrafficStats({
    required this.bytesIn,
    required this.bytesOut,
    required this.sinceMs,
  });

  static const zero = TrafficStats(bytesIn: 0, bytesOut: 0, sinceMs: 0);

  factory TrafficStats.fromJson(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return TrafficStats(
        bytesIn: (map['bytes_in'] as num?)?.toInt() ?? 0,
        bytesOut: (map['bytes_out'] as num?)?.toInt() ?? 0,
        sinceMs: (map['since_ms'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return zero;
    }
  }

  @override
  String toString() => 'TrafficStats(in=$bytesIn, out=$bytesOut, since=$sinceMs)';
}

class TrafficSample {
  final double kbpsIn;
  final double kbpsOut;
  final DateTime timestamp;

  TrafficSample({
    required this.kbpsIn,
    required this.kbpsOut,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  static TrafficSample fromDelta(TrafficStats prev, TrafficStats curr, Duration elapsed) {
    if (elapsed.inMilliseconds <= 0) {
      return TrafficSample(kbpsIn: 0, kbpsOut: 0, timestamp: DateTime.now());
    }
    final seconds = elapsed.inMilliseconds / 1000.0;
    final deltaIn = curr.bytesIn - prev.bytesIn;
    final deltaOut = curr.bytesOut - prev.bytesOut;
    // Negative delta means counter reset (reconnect) — treat as zero
    final kbpsIn = deltaIn > 0 ? (deltaIn / 1024.0) / seconds : 0.0;
    final kbpsOut = deltaOut > 0 ? (deltaOut / 1024.0) / seconds : 0.0;
    return TrafficSample(kbpsIn: kbpsIn, kbpsOut: kbpsOut, timestamp: DateTime.now());
  }
}

class TrafficSnapshot {
  final TrafficStats cumulative;
  final List<TrafficSample> samples;

  const TrafficSnapshot({required this.cumulative, required this.samples});
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
