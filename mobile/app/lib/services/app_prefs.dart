import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Appearance preferences shared by the whole UI. Loaded once at startup
/// ([load]) and then observed through the notifiers.
class AppPrefs {
  AppPrefs._();
  static final instance = AppPrefs._();

  static const _keyTheme = 'theme_mode';
  static const _keyAnimations = 'max_animations';
  // Read natively too (FlutterSharedPreferences "flutter.status_in_shade"),
  // so the service can decide what its notification shows.
  static const _keyStatusInShade = 'status_in_shade';

  final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

  /// "Анимации на максимум". Off (or the system's reduce-motion setting)
  /// freezes the orb and the backdrop into static frames.
  final maxAnimations = ValueNotifier<bool>(true);

  /// «Статус в шторке»: timer and traffic in the ongoing notification.
  final statusInShade = ValueNotifier<bool>(true);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    themeMode.value = switch (p.getString(_keyTheme)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    maxAnimations.value = p.getBool(_keyAnimations) ?? true;
    statusInShade.value = p.getBool(_keyStatusInShade) ?? true;
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode.value = m;
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyTheme, m.name);
  }

  Future<void> setMaxAnimations(bool v) async {
    maxAnimations.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyAnimations, v);
  }

  Future<void> setStatusInShade(bool v) async {
    statusInShade.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyStatusInShade, v);
  }

  /// Whether decorative motion should run in [context].
  bool animate(BuildContext context) =>
      maxAnimations.value && !MediaQuery.of(context).disableAnimations;
}
