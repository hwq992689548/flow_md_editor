import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted appearance settings shared by [FlowMdApp] and the editor chrome.
class AppSettings {
  AppSettings(this.prefs)
      : themeMode = ValueNotifier(_readTheme(prefs)),
        fontSize = ValueNotifier(_readFont(prefs));

  static const themeModeKey = 'theme_mode';
  static const fontSizeKey = 'font_size';
  static const minFontSize = 12.0;
  static const maxFontSize = 22.0;
  static const defaultFontSize = 14.0;

  final SharedPreferences prefs;
  final ValueNotifier<ThemeMode> themeMode;
  final ValueNotifier<double> fontSize;

  void dispose() {
    themeMode.dispose();
    fontSize.dispose();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (themeMode.value == mode) return;
    themeMode.value = mode;
    await prefs.setString(themeModeKey, encodeThemeMode(mode));
  }

  Future<void> setFontSize(double size) async {
    final next = size.clamp(minFontSize, maxFontSize);
    if ((fontSize.value - next).abs() < 0.01) return;
    fontSize.value = next;
    await prefs.setDouble(fontSizeKey, next);
  }

  Future<void> bumpFontSize(double delta) =>
      setFontSize(fontSize.value + delta);

  static ThemeMode _readTheme(SharedPreferences prefs) =>
      decodeThemeMode(prefs.getString(themeModeKey));

  static double _readFont(SharedPreferences prefs) {
    final raw = prefs.getDouble(fontSizeKey) ?? defaultFontSize;
    return raw.clamp(minFontSize, maxFontSize);
  }

  static String encodeThemeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static ThemeMode decodeThemeMode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  static String themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
      case ThemeMode.system:
        return '随系统';
    }
  }
}
