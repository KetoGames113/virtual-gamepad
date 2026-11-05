import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A PC the phone connected to before.
class SavedHost {
  final String name;
  final String address;
  final int lastUsed; // millisecondsSinceEpoch

  const SavedHost({required this.name, required this.address, required this.lastUsed});

  Map<String, dynamic> toJson() => {'n': name, 'a': address, 't': lastUsed};

  static SavedHost? fromJson(Object? j) {
    if (j is! Map || j['a'] is! String) return null;
    return SavedHost(
      name: j['n'] is String ? j['n'] as String : 'PC',
      address: j['a'] as String,
      lastUsed: j['t'] is int ? j['t'] as int : 0,
    );
  }
}

/// Remembers the last few PCs so reconnecting is one tap.
class SavedHosts {
  static const _key = 'recent_hosts_v1';
  static const _max = 5;

  static Future<List<SavedHost>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      final data = jsonDecode(raw);
      if (data is! List) return [];
      final list = [for (final e in data) SavedHost.fromJson(e)].whereType<SavedHost>().toList();
      list.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<SavedHost> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode([for (final h in list) h.toJson()]));
    } catch (_) {}
  }

  static Future<void> remember(String address, String name) async {
    final list = await load();
    list.removeWhere((h) => h.address == address);
    list.insert(
      0,
      SavedHost(
        name: name.trim().isEmpty ? 'PC' : name.trim(),
        address: address,
        lastUsed: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await _save(list.take(_max).toList());
  }

  static Future<void> forget(String address) async {
    final list = await load();
    list.removeWhere((h) => h.address == address);
    await _save(list);
  }
}
