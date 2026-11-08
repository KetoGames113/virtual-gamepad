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
  /// Per-stick radial deadzone (0 = none) and gain.
  /// Gain >1 reaches full deflection sooner, <1 is gentler.
  double deadzoneL, deadzoneR, sensL, sensR;

  /// Per-stick response curve (1 = linear, >1 = finer near the centre) and
  /// vertical gain (separate Y sensitivity).
  double curveL, curveR, yScaleL, yScaleR;

  bool floatLeft, floatRight;

  /// Vibration feedback on touches: 0 = off, 1 = light, 2 = strong.
  int haptics;

  /// Game rumble coming from the PC: 0 = off, 1 = full strength.
  double rumble;

  /// Double-tap-to-lock on the triggers, and how far they lock (0..1).
  bool latchLt, latchRt;
  double latchLevelLt, latchLevelRt;

  /// Sliding a pressed trigger also moves the right stick.
  bool steerLt, steerRt;

  /// Aim & fire: slide = aim with the right stick, pull further = full press.
  bool aimLt, aimRt;
  double aimFire; // pull distance (in aim radii) that fires

  /// Item ids whose button works as a toggle (tap on / tap off).
  Set<String> toggles;

  /// PC process names (lowercase, no .exe) that auto-select this profile.
  List<String> games;

  /// Item ids whose button auto-repeats while held (rapid fire).
  Set<String> turbo;

  /// Rapid-fire speed: presses per second (shared by buttons and triggers).
  double turboRate;

  /// Show the ping badge on the gamepad screen.
  bool showPing;

  /// Click L3 automatically when the left stick is pushed fully forward.
  bool autoSprint;

  /// Gyro aiming: rotating the phone moves the right stick.
  bool gyro;
  double gyroSens;
  bool gyroInvertY;

  /// Tilt steering (phone rotated like a steering wheel).
  bool tilt;
  bool tiltRightStick; // false = drives the left stick X, true = right stick X
  bool tiltInvert;
  double tiltSens; // gain: full lock at 45° / tiltSens
  double tiltDeadzone; // degrees
  double tiltSmooth; // 0 = raw, 0.9 = very smooth
  double tiltCurve; // 1 = linear
  double tiltCenter; // calibrated "straight" angle in degrees
  bool tiltAuto; // re-centre automatically when play starts

  ProfileSettings({
    this.deadzoneL = 0.0,
    this.deadzoneR = 0.0,
    this.sensL = 1.0,
    this.sensR = 1.0,
    this.curveL = 1.0,
    this.curveR = 1.0,
    this.yScaleL = 1.0,
    this.yScaleR = 1.0,
    this.floatLeft = false,
    this.floatRight = false,
    this.haptics = 1,
    this.rumble = 1.0,
    this.latchLt = false,
    this.latchRt = false,
    this.latchLevelLt = 1.0,
    this.latchLevelRt = 1.0,
    this.steerLt = false,
    this.steerRt = false,
    this.aimLt = false,
    this.aimRt = false,
    this.aimFire = 1.8,
    this.turboRate = 12.0,
    this.showPing = true,
    Set<String>? toggles,
    List<String>? games,
    Set<String>? turbo,
    this.autoSprint = false,
    this.gyro = false,
    this.gyroSens = 1.0,
    this.gyroInvertY = false,
    this.tilt = false,
    this.tiltRightStick = false,
    this.tiltInvert = false,
    this.tiltSens = 1.0,
    this.tiltDeadzone = 2.0,
    this.tiltSmooth = 0.3,
    this.tiltCurve = 1.0,
    this.tiltCenter = 0.0,
    this.tiltAuto = false,
  })  : toggles = toggles ?? <String>{},
        games = games ?? <String>[],
        turbo = turbo ?? <String>{};

  Map<String, dynamic> toJson() => {
        'dzl': deadzoneL,
        'dzr': deadzoneR,
        'sl': sensL,
        'sr': sensR,
        'cl': curveL,
        'cr': curveR,
        'yl': yScaleL,
        'yr': yScaleR,
        'fl': floatLeft,
        'fr': floatRight,
        'hp': haptics,
        'rmb': rumble,
        'llt': latchLt,
        'lrt': latchRt,
        'llv': latchLevelLt,
        'rlv': latchLevelRt,
        'slt': steerLt,
        'srt': steerRt,
        'alt': aimLt,
        'art': aimRt,
        'af': aimFire,
        'tg': toggles.toList(),
        'ga': games,
        'tb': turbo.toList(),
        'tbr': turboRate,
        'spg': showPing,
        'asp': autoSprint,
        'gy': gyro,
        'gs': gyroSens,
        'gyi': gyroInvertY,
        'tilt': tilt,
        'tr': tiltRightStick,
        'ti': tiltInvert,
        'ts': tiltSens,
        'tdz': tiltDeadzone,
        'tsm': tiltSmooth,
        'tcv': tiltCurve,
        'tc': tiltCenter,
        'tac': tiltAuto,
      };

  static ProfileSettings fromJson(Object? j) {
    if (j is! Map) return ProfileSettings();
    double n(Object? v, double d) => v is num ? v.toDouble() : d;
    double c(Object? v, double d, double lo, double hi) =>
        n(v, d).clamp(lo, hi).toDouble();
    double sens(Object? v, Object? legacy) => n(v, n(legacy, 1))
        .clamp(LayoutStore.minSensitivity, LayoutStore.maxSensitivity)
        .toDouble();
    double dz(Object? v, Object? legacy) =>
        n(v, n(legacy, 0)).clamp(0.0, LayoutStore.maxDeadzone).toDouble();
    return ProfileSettings(
      // Older profiles stored one shared 'dz' / 'sens' for both sticks.
      deadzoneL: dz(j['dzl'], j['dz']),
      deadzoneR: dz(j['dzr'], j['dz']),
      sensL: sens(j['sl'], j['sens']),
      sensR: sens(j['sr'], j['sens']),
      curveL: c(j['cl'], 1, LayoutStore.minCurve, LayoutStore.maxCurve),
      curveR: c(j['cr'], 1, LayoutStore.minCurve, LayoutStore.maxCurve),
      yScaleL: c(j['yl'], 1, LayoutStore.minYScale, LayoutStore.maxYScale),
      yScaleR: c(j['yr'], 1, LayoutStore.minYScale, LayoutStore.maxYScale),
      floatLeft: j['fl'] == true,
      floatRight: j['fr'] == true,
      // Older versions stored a bool here.
      haptics: j['hp'] is int ? (j['hp'] as int).clamp(0, 2) : (j['hp'] == false ? 0 : 1),
      rumble: c(j['rmb'], 1, 0.0, 1.0),
      latchLt: j['llt'] == true,
      latchRt: j['lrt'] == true,
      latchLevelLt: c(j['llv'], 1, LayoutStore.minLatchLevel, 1.0),
      latchLevelRt: c(j['rlv'], 1, LayoutStore.minLatchLevel, 1.0),
      steerLt: j['slt'] == true,
      steerRt: j['srt'] == true,
      aimLt: j['alt'] == true,
      aimRt: j['art'] == true,
      aimFire: c(j['af'], 1.8, LayoutStore.minAimFire, LayoutStore.maxAimFire),
      toggles: j['tg'] is List
          ? {for (final e in j['tg'] as List) if (e is String) e}
          : <String>{},
      turbo: j['tb'] is List
          ? {for (final e in j['tb'] as List) if (e is String) e}
          : <String>{},
      turboRate: c(j['tbr'], 12, LayoutStore.minTurboRate, LayoutStore.maxTurboRate),
      showPing: j['spg'] != false,
      autoSprint: j['asp'] == true,
      gyro: j['gy'] == true,
      gyroSens: c(j['gs'], 1, LayoutStore.minTiltSens, LayoutStore.maxTiltSens),
      gyroInvertY: j['gyi'] == true,
      games: j['ga'] is List
          ? [for (final e in j['ga'] as List) if (e is String) e]
          : <String>[],
      tilt: j['tilt'] == true,
      tiltRightStick: j['tr'] == true,
      tiltInvert: j['ti'] == true,
      tiltSens: c(j['ts'], 1, LayoutStore.minTiltSens, LayoutStore.maxTiltSens),
      tiltDeadzone: c(j['tdz'], 2, 0.0, LayoutStore.maxTiltDeadzone),
      tiltSmooth: c(j['tsm'], 0.3, 0.0, 0.9),
      tiltCurve: c(j['tcv'], 1, LayoutStore.minCurve, LayoutStore.maxCurve),
      tiltCenter: c(j['tc'], 0, -90.0, 90.0),
      tiltAuto: j['tac'] == true,
    );
  }

  ProfileSettings copy() => ProfileSettings(
        deadzoneL: deadzoneL,
        deadzoneR: deadzoneR,
        sensL: sensL,
        sensR: sensR,
        curveL: curveL,
        curveR: curveR,
        yScaleL: yScaleL,
        yScaleR: yScaleR,
        floatLeft: floatLeft,
        floatRight: floatRight,
        haptics: haptics,
        rumble: rumble,
        latchLt: latchLt,
        latchRt: latchRt,
        latchLevelLt: latchLevelLt,
        latchLevelRt: latchLevelRt,
        steerLt: steerLt,
        steerRt: steerRt,
        aimLt: aimLt,
        aimRt: aimRt,
        aimFire: aimFire,
        toggles: {...toggles},
        games: [...games],
        turbo: {...turbo},
        turboRate: turboRate,
        showPing: showPing,
        autoSprint: autoSprint,
        gyro: gyro,
        gyroSens: gyroSens,
        gyroInvertY: gyroInvertY,
        tilt: tilt,
        tiltRightStick: tiltRightStick,
        tiltInvert: tiltInvert,
        tiltSens: tiltSens,
        tiltDeadzone: tiltDeadzone,
        tiltSmooth: tiltSmooth,
        tiltCurve: tiltCurve,
        tiltCenter: tiltCenter,
        tiltAuto: tiltAuto,
      );
}

class _Snapshot {
  final String profile;
  final _Profile data;
  _Snapshot(this.profile, this.data);
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
    // Older profiles had one combined "face" diamond: spread the four
    // buttons around where the diamond used to be.
    if (raw is Map && raw['face'] is Map) {
      final f = ItemLayout.fromJson(raw['face'], LayoutStore.faceLegacySpec);
      if (f != null) {
        const offs = {
          'btn_y': [0.0, -0.12],
          'btn_a': [0.0, 0.12],
          'btn_x': [-0.055, 0.0],
          'btn_b': [0.055, 0.0],
        };
        offs.forEach((id, o) {
          if (raw[id] != null) return;
          items[id] = ItemLayout(
            x: (f.x + o[0] * f.scale).clamp(0.0, 1.0).toDouble(),
            y: (f.y + o[1] * f.scale).clamp(0.0, 1.0).toDouble(),
            scale: f.scale,
            opacity: f.opacity,
            visible: f.visible,
          );
        });
      }
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
  static const double minSensitivity = 0.2;
  static const double maxSensitivity = 3.0;
  static const double minTiltSens = 0.3;
  static const double maxTiltSens = 3.0;
  static const double maxTiltDeadzone = 15.0;
  static const double minCurve = 1.0;
  static const double maxCurve = 3.0;
  static const double minYScale = 0.3;
  static const double maxYScale = 2.0;
  static const double minLatchLevel = 0.2;
  static const double minAimFire = 1.2;
  static const double maxAimFire = 3.0;

  // Capped at 20/s: the app sends input 60 times a second, so faster pulses
  // would be merged and some presses lost.
  static const double minTurboRate = 4.0;
  static const double maxTurboRate = 20.0;

  /// Only used to read the position of the old combined A/B/X/Y control.
  static const ItemSpec faceLegacySpec =
      ItemSpec('face', 'A / B / X / Y', 0.890, 0.620, 150, 150);

  /// Default positions copied from the original fixed layout.
  static const List<ItemSpec> specs = [
    // Top row: triggers in the corners, bumpers next to them.
    ItemSpec('lt', 'LT trigger', 0.080, 0.200, 100, 100),
    ItemSpec('lb', 'LB bumper', 0.215, 0.140, 80, 46),
    ItemSpec('rb', 'RB bumper', 0.785, 0.140, 80, 46),
    ItemSpec('rt', 'RT trigger', 0.920, 0.200, 100, 100),
    // Left thumb: D-pad + left stick.
    ItemSpec('dpad', 'D-pad', 0.115, 0.620, 180, 180, canColor: false),
    ItemSpec('lstick', 'Left stick', 0.335, 0.745, 160, 160,
        floatW: 260, floatH: 220),
    // Right thumb: right stick + A/B/X/Y diamond.
    ItemSpec('rstick', 'Right stick', 0.665, 0.745, 160, 160,
        floatW: 260, floatH: 220),
    ItemSpec('btn_y', 'Y button', 0.885, 0.455, 62, 62),
    ItemSpec('btn_a', 'A button', 0.885, 0.745, 62, 62),
    ItemSpec('btn_x', 'X button', 0.820, 0.600, 62, 62),
    ItemSpec('btn_b', 'B button', 0.950, 0.600, 62, 62),
    // Centre cluster.
    ItemSpec('disconnect', 'Disconnect', 0.500, 0.065, 44, 44, canHide: false),
    ItemSpec('back', 'Back (menu)', 0.405, 0.220, 56, 56),
    ItemSpec('guide', 'Guide', 0.500, 0.220, 64, 64),
    ItemSpec('start', 'Start', 0.595, 0.220, 56, 56),
    ItemSpec('l3', 'L3 (left stick click)', 0.435, 0.440, 80, 44),
    ItemSpec('r3', 'R3 (right stick click)', 0.565, 0.440, 80, 44),
  ];

  static final Map<String, ItemSpec> _specById = {
    for (final s in specs) s.id: s,
  };

  final Map<String, _Profile> _profiles = {
    defaultProfileName: _Profile.defaults(),
  };
  String _active = defaultProfileName;

  /// Switch profiles automatically when the PC reports a known game.
  bool autoSwitch = false;

  // ───────────── undo (editor) ─────────────
  final List<_Snapshot> _undo = [];
  String? _lastCheckpointGroup;
  DateTime _lastCheckpointAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get canUndo => _undo.any((s) => s.profile == _active);

  /// Remembers the active profile so [undo] can bring it back. Calls with the
  /// same [group] within 1.5 s (a slider drag, repeated nudges) count as one.
  void checkpoint({String? group}) {
    final now = DateTime.now();
    if (group != null &&
        group == _lastCheckpointGroup &&
        now.difference(_lastCheckpointAt).inMilliseconds < 1500) {
      _lastCheckpointAt = now;
      return;
    }
    _lastCheckpointGroup = group;
    _lastCheckpointAt = now;
    _undo.add(_Snapshot(_active, _profiles[_active]!.copy()));
    if (_undo.length > 40) _undo.removeAt(0);
  }

  void undo() {
    final i = _undo.lastIndexWhere((s) => s.profile == _active);
    if (i < 0) return;
    _profiles[_active] = _undo.removeAt(i).data;
    _lastCheckpointGroup = null;
    notifyListeners();
  }

  void clearUndo() {
    _undo.clear();
    _lastCheckpointGroup = null;
  }

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
    _profiles[n]!.settings.games.clear(); // a game maps to one profile only
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
      _profiles[n]!.settings.games.clear();
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

  void setDeadzone(bool left, double v) {
    final c = v.clamp(0.0, maxDeadzone).toDouble();
    if (left) {
      settings.deadzoneL = c;
    } else {
      settings.deadzoneR = c;
    }
    notifyListeners();
  }

  void setSensitivity(bool left, double v) {
    final c = v.clamp(minSensitivity, maxSensitivity).toDouble();
    if (left) {
      settings.sensL = c;
    } else {
      settings.sensR = c;
    }
    notifyListeners();
  }

  void setLatch(bool left, bool v) {
    if (left) {
      settings.latchLt = v;
    } else {
      settings.latchRt = v;
    }
    notifyListeners();
  }

  void setSteer(bool left, bool v) {
    if (left) {
      settings.steerLt = v;
    } else {
      settings.steerRt = v;
    }
    notifyListeners();
  }

  /// Applies [fn] to the profile's settings and notifies listeners.
  void tweak(void Function(ProfileSettings s) fn) {
    fn(settings);
    notifyListeners();
  }

  // ───────────── auto-switch by game ─────────────
  static String normApp(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\.exe$'), '');

  void setAutoSwitch(bool v) {
    autoSwitch = v;
    notifyListeners();
  }

  /// Profile that lists [app] as one of its games, or null.
  String? profileForApp(String app) {
    final a = normApp(app);
    for (final e in _profiles.entries) {
      if (e.value.settings.games.contains(a)) return e.key;
    }
    return null;
  }

  /// Assigns [app] to the active profile (and removes it from any other).
  void addGame(String app) {
    final a = normApp(app);
    if (a.isEmpty) return;
    for (final p in _profiles.values) {
      p.settings.games.remove(a);
    }
    settings.games.add(a);
    notifyListeners();
  }

  void removeGame(String app) {
    settings.games.remove(normApp(app));
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
    checkpoint();
    final s = spec(id);
    _profiles[_active]!.items[id] = ItemLayout(x: s.x, y: s.y);
    if (id == 'lstick') settings.floatLeft = false;
    if (id == 'rstick') settings.floatRight = false;
    notifyListeners();
  }

  /// Resets the active profile only.
  void resetAll() {
    checkpoint();
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
            autoSwitch = data['auto'] == true;
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
          'auto': autoSwitch,
          'profiles': {for (final e in _profiles.entries) e.key: e.value.toJson()},
        }),
      );
    } catch (_) {}
  }
}
