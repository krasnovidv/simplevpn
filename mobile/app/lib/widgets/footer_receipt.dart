import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'footer_common.dart';

/// Denial Receipt footer — a dot-matrix receipt that feeds out of a printer
/// slot and prints line-by-line on connect, ending in a tilted magenta
/// ★ NOT APPROVED ★ stamp, then live TRACKERS DENIED / DECOYS SENT counters.
class FooterReceipt extends StatefulWidget {
  final FooterConnState state;
  final int secs;

  const FooterReceipt({super.key, required this.state, required this.secs});

  @override
  State<FooterReceipt> createState() => _FooterReceiptState();
}

class _ReceiptLine {
  final String text;
  final bool stamp;
  final bool header;
  final bool centered;
  const _ReceiptLine(this.text,
      {this.stamp = false, this.header = false, this.centered = false});
}

class _FooterReceiptState extends State<FooterReceipt>
    with SingleTickerProviderStateMixin {
  static const _lines = <_ReceiptLine>[
    _ReceiptLine('━━ RKN·PNH ━━━━━━━━━━━━━━', header: true),
    _ReceiptLine('УПРАВЛЕНИЕ ОТКАЗАННЫХ ПРАВ', header: true, centered: true),
    _ReceiptLine('2026-05-05 · ТАЛОН #2C7F4A', centered: true),
    _ReceiptLine('────────────────────────'),
    _ReceiptLine('IP-АДРЕС ........... ОТОЗВАН'),
    _ReceiptLine('ЛИЧНОСТЬ ........... СТЁРТА'),
    _ReceiptLine('ЛОКАЦИЯ ......... РЕЙКЬЯВИК'),
    _ReceiptLine('ТРЕКЕРЫ ........... ОТКЛОНЕНЫ'),
    _ReceiptLine('────────────────────────'),
    _ReceiptLine('★ НЕ ОДОБРЕНО ★', stamp: true, centered: true),
    _ReceiptLine('ПО ПРИКАЗУ: PNH'),
    _ReceiptLine('СОХРАНИ ЭТОТ ЧЕК. ОНИ — НЕТ.', centered: true),
    _ReceiptLine('✂ - - - - - - - - - - - - - -', centered: true),
  ];

  // Receipt-paper local palette (warmer inks over the cream paper).
  static const _paperDim = Color(0xFF7a6f5e);
  static const _paperFaint = Color(0xFFa8987c);
  static const _paperRule = Color(0xFFb8a98c);

  int _revealed = 0;
  int _blocked = 0;
  int _decoys = 0;
  Timer? _printTimer;
  Timer? _counterTimer;
  final _rng = Random();
  late final AnimationController _feedCtl;

  @override
  void initState() {
    super.initState();
    _feedCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _syncToState();
  }

  @override
  void didUpdateWidget(FooterReceipt old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _syncToState();
  }

  void _syncToState() {
    _printTimer?.cancel();
    _counterTimer?.cancel();
    final st = widget.state;

    if (st == FooterConnState.connecting) {
      _feedCtl.repeat();
    } else {
      _feedCtl.stop();
    }

    if (st != FooterConnState.connected) {
      _revealed = (st == FooterConnState.disconnecting) ? _lines.length : 0;
      _blocked = 0;
      _decoys = 0;
      return;
    }

    // connected: print lines one by one, then tick counters.
    _revealed = 0;
    _blocked = 0;
    _decoys = 0;
    _printTimer = Timer.periodic(const Duration(milliseconds: 110), (t) {
      if (!mounted) return;
      setState(() => _revealed++);
      if (_revealed >= _lines.length) t.cancel();
    });
    _counterTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (!mounted) return;
      setState(() {
        _blocked += _rng.nextInt(3);
        _decoys += _rng.nextInt(2);
      });
    });
  }

  @override
  void dispose() {
    _printTimer?.cancel();
    _counterTimer?.cancel();
    _feedCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    final connected = st == FooterConnState.connected;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // printer slot
          Container(
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.bgDeep,
              borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
              border: Border(
                top: BorderSide(color: AppColors.dim2),
                left: BorderSide(color: AppColors.dim2),
                right: BorderSide(color: AppColors.dim2),
              ),
            ),
          ),
          ClipPath(
            clipper: _ReceiptEdgeClipper(),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 80),
              decoration: const BoxDecoration(
                color: AppColors.paper,
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(4)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 20,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: _body(st, connected),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(FooterConnState st, bool connected) {
    if (st == FooterConnState.idle) {
      return const Column(
        children: [
          SizedBox(height: 12),
          Text('— ПУСТО —',
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
                color: _paperDim,
              )),
          SizedBox(height: 4),
          Text('ТАЛОН НЕ ВЫДАН',
              style: TextStyle(
                  fontFamily: AppFonts.mono, fontSize: 10, color: _paperDim)),
          SizedBox(height: 10),
          Text('нажми штамп, чтобы оформить',
              style: TextStyle(
                  fontFamily: AppFonts.mono, fontSize: 10, color: _paperFaint)),
          SizedBox(height: 18),
        ],
      );
    }

    if (st == FooterConnState.connecting) {
      return Column(
        children: [
          const SizedBox(height: 12),
          const Text('ПЕЧАТЬ…',
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
                color: Color(0xFF5a4f3e),
              )),
          const SizedBox(height: 6),
          FadeTransition(
            opacity: _feedCtl.drive(
              TweenSequence([
                TweenSequenceItem(tween: ConstantTween(1.0), weight: 50),
                TweenSequenceItem(tween: ConstantTween(0.25), weight: 50),
              ]),
            ),
            child: const Text('▮▮▮▮▮▮▮▮',
                style: TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 10,
                    color: Color(0xFF5a4f3e))),
          ),
          const SizedBox(height: 18),
        ],
      );
    }

    // connected / disconnecting: show revealed lines + counters
    final count =
        st == FooterConnState.disconnecting ? _lines.length : _revealed;
    final shown = _lines.take(count).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final line in shown) _lineWidget(line),
        if (connected && _revealed >= _lines.length) _counters(),
      ],
    );
  }

  Widget _lineWidget(_ReceiptLine line) {
    final child = Text(
      line.text,
      textAlign: line.centered ? TextAlign.center : TextAlign.left,
      style: TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: line.stamp ? 13 : 11,
        height: 1.45,
        letterSpacing: line.stamp ? 2 : 0.5,
        fontWeight:
            (line.header || line.stamp) ? FontWeight.w700 : FontWeight.w400,
        color: line.stamp ? AppColors.magenta : AppColors.paperInk,
      ),
    );
    if (line.stamp) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Transform.rotate(angle: -3 * pi / 180, child: child),
        ),
      );
    }
    return child;
  }

  Widget _counters() {
    TextStyle label() => const TextStyle(
        fontFamily: AppFonts.mono, fontSize: 10, color: Color(0xFF5a4f3e));
    Widget cell(String l, String v, {bool right = false}) => Row(
          mainAxisAlignment:
              right ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Text('$l ', style: label()),
            Text(v,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.paperInk,
                  fontFeatures: [FontFeature.tabularFigures()],
                )),
          ],
        );

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding: const EdgeInsets.only(top: 6),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: _paperRule)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: cell('ТРЕКЕРЫ', '$_blocked')),
                Expanded(child: cell('ДЕКОИ', '$_decoys', right: true)),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(child: cell('АПТАЙМ', fmtFooterTime(widget.secs))),
                Expanded(child: cell('ВЫХОД', 'REY', right: true)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Torn / zig-zag bottom edge of the receipt paper.
class _ReceiptEdgeClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()..lineTo(size.width, 0)..lineTo(size.width, size.height);
    const teeth = 26;
    final step = size.width / teeth;
    for (var i = 0; i < teeth; i++) {
      final x = size.width - step * (i + 0.5);
      path.lineTo(x, size.height - 2);
      path.lineTo(x - step / 2, size.height);
    }
    path.lineTo(0, size.height - 2);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
