import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PulseRings extends StatefulWidget {
  final Color color;

  const PulseRings({super.key, this.color = AppColors.magenta});

  @override
  State<PulseRings> createState() => _PulseRingsState();
}

class _PulseRingsState extends State<PulseRings> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: const Size(280, 280),
          painter: _PulseRingsPainter(
            progress: _controller.value,
            color: widget.color,
          ),
        );
      },
    );
  }
}

class _PulseRingsPainter extends CustomPainter {
  final double progress;
  final Color color;

  static const _ringCount = 3;
  static const _staggerOffset = 1.0 / _ringCount;

  _PulseRingsPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (int i = 0; i < _ringCount; i++) {
      final ringProgress = (progress + i * _staggerOffset) % 1.0;
      final scale = 0.6 + ringProgress * 1.0;
      final opacity = (0.6 * (1 - ringProgress)).clamp(0.0, 1.0);

      if (opacity < 0.01) continue;

      canvas.drawCircle(
        center,
        maxRadius * scale,
        Paint()
          ..color = color.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_PulseRingsPainter old) =>
      old.progress != progress || old.color != color;
}
