import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../theme/app_theme.dart';
import 'footer_common.dart';

/// Tug of War footer (default / hero) — YOU (magenta scrapper) vs THE WATCHER
/// (a surveillance eyeball on legs) hauling a rope across the firewall. Your
/// traffic is ground you reel in. A [_pos] value runs −1 (you fully win) … +1
/// (watcher wins), eased toward a target each frame; data packets travelling
/// down the rope nudge it negative and bump REELED IN MB.
class FooterTugWar extends StatefulWidget {
  final FooterConnState state;
  final int secs;

  const FooterTugWar({super.key, required this.state, required this.secs});

  @override
  State<FooterTugWar> createState() => _FooterTugWarState();
}

class _Packet {
  double u = 0;
  final double size;
  final Color color;
  _Packet(this.size, this.color);
}

class _FooterTugWarState extends State<FooterTugWar>
    with SingleTickerProviderStateMixin {
  // Arena aspect ratio (320×132 design viewBox); full geometry is in _TugPainter.
  static const double _w = 320, _h = 132;

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  final _rng = Random();

  double _pos = 0.55; // -1 you win .. +1 watcher wins
  double _pull = 0.15;
  double _ground = 0; // MB reeled in
  final List<_Packet> _packets = [];
  double _spawnAcc = 0;
  double _nextGap = 420;
  double _sinceYank = 9999;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(FooterTugWar old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state && widget.state == FooterConnState.idle) {
      _pos = 0.55;
      _packets.clear();
      _ground = 0;
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
    if (dt <= 0) return;
    final st = widget.state;

    final target = st == FooterConnState.idle
        ? 0.55
        : st == FooterConnState.connecting
            ? 0.0
            : -0.92;
    final ease = st == FooterConnState.connected ? 0.010 : 0.05;
    _pos += (target - _pos) * ease * (dt / 16);

    if (st == FooterConnState.connecting || st == FooterConnState.connected) {
      _spawnAcc += dt;
      if (_spawnAcc >= _nextGap) {
        _spawnAcc = 0;
        final base = st == FooterConnState.connecting ? 420.0 : 560.0;
        _nextGap = base + _rng.nextDouble() * 280;
        _packets.add(_Packet(
          0.4 + _rng.nextDouble() * 2.4,
          _rng.nextBool() ? AppColors.cyan : AppColors.magenta,
        ));
      }
    }

    double arrived = 0;
    _packets.removeWhere((p) {
      p.u += (0.0011 + p.size * 0.0002) * dt;
      if (p.u >= 1) {
        arrived += p.size;
        return true;
      }
      return false;
    });
    if (arrived > 0) {
      _ground += arrived;
      _pos = (_pos - arrived * 0.04).clamp(-1.0, 1.0);
      _sinceYank = 0;
    } else {
      _sinceYank += dt;
    }

    _pull = st == FooterConnState.connecting
        ? 0.85
        : _sinceYank < 220
            ? 1.0
            : st == FooterConnState.connected
                ? 0.45
                : 0.12;

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    final youWin = _pos < 0;
    final youPct = ((1 - _pos) / 2 * 100).round();
    final defeated = _pos <= -0.86;

    final status = st == FooterConnState.idle
        ? 'OUTGUNNED'
        : st == FooterConnState.connecting
            ? 'TAKING THE STRAIN…'
            : defeated
                ? 'FLAWLESS'
                : 'WINNING';
    final statusColor = st == FooterConnState.idle
        ? AppColors.red
        : st == FooterConnState.connecting
            ? AppColors.yellow
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
            // header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('// КАНАТ · ТЫ vs ОНИ',
                    style: TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 9,
                        color: AppColors.dim,
                        letterSpacing: 2)),
                Text(status,
                    style: TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 9,
                        color: statusColor,
                        letterSpacing: 2)),
              ],
            ),
            const SizedBox(height: 8),
            // arena
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
                      painter: _TugPainter(
                        pos: _pos,
                        pull: _pull,
                        packets: _packets,
                        defeated: defeated,
                        youWin: youWin,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _statStrip(st, youWin, youPct),
          ],
        ),
      ),
    );
  }

  Widget _statStrip(FooterConnState st, bool youWin, int youPct) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('↙ НАМОТАНО',
                style: TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 9,
                    color: AppColors.dim,
                    letterSpacing: 1.5)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(_ground.toStringAsFixed(1),
                    style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.cyan,
                        height: 1,
                        fontFeatures: [FontFeature.tabularFigures()])),
                const SizedBox(width: 3),
                const Text('MB',
                    style: TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 10,
                        color: AppColors.dim)),
              ],
            ),
          ],
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('ТЫ',
                        style: TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 8,
                            color: AppColors.magenta,
                            letterSpacing: 1)),
                    Text('ОНИ',
                        style: TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 8,
                            color: AppColors.dim,
                            letterSpacing: 1)),
                  ],
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: youPct / 100,
                    minHeight: 6,
                    backgroundColor: AppColors.dim2,
                    valueColor:
                        const AlwaysStoppedAnimation(AppColors.magenta),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  st == FooterConnState.connected
                      ? '${fmtFooterTime(widget.secs)} HELD'
                      : st == FooterConnState.connecting
                          ? 'bracing…'
                          : 'rope slipping',
                  style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 8,
                      color: AppColors.dim,
                      letterSpacing: 1),
                ),
              ],
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text('ПЕРЕВЕС',
                style: TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 9,
                    color: AppColors.dim,
                    letterSpacing: 1.5)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('$youPct',
                    style: TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        color: youWin ? AppColors.magentaHi : AppColors.dim,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: 2),
                const Text('%',
                    style: TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 10,
                        color: AppColors.dim)),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _TugPainter extends CustomPainter {
  final double pos;
  final double pull;
  final List<_Packet> packets;
  final bool defeated;
  final bool youWin;

  _TugPainter({
    required this.pos,
    required this.pull,
    required this.packets,
    required this.defeated,
    required this.youWin,
  });

  static const double _w = 320, _h = 132;
  static const double _fire = 160, _ropeY = 64, _floor = 104;
  static const Offset _youHand = Offset(70, 64);
  static const Offset _themHand = Offset(250, 64);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _w, size.height / _h);

    final markerX = _fire + pos * 78;

    // floor
    _line(canvas, const Offset(0, _floor), const Offset(_w, _floor),
        AppColors.dim2, 1);

    // firewall dashed vertical line
    _dashedLine(canvas, Offset(_fire, 20), const Offset(_fire, _floor),
        youWin ? AppColors.cyan : AppColors.dim, 1, 3, 4, 0.7);
    _text(canvas, 'FIREWALL', Offset(_fire, 12),
        youWin ? AppColors.cyan : AppColors.dim, 7,
        center: true, letterSpacing: 2);

    // rope: two quadratic segments through the marker
    final rope = Path()..moveTo(_youHand.dx, _youHand.dy);
    rope.quadraticBezierTo((_youHand.dx + markerX) / 2, _ropeY + 7, markerX,
        _ropeY.toDouble());
    rope.quadraticBezierTo((markerX + _themHand.dx) / 2, _ropeY + 7,
        _themHand.dx, _themHand.dy);
    canvas.drawPath(
        rope,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = AppColors.dim
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round);

    // packets reeling along the rope
    for (final p in packets) {
      final x = _themHand.dx + (_youHand.dx - _themHand.dx) * p.u;
      final y = _ropeY + 7 * sin(pi * (1 - (0.5 - p.u).abs() * 2)) - 3;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(((p.u * 180) % 90) * pi / 180);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(-4, -4, 8, 8), const Radius.circular(1.5)),
          Paint()
            ..style = PaintingStyle.stroke
            ..color = p.color
            ..strokeWidth = 1.5);
      canvas.restore();
    }

    // center knot + pennant (leader's colour)
    canvas.save();
    canvas.translate(markerX, _ropeY.toDouble());
    final pennant = Path()
      ..moveTo(1, -3)
      ..lineTo(youWin ? 16 : -16, -10)
      ..lineTo(1, -17)
      ..close();
    canvas.drawPath(pennant,
        Paint()..color = youWin ? AppColors.magenta : AppColors.cyan);
    canvas.save();
    canvas.rotate(45 * pi / 180);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(-3.5, -3.5, 7, 7), const Radius.circular(1.5)),
        Paint()..color = AppColors.white);
    canvas.restore();
    canvas.restore();

    _drawYou(canvas);
    _drawWatcher(canvas);

    canvas.restore();
  }

  void _drawYou(Canvas canvas) {
    final youLean = (youWin ? 9 : 3) + pull * 7;
    final youSlide = max(0.0, pos) * 10;
    final yX = 50 + youSlide;
    final hip = Offset(yX, 86);
    final sh = Offset(yX - youLean, 64);
    final head = Offset(yX - youLean * 1.25, 53);
    final mg = Paint()
      ..color = AppColors.magenta
      ..strokeCap = StrokeCap.round;

    _line(canvas, hip, Offset(yX - 16, _floor), AppColors.magenta, 5);
    _line(canvas, hip, Offset(yX + 8, _floor), AppColors.magenta, 5);
    _line(canvas, hip, sh, AppColors.magenta, 7);
    _line(canvas, sh, _youHand, AppColors.magenta, 5);
    canvas.drawCircle(head, 9, mg);
    canvas.drawCircle(Offset(head.dx - 3, head.dy - 2), 2,
        Paint()..color = AppColors.bgDeep.withValues(alpha: 0.5));
    if (pull > 0.6) {
      _text(canvas, '!', Offset(head.dx - 14, head.dy - 16),
          AppColors.magentaHi, 9);
    }
  }

  void _drawWatcher(Canvas canvas) {
    final themSlide = max(0.0, -pos) * 22;
    final tX = 270 - themSlide;
    final themLean = defeated ? -10.0 : (pos > 0 ? 8 : 3) + pull * 6;
    final irisDX = -4 - pull * 2;

    canvas.save();
    canvas.translate(tX, _floor);
    canvas.rotate(themLean * pi / 180);
    canvas.translate(-tX, -_floor);

    final dim = AppColors.dim;
    // legs
    _line(canvas, Offset(tX - 6, 84),
        Offset(defeated ? tX - 16 : tX - 7, _floor), dim, 5);
    _line(canvas, Offset(tX + 6, 84),
        Offset(defeated ? tX + 16 : tX + 7, _floor), dim, 5);
    // arms gripping rope
    _line(canvas, Offset(tX - 10, 72), _themHand, dim, 5);
    _line(canvas, Offset(tX + 4, 74),
        Offset(_themHand.dx + 4, _themHand.dy + 5), dim, 4);
    // eyeball body
    canvas.drawCircle(Offset(tX, 68), 16, Paint()..color = AppColors.white);
    canvas.drawCircle(
        Offset(tX, 68),
        16,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = AppColors.dim2
          ..strokeWidth = 1.5);
    if (defeated) {
      _line(canvas, Offset(tX - 6, 62), Offset(tX + 6, 74), AppColors.red, 2.4);
      _line(canvas, Offset(tX + 6, 62), Offset(tX - 6, 74), AppColors.red, 2.4);
    } else {
      canvas.drawCircle(
          Offset(tX + irisDX, 68), 7, Paint()..color = AppColors.cyan);
      canvas.drawCircle(
          Offset(tX + irisDX, 68), 3, Paint()..color = AppColors.bgDeep);
      if (pos < 0) {
        final sweat = Path()
          ..moveTo(tX + 13, 60)
          ..quadraticBezierTo(tX + 16, 65, tX + 13, 68)
          ..quadraticBezierTo(tX + 10, 65, tX + 13, 60);
        canvas.drawPath(sweat,
            Paint()..color = AppColors.cyan.withValues(alpha: 0.8));
      }
    }
    canvas.restore();
  }

  // ── canvas helpers ─────────────────────────────────────────────────
  void _line(Canvas c, Offset a, Offset b, Color color, double w) {
    c.drawLine(
        a,
        b,
        Paint()
          ..color = color
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round);
  }

  void _dashedLine(Canvas c, Offset a, Offset b, Color color, double w,
      double dash, double gap, double opacity) {
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..strokeWidth = w;
    final total = (b - a).distance;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final s = a + dir * d;
      final e = a + dir * min(d + dash, total);
      c.drawLine(s, e, paint);
      d += dash + gap;
    }
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
  bool shouldRepaint(covariant _TugPainter old) => true;
}
