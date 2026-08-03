import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:launcher_shortcuts/launcher_shortcuts.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PendingShortcutAction { none, create, scan, search, assigned }

/// Bridges launcher_shortcuts' raw String actions to typed app actions,
/// and persists a tapped shortcut across the auto-login/login flow so it
/// isn't lost if the app cold-starts logged out.
class ShortcutRouter {
  static const _prefsKey = 'pending_shortcut_action';
  static StreamSubscription<String>? _globalSub;

  static PendingShortcutAction parse(String type) {
    switch (type) {
      case 'create':
        return PendingShortcutAction.create;
      case 'scan':
        return PendingShortcutAction.scan;
      case 'search':
        return PendingShortcutAction.search;
      case 'assigned':
        return PendingShortcutAction.assigned;
      default:
        return PendingShortcutAction.none;
    }
  }

  static String _serialize(PendingShortcutAction action) => switch (action) {
        PendingShortcutAction.create => 'create',
        PendingShortcutAction.scan => 'scan',
        PendingShortcutAction.search => 'search',
        PendingShortcutAction.assigned => 'assigned',
        PendingShortcutAction.none => '',
      };

  /// Call once from main(), after LauncherShortcuts.initialize() and before
  /// runApp(). Catches the cold-start action (if any) plus any tap that
  /// arrives before HomeScreen exists to handle it directly, and stashes it
  /// so it survives however long login/auto-login takes.
  static void attachGlobalListener() {
    _globalSub ??= LauncherShortcuts.shortcutStream.listen((type) {
      final action = parse(type);
      if (action == PendingShortcutAction.none) return;
      _stash(action);
    });
  }

  static Future<void> _stash(PendingShortcutAction action) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _serialize(action));
    debugPrint('🔗 Shortcut stashed: $action');
  }

  /// Reads and clears whatever shortcut action is pending. Call this once
  /// HomeScreen has finished loading its initial data (i.e. the service is
  /// definitely ready — no separate readiness check needed).
  static Future<PendingShortcutAction> consume() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return PendingShortcutAction.none;
    await prefs.remove(_prefsKey);
    return parse(raw);
  }

  /// Clears any stashed action without reading it. Used by HomeScreen's own
  /// live listener after it handles a warm-start tap directly, so the
  /// global listener's stash of the same event doesn't get replayed later.
  static Future<void> clearStash() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}