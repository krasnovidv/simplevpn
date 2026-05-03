import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/traffic_stats.dart';

class StatsSparkline extends StatelessWidget {
  final List<TrafficSample> samples;
  final bool reconnecting;

  const StatsSparkline({
    super.key,
    required this.samples,
    this.reconnecting = false,
  });

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) {
      return const SizedBox(height: 60);
    }

    final downSpots = <FlSpot>[];
    final upSpots = <FlSpot>[];
    for (var i = 0; i < samples.length; i++) {
      downSpots.add(FlSpot(i.toDouble(), samples[i].kbpsIn));
      upSpots.add(FlSpot(i.toDouble(), samples[i].kbpsOut));
    }

    final maxY = samples.fold<double>(0.0, (prev, s) {
      final m = s.kbpsIn > s.kbpsOut ? s.kbpsIn : s.kbpsOut;
      return m > prev ? m : prev;
    });

    return Stack(
      children: [
        SizedBox(
          height: 60,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: 59,
              minY: 0,
              maxY: maxY > 0 ? maxY * 1.2 : 1,
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: downSpots,
                  isCurved: true,
                  curveSmoothness: 0.2,
                  color: Colors.blue.withAlpha(200),
                  barWidth: 1.5,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: Colors.blue.withAlpha(40),
                  ),
                ),
                LineChartBarData(
                  spots: upSpots,
                  isCurved: true,
                  curveSmoothness: 0.2,
                  color: Colors.green.withAlpha(200),
                  barWidth: 1.5,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: Colors.green.withAlpha(40),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (reconnecting)
          Positioned.fill(
            child: Container(
              color: Colors.black26,
              alignment: Alignment.center,
              child: const Text(
                'Reconnecting…',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}
