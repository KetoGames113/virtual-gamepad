import 'package:shared_preferences/shared_preferences.dart';

/// The name this player shows on the PC (e.g. in a multi-player session).
class PlayerName {
  static const _key = 'player_name_v1';
  static const maxLength = 20;
  static const fallback = 'Player';

  static String clean(String raw) {
    final t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    final cut = t.length > maxLength ? t.substring(0, maxLength) : t;
    return cut.isEmpty ? fallback : cut;
  }

  static Future<String> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return clean(prefs.getString(_key) ?? fallback);
    } catch (_) {
      return fallback;
    }
  }

  static Future<void> save(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, clean(name));
    } catch (_) {}
  }
}
