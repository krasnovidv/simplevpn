import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../theme/app_theme.dart';
import 'footer_common.dart';

/// Traffic Gremlin footer — a hungry pixel gremlin in a feeding tank. Download
/// packets fly in from the right; it chomps them (↓ EATEN), its belly fills,
/// then it burps them back as upload (↑ BURPED). Numbers are theatre.
class FooterMonster extends StatefulWidget {
  final FooterConnState state;
  final int secs;

  const FooterMonster({super.key, required this.state, required this.secs});

  @override
  State<FooterMonster> createState() => _FooterMonsterState();
}

class _MPacket {
  double x, y;
  final double size, spd;
  final Color color;
  _MPacket(this.x, this.y, this.size, this.spd, this.color);
}

class _Burp {
  final double born;
  _Burp(this.born);
}

class _FooterMonsterState extends State<FooterMonster>
    with SingleTickerProviderStateMixin {
  static const double _w = 320, _h = 120;
  static const Offset _mouth = Offset(74, 64);

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _nowMs = 0;
  final _rng = Random();

  final List<_MPacket> _packets = [];
  final List<_Burp> _burps = [];
  double _eaten = 0, _burped = 0, _belly = 0;
  double _chompAt = -1000;
  double _spawnAcc = 0;
  double _nextGap = 260;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(FooterMonster old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state && widget.state == FooterConnState.idle) {
      _packets.clear();
      _burps.clear();
      _eaten = 0;
      _burped = 0;
      _belly = 0;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = min(64.0, (elapsed - _last).inMicroseconds / 1000.0);
    _last = elapsed;
    _nowMs = elapsed.inMicroseconds / 1000.0;
    if (dt <= 0) return;
    final st = widget.state;
    final eating =
        st == FooterConnState.connecting || st == FooterConnState.connected;

    // spawn packets from the right edge
    if (eating) {
      _spawnAcc += dt;
      if (_spawnAcc >= _nextGap) {
        _spawnAcc = 0;
        final gap = st == FooterConnState.connecting ? 260.0 : 480.0;
        _nextGap = gap + _rng.nextDouble() * 240;
        _packets.add(_MPacket(
          _w + 8,
          30 + _rng.nextDouble() * 60,
          0.4 + _rng.nextDouble() * 2.6,
          0.06 + _rng.nextDouble() * 0.05,
          _rng.nextBool() ? AppColors.cyan : AppColors.magenta,
        ));
      }
    }

    final speedMul = st == FooterConnState.connecting ? 1.5 : 1.0;
    double ate = 0;
    _packets.removeWhere((p) {
      p.x -= p.spd * dt * 60 / 16 * speedMul;
      p.y += (_mouth.dy - p.y) * 0.06;
      if (p.x <= _mouth.dx) {
        ate += p.size;
        return true;
      }
      return false;
    });

    if (ate > 0) {
      _eaten += ate;
      _chompAt = _nowMs;
      _belly += ate * 9;
      if (_belly >= 100) {
        _burped += 1 + _rng.nextDouble() * 4;
        _burps.add(_Burp(_nowMs));
        if (_burps.length > 5) _burps.removeAt(0);
        _belly -= 100;
      }
    }

    _burps.removeWhere((b) => _nowMs - b.born > 1100);

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    final chomping = _nowMs - _chompAt < 160;
    final mood = st == FooterConnState.idle
        ? 'STARVING'
        : st == FooterConnState.connecting
            ? 'WAKING UP'
            : _belly > 75
                ? 'STUFFED'
                : chomping
                    ? 'NOM NOM'
                    : 'MUNCHING';
    final moodColor = st == FooterConnState.idle
        ? AppColors.dim
        : st == FooterConnState.connecting
            ? AppColors.yellow
            : _belly > 75
                ? AppColors.magentaHi
                : AppColors.cyan;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.dim2),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('// ТРАФИК-ГРЕМЛИН',
                    style: TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 9,
                        color: AppColors.dim,
                        letterSpacing: 2)),
                Text(mood,
                    style: TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 9,
                        color: moodColor,
                        letterSpacing: 2)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.bgDeep,
                  border: Border.all(color: AppColors.dim2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: AspectRatio(
                  aspectRatio: _w / _h,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _MonsterPainter(
                        packets: _packets,
                        burps: _burps,
                        belly: _belly,
                        chomping: chomping,
                        asleep: st == FooterConnState.idle,
                        nowMs: _nowMs,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _statStrip(st),
          ],
        ),
      ),
    );
  }

  Widget _statStrip(FooterConnState st) {
    Widget bigStat(String label, String value, Color color, bool right) {
      return Column(
        crossAxisAlignment:
            right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 9,
                  color: AppColors.dim,
                  letterSpacing: 1.5)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      color: color,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(width: 3),
              const Text('MB',
                  style: TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 10,
                      color: AppColors.dim)),
            ],
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        bigStat('↓ СЪЕДЕНО', _eaten.toStringAsFixed(1), AppColors.cyan, false),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              st == FooterConnState.connected
                  ? fmtFooterTime(widget.secs)
                  : st == FooterConnState.connecting
                      ? 'нюхает…'
                      : 'спит',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 9,
                  color: AppColors.dim,
                  letterSpacing: 1),
            ),
          ),
        ),
        bigStat('↑ ОТРЫГНУТО', _burped.toStringAsFixed(1), AppColors.magentaHi,
            true),
      ],
    );
  }
}

class _MonsterPainter extends CustomPainter {
  final List<_MPacket> packets;
  final List<_Burp> burps;
  final double belly;
  final bool chomping;
  final bool asleep;
  final double nowMs;

  _MonsterPainter({
    required this.packets,
    required this.burps,
    required this.belly,
    required this.chomping,
    required this.asleep,
    required this.nowMs,
  });

  static const double _w = 320, _h = 120;
  static const Offset _mouth = Offset(74, 64);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _w, size.height / _h);

    final bodyColor = asleep ? AppColors.dim : AppColors.cyan;
    final bellyBulge = 1.0 + min(0.22, belly / 100 * 0.22);
    final mouthOpen = asleep
        ? 3.0
        : chomping
            ? 22.0
            : 9.0;

    // floor line
    canvas.drawLine(const Offset(0, _h - 16), const Offset(_w, _h - 16),
        Paint()..color = AppColors.dim2..strokeWidth = 1);

    // incoming packets
    for (final p in packets) {
      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(-6, -6, 12, 12), const Radius.circular(2)),
          Paint()
            ..style = PaintingStyle.stroke
            ..color = p.color
            ..strokeWidth = 1.6);
      canvas.drawRect(
          const Rect.fromLTWH(-2.5, -2.5, 5, 5), Paint()..color = p.color);
      canvas.restore();
    }

    // burp bubbles rising from the mouth
    for (final b in burps) {
      final t = ((nowMs - b.born) / 1100).clamp(0.0, 1.0);
      final opacity = t < 0.25 ? t / 0.25 : (1 - t);
      _text(canvas, '↑', Offset(_mouth.dx + 6 + 10 * t, _mouth.dy - 14 - 26 * t),
          AppColors.cyanHi.withValues(alpha: opacity.clamp(0.0, 1.0)), 11);
    }

    // gremlin — outer group, then bob/belch
    canvas.save();
    canvas.translate(46, _h - 16);
    if (!asleep) {
      if (chomping) {
        canvas.translate(sin(nowMs / 30) * 2, 0); // belch jitter
      } else {
        canvas.translate(0, sin(nowMs / 1600 * 2 * pi) * 2); // gentle bob
      }
    }

    // glow when fed
    if (!asleep) {
      canvas.drawOval(
          Rect.fromCenter(
              center: const Offset(14, -26), width: 68 * bellyBulge, height: 60),
          Paint()..color = AppColors.cyan.withValues(alpha: 0.10));
    }

    // body (scaled horizontally by bellyBulge around x=14)
    canvas.save();
    canvas.translate(14, -26);
    canvas.scale(bellyBulge, 1);
    canvas.translate(-14, 26);
    final body = Path()
      ..moveTo(-16, 0)
      ..cubicTo(-20, -36, 12, -52, 14, -52)
      ..cubicTo(16, -52, 48, -36, 44, 0)
      ..close();
    canvas.drawPath(body, Paint()..color = bodyColor);
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(14, -12), width: 36, height: 28),
        Paint()..color = AppColors.bgDeep.withValues(alpha: 0.18));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(-8, -4, 12, 8), const Radius.circular(3)),
        Paint()..color = bodyColor);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(24, -4, 12, 8), const Radius.circular(3)),
        Paint()..color = bodyColor);
    canvas.restore();

    // eyes
    if (asleep) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..color = AppColors.bgDeep
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;
      final e1 = Path()
        ..moveTo(2, -40)
        ..quadraticBezierTo(8, -36, 14, -40);
      final e2 = Path()
        ..moveTo(18, -40)
        ..quadraticBezierTo(24, -36, 30, -40);
      canvas.drawPath(e1, arc);
      canvas.drawPath(e2, arc);
      _text(canvas, 'z', const Offset(40, -52), AppColors.dim, 10);
    } else {
      canvas.drawCircle(const Offset(8, -40), 7, Paint()..color = AppColors.white);
      canvas.drawCircle(const Offset(26, -40), 7, Paint()..color = AppColors.white);
      final pd = chomping ? 1.0 : 2.0;
      canvas.drawCircle(
          Offset(8 + pd, -38), 3.2, Paint()..color = AppColors.bgDeep);
      canvas.drawCircle(
          Offset(26 + pd, -38), 3.2, Paint()..color = AppColors.bgDeep);
    }

    // mouth
    canvas.save();
    canvas.translate(17, -26);
    canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 22, height: mouthOpen * 2),
        Paint()..color = AppColors.bgDeep);
    if (!asleep && mouthOpen > 12) {
      final teeth = Path()
        ..moveTo(-9, -6)
        ..lineTo(-6, -2)
        ..lineTo(-3, -6)
        ..lineTo(0, -2)
        ..lineTo(3, -6)
        ..lineTo(6, -2)
        ..lineTo(9, -6);
      canvas.drawPath(
          teeth,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = AppColors.white
            ..strokeWidth = 1.4);
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(0, mouthOpen * 0.45), width: 12, height: 7),
          Paint()..color = AppColors.magenta);
    }
    canvas.restore(); // mouth

    canvas.restore(); // gremlin group

    // belly meter, vertical, right side
    canvas.save();
    canvas.translate(_w - 26, 18);
    _text(canvas, 'BELLY', const Offset(6, -12), AppColors.dim, 7,
        center: true, letterSpacing: 1);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(0, 0, 12, 72), const Radius.circular(3)),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = AppColors.dim2
          ..strokeWidth = 1);
    final fillH = (72 - 4) * (belly / 100);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(2, 2 + (72 - 4) * (1 - belly / 100), 8, fillH),
            const Radius.circular(2)),
        Paint()..color = belly > 75 ? AppColors.magenta : AppColors.cyan);
    canvas.restore();

    canvas.restore();
  }

  void _text(Canvas c, String s, Offset pos, Color color, double size,
      {bool center = false, double letterSpacing = 0}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: size,
          color: color,
          letterSpacing: letterSpacing,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final dx = center ? pos.dx - tp.width / 2 : pos.dx;
    tp.paint(c, Offset(dx, pos.dy));
  }

  @override
  bool shouldRepaint(covariant _MonsterPainter old) => true;
}
