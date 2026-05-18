import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum FooterMapState { idle, connecting, connected, disconnecting }

class _Hop {
  final String code;
  final int x, y;
  final bool real, exit;
  const _Hop(this.code, this.x, this.y, {this.real = false, this.exit = false});
}

class FooterMap extends StatefulWidget {
  final FooterMapState state;
  final int secs;

  const FooterMap({super.key, required this.state, required this.secs});

  @override
  State<FooterMap> createState() => _FooterMapState();
}

class _FooterMapState extends State<FooterMap>
    with SingleTickerProviderStateMixin {
  static const _hops = [
    _Hop('YOU', 8, 4, real: true),
    _Hop('AMS', 26, 2),
    _Hop('STO', 36, 5),
    _Hop('OSL', 44, 3),
    _Hop('REY', 52, 4, exit: true),
  ];
  static const _w = 60;
  static const _h = 7;

  static const _land = [
    '       ___        ___       __     __',
    r'      /   \__   _/   \__  _/  \___/  \__',
    r'     /        \_/        \/            \',
    r'    /                                   \',
  ];

  int _pulse = 0;
  Timer? _pulseTimer;
  late final AnimationController _cursorCtl;

  @override
  void initState() {
    super.initState();
    _cursorCtl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _resetPulseTimer();
  }

  @override
  void didUpdateWidget(FooterMap old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) {
      _pulse = 0;
      _resetPulseTimer();
    }
  }

  void _resetPulseTimer() {
    _pulseTimer?.cancel();
    _pulseTimer = null;
    final st = widget.state;
    if (st == FooterMapState.idle || st == FooterMapState.disconnecting) return;
    final ms = st == FooterMapState.connecting ? 220 : 700;
    _pulseTimer = Timer.periodic(Duration(milliseconds: ms), (_) {
      if (mounted) setState(() => _pulse++);
    });
  }

  int _activeHop() => switch (widget.state) {
        FooterMapState.idle || FooterMapState.disconnecting => 0,
        FooterMapState.connecting =>
          min(_hops.length - 1, _pulse % (_hops.length + 1)),
        FooterMapState.connected => _pulse % _hops.length,
      };

  @override
  void dispose() {
    _pulseTimer?.cancel();
    _cursorCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ah = _activeHop();
    final isConn = widget.state == FooterMapState.connected;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
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
                _headerRow(isConn),
                const SizedBox(height: 8),
                _mapBlock(ah),
                const SizedBox(height: 8),
                _cityLabels(ah),
                const SizedBox(height: 10),
                SizedBox(
                  height: 1,
                  width: double.infinity,
                  child: CustomPaint(painter: _DashedPainter()),
                ),
                const SizedBox(height: 10),
                _statusRow(isConn),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerRow(bool isConn) {
    final label = switch (widget.state) {
      FooterMapState.idle || FooterMapState.disconnecting => '// ROUTE/DIRECT',
      FooterMapState.connecting => '// ROUTE/BUILDING…',
      FooterMapState.connected => '// ROUTE/OBFUSCATED',
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 9,
            color: AppColors.dim,
            letterSpacing: 2,
          ),
        ),
        Text(
          isConn ? '▲ HOPS: ${_hops.length - 1}' : '▲ HOPS: 0',
          style: TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 9,
            color: isConn ? AppColors.cyan : AppColors.dim,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  Widget _mapBlock(int ah) {
    final st = widget.state;
    final chars = List.generate(_h, (_) => List.filled(_w, ' '));
    final colors =
        List.generate(_h, (_) => List<Color>.filled(_w, AppColors.dim));
    final weights =
        List.generate(_h, (_) => List.filled(_w, FontWeight.w400));

    // Stipple background — cyan when connected, dim otherwise
    final stippleColor =
        st == FooterMapState.connected ? AppColors.cyan : AppColors.dim;
    for (var y = 0; y < _h; y++) {
      for (var x = 0; x < _w; x++) {
        if ((x * 7 + y * 13) % 11 == 0) {
          chars[y][x] = '·';
          colors[y][x] = stippleColor;
        }
      }
    }

    // Land outlines
    for (var i = 0; i < _land.length && i < _h; i++) {
      for (var x = 0; x < _land[i].length && x < _w; x++) {
        if (_land[i][x] != ' ') {
          chars[i][x] = _land[i][x];
          colors[i][x] = AppColors.dim2;
        }
      }
    }

    // Trail between hops
    if (st != FooterMapState.idle && st != FooterMapState.disconnecting) {
      final trailColor =
          st == FooterMapState.connected ? AppColors.cyan : AppColors.dim;
      for (var i = 0; i < _hops.length - 1; i++) {
        if (st == FooterMapState.connecting && i >= ah) break;
        final a = _hops[i], b = _hops[i + 1];
        final steps = (b.x - a.x).abs();
        for (var s = 1; s < steps; s++) {
          final x = a.x + s;
          final y = (a.y + (b.y - a.y) * s / steps).round();
          if (y >= 0 && y < _h && x >= 0 && x < _w) {
            chars[y][x] = s.isEven ? '─' : '·';
            colors[y][x] = trailColor;
          }
        }
      }
    }

    // Stamp hops on top
    for (var i = 0; i < _hops.length; i++) {
      final h = _hops[i];
      if (h.y >= _h || h.x >= _w) continue;
      final isActive = st == FooterMapState.connected && i == ah;
      final reached =
          (st == FooterMapState.idle || st == FooterMapState.disconnecting)
              ? i == 0
              : i <= ah;

      if (h.real) {
        chars[h.y][h.x] = '◉';
        colors[h.y][h.x] = AppColors.magenta;
        weights[h.y][h.x] = FontWeight.w700;
      } else if (h.exit) {
        chars[h.y][h.x] = '◆';
        colors[h.y][h.x] =
            st == FooterMapState.connected ? AppColors.cyan : AppColors.dim;
        weights[h.y][h.x] = FontWeight.w700;
      } else if (isActive) {
        chars[h.y][h.x] = '●';
        colors[h.y][h.x] = AppColors.white;
      } else if (reached) {
        chars[h.y][h.x] = '○';
        colors[h.y][h.x] = AppColors.cyanHi;
      } else {
        chars[h.y][h.x] = '·';
        colors[h.y][h.x] = AppColors.dim;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.dim2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: FittedBox(
        fit: BoxFit.fitWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(_h, (y) {
            return RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 10,
                  height: 1.15,
                ),
                children: List.generate(_w, (x) {
                  return TextSpan(
                    text: chars[y][x],
                    style: TextStyle(
                      color: colors[y][x],
                      fontWeight: weights[y][x],
                    ),
                  );
                }),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _cityLabels(int ah) {
    final st = widget.state;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(_hops.length, (i) {
        final h = _hops[i];
        Color color;
        var weight = FontWeight.w400;

        if (h.real) {
          color = AppColors.magenta;
          weight = FontWeight.w700;
        } else if (h.exit) {
          color = st == FooterMapState.connected ? AppColors.cyan : AppColors.dim;
          weight = FontWeight.w700;
        } else if (st == FooterMapState.connected) {
          color = AppColors.cyan;
        } else if (st == FooterMapState.connecting && i <= ah) {
          color = AppColors.cyanHi;
        } else {
          color = AppColors.dim;
        }

        return Text(
          h.code,
          style: TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 9,
            letterSpacing: 1.5,
            color: color,
            fontWeight: weight,
          ),
        );
      }),
    );
  }

  Widget _statusRow(bool isConn) {
    final timeText = isConn ? _fmtTime(widget.secs) : '00:00:00';
    final timeColor = isConn ? AppColors.cyan : AppColors.dim;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          isConn ? 'EXIT → REY \u{1f1ee}\u{1f1f8}' : 'EXIT → —',
          style: const TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 10,
            color: AppColors.dim,
            letterSpacing: 1,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              timeText,
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 10,
                color: timeColor,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            AnimatedBuilder(
              animation: _cursorCtl,
              builder: (_, __) => Opacity(
                opacity: _cursorCtl.value < 0.5 ? 1.0 : 0.0,
                child: Text(
                  '▎',
                  style: TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 10,
                    color: timeColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _fmtTime(int s) {
    final h = (s ~/ 3600).toString().padLeft(2, '0');
    final m = ((s ~/ 60) % 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$h:$m:$sec';
  }
}

class _DashedPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.dim2
      ..strokeWidth = 1;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(min(x + 4, size.width), 0), paint);
      x += 7;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
