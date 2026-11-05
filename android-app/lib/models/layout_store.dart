import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Static description of one movable on-screen control.
class ItemSpec {
  final String id;
  final String title;

  /// Default centre position, as a fraction of the play area (0..1).
  final double x, y;

  /// Base box size in logical pixels (at scale 1.0).
  final double w, h;

  /// Touch-zone size used when the control is in "floating" mode.
  final double? floatW, floatH;

  /// Whether the user may hide this control.
  final bool canHide;

  /// Whether the user may recolour this control.
  final bool canColor;

  const ItemSpec(this.id, this.title, this.x, this.y, this.w, this.h,
      {this.canHide = true, this.canColor = true, this.floatW, this.floatH});
}

/// User-adjustable state of one control.
class ItemLayout {
  double x, y, scale, opacity;
  bool visible;

  /// ARGB colour override, or null for the built-in colour.
  int? color;

  ItemLayout({
    required this.x,
    required this.y,
    this.scale = 1.0,
    this.opacity = 1.0,
    this.visible = true,
    this.color,
  });

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        's': scale,
        'o': opacity,
        'v': visible,
        if (color != null) 'c': color,
      };

  static ItemLayout? fromJson(Object? j, ItemSpec spec) {
    if (j is! Map) return null;
    double n(Object? v, double d) => v is num ? v.toDouble() : d;
    return ItemLayout(
      x: n(j['x'], spec.x).clamp(0.0, 1.0).toDouble(),
      y: n(j['y'], spec.y).clamp(0.0, 1.0).toDouble(),
      scale: n(j['s'], 1.0).clamp(LayoutStore.minScale, LayoutStore.maxScale).toDouble(),
      opacity: n(j['o'], 1.0).clamp(LayoutStore.minOpacity, 1.0).toDouble(),
      visible: j['v'] is bool ? j['v'] as bool : true,
      color: (spec.canColor && j['c'] is int) ? j['c'] as int : null,
    );
  }

  ItemLayout copy() => ItemLayout(
      x: x, y: y, scale: scale, opacity: opacity, visible: visible, color: color);
}

/// Per-profile input tuning.
class ProfileSettings {
  /// Radial deadzone for both sticks (0 = none).
  double deadzone;

  /// Stick gain: >1 reaches full deflection sooner, <1 is gentler.
  double sensitivity;

  bool floatLeft, floatRight;

  /// Vibration feedback on touches: 0 = off, 1 = light, 2 = strong.
  int haptics;

  ProfileSettings({
    this.deadzone = 0.0,
    this.sensitivity = 1.0,
    this.floatLeft = false,
    this.floatRight = false,
    this.haptics = 1,
  });

  Map<String, dynamic> toJson() => {
        'dz': deadzone,
        'sens': sensitivity,
        'fl': floatLeft,
        'fr': floatRight,
        'hp': haptics,
      };

  static ProfileSettings fromJson(Object? j) {
    if (j is! Map) return ProfileSettings();
    double n(Object? v, double d) => v is num ? v.toDouble() : d;
    return ProfileSettings(
      deadzone: n(j['dz'], 0).clamp(0.0, LayoutStore.maxDeadzone).toDouble(),
      sensitivity: n(j['sens'], 1)
          .clamp(LayoutStore.minSensitivity, LayoutStore.maxSensitivity)
          .toDouble(),
      floatLeft: j['fl'] == true,
      floatRight: j['fr'] == true,
      // Older versions stored a bool here.
      haptics: j['hp'] is int ? (j['hp'] as int).clamp(0, 2) : (j['hp'] == false ? 0 : 1),
    );
  }

  ProfileSettings copy() => ProfileSettings(
        deadzone: deadzone,
        sensitivity: sensitivity,
        floatLeft: floatLeft,
        floatRight: floatRight,
        haptics: haptics,
      );
}

class _Profile {
  final Map<String, ItemLayout> items;
  final ProfileSettings settings;
  _Profile(this.items, this.settings);

  factory _Profile.defaults() => _Profile({
        for (final s in LayoutStore.specs) s.id: ItemLayout(x: s.x, y: s.y),
      }, ProfileSettings());

  _Profile copy() => _Profile(
        {for (final e in items.entries) e.key: e.value.copy()},
        settings.copy(),
      );

  Map<String, dynamic> toJson() => {
        'items': {for (final i in items.entries) i.key: i.value.toJson()},
        'settings': settings.toJson(),
      };

  static _Profile fromJson(Map p) {
    final raw = p['items'];
    final items = <String, ItemLayout>{};
    for (final s in LayoutStore.specs) {
      items[s.id] = ItemLayout.fromJson(raw is Map ? raw[s.id] : null, s) ??
          ItemLayout(x: s.x, y: s.y);
    }
    return _Profile(items, ProfileSettings.fromJson(p['settings']));
  }
}

/// Holds the layout profiles and persists them on the device.
class LayoutStore extends ChangeNotifier {
  static const _prefsKeyV1 = 'gamepad_layout_v1';
  static const _prefsKey = 'gamepad_layout_v2';
  static const _shareTag = 'vgamepad_profile';
  static const defaultProfileName = 'Default';

  static const double minScale = 0.5;
  static const double maxScale = 2.0;
  static const double minOpacity = 0.2;
  static const double maxDeadzone = 0.35;
  static const double minSensitivity = 0.5;
  static const double maxSensitivity = 1.5;

  /// Default positions copied from the original fixed layout.
  static const List<ItemSpec> specs = [
    ItemSpec('lt', 'LT trigger', 0.078, 0.182, 112, 112),
    ItemSpec('lb', 'LB bumper', 0.184, 0.339, 70, 70),
    ItemSpec('dpad', 'D-pad', 0.112, 0.620, 180, 180, canColor: false),
    ItemSpec('disconnect', 'Disconnect', 0.470, 0.068, 50, 50, canHide: false),
    ItemSpec('back', 'Back (menu)', 0.371, 0.242, 60, 60),
    ItemSpec('guide', 'Guide', 0.470, 0.242, 68, 68),
    ItemSpec('start', 'Start', 0.570, 0.242, 60, 60),
    ItemSpec('l3', 'L3 (left stick click)', 0.416, 0.475, 90, 56),
    ItemSpec('r3', 'R3 (right stick click)', 0.526, 0.475, 90, 56),
    ItemSpec('lstick', 'Left stick', 0.310, 0.751, 160, 160,
        floatW: 260, floatH: 220),
    ItemSpec('rstick', 'Right stick', 0.685, 0.751, 160, 160,
        floatW: 260, floatH: 220),
    ItemSpec('rb', 'RB bumper', 0.815, 0.346, 70, 70),
    ItemSpec('rt', 'RT trigger', 0.922, 0.182, 112, 112),
    ItemSpec('face', 'A / B / X / Y', 0.890, 0.620, 150, 150, canColor: false),
  ];

  static final Map<String, ItemSpec> _specById = {
    for (final s in specs) s.id: s,
  };

  final Map<String, _Profile> _profiles = {
    defaultProfileName: _Profile.defaults(),
  };
  String _active = defaultProfileName;

  // ───────────── profiles ─────────────
  List<String> get profileNames => _profiles.keys.toList();
  String get active => _active;
  ProfileSettings get settings => _profiles[_active]!.settings;

  void switchTo(String name) {
    if (!_profiles.containsKey(name) || name == _active) return;
    _active = name;
    notifyListeners();
  }

  void nextProfile() {
    final names = profileNames;
    if (names.length < 2) return;
    switchTo(names[(names.indexOf(_active) + 1) % names.length]);
  }

  String _uniqueName(String wanted) {
    var name = wanted.trim().isEmpty ? 'Profile' : wanted.trim();
    if (!_profiles.containsKey(name)) return name;
    var i = 2;
    while (_profiles.containsKey('$name $i')) {
      i++;
    }
    return '$name $i';
  }

  /// New profile starts as a copy of the current one.
  void createProfile(String name) {
    final n = _uniqueName(name);
    _profiles[n] = _profiles[_active]!.copy();
    _active = n;
    notifyListeners();
  }

  void renameActive(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == _active) return;
    final n = _uniqueName(trimmed);
    // Rebuild the map so the profile keeps its position in the list.
    final rebuilt = <String, _Profile>{
      for (final e in _profiles.entries) (e.key == _active ? n : e.key): e.value,
    };
    _profiles
      ..clear()
      ..addAll(rebuilt);
    _active = n;
    notifyListeners();
  }

  bool get canDeleteActive => _profiles.length > 1;

  void deleteActive() {
    if (!canDeleteActive) return;
    final names = profileNames;
    final idx = names.indexOf(_active);
    _profiles.remove(_active);
    final left = profileNames;
    _active = left[idx.clamp(0, left.length - 1)];
    notifyListeners();
  }

  /// The active profile as shareable text (copy it, paste it elsewhere).
  String exportActive() => jsonEncode({
        _shareTag: 1,
        'name': _active,
        ..._profiles[_active]!.toJson(),
      });

  /// Adds a profile from text made by [exportActive]. Returns its name,
  /// or null if the text isn't a valid profile.
  String? importProfile(String text) {
    try {
      final data = jsonDecode(text.trim());
      if (data is! Map || data[_shareTag] == null) return null;
      final n = _uniqueName(data['name'] is String ? data['name'] as String : 'Imported');
      _profiles[n] = _Profile.fromJson(data);
      _active = n;
      notifyListeners();
      return n;
    } catch (_) {
      return null;
    }
  }

  // ───────────── items ─────────────
  ItemSpec spec(String id) => _specById[id]!;
  ItemLayout of(String id) => _profiles[_active]!.items[id]!;

  bool isFloating(String id) {
    final s = settings;
    return (id == 'lstick' && s.floatLeft) || (id == 'rstick' && s.floatRight);
  }

  double boxW(String id) {
    final sp = spec(id);
    return isFloating(id) && sp.floatW != null ? sp.floatW! : sp.w;
  }

  double boxH(String id) {
    final sp = spec(id);
    return isFloating(id) && sp.floatH != null ? sp.floatH! : sp.h;
  }

  void setFloating(String id, bool v) {
    if (id == 'lstick') settings.floatLeft = v;
    if (id == 'rstick') settings.floatRight = v;
    notifyListeners();
  }

  void setDeadzone(double v) {
    settings.deadzone = v.clamp(0.0, maxDeadzone).toDouble();
    notifyListeners();
  }

  void setSensitivity(double v) {
    settings.sensitivity = v.clamp(minSensitivity, maxSensitivity).toDouble();
    notifyListeners();
  }

  void setHaptics(int v) {
    settings.haptics = v.clamp(0, 2);
    notifyListeners();
  }

  void setPosition(String id, double x, double y) {
    final it = of(id);
    it.x = x.clamp(0.0, 1.0).toDouble();
    it.y = y.clamp(0.0, 1.0).toDouble();
    notifyListeners();
  }

  void setScale(String id, double v) {
    of(id).scale = v.clamp(minScale, maxScale).toDouble();
    notifyListeners();
  }

  void setOpacity(String id, double v) {
    of(id).opacity = v.clamp(minOpacity, 1.0).toDouble();
    notifyListeners();
  }

  void setVisible(String id, bool v) {
    of(id).visible = v;
    notifyListeners();
  }

  void setColor(String id, int? argb) {
    if (!spec(id).canColor) return;
    of(id).color = argb;
    notifyListeners();
  }

  void resetItem(String id) {
    final s = spec(id);
    _profiles[_active]!.items[id] = ItemLayout(x: s.x, y: s.y);
    if (id == 'lstick') settings.floatLeft = false;
    if (id == 'rstick') settings.floatRight = false;
    notifyListeners();
  }

  /// Resets the active profile only.
  void resetAll() {
    _profiles[_active] = _Profile.defaults();
    notifyListeners();
  }

  // ───────────── persistence ─────────────
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final data = jsonDecode(raw);
        if (data is Map && data['profiles'] is Map) {
          final loaded = <String, _Profile>{};
          (data['profiles'] as Map).forEach((name, p) {
            if (name is String && p is Map) loaded[name] = _Profile.fromJson(p);
          });
          if (loaded.isNotEmpty) {
            _profiles
              ..clear()
              ..addAll(loaded);
            final a = data['active'];
            _active = (a is String && _profiles.containsKey(a))
                ? a
                : _profiles.keys.first;
            notifyListeners();
            return;
          }
        }
      }

      // Migrate the single-layout format from the first version.
      final old = prefs.getString(_prefsKeyV1);
      if (old != null) {
        final data = jsonDecode(old);
        if (data is Map) {
          final p = _Profile.defaults();
          for (final s in specs) {
            final l = ItemLayout.fromJson(data[s.id], s);
            if (l != null) p.items[s.id] = l;
          }
          _profiles
            ..clear()
            ..[defaultProfileName] = p;
          _active = defaultProfileName;
          notifyListeners();
        }
      }
    } catch (_) {
      // Corrupt or unreadable data: keep the defaults.
    }
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode({
          'active': _active,
          'profiles': {for (final e in _profiles.entries) e.key: e.value.toJson()},
        }),
      );
    } catch (_) {}
  }
}
