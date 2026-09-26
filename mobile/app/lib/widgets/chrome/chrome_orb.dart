import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/chrome.dart';

/// Visual state of the orb (and of the screens around it).
enum OrbMood { idle, connecting, connected, disconnecting, error }

/// The liquid-chrome orb: a central blob and four satellites merged by a
/// "gooey" metaball effect (blur → alpha threshold), filled with a vertical
/// chrome gradient, a rotating holographic layer, travelling ripples and a
/// soft specular highlight that follows a slow virtual light.
///
/// Port of `ChromeHero` in design/v2/handoff_chrome/y2k/heroes.jsx.
class ChromeOrb extends StatefulWidget {
  final OrbMood mood;
  final double size;
  final bool pressed;

  /// When false the orb is drawn once, at rest, for the current mood.
  final bool animate;

  const ChromeOrb({
    super.key,
    required this.mood,
    this.size = 270,
    this.pressed = false,
    this.animate = true,
  });

  @override
  State<ChromeOrb> createState() => _ChromeOrbState();
}

class _Ripple {
  final double t0, x, y;
  final int k;
  final bool big;
  _Ripple(this.t0, this.x, this.y, this.k, {this.big = false});
}

/// Mutable simulation state, advanced once per frame.
class _OrbSim extends ChangeNotifier {
  double t = 0;
  double spread = 0.3, speed = 0.4, main = 0.28, drip = 0, rot = 0;
  double holo = 0.08, orbit = 0, glow = 0;
  List<Color> pal = _palettes[OrbMood.idle]!;
  final ripples = <_Ripple>[];
  double nextRipple = 0.8;
  final rnd = math.Random();

  void settle(OrbMood mood) {
    final tg = _targets[mood]!;
    spread = tg[0];
    speed = tg[1];
    main = tg[2];
    drip = tg[3];
    holo = _holo[mood]!;
    orbit = mood == OrbMood.connecting ? 1 : 0;
    glow = mood == OrbMood.connected ? 1 : 0;
    pal = _palettes[mood]!;
    ripples.clear();
  }

  void step(double now, OrbMood mood, bool tapped) {
    final dt = (now - t).clamp(0.0, 0.05);
    t = now;
    // The design lerps per frame at 60 fps; scale so the feel is the same
    // at any refresh rate.
    double k(double perFrame) => 1 - math.pow(1 - perFrame, dt * 60).toDouble();

    final tg = _targets[mood]!;
    spread += (tg[0] - spread) * k(0.06);
    speed += (tg[1] - speed) * k(0.05);
    main += (tg[2] - main) * k(0.08);
    drip += (tg[3] - drip) * k(0.05);
    holo += (_holo[mood]! - holo) * k(0.05);
    orbit += ((mood == OrbMood.connecting ? 1 : 0) - orbit) * k(0.08);
    glow += ((mood == OrbMood.connected ? 1 : 0) - glow) * k(0.06);
    final tp = _palettes[mood]!;
    pal = [for (var i = 0; i < 5; i++) Color.lerp(pal[i], tp[i], k(0.06))!];
    rot += dt * speed;

    final period = _ripplePeriod[mood]!;
    if (period > 0 && t > nextRipple) {
      ripples.add(_Ripple(t, (rnd.nextDouble() - 0.5) * 0.25, (rnd.nextDouble() - 0.5) * 0.25,
          5 + rnd.nextInt(4)));
      nextRipple = t + period * (0.7 + rnd.nextDouble() * 0.6);
    } else if (period == 0) {
      nextRipple = t + 0.8;
    }
    if (tapped) ripples.add(_Ripple(t, 0, 0, 8, big: true));
    ripples.removeWhere((r) => t - r.t0 >= 1.8);
    notifyListeners();
  }

  static const _targets = {
    OrbMood.idle: [0.30, 0.5, 0.27, 0.0],
    OrbMood.connecting: [0.42, 3.2, 0.24, 0.0],
    OrbMood.connected: [0.02, 0.6, 0.33, 0.0],
    OrbMood.disconnecting: [0.38, 1.6, 0.26, 0.0],
    OrbMood.error: [0.20, 0.15, 0.25, 1.0],
  };

  static const _holo = {
    OrbMood.idle: 0.08,
    OrbMood.connecting: 0.35,
    OrbMood.connected: 0.55,
    OrbMood.disconnecting: 0.15,
    OrbMood.error: 0.08,
  };

  static const _ripplePeriod = {
    OrbMood.idle: 3.8,
    OrbMood.connecting: 1.1,
    OrbMood.connected: 2.6,
    OrbMood.disconnecting: 1.6,
    OrbMood.error: 0.0,
  };

  static const _palettes = {
    OrbMood.idle: [Color(0xFFFFFFFF), Color(0xFFD6DAE6), Color(0xFF474B61), Color(0xFF9AA0B8), Color(0xFFF4F5FB)],
    OrbMood.connecting: [Color(0xFFFFFFFF), Color(0xFFCFE9FF), Color(0xFF3B3F66), Color(0xFFB7A9FF), Color(0xFFFFF4FB)],
    OrbMood.connected: [Color(0xFFFFFFFF), Color(0xFFB8F4FF), Color(0xFF5E4BFF), Color(0xFFFF9EE6), Color(0xFFFFF6C9)],
    OrbMood.disconnecting: [Color(0xFFFFFFFF), Color(0xFFDCDDE8), Color(0xFF45485E), Color(0xFFA7A2C9), Color(0xFFF5F4FB)],
    OrbMood.error: [Color(0xFFF4ECEC), Color(0xFFC7B0B0), Color(0xFF5A3B3B), Color(0xFFB99494), Color(0xFFF1E6E6)],
  };
}

class _ChromeOrbState extends State<ChromeOrb> with SingleTickerProviderStateMixin {
  final _sim = _OrbSim();
  Ticker? _ticker;
  bool _wasPressed = false;
  // Tickers start at zero; offset so the idle wobble does not always begin
  // from the same pose. A static orb always shows the same one.
  late final double _t0 = widget.animate ? math.Random().nextDouble() * 100 : 0;

  @override
  void initState() {
    super.initState();
    _sim.settle(widget.mood);
    _sim.t = _t0;
    _sync();
  }

  @override
  void didUpdateWidget(ChromeOrb old) {
    super.didUpdateWidget(old);
    if (!widget.animate) _sim.settle(widget.mood);
    _sync();
  }

  void _sync() {
    if (widget.animate) {
      _ticker ??= createTicker((elapsed) {
        final tapped = widget.pressed && !_wasPressed;
        _wasPressed = widget.pressed;
        _sim.step(_t0 + elapsed.inMicroseconds / 1e6, widget.mood, tapped);
      });
      if (!_ticker!.isActive) _ticker!.start();
    } else {
      _ticker?.stop();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _sim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _OrbPainter(_sim, widget.mood, Chrome.of(context)),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final _OrbSim s;
  final OrbMood mood;
  final Chrome c;

  _OrbPainter(this.s, this.mood, this.c) : super(repaint: s);

  // alpha' = 24·alpha − 10: turns the blurred blobs into one crisp shape.
  static const _threshold = ColorFilter.matrix([
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 24, -10 * 255,
  ]);

  @override
  void paint(Canvas canvas, Size size) {
    final S = size.width, C = S / 2, t = s.t;

    // Ripple envelope drives the edge wobble and the highlight flare.
    var env = 0.0;
    for (final r in s.ripples) {
      env += math.exp(-(t - r.t0) * 2.6) * (r.big ? 1.4 : 1);
    }
    env = math.min(env, 1.6);

    // Pulsing glow behind a connected orb.
    if (s.glow > 0.01) {
      final gr = S * 0.55 * (1 + 0.04 * math.sin(t * 2));
      canvas.drawCircle(
        Offset(C, C),
        gr,
        Paint()
          ..shader = ui.Gradient.radial(Offset(C, C), gr, [
            c.accent.withValues(alpha: 0.55 * s.glow),
            c.accent.withValues(alpha: 0),
          ]),
      );
    }

    // Dashed orbit while connecting.
    if (s.orbit > 0.01) {
      canvas.save();
      canvas.translate(C, C);
      canvas.rotate(t * 120 * math.pi / 180);
      final orbit = Path()..addOval(Rect.fromCenter(center: Offset.zero, width: S * 0.96, height: S * 0.32));
      final dash = Path();
      for (final m in orbit.computeMetrics()) {
        for (var d = 0.0; d < m.length; d += 12) {
          dash.addPath(m.extractPath(d, d + 4), Offset.zero);
        }
      }
      canvas.drawPath(
        dash,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..color = c.accent.withValues(alpha: 0.7 * s.orbit),
      );
      canvas.restore();
    }

    // Geometry.
    final main = Offset(C, C + s.drip * S * 0.06 + math.sin(t * 1.2) * 3);
    final mainR = S * s.main * (1 + 0.02 * math.sin(t * 2.3));
    const n = 72;
    final mainPath = Path();
    for (var i = 0; i < n; i++) {
      final th = i / n * math.pi * 2;
      var k = 1 + 0.012 * math.sin(3 * th + t * 1.5);
      for (final r in s.ripples) {
        final a = t - r.t0;
        k += 0.075 * math.exp(-a * 2.6) * (r.big ? 1.4 : 1) * math.sin(r.k * th - a * 14);
      }
      final p = Offset(main.dx + math.cos(th) * mainR * k, main.dy + math.sin(th) * mainR * k);
      i == 0 ? mainPath.moveTo(p.dx, p.dy) : mainPath.lineTo(p.dx, p.dy);
    }
    mainPath.close();

    final bounds = Rect.fromLTWH(-S * 0.3, -S * 0.3, S * 1.6, S * 1.6);
    canvas.saveLayer(bounds, Paint()..colorFilter = _threshold);
    final blob = Paint()
      ..color = Colors.white
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, S * 0.035);
    canvas.drawPath(mainPath, blob);
    for (var i = 0; i < 4; i++) {
      final a = s.rot + i * math.pi / 2 + math.sin(t * 0.9 + i) * 0.3;
      final d = S * (s.spread + 0.04 * math.sin(t * 1.7 + i * 2));
      final dripY = s.drip * (S * 0.2 + i * S * 0.06);
      final p = Offset(
        C + math.cos(a) * d * (1 - s.drip * 0.6),
        C + math.sin(a) * d * 0.9 * (1 - s.drip) + dripY,
      );
      canvas.drawCircle(p, S * (0.12 + 0.03 * (i.isOdd ? 1 : 0.4)), blob);
    }

    // Everything below is clipped to the merged shape.
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.srcIn);
    final fill = Rect.fromLTWH(-S * 0.2, -S * 0.2, S * 1.4, S * 1.4);

    canvas.drawRect(
      fill,
      Paint()
        ..shader = ui.Gradient.linear(
          _rot(Offset(C, fill.top), Offset(C, C), math.sin(t * 0.7) * 12),
          _rot(Offset(C, fill.bottom), Offset(C, C), math.sin(t * 0.7) * 12),
          s.pal,
          const [0, 0.42, 0.5, 0.6, 1],
        ),
    );

    final holoA = math.min(0.8, s.holo + env * 0.25);
    canvas.drawRect(
      fill,
      Paint()
        ..blendMode = BlendMode.color
        ..shader = ui.Gradient.linear(
          _rot(fill.topLeft, Offset(C, C), t * 50),
          _rot(fill.bottomRight, Offset(C, C), t * 50),
          [
            for (final h in const [0xFFFF6BD6, 0xFF6BF0FF, 0xFFD4FF6B, 0xFFFF6BD6])
              Color(h).withValues(alpha: holoA),
          ],
          const [0, 0.33, 0.66, 1],
        ),
    );

    // Ripple rings.
    for (final r in s.ripples) {
      final a = t - r.t0, fade = math.max(0.0, 1 - a / 1.8);
      final center = Offset(C + r.x * S, C + r.y * S);
      for (var k = 0; k < 3; k++) {
        final rr = (a * (r.big ? 1.15 : 0.95) - k * 0.13) * S * 0.5;
        if (rr <= 2) continue;
        canvas.drawCircle(
          center,
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.2 - k * 0.8
            ..color = Colors.white.withValues(alpha: 0.7 * fade),
        );
        canvas.drawCircle(
          center,
          math.max(1, rr - 5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6 - k * 0.3
            ..color = (c.dark ? const Color(0xFF1A1B3A) : const Color(0xFF3B3F66))
                .withValues(alpha: 0.35 * fade),
        );
      }
    }

    // Soft specular following a slow virtual light, plus a faint reflex
    // on the opposite side.
    final la = -2.2 + math.sin(t * 0.35) * 0.9 + s.rot * 0.15;
    final ang = la + math.pi / 2;
    final w = mainR * (0.5 + 0.08 * math.sin(t * 0.9)) * (1 + env * 0.25);
    final h = mainR * (0.2 + 0.04 * math.cos(t * 1.3));
    final op = (mood == OrbMood.error ? 0.3 : 0.65) + env * 0.25;
    _specular(canvas, main + Offset(math.cos(la), math.sin(la)) * mainR * 0.48, w, h, ang, op);
    _specular(canvas, main + Offset(math.cos(la + math.pi), math.sin(la + math.pi)) * mainR * 0.7,
        mainR * 0.55, mainR * 0.12, ang, 0.18 + env * 0.15);

    canvas.restore();
    canvas.restore();
  }

  void _specular(Canvas canvas, Offset at, double w, double h, double angle, double opacity) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle);
    canvas.scale(1, h / w);
    canvas.drawCircle(
      Offset.zero,
      w,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = ui.Gradient.radial(Offset.zero, w, [
          Colors.white.withValues(alpha: opacity.clamp(0.0, 1.0)),
          Colors.white.withValues(alpha: 0.75 * opacity.clamp(0.0, 1.0)),
          Colors.white.withValues(alpha: 0),
        ], const [0, 0.5, 1]),
    );
    canvas.restore();
  }

  static Offset _rot(Offset p, Offset around, double degrees) {
    final a = degrees * math.pi / 180;
    final d = p - around;
    return around + Offset(d.dx * math.cos(a) - d.dy * math.sin(a), d.dx * math.sin(a) + d.dy * math.cos(a));
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.mood != mood || old.c != c;
}
