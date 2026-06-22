import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'footer_common.dart';

/// Ghost Pet footer — a pixel mascot ("GHOST") that stands in for your
/// anonymity. Mood goes exposed → hopeful → safe → gleeful; ANONYMITY and
/// VIBES bars fill while connected; hearts when safe, sleepy z when idle.
class FooterPet extends StatefulWidget {
  final FooterConnState state;
  final int secs;

  const FooterPet({super.key, required this.state, required this.secs});

  @override
  State<FooterPet> createState() => _FooterPetState();
}

enum _Mood { exposed, worried, hopeful, safe, gleeful }

class _FooterPetState extends State<FooterPet>
    with SingleTickerProviderStateMixin {
  // 12×10 sprite sheets. '.' empty, '1' body(moodColor), '2'/'3' ink(bgDeep).
  static const _sheets = <_Mood, List<String>>{
    _Mood.exposed: [
      '............',
      '...111111...',
      '..11111111..',
      '.1112112111.',
      '.1112112111.',
      '.111111111..',
      '.11111111...',
      '.111133111..',
      '.1133113311.',
      '..1.1..1.1..',
    ],
    _Mood.worried: [
      '............',
      '...111111...',
      '..11111111..',
      '.1112112111.',
      '.1112112111.',
      '.1111111111.',
      '.1111111111.',
      '.111133111..',
      '.1111111111.',
      '..1.11.1.1..',
    ],
    _Mood.hopeful: [
      '............',
      '...111111...',
      '..11111111..',
      '.1112112111.',
      '.1112112111.',
      '.1111111111.',
      '.1111111111.',
      '.1113113111.',
      '.1111111111.',
      '..11..11..11',
    ],
    _Mood.safe: [
      '............',
      '...111111...',
      '..11111111..',
      '.1111121111.',
      '.1112221111.',
      '.1111111111.',
      '.1111111111.',
      '.1133333111.',
      '.1111111111.',
      '..11..11....',
    ],
    _Mood.gleeful: [
      '...11..11...',
      '..1111111...',
      '.111111111..',
      '.1112112111.',
      '.1112112111.',
      '.1111111111.',
      '.1111111111.',
      '.1133333111.',
      '.1111111111.',
      '..11..11....',
    ],
  };

  static const _px = 7.0;

  int _health = 20;
  _Mood _mood = _Mood.exposed;
  Timer? _healthTimer;
  late final AnimationController _ctl; // bob / shake / zzz / heartbeat driver

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _startHealthTimer();
    _recomputeMood();
  }

  void _startHealthTimer() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      setState(() {
        switch (widget.state) {
          case FooterConnState.connected:
            _health = min(100, _health + 4);
          case FooterConnState.connecting:
            _health = min(100, _health + 8);
          case FooterConnState.idle:
            _health = max(0, _health - 2);
          case FooterConnState.disconnecting:
            break;
        }
        _recomputeMood();
      });
    });
  }

  void _recomputeMood() {
    _mood = switch (widget.state) {
      FooterConnState.idle => _Mood.exposed,
      FooterConnState.connecting => _Mood.hopeful,
      FooterConnState.connected =>
        _health > 80 ? _Mood.gleeful : _Mood.safe,
      FooterConnState.disconnecting => _Mood.worried,
    };
  }

  @override
  void didUpdateWidget(FooterPet old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) setState(_recomputeMood);
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  Color get _moodColor => switch (_mood) {
        _Mood.exposed => AppColors.red,
        _Mood.worried => AppColors.yellow,
        _Mood.hopeful => AppColors.cyan,
        _Mood.safe => AppColors.cyan,
        _Mood.gleeful => AppColors.green,
      };

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    final connected = st == FooterConnState.connected;

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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _enclosure(st, connected),
                const SizedBox(width: 14),
                Expanded(child: _stats(st, connected)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _enclosure(FooterConnState st, bool connected) {
    return SizedBox(
      width: 108,
      height: 108,
      child: AnimatedBuilder(
        animation: _ctl,
        builder: (context, _) {
          final t = _ctl.value;
          // bob / shake offset
          Offset off = Offset.zero;
          if (st == FooterConnState.connecting) {
            off = Offset(sin(t * pi * 8).sign * 1.0, 0); // jitter
          } else if (connected) {
            off = Offset(0, sin(t * 2 * pi) * 2); // gentle bob
          }
          return Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, 0.4),
                radius: 0.9,
                colors: [
                  (connected ? AppColors.cyan : AppColors.red)
                      .withValues(alpha: 0.13),
                  AppColors.bgDeep,
                ],
              ),
              border: Border.all(color: AppColors.dim2),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // horizon line
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 14,
                  child: Container(height: 1, color: AppColors.dim2),
                ),
                // zzz when idle
                if (st == FooterConnState.idle)
                  Positioned(
                    top: 8 - 8 * t,
                    right: 10 + 6 * t,
                    child: Opacity(
                      opacity: (sin(t * pi)).clamp(0.0, 1.0),
                      child: const Text('z',
                          style: TextStyle(
                              fontFamily: AppFonts.mono,
                              fontSize: 10,
                              color: AppColors.dim)),
                    ),
                  ),
                // heart when connected
                if (connected)
                  Positioned(
                    top: 8,
                    right: 10,
                    child: Transform.scale(
                      scale: 1 + 0.2 * sin(t * 2 * pi),
                      child: const Text('♥',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.magenta)),
                    ),
                  ),
                // pixel pet
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 10,
                  child: Center(
                    child: Transform.translate(
                      offset: off,
                      child: CustomPaint(
                        size: const Size(12 * _px, 10 * _px),
                        painter: _PetPainter(_sheets[_mood]!, _moodColor),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _stats(FooterConnState st, bool connected) {
    final vibes = switch (st) {
      FooterConnState.connected => min(100, 60 + widget.secs),
      FooterConnState.connecting => 50,
      _ => 15,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Text('GHOST',
                style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 14,
                    color: AppColors.white,
                    letterSpacing: 1)),
            Text(_moodName.toUpperCase(),
                style: TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 9,
                    letterSpacing: 2,
                    color: _moodColor)),
          ],
        ),
        const SizedBox(height: 8),
        _StatBar(label: 'АНОНИМНОСТЬ', value: _health.toDouble(), color: _moodColor),
        const SizedBox(height: 8),
        _StatBar(
            label: 'НАСТРОЙ',
            value: vibes.toDouble(),
            color: connected ? AppColors.cyan : AppColors.dim),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('ВОЗРАСТ ${connected ? fmtFooterTime(widget.secs) : '00:00:00'}',
                style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 9,
                    color: AppColors.dim,
                    letterSpacing: 1.5)),
            Text(
                switch (st) {
                  FooterConnState.connected => '🇮🇸 ПОД ЗАЩИТОЙ',
                  FooterConnState.connecting => '… ПРЯЧЕМСЯ',
                  _ => '👁 НА ВИДУ',
                },
                style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 9,
                    color: AppColors.dim,
                    letterSpacing: 1.5)),
          ],
        ),
      ],
    );
  }

  String get _moodName => switch (_mood) {
        _Mood.exposed => 'exposed',
        _Mood.worried => 'worried',
        _Mood.hopeful => 'hopeful',
        _Mood.safe => 'safe',
        _Mood.gleeful => 'gleeful',
      };
}

class _StatBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _StatBar(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0, 100).toDouble();
    final filled = (v / 10).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 9,
                    color: AppColors.dim,
                    letterSpacing: 1.5)),
            Text('${v.round()}%',
                style: TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 9,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: List.generate(10, (i) {
            return Expanded(
              child: Text('█',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11,
                      height: 1,
                      color: color.withValues(alpha: i < filled ? 1.0 : 0.18))),
            );
          }),
        ),
      ],
    );
  }
}

class _PetPainter extends CustomPainter {
  final List<String> sheet;
  final Color moodColor;
  const _PetPainter(this.sheet, this.moodColor);

  @override
  void paint(Canvas canvas, Size size) {
    final body = Paint()..color = moodColor;
    final ink = Paint()..color = AppColors.bgDeep;
    const px = 7.0;
    for (var y = 0; y < sheet.length; y++) {
      final row = sheet[y];
      for (var x = 0; x < row.length; x++) {
        final c = row[x];
        if (c == '.') continue;
        final paint = (c == '1') ? body : ink;
        canvas.drawRect(
            Rect.fromLTWH(x * px, y * px, px, px), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PetPainter old) =>
      old.sheet != sheet || old.moodColor != moodColor;
}
