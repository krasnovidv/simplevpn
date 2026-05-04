import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StampWidget extends StatelessWidget {
  final double size;
  final Color color;
  final double scale;
  final double rotation;

  const StampWidget({
    super.key,
    this.size = 220,
    this.color = AppColors.magenta,
    this.scale = 1.0,
    this.rotation = -7.0,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      child: Transform.rotate(
        angle: rotation * math.pi / 180,
        child: CustomPaint(
          size: Size(size, size),
          painter: _StampPainter(color: color),
        ),
      ),
    );
  }
}

class _StampPainter extends CustomPainter {
  final Color color;

  _StampPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 200;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.translate(-72 * s, -64 * s);

    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5 * s;

    final innerBorderPaint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 * s;

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, 144 * s, 128 * s),
        Radius.circular(8 * s),
      ),
      borderPaint,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(5 * s, 5 * s, 134 * s, 118 * s),
        Radius.circular(5 * s),
      ),
      innerBorderPaint,
    );

    final corners = [
      Offset(8 * s, 8 * s),
      Offset(136 * s, 8 * s),
      Offset(8 * s, 120 * s),
      Offset(136 * s, 120 * s),
    ];
    for (final c in corners) {
      canvas.drawCircle(c, 1.8 * s, dotPaint);
    }

    final rknStyle = TextStyle(
      fontFamily: AppFonts.display,
      fontSize: 42 * s,
      fontWeight: FontWeight.w900,
      color: color,
      letterSpacing: 2 * s,
    );
    _drawCenteredText(canvas, 'RKN', 72 * s, 46 * s, rknStyle);
    _drawCenteredText(canvas, 'PNH', 72 * s, 84 * s, rknStyle);

    final subStyle = TextStyle(
      fontFamily: AppFonts.body,
      fontSize: 7.5 * s,
      fontWeight: FontWeight.w700,
      color: color,
      letterSpacing: 3 * s,
    );
    _drawCenteredText(canvas, '★ NOT APPROVED ★', 72 * s, 104 * s, subStyle);

    canvas.restore();
  }

  void _drawCenteredText(
    Canvas canvas,
    String text,
    double cx,
    double cy,
    TextStyle style,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_StampPainter old) => old.color != color;
}
