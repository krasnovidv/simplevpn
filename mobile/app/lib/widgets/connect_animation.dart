import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

double _clamp01(double v) => v.clamp(0.0, 1.0);

double _easeInOutCubic(double t) {
  return t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
}

Offset _quadBezier(double t, Offset p0, Offset p1, Offset p2) {
  final u = 1 - t;
  return Offset(
    u * u * p0.dx + 2 * u * t * p1.dx + t * t * p2.dx,
    u * u * p0.dy + 2 * u * t * p1.dy + t * t * p2.dy,
  );
}

class ConnectAnimation extends StatelessWidget {
  final double t;

  const ConnectAnimation({super.key, required this.t});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(300, 360),
      painter: _ConnectAnimPainter(t: t),
    );
  }
}

class _ConnectAnimPainter extends CustomPainter {
  final double t;

  _ConnectAnimPainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final splitT = _clamp01((t - 0.4) / 0.8);
    final figT = _clamp01((t - 1.0) / 0.6);
    final armT = _clamp01((t - 1.4) / 0.5);
    final streamT = _clamp01((t - 1.6) / 1.0);
    final streamHead = _easeInOutCubic(streamT);
    final splashT = _clamp01((t - 2.4) / 0.7);
    final healing = _clamp01((t - 2.6) / 0.8);
    final protT = _clamp01((t - 3.4) / 0.4);

    _drawSplitLogo(canvas, w, h, splitT);

    final pnhPos = Offset(70, h / 2);
    final rknPos = Offset(220, h / 2 + 40);

    if (figT > 0) {
      _drawPNHFigure(canvas, pnhPos, figT, armT);
      _drawRKNFigure(canvas, rknPos, figT, healing);
    }

    final armR = (-10 - armT * 40) * math.pi / 180;
    final tip = Offset(
      pnhPos.dx + math.cos(armR) * 60,
      pnhPos.dy - 2 + math.sin(armR) * 60,
    );
    final target = Offset(rknPos.dx - 18, rknPos.dy - 20);
    final ctrl = Offset(
      (tip.dx + target.dx) / 2,
      math.min(tip.dy, target.dy) - 50,
    );

    if (streamHead > 0.01) {
      _drawStream(canvas, tip, ctrl, target, streamHead);
    }

    if (splashT > 0) {
      _drawSplash(canvas, target, splashT);
    }

    if (protT > 0) {
      _drawProtected(canvas, w, h, protT);
    }
  }

  void _drawSplitLogo(Canvas canvas, double w, double h, double splitT) {
    if (splitT >= 1) return;
    final opacity = (1 - splitT).clamp(0.0, 1.0);
    if (opacity < 0.01) return;

    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.rotate(-7.0 * math.pi / 180);

    // Stamp border fading out
    final borderOpacity = _clamp01(1 - splitT * 2.5);
    if (borderOpacity > 0.01) {
      const stampW = 158.0;
      const stampH = 141.0;
      final borderPaint = Paint()
        ..color = AppColors.magenta.withValues(alpha: borderOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5;
      final innerBorderPaint = Paint()
        ..color = AppColors.magenta.withValues(alpha: borderOpacity * 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      final dotPaint = Paint()
        ..color = AppColors.magenta.withValues(alpha: borderOpacity);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: stampW, height: stampH),
          const Radius.circular(8),
        ),
        borderPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: stampW - 11, height: stampH - 11),
          const Radius.circular(5),
        ),
        innerBorderPaint,
      );
      final corners = [
        Offset(-stampW / 2 + 8, -stampH / 2 + 8),
        Offset(stampW / 2 - 8, -stampH / 2 + 8),
        Offset(-stampW / 2 + 8, stampH / 2 - 8),
        Offset(stampW / 2 - 8, stampH / 2 - 8),
      ];
      for (final c in corners) {
        canvas.drawCircle(c, 1.8, dotPaint);
      }

      // Subtext
      _drawCenteredText(
        canvas,
        '★ NOT APPROVED ★',
        Offset(0, 38),
        TextStyle(
          fontFamily: AppFonts.body,
          fontSize: 8,
          fontWeight: FontWeight.w700,
          color: AppColors.magenta.withValues(alpha: borderOpacity),
          letterSpacing: 3,
        ),
      );
    }

    // Text splitting apart under tilt
    final rknStyle = TextStyle(
      fontFamily: AppFonts.display,
      fontSize: 44,
      fontWeight: FontWeight.w900,
      color: AppColors.magenta.withValues(alpha: opacity),
      letterSpacing: 2,
    );

    final rknOffset = Offset(splitT * 50, -20 - splitT * 25);
    final pnhOffset = Offset(-splitT * 50, 20 + splitT * 25);

    _drawCenteredText(canvas, 'RKN', rknOffset, rknStyle);
    _drawCenteredText(canvas, 'PNH', pnhOffset, rknStyle);

    canvas.restore();

    if (splitT > 0 && splitT < 1) {
      final particlePaint = Paint()
        ..color = AppColors.magenta.withValues(alpha: (1 - splitT) * 0.8);
      for (int i = 0; i < 14; i++) {
        final angle = (i / 14) * math.pi * 2;
        final r = splitT * 80;
        canvas.drawCircle(
          Offset(w / 2 + math.cos(angle) * r, h / 2 + math.sin(angle) * r),
          2,
          particlePaint,
        );
      }
    }
  }

  void _drawPNHFigure(Canvas canvas, Offset pos, double figT, double armT) {
    final paint = Paint()..color = AppColors.magenta.withValues(alpha: figT);

    canvas.drawCircle(Offset(pos.dx, pos.dy - 50), 13, paint);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(pos.dx, pos.dy - 11), width: 28, height: 50),
        const Radius.circular(14),
      ),
      paint,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pos.dx - 12, pos.dy + 14, 9, 38),
        const Radius.circular(4),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pos.dx + 3, pos.dy + 14, 9, 38),
        const Radius.circular(4),
      ),
      paint,
    );


    final armR = (-10 - armT * 40) * math.pi / 180;
    canvas.save();
    canvas.translate(pos.dx + 12, pos.dy - 2);
    canvas.rotate(armR);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, -3, 40, 6),
        const Radius.circular(3),
      ),
      paint,
    );
    final syringePaint = Paint()
      ..color = AppColors.magenta.withValues(alpha: figT)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(42, -5, 14, 10),
        const Radius.circular(2),
      ),
      syringePaint,
    );
    canvas.drawLine(
      const Offset(56, 0),
      const Offset(62, 0),
      Paint()
        ..color = AppColors.magenta.withValues(alpha: figT)
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      const Offset(62, 0),
      2 + armT,
      Paint()..color = AppColors.cyan.withValues(alpha: (0.5 + armT * 0.5) * figT),
    );
    canvas.restore();
  }

  void _drawRKNFigure(Canvas canvas, Offset pos, double figT, double healing) {
    final baseColor = healing > 0.5 ? AppColors.cyan : AppColors.magenta;
    final paint = Paint()..color = baseColor.withValues(alpha: figT);

    if (healing > 0) {
      canvas.drawCircle(
        Offset(pos.dx, pos.dy - 15),
        45 + healing * 15,
        Paint()..color = AppColors.cyan.withValues(alpha: healing * 0.18 * figT),
      );
    }

    canvas.drawCircle(Offset(pos.dx - 2, pos.dy - 50), 13, paint);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(pos.dx, pos.dy - 11), width: 28, height: 50),
        const Radius.circular(14),
      ),
      paint,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pos.dx - 12, pos.dy + 14, 9, 38),
        const Radius.circular(4),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pos.dx + 3, pos.dy + 14, 9, 38),
        const Radius.circular(4),
      ),
      paint,
    );

    final labelBg = Paint()..color = AppColors.bgDeep.withValues(alpha: 0.45 * figT);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(pos.dx, pos.dy - 10), width: 44, height: 14),
        const Radius.circular(3),
      ),
      labelBg,
    );
    _drawCenteredText(
      canvas,
      'RKN',
      Offset(pos.dx, pos.dy - 10),
      TextStyle(
        fontFamily: AppFonts.display,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        color: AppColors.white.withValues(alpha: figT),
        letterSpacing: 1,
      ),
    );

  }

  void _drawStream(
    Canvas canvas,
    Offset tip,
    Offset ctrl,
    Offset target,
    double head,
  ) {
    final points = <Offset>[];
    const segs = 22;
    for (int i = 0; i <= segs; i++) {
      final u = i / segs;
      if (u > head) break;
      points.add(_quadBezier(u, tip, ctrl, target));
    }
    if (points.length < 2) return;

    final outerPaint = Paint()
      ..color = AppColors.cyan.withValues(alpha: 0.35)
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    final midPaint = Paint()
      ..color = AppColors.cyan.withValues(alpha: 0.85)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    final corePaint = Paint()
      ..color = AppColors.white.withValues(alpha: 0.95)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    canvas.drawPath(path, outerPaint);
    canvas.drawPath(path, midPaint);
    canvas.drawPath(path, corePaint);

    final headPt = points.last;
    canvas.drawCircle(
      headPt,
      8,
      Paint()
        ..color = const Color(0xFF7df9ff).withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(headPt, 3, Paint()..color = AppColors.white);
  }

  void _drawSplash(Canvas canvas, Offset target, double splashT) {
    canvas.save();
    canvas.translate(target.dx, target.dy);

    for (final delay in [0.0, 0.25, 0.5]) {
      final lt = _clamp01(splashT - delay);
      if (lt <= 0) continue;
      final r = lt * 40;
      canvas.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..color = AppColors.cyan.withValues(alpha: 1 - lt)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 - lt,
      );
    }

    final rng = math.Random(42);
    for (int i = 0; i < 14; i++) {
      final angle = rng.nextDouble() * math.pi * 2;
      final speed = 20 + rng.nextDouble() * 30;
      final r = splashT * speed;
      final fall = splashT * splashT * 8;
      canvas.drawCircle(
        Offset(math.cos(angle) * r, math.sin(angle) * r * 0.7 + fall),
        1.5,
        Paint()..color = AppColors.cyan.withValues(alpha: (1 - splashT * 0.9).clamp(0.0, 1.0)),
      );
    }

    canvas.restore();
  }

  void _drawProtected(Canvas canvas, double w, double h, double protT) {
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(w / 2, h - 60), width: 170 * (0.9 + protT * 0.1), height: 36),
      const Radius.circular(18),
    );
    canvas.drawRRect(
      pillRect,
      Paint()..color = AppColors.cyan.withValues(alpha: 0.1 * protT),
    );
    canvas.drawRRect(
      pillRect,
      Paint()
        ..color = AppColors.cyan.withValues(alpha: protT)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    canvas.drawCircle(
      Offset(w / 2 - 60, h - 60),
      4,
      Paint()..color = const Color(0xFF4ade80).withValues(alpha: protT),
    );

    _drawCenteredText(
      canvas,
      'ЗАЩИЩЁН',
      Offset(w / 2 + 8, h - 60),
      TextStyle(
        fontFamily: AppFonts.body,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.white.withValues(alpha: protT),
        letterSpacing: 2,
      ),
    );
  }

  void _drawCenteredText(Canvas canvas, String text, Offset center, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_ConnectAnimPainter old) => old.t != t;
}
