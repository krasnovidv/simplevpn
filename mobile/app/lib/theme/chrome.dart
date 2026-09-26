import 'package:flutter/material.dart';

/// "Liquid chrome" design tokens (design/v2/handoff_chrome/SPEC.md).
/// Reached through `Chrome.of(context)`; both themes carry one.
@immutable
class Chrome extends ThemeExtension<Chrome> {
  final bool dark;
  final Color bg;
  final Color text;
  final Color sub;
  final Color card;
  final Color line;
  final Color accent;
  final Color good;
  final Color bad;
  final Color nav;
  final Color onAccent;
  final List<Color> gradColors;
  final List<Color> blobs;

  const Chrome._({
    required this.dark,
    required this.bg,
    required this.text,
    required this.sub,
    required this.card,
    required this.line,
    required this.accent,
    required this.good,
    required this.bad,
    required this.nav,
    required this.onAccent,
    required this.gradColors,
    required this.blobs,
  });

  static const darkTokens = Chrome._(
    dark: true,
    bg: Color(0xFF0A0B18),
    text: Color(0xFFF2F4FF),
    sub: Color(0xFF9CA3C9),
    card: Color(0xFF14152A),
    line: Color(0x1AFFFFFF),
    accent: Color(0xFFC9B8FF),
    good: Color(0xFF8CFFD9),
    bad: Color(0xFFFF8FA8),
    nav: Color(0xB80E0F20),
    onAccent: Color(0xFF0A0B18),
    gradColors: [Color(0xFFA8F0FF), Color(0xFFD9B8FF), Color(0xFFFFC4EC), Color(0xFFFFF3B8)],
    blobs: [Color(0xFF5B3BFF), Color(0xFF00D1FF), Color(0xFFFF4FD8)],
  );

  static const lightTokens = Chrome._(
    dark: false,
    bg: Color(0xFFECEEF6),
    text: Color(0xFF121320),
    sub: Color(0xFF5A6082),
    card: Color(0xFFF6F7FC),
    line: Color(0x14121320),
    accent: Color(0xFF6B4DFF),
    good: Color(0xFF00A67E),
    bad: Color(0xFFE0325C),
    nav: Color(0xB8FFFFFF),
    onAccent: Color(0xFF121320),
    gradColors: [Color(0xFF7FE3FF), Color(0xFFB79BFF), Color(0xFFFF9BDB), Color(0xFFFFE58A)],
    blobs: [Color(0xFFB9A8FF), Color(0xFF9BEAFF), Color(0xFFFFB8E6)],
  );

  static Chrome of(BuildContext context) =>
      Theme.of(context).extension<Chrome>() ?? darkTokens;

  static const gradStops = [0.0, 0.45, 0.75, 1.0];

  /// The chrome gradient (115°) used for buttons, active tabs, switches,
  /// headline accents and card outlines.
  LinearGradient get grad => LinearGradient(
        begin: const Alignment(-0.9, -0.42),
        end: const Alignment(0.9, 0.42),
        colors: gradColors,
        stops: gradStops,
      );

  /// Gradient for text. On light backgrounds the pastel gradient is too pale
  /// to read, so it is darkened and saturated (CSS: saturate(1.5) brightness(.78)).
  LinearGradient get textGrad => dark
      ? grad
      : LinearGradient(
          begin: grad.begin,
          end: grad.end,
          colors: gradColors.map(_deepen).toList(),
          stops: gradStops,
        );

  /// CSS `saturate(1.5) brightness(.78)`, applied to one colour.
  static Color _deepen(Color c) {
    const s = 1.5, b = 0.78;
    final r = c.r * 255, g = c.g * 255, bl = c.b * 255;
    int ch(double v) => (v.clamp(0.0, 255.0) * b).round();
    return Color.fromARGB(
      255,
      ch((0.213 + 0.787 * s) * r + (0.715 - 0.715 * s) * g + (0.072 - 0.072 * s) * bl),
      ch((0.213 - 0.213 * s) * r + (0.715 + 0.285 * s) * g + (0.072 - 0.072 * s) * bl),
      ch((0.213 - 0.213 * s) * r + (0.715 - 0.715 * s) * g + (0.072 + 0.928 * s) * bl),
    );
  }

  List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: dark ? const Color(0x2E5B3BFF) : const Color(0x1F6B4DFF),
          blurRadius: dark ? 40 : 30,
          offset: const Offset(0, 10),
        ),
      ];

  @override
  Chrome copyWith() => this;

  @override
  Chrome lerp(ThemeExtension<Chrome>? other, double t) =>
      (other is Chrome && t >= 0.5) ? other : this;
}

abstract final class ChromeFonts {
  static const display = 'Unbounded';
  static const body = 'Manrope';
}

/// Spring used for everything interactive: cubic-bezier(.3,1.6,.5,1).
const springCurve = Cubic(0.3, 1.6, 0.5, 1);

/// Entrance of screens/texts: cubic-bezier(.2,1.4,.4,1).
const enterCurve = Cubic(0.2, 1.4, 0.4, 1);

ThemeData buildChromeTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? Chrome.darkTokens : Chrome.lightTokens;
  final base = ThemeData(brightness: brightness, useMaterial3: true, fontFamily: ChromeFonts.body);
  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    colorScheme: (brightness == Brightness.dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
      surface: c.bg,
      primary: c.accent,
      secondary: c.accent,
      onPrimary: c.onAccent,
      onSurface: c.text,
      error: c.bad,
    ),
    textTheme: base.textTheme.apply(
      fontFamily: ChromeFonts.body,
      bodyColor: c.text,
      displayColor: c.text,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.text,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: ChromeFonts.display,
        fontWeight: FontWeight.w800,
        fontSize: 18,
        color: c.text,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.dark ? const Color(0xFFF4F1FA) : const Color(0xFF1E1B26),
      contentTextStyle: TextStyle(
        fontFamily: ChromeFonts.body,
        fontWeight: FontWeight.w700,
        color: c.dark ? const Color(0xFF1E1B26) : const Color(0xFFF4F1FA),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    extensions: [c],
  );
}
