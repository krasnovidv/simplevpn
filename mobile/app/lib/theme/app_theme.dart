import 'package:flutter/material.dart';

abstract final class AppColors {
  static const bg = Color(0xFF120a1f);
  static const bgDeep = Color(0xFF0a0612);
  static const magenta = Color(0xFFff2bd6);
  static const magentaHi = Color(0xFFff5ce0);
  static const cyan = Color(0xFF00f0ff);
  static const cyanHi = Color(0xFF7af6ff);
  static const white = Color(0xFFF5F3FF);
  static const dim = Color(0xFF5a4a7a);
  static const dim2 = Color(0xFF2a1f3a);
}

abstract final class AppFonts {
  static const display = 'ArchivoBlack';
  static const body = 'SpaceGrotesk';
  static const mono = 'JetBrainsMono';
}

final darkTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: AppColors.bg,
  colorScheme: const ColorScheme.dark(
    surface: AppColors.bg,
    primary: AppColors.magenta,
    secondary: AppColors.cyan,
    error: Color(0xFFFF4444),
    onSurface: AppColors.white,
    onPrimary: AppColors.white,
  ),
  fontFamily: AppFonts.body,
  textTheme: const TextTheme(
    displayLarge: TextStyle(fontFamily: AppFonts.display, color: AppColors.white),
    displayMedium: TextStyle(fontFamily: AppFonts.display, color: AppColors.white),
    displaySmall: TextStyle(fontFamily: AppFonts.display, color: AppColors.white),
    headlineLarge: TextStyle(fontFamily: AppFonts.display, color: AppColors.white),
    headlineMedium: TextStyle(fontFamily: AppFonts.display, color: AppColors.white),
    headlineSmall: TextStyle(fontFamily: AppFonts.display, color: AppColors.white),
    titleLarge: TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w700, color: AppColors.white),
    titleMedium: TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w500, color: AppColors.white),
    titleSmall: TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w500, color: AppColors.dim),
    bodyLarge: TextStyle(fontFamily: AppFonts.body, color: AppColors.white),
    bodyMedium: TextStyle(fontFamily: AppFonts.body, color: AppColors.white),
    bodySmall: TextStyle(fontFamily: AppFonts.body, color: AppColors.dim),
    labelLarge: TextStyle(fontFamily: AppFonts.mono, fontWeight: FontWeight.w500, color: AppColors.white),
    labelMedium: TextStyle(fontFamily: AppFonts.mono, fontWeight: FontWeight.w500, color: AppColors.dim),
    labelSmall: TextStyle(fontFamily: AppFonts.mono, fontWeight: FontWeight.w500, color: AppColors.dim),
  ),
  useMaterial3: true,
);
