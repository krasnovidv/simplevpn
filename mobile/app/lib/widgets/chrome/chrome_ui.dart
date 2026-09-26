import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/chrome.dart';
import 'chrome_orb.dart';

/// Replays a fade + rise + scale entrance whenever its key changes
/// (design: y2k-in, 550 ms, cubic-bezier(.2,1.4,.4,1)).
class EnterAnim extends StatelessWidget {
  final Widget child;
  final Duration delay;
  const EnterAnim({super.key, required this.child, this.delay = Duration.zero});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 550) + delay,
      curve: Interval(delay.inMilliseconds / (550 + delay.inMilliseconds), 1, curve: enterCurve),
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - v)),
          child: Transform.scale(scale: 0.97 + 0.03 * v, child: child),
        ),
      ),
      child: child,
    );
  }
}

/// Paints [child] with the chrome gradient.
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextAlign? align;
  const GradientText(this.text, {super.key, required this.style, this.align});

  @override
  Widget build(BuildContext context) {
    final g = Chrome.of(context).textGrad;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => g.createShader(Offset.zero & bounds.size),
      child: Text(text, style: style, textAlign: align),
    );
  }
}

TextStyle displayStyle(double size, Color color) => TextStyle(
      fontFamily: ChromeFonts.display,
      fontWeight: FontWeight.w800,
      fontSize: size,
      height: 0.98,
      letterSpacing: -1,
      color: color,
    );

TextStyle bodyStyle(Chrome c, {double size = 15, FontWeight weight = FontWeight.w600, Color? color, double height = 1.45}) =>
    TextStyle(fontFamily: ChromeFonts.body, fontSize: size, fontWeight: weight, height: height, color: color ?? c.sub);

/// Uppercase display headline; the last line is chrome when [hot], else muted.
class Headline extends StatelessWidget {
  final List<String> lines;
  final double size;
  final bool hot;
  const Headline({super.key, required this.lines, this.size = 46, this.hot = false});

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    return EnterAnim(
      key: ValueKey(lines.join('|')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++)
            if (i == lines.length - 1 && hot)
              GradientText(lines[i].toUpperCase(), style: displayStyle(size, Colors.white))
            else
              Text(lines[i].toUpperCase(),
                  style: displayStyle(size, i == lines.length - 1 ? c.sub : c.text)),
        ],
      ),
    );
  }
}

class Wordmark extends StatelessWidget {
  const Wordmark({super.key});

  @override
  Widget build(BuildContext context) => const GradientText(
        'RKNPNH',
        style: TextStyle(
          fontFamily: ChromeFonts.display,
          fontWeight: FontWeight.w800,
          fontSize: 20,
          letterSpacing: 1,
          color: Colors.white,
        ),
      );
}

/// Card with a 1.5 px chrome-gradient outline.
class ChromeCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool shadow;
  const ChromeCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 28,
    this.shadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: c.grad,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow ? c.cardShadow : null,
      ),
      padding: const EdgeInsets.all(1.5),
      child: Container(
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(radius - 1.5)),
        padding: padding,
        child: child,
      ),
    );
  }
}

/// Connection status pill with a glowing dot (pulsing while busy).
class StatusChip extends StatelessWidget {
  final OrbMood mood;
  const StatusChip({super.key, required this.mood});

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    final label = switch (mood) {
      OrbMood.idle => 'засвечен',
      OrbMood.connecting => 'прячемся',
      OrbMood.disconnecting => 'выходим',
      OrbMood.connected => 'невидимка',
      OrbMood.error => 'нет сети',
    };
    final busy = mood == OrbMood.connecting || mood == OrbMood.disconnecting;
    final dot = mood == OrbMood.connected ? c.good : busy ? c.accent : c.bad;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: c.dark ? const Color(0x0FFFFFFF) : const Color(0x9EFFFFFF),
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _Dot(color: dot, pulse: busy),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontFamily: ChromeFonts.body,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.5,
                    color: c.text)),
          ]),
        ),
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  final Color color;
  final bool pulse;
  const _Dot({required this.color, required this.pulse});

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    if (widget.pulse) _ctl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_Dot old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_ctl.isAnimating) _ctl.repeat(reverse: true);
    if (!widget.pulse) _ctl.value = 1;
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctl,
        builder: (context, _) {
          final v = widget.pulse ? _ctl.value : 1.0;
          return Transform.scale(
            scale: widget.pulse ? 1 + 0.25 * v : 1,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: widget.pulse ? 0.5 + 0.5 * v : 1),
                boxShadow: [BoxShadow(color: widget.color, blurRadius: 10)],
              ),
            ),
          );
        },
      );
}

/// 52×32 switch: outlined when off, chrome track with a large knob when on.
class ChromeSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const ChromeSwitch({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 52,
            height: 32,
            decoration: BoxDecoration(
              gradient: value ? c.grad : null,
              border: value ? null : Border.all(color: c.sub, width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 350),
                curve: springCurve,
                left: value ? 24 : 6 - (value ? 0 : 2),
                top: value ? 4 : 6,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  curve: springCurve,
                  width: value ? 24 : 16,
                  height: value ? 24 : 16,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: value ? c.onAccent : c.sub),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Scales down on press with the spring curve.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  const Pressable({super.key, required this.child, this.onTap, this.scale = 0.96});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
        onTapUp: widget.onTap == null ? null : (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: const Duration(milliseconds: 400),
          curve: springCurve,
          child: widget.child,
        ),
      );
}

/// Pill button filled with the chrome gradient, optionally with a running shine.
class PrimaryButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final bool iconTrailing;
  final VoidCallback? onTap;
  final bool shine;
  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.iconTrailing = false,
    this.onTap,
    this.shine = false,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> with SingleTickerProviderStateMixin {
  late final AnimationController _shine;

  @override
  void initState() {
    super.initState();
    _shine = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));
    if (widget.shine) _shine.repeat();
  }

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    final icon = widget.icon == null ? null : Icon(widget.icon, size: 20, color: c.onAccent);
    return Semantics(
      button: true,
      label: widget.label,
      child: Pressable(
        onTap: widget.onTap,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: c.grad,
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [BoxShadow(color: Color(0x59C9B8FF), blurRadius: 30, offset: Offset(0, 8))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(alignment: Alignment.center, children: [
            if (widget.shine && !MediaQuery.of(context).disableAnimations)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _shine,
                  builder: (context, _) {
                    // translateX(-120% → 220%) over the first 60% of the loop.
                    final p = (_shine.value / 0.6).clamp(0.0, 1.0);
                    return FractionalTranslation(
                      translation: Offset(-1.2 + 3.4 * Curves.easeInOut.transform(p), 0),
                      child: FractionallySizedBox(
                        widthFactor: 0.4,
                        alignment: Alignment.centerLeft,
                        child: Transform(
                          transform: Matrix4.skewX(-0.35),
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [
                                Color(0x00FFFFFF),
                                Color(0xB3FFFFFF),
                                Color(0x00FFFFFF),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (icon != null && !widget.iconTrailing) ...[icon, const SizedBox(width: 8)],
              Text(widget.label,
                  style: TextStyle(
                      fontFamily: ChromeFonts.body, fontWeight: FontWeight.w800, fontSize: 16, color: c.onAccent)),
              if (icon != null && widget.iconTrailing) ...[const SizedBox(width: 4), icon],
            ]),
          ]),
        ),
      ),
    );
  }
}

class GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const GhostButton({super.key, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    return Semantics(
      button: true,
      child: Pressable(
        onTap: onTap,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: c.dark ? const Color(0x33FFFFFF) : const Color(0x26121320), width: 2),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label,
              style: TextStyle(fontFamily: ChromeFonts.body, fontWeight: FontWeight.w800, fontSize: 16, color: c.text)),
        ),
      ),
    );
  }
}

/// Pill segmented control; the active segment is filled with the gradient.
class ChromeSegmented extends StatelessWidget {
  final List<String> options;
  final int index;
  final ValueChanged<int> onChanged;
  final bool framed;
  const ChromeSegmented({
    super.key,
    required this.options,
    required this.index,
    required this.onChanged,
    this.framed = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: framed
          ? BoxDecoration(
              color: c.card,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(999),
            )
          : null,
      child: Row(children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Semantics(
              selected: i == index,
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  curve: springCurve,
                  constraints: const BoxConstraints(minHeight: 40),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  decoration: BoxDecoration(
                    gradient: i == index ? c.grad : null,
                    border: framed || i == index ? null : Border.all(color: c.line, width: 1.5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    options[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: ChromeFonts.body,
                      fontWeight: FontWeight.w800,
                      fontSize: framed ? 12.5 : 14,
                      color: i == index ? c.onAccent : c.sub,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Top bar: wordmark on the left, optional trailing widget.
class TopBar extends StatelessWidget {
  final Widget? trailing;
  const TopBar({super.key, this.trailing});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Row(children: [const Wordmark(), const Spacer(), if (trailing != null) trailing!]),
        ),
      );
}

class NavItem {
  final IconData icon;
  final String label;
  const NavItem(this.icon, this.label);
}

/// Bottom navigation: blurred bar, active item is a 64×32 chrome pill.
class ChromeNavBar extends StatelessWidget {
  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onTap;
  const ChromeNavBar({super.key, required this.items, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    final bottom = MediaQuery.of(context).padding.bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(top: 12, bottom: 12 + bottom),
          decoration: BoxDecoration(color: c.nav, border: Border(top: BorderSide(color: c.line))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            for (var i = 0; i < items.length; i++)
              Semantics(
                selected: i == index,
                button: true,
                label: items[i].label,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: SizedBox(
                    width: 88,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        curve: springCurve,
                        width: i == index ? 64 : 32,
                        height: 32,
                        decoration: BoxDecoration(
                          gradient: i == index ? c.grad : null,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(items[i].icon, size: 22, color: i == index ? c.onAccent : c.sub),
                      ),
                      const SizedBox(height: 4),
                      Text(items[i].label,
                          style: TextStyle(
                            fontFamily: ChromeFonts.body,
                            fontSize: 12,
                            fontWeight: i == index ? FontWeight.w800 : FontWeight.w600,
                            color: i == index ? c.text : c.sub,
                          )),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Netherlands flag disc.
class FlagNL extends StatelessWidget {
  final double size;
  const FlagNL({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x1F000000), width: 1.5),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFAE1C28), Color(0xFFAE1C28), Colors.white, Colors.white, Color(0xFF21468B), Color(0xFF21468B)],
            stops: [0, 0.333, 0.333, 0.666, 0.666, 1],
          ),
        ),
      );
}

/// Four signal bars; [lit] of them light up in [color].
class SignalBars extends StatelessWidget {
  final int lit;
  final Color color;
  const SignalBars({super.key, required this.lit, required this.color});

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < 4; i++) ...[
        if (i > 0) const SizedBox(width: 3),
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          width: 4,
          height: 6.0 + i * 4,
          decoration: BoxDecoration(
            color: i < lit ? color : c.line,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    ]);
  }
}

/// Grouped settings list: caps label + card of rows.
class SettingsGroup extends StatelessWidget {
  final String label;
  final List<Widget> children;
  const SettingsGroup({super.key, required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
          child: Text(label.toUpperCase(),
              style: TextStyle(
                  fontFamily: ChromeFonts.body,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: c.sub)),
        ),
        ChromeCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: c.line),
              children[i],
            ],
          ]),
        ),
      ]),
    );
  }
}

/// One settings row: title, optional subtitle, and a switch or a value+chevron.
class SettingsRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool? value;
  final ValueChanged<bool>? onChanged;
  final String? trailingText;
  final VoidCallback? onTap;
  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.value,
    this.onChanged,
    this.trailingText,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    final isSwitch = value != null;
    return InkWell(
      onTap: isSwitch ? (onChanged == null ? null : () => onChanged!(!value!)) : onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: isSwitch ? 6 : 14),
        child: Row(children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: isSwitch ? 8 : 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: TextStyle(
                        fontFamily: ChromeFonts.body, fontSize: 15, fontWeight: FontWeight.w800, color: c.text)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: bodyStyle(c, size: 12.5, height: 1.4)),
                  ),
              ]),
            ),
          ),
          const SizedBox(width: 14),
          if (isSwitch)
            ChromeSwitch(value: value!, onChanged: onChanged)
          else
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (trailingText != null)
                Text(trailingText!, style: bodyStyle(c, size: 13, weight: FontWeight.w700)),
              if (onTap != null) Icon(Icons.chevron_right_rounded, size: 20, color: c.sub),
            ]),
        ]),
      ),
    );
  }
}
