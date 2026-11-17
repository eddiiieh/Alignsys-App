import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the user's theme preference. Persists to SharedPreferences.
///
/// Default is [ThemeMode.system] so a fresh install respects the OS
/// appearance. The sun/moon toggle in the profile menu calls [toggle],
/// which snaps to an explicit light/dark override.
class ThemeService extends ChangeNotifier {
  static const _key = 'theme_mode';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  /// True only when the *explicit* preference is dark. If the mode is
  /// [ThemeMode.system], use `Theme.of(context).brightness` for the
  /// effective state.
  bool get isExplicitDark => _mode == ThemeMode.dark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    _mode = switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  /// Binary toggle — flips between explicit light and explicit dark,
  /// regardless of what `system` currently resolves to.
  void toggle(BuildContext context) {
    final effectiveDark = Theme.of(context).brightness == Brightness.dark;
    setMode(effectiveDark ? ThemeMode.light : ThemeMode.dark);
  }

  /// Optional: long-press on the toggle to return to system-follow.
  void resetToSystem() => setMode(ThemeMode.system);
}