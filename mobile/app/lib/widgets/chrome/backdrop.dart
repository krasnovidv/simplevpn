import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/chrome.dart';
import 'chrome_orb.dart';

/// Full-screen chrome backdrop: three soft colour blobs drifting slowly
/// (three times faster while connecting) under a fine dot grain. Blob
/// intensity follows the connection mood.
class ChromeBackdrop extends StatefulWidget {
  final OrbMood mood;
  final bool animate;
  final Widget? child;

  const ChromeBackdrop({super.key, required this.mood, this.animate = true, this.child});

  @override
  State<ChromeBackdrop> createState() => _ChromeBackdropState();
}

class _ChromeBackdropState extends State<ChromeBackdrop> with SingleTickerProviderStateMixin {
  // Keyframe phase of each blob, 0..1, advanced at 1/period per second.
  final _phase = ValueNotifier<List<double>>([0, 0.3, 0.6]);
  Ticker? _ticker;
  Duration _last = Duration.zero;

  static const _periods = [14.0, 18.0, 22.0];

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ChromeBackdrop old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.animate) {
      _ticker ??= createTicker((elapsed) {
        final dt = (elapsed - _last).inMicroseconds / 1e6;
        _last = elapsed;
        final speed = widget.mood == OrbMood.connecting ? 3.0 : 1.0;
        _phase.value = [
          for (var i = 0; i < 3; i++) (_phase.value[i] + dt * speed / _periods[i]) % 1.0,
        ];
      });
      if (!_ticker!.isActive) {
        _last = Duration.zero;
        _ticker!.start();
      }
    } else {
      _ticker?.stop();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _phase.dispose();
    super.dispose();
  }

  double get _intensity => switch (widget.mood) {
        OrbMood.connected => 1.0,
        OrbMood.error => 0.35,
        _ => 0.6,
      };

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: c.bg),
        TweenAnimationBuilder<double>(
          tween: Tween(end: _intensity),
          duration: const Duration(seconds: 1),
          builder: (context, k, _) => RepaintBoundary(
            child: CustomPaint(painter: _BlobPainter(_phase, c, (c.dark ? 0.45 : 0.7) * k)),
          ),
        ),
        RepaintBoundary(child: CustomPaint(painter: _GrainPainter(c.dark))),
        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _BlobPainter extends CustomPainter {
  final ValueNotifier<List<double>> phase;
  final Chrome c;
  final double opacity;

  _BlobPainter(this.phase, this.c, this.opacity) : super(repaint: phase);

  // Keyframes in design pixels (412×880 frame): [at, dx, dy, scale].
  static const _frames = [
    [[0.0, 0.0, 0.0, 1.0], [0.33, 60.0, 40.0, 1.15], [0.66, -40.0, 80.0, 0.9], [1.0, 0.0, 0.0, 1.0]],
    [[0.0, 0.0, 0.0, 1.0], [0.5, -70.0, -50.0, 1.2], [1.0, 0.0, 0.0, 1.0]],
    [[0.0, 0.0, 0.0, 1.0], [0.5, 50.0, -90.0, 1.0], [1.0, 0.0, 0.0, 1.0]],
  ];
  static const _centers = [Offset(90, 250), Offset(350, 470), Offset(210, 730)];

  static List<double> _at(List<List<double>> kf, double p) {
    for (var i = 0; i < kf.length - 1; i++) {
      final a = kf[i], b = kf[i + 1];
      if (p <= b[0]) {
        final t = Curves.easeInOut.transform((p - a[0]) / (b[0] - a[0]));
        return [for (var j = 1; j < 4; j++) a[j] + (b[j] - a[j]) * t];
      }
    }
    return kf.last.sublist(1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 412, sy = size.height / 880;
    for (var i = 0; i < 3; i++) {
      final f = _at(_frames[i], phase.value[i]);
      final center = Offset((_centers[i].dx + f[0]) * sx, (_centers[i].dy + f[1]) * sy);
      // A 340 px disc blurred by 70 px, approximated by a radial falloff.
      final r = 310 * f[2] * sx;
      final col = c.blobs[i];
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = ui.Gradient.radial(center, r, [
            col.withValues(alpha: opacity),
            col.withValues(alpha: opacity * 0.85),
            col.withValues(alpha: opacity * 0.4),
            col.withValues(alpha: 0),
          ], const [0, 0.35, 0.6, 1]),
      );
    }
  }

  @override
  bool shouldRepaint(_BlobPainter old) => old.opacity != opacity || old.c != c;
}

class _GrainPainter extends CustomPainter {
  final bool dark;
  _GrainPainter(this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final pts = <Offset>[];
    for (var y = 2.0; y < size.height; y += 4) {
      for (var x = 2.0; x < size.width; x += 4) {
        pts.add(Offset(x, y));
      }
    }
    canvas.drawPoints(
      ui.PointMode.points,
      pts,
      Paint()
        ..color = (dark ? Colors.white : const Color(0xFF121320)).withValues(alpha: 0.05)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.dark != dark;
}
