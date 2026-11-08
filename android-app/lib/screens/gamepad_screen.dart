import 'dart:async'; // Added to handle stream subscriptions
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../network/rumble_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/gamepad_state.dart';
import '../models/layout_store.dart';
import '../network/gamepad_socket.dart';
import '../network/player_name.dart';
import '../network/protocol.dart';
import '../theme.dart';
import '../widgets/dpad_widget.dart';
import '../widgets/floating_joystick_widget.dart';
import '../widgets/gamepad_button_widget.dart';
import '../widgets/joystick_widget.dart';
import '../widgets/app_background.dart';
import '../widgets/trigger_widget.dart';
import 'layout_editor.dart';

class GamepadScreen extends StatefulWidget {
  /// The live connection. Null in [editorOnly] mode.
  final GamepadSocket? socket;

  /// Layout editor opened from the menu, before connecting to a PC.
  final bool editorOnly;

  const GamepadScreen({super.key, this.socket, this.editorOnly = false});

  @override
  State<GamepadScreen> createState() => _GamepadScreenState();
}

class _GamepadScreenState extends State<GamepadScreen> {
  late final GamepadState _state;
  GamepadSocket? _ownSocket; // throwaway socket for the offline editor
  StreamSubscription? _connectionSubscription; // Handles the socket listener state
  StreamSubscription<String>? _appSub; // PC foreground-app reports
  StreamSubscription<List<int>>? _rumbleSub; // game rumble from the PC
  final RumblePlayer _rumble = RumblePlayer();
  String? _lastApp; // last app the PC reported

  // Track D-pad states to only vibrate when a direction is freshly clicked down
  bool _upPressed = false;
  bool _downPressed = false;
  bool _leftPressed = false;
  bool _rightPressed = false;

  // Track Trigger steps locally so they click at distinct thresholds (e.g., 10%, 50%, 90%)
  int _leftTriggerStep = 0;
  int _rightTriggerStep = 0;

  // Track Joystick center deadzones locally to tick right when exiting the middle
  bool _leftStickActive = false;
  bool _rightStickActive = false;

  // Customisable layout (positions / size / opacity / visibility)
  final LayoutStore _layout = LayoutStore();
  bool _editing = false;
  bool _snap = false; // align dragged controls to a grid
  Offset? _dragRaw; // finger-accurate centre while dragging
  static const double _grid = 20;
  String? _selected;
  double? _guideX, _guideY; // alignment guides shown while dragging

  // Tilt steering
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  double _fz = 0; // smoothed accelerometer z (gravity direction for gyro aim)
  bool _autoSprintOn = false;
  final ValueNotifier<double> _tiltPreview = ValueNotifier(0);
  double _fx = 0, _fy = 0; // smoothed accelerometer x / y
  bool _fInit = false;
  double _orient = 1; // +1 / -1: landscape-left vs landscape-right
  double _tiltAngle = 0; // current wheel angle in degrees (+ = clockwise)
  DateTime? _calUntil; // auto-centre window end
  double _calS = 0, _calC = 0; // running sin / cos sums for the average angle

  bool _tg(String id) => _layout.settings.toggles.contains(id);
  bool _tb(String id) => _layout.settings.turbo.contains(id);

  /// Half of one turbo press/release cycle, from the "Turbo speed" setting.
  int get _turboHalfMs =>
      (500 / _layout.settings.turboRate).round().clamp(15, 125).toInt();

  // Connection quality shown on screen: round-trip time and reconnecting state.
  final ValueNotifier<int?> _ping = ValueNotifier<int?>(null);
  final ValueNotifier<bool> _reconnecting = ValueNotifier<bool>(false);
  StreamSubscription<int>? _pingSub;
  StreamSubscription<bool>? _reconnectSub;

  @override
  void initState() {
    super.initState();
    if (widget.socket == null) _ownSocket = GamepadSocket();
    _state = GamepadState(widget.socket ?? _ownSocket!);
    if (widget.editorOnly) {
      _editing = true; // open straight in edit mode
    } else {
      _state.start();
    }
    _appSub = widget.socket?.activeAppStream.listen(_onActiveApp);
    _rumble.init();
    _rumbleSub = widget.socket?.rumbleStream
        .listen((m) => _rumble.update(m[0], m[1], _layout.settings.rumble));
    _pingSub = widget.socket?.pingStream.listen((ms) => _ping.value = ms);
    _reconnectSub = widget.socket?.reconnectingStream.listen(_onReconnecting);
    _layout.addListener(_syncTilt);
    _layout.load();
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Listen for disconnections automatically from the socket network manager
    _connectionSubscription = widget.socket?.connectionStream.listen((isConnected) {
      if (!isConnected) {
        _handleConnectionLoss();
      }
    });
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel(); // Cancel network listeners to prevent memory leaks
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _appSub?.cancel();
    _rumbleSub?.cancel();
    _pingSub?.cancel();
    _reconnectSub?.cancel();
    _ping.dispose();
    _reconnecting.dispose();
    _rumble.dispose();
    _tiltPreview.dispose();
    _state.stop();
    _layout.save();
    _layout.removeListener(_syncTilt);
    _layout.dispose();
    _ownSocket?.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  /// The PC stopped answering (or answers again): the socket keeps trying by
  /// itself, we only tell the player and make sure nothing stays held.
  void _onReconnecting(bool v) {
    _reconnecting.value = v;
    if (v) {
      HapticFeedback.heavyImpact();
      _releaseAll();
    }
  }

  /// Small badge at the top centre: ping in ms, or "Reconnecting…".
  Widget _netBadge() {
    return Positioned(
      top: 6,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: ValueListenableBuilder<bool>(
            valueListenable: _reconnecting,
            builder: (context, reconnecting, _) {
              return ValueListenableBuilder<int?>(
                valueListenable: _ping,
                builder: (context, ping, _) {
                  if (!reconnecting && (ping == null || !_layout.settings.showPing)) {
                    return const SizedBox.shrink();
                  }
                  final p = ping ?? 0;
                  final Color color = reconnecting
                      ? AppColors.warning
                      : (p < 40
                          ? AppColors.success
                          : (p < 90 ? AppColors.warning : AppColors.danger));
                  final String text = reconnecting ? 'Reconnecting…' : '$p ms';
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      text,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  /// Automatically safely updates UI state and resets navigation back to the connection layout
  void _handleConnectionLoss() {
    if (!mounted) return;

    // Fire an aggressive vibration alert so the user notices the drop immediately
    HapticFeedback.heavyImpact();

    // Notify the user via a quick temporary banner notification overlay
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Connection lost! Returning to menu...'),
        duration: Duration(seconds: 2),
      ),
    );

    // Clears any active popups or dialogs and steps cleanly back to the absolute base view
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Color? _colorOf(String id) {
    final c = _layout.of(id).color;
    return c == null ? null : Color(c);
  }

  Color _colorOr(String id, Color fallback) => _colorOf(id) ?? fallback;

  // ───────────────────── Auto profile by game ─────────────────────

  void _onActiveApp(String app) {
    final changed = app != _lastApp;
    _lastApp = app;
    if (changed && _editing && mounted) setState(() {}); // refresh "Add <game>"
    _applyAutoProfile();
  }

  void _applyAutoProfile() {
    final app = _lastApp;
    if (app == null || !_layout.autoSwitch || _editing) return;
    final target = _layout.profileForApp(app);
    if (target == null || target == _layout.active) return;
    _releaseAll();
    _layout.switchTo(target);
    _layout.save();
    _toast('Profile: $target');
  }

  void _addGame(String name) {
    _layout.addGame(name);
    _layout.save();
    _toast('"${LayoutStore.normApp(name)}" → profile "${_layout.active}"');
  }

  /// Releases everything held on the PC and resets local haptic trackers.
  void _releaseAll() {
    _state.releaseAll();
    _leftTriggerStep = _rightTriggerStep = 0;
    _leftStickActive = _rightStickActive = false;
    _autoSprintOn = false;
  }

  // ───────────────────────── Tilt steering ─────────────────────────

  /// Averages the wheel angle for one second and uses it as "straight".
  void _beginAutoCal() {
    if (!_layout.settings.tiltAuto) return;
    _calUntil = DateTime.now().add(const Duration(seconds: 1));
    _calS = 0;
    _calC = 0;
  }

  void _syncTilt() {
    final cfg = _layout.settings;
    final wantGyro = cfg.gyro;
    if (wantGyro && _gyroSub == null) {
      try {
        _gyroSub = gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval)
            .listen(_onGyro, onError: (_) {
          _gyroSub?.cancel();
          _gyroSub = null;
          _toast('Gyroscope not available on this device');
        });
      } catch (_) {
        _gyroSub = null;
        _toast('Gyroscope not available on this device');
      }
    } else if (!wantGyro && _gyroSub != null) {
      _gyroSub!.cancel();
      _gyroSub = null;
      _state.gyroRx = _state.gyroRy = null;
    }

    // The accelerometer serves tilt steering and (for gravity) gyro aiming.
    final want = cfg.tilt || cfg.gyro;
    if (want && _accelSub == null) {
      _fInit = false;
      _beginAutoCal();
      try {
        _accelSub = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval)
            .listen(_onAccel, onError: (_) {
          _accelSub?.cancel();
          _accelSub = null;
          _toast('Tilt sensor not available on this device');
        });
      } catch (_) {
        _accelSub = null;
        _toast('Tilt sensor not available on this device');
      }
    } else if (!want && _accelSub != null) {
      _accelSub!.cancel();
      _accelSub = null;
      _tiltPreview.value = 0;
      _state.tiltLx = _state.tiltRx = null;
    }
  }

  /// Phone held in landscape like a steering wheel: turning it clockwise
  /// shifts gravity between the device's x and y axes.
  void _onAccel(AccelerometerEvent e) {
    final st = _layout.settings;
    if (!_fInit) {
      _fx = e.x;
      _fy = e.y;
      _fz = e.z;
      _fInit = true;
    } else {
      final k = 1.0 - st.tiltSmooth;
      _fx += (e.x - _fx) * k;
      _fy += (e.y - _fy) * k;
      _fz += (e.z - _fz) * k;
    }

    double steer = 0;
    // If the phone lies flat there is no wheel angle to read.
    if (math.sqrt(_fx * _fx + _fy * _fy) > 3.0) {
      if (_fx.abs() > 4.0) _orient = _fx >= 0 ? 1.0 : -1.0; // landscape L/R
      final deg = math.atan2(_fy * _orient, _fx * _orient) * 180 / math.pi;
      _tiltAngle = deg;

      final until = _calUntil;
      if (until != null) {
        if (DateTime.now().isBefore(until)) {
          final rad = deg * math.pi / 180;
          _calS += math.sin(rad);
          _calC += math.cos(rad);
          st.tiltCenter = math.atan2(_calS, _calC) * 180 / math.pi;
        } else {
          _calUntil = null;
          _layout.save();
        }
      }

      var d = deg - st.tiltCenter;
      if (d > 180) d -= 360;
      if (d < -180) d += 360;
      if (st.tiltInvert) d = -d;

      final dz = st.tiltDeadzone;
      var full = 45.0 / st.tiltSens; // degrees for full lock
      if (full < dz + 1) full = dz + 1;
      final m = d.abs();
      if (m > dz) {
        final t = ((m - dz) / (full - dz)).clamp(0.0, 1.0).toDouble();
        steer = math.pow(t, st.tiltCurve).toDouble() * (d < 0 ? -1.0 : 1.0);
      }
    }

    if (!st.tilt) {
      // Sensor is only running for gyro aiming.
      _state.tiltLx = _state.tiltRx = null;
      return;
    }
    _tiltPreview.value = steer;
    if (_editing || widget.editorOnly) {
      _state.tiltLx = _state.tiltRx = null;
      return;
    }
    if (st.tiltRightStick) {
      _state.tiltLx = null;
      _state.tiltRx = steer;
    } else {
      _state.tiltRx = null;
      _state.tiltLx = steer;
    }
  }

  /// A trigger being slid: drives the right stick (with its sensitivity).
  void _handleTriggerSteer(double x, double y, bool active) {
    if (!active) {
      _state.trigRx = _state.trigRy = null;
      return;
    }
    final v = _shape(x, y, left: false);
    _state.trigRx = v[0];
    _state.trigRy = v[1];
  }

  /// Gyro aiming: turning the phone moves the right stick. Yaw is measured
  /// around the true vertical axis (from gravity) so it works at any hold angle.
  void _onGyro(GyroscopeEvent e) {
    final st = _layout.settings;
    if (!st.gyro || _editing || widget.editorOnly) {
      _state.gyroRx = _state.gyroRy = null;
      return;
    }
    final g = math.sqrt(_fx * _fx + _fy * _fy + _fz * _fz);
    if (g < 5.0) return; // no gravity reading yet
    final yaw = (_fx * e.x + _fy * e.y + _fz * e.z) / g; // rad/s, CCW positive
    final pitch = -e.y * _orient; // pointing up = positive

    double dead(double r) {
      const dz = 0.05; // ignore hand tremor
      final m = r.abs();
      return m < dz ? 0.0 : (m - dz) * (r < 0 ? -1.0 : 1.0);
    }

    final k = 0.5 * st.gyroSens; // full stick at ~2 rad/s with sensitivity 1
    _state.gyroRx = (-dead(yaw) * k).clamp(-1.0, 1.0).toDouble();
    _state.gyroRy =
        (dead(pitch) * k * (st.gyroInvertY ? -1.0 : 1.0)).clamp(-1.0, 1.0).toDouble();
  }

  /// Auto-sprint: click L3 while the left stick is held fully forward.
  void _updateAutoSprint(double x, double y) {
    if (!_layout.settings.autoSprint) {
      if (_autoSprintOn) {
        _autoSprintOn = false;
        _state.setButton(Protocol.bitLsClick, false);
      }
      return;
    }
    final m = math.sqrt(x * x + y * y);
    final want = _autoSprintOn ? (m > 0.8 && y > 0.3) : (m > 0.95 && y > 0.5);
    if (want == _autoSprintOn) return;
    _autoSprintOn = want;
    _state.setButton(Protocol.bitLsClick, want);
  }

  void _calibrateTilt() {
    _layout.tweak((s) => s.tiltCenter = _tiltAngle);
    _layout.save();
    HapticFeedback.selectionClick();
  }

  /// Light vibration, unless the active profile turned vibration off.
  void _buzz() {
    switch (_layout.settings.haptics) {
      case 1:
        HapticFeedback.lightImpact();
        break;
      case 2:
        HapticFeedback.mediumImpact();
        break;
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  void _disconnect() {
    _buzz();
    final socket = widget.socket;
    if (socket == null) {
      Navigator.of(context).pop(); // offline editor: just leave
      return;
    }
    socket.disconnect();
    // No explicit call to pop() is needed here anymore! 
    // widget.socket.disconnect() will push a value to 'connectionStream', 
    // triggering _handleConnectionLoss() naturally.
  }

  /// Handles standard button haptics cleanly — fires only on down-press
  void _handleButtonPress(int buttonBit, bool isPressed) {
    if (isPressed) {
      _buzz();
    }
    _state.setButton(buttonBit, isPressed);
  }

  /// Handles analog triggers: vibrates dynamically at progressive pull thresholds
  void _handleTriggerHaptic(double value, bool isLeft) {
    // Determine a step integer from 0 to 3 based on pressure deepness
    int currentStep = 0;
    if (value > 0.9) {
      currentStep = 3;
    } else if (value > 0.5) {
      currentStep = 2;
    } else if (value > 0.1) {
      currentStep = 1;
    }

    final oldStep = isLeft ? _leftTriggerStep : _rightTriggerStep;
    if (currentStep != oldStep) {
      // Tick on both pulling further down and popping all the way back out
      if (currentStep > oldStep || currentStep == 0) {
        _buzz();
      }
      if (isLeft) {
        _leftTriggerStep = currentStep;
      } else {
        _rightTriggerStep = currentStep;
      }
    }
  }

  /// Handles joystick deadzones: vibrates exactly when the stick breaks out of center rest
  void _handleJoystickHaptic(double x, double y, bool isLeft) {
    // Check vector distance from center point (0,0)
    final bool isMoving = (x * x + y * y) > 0.04; // ~20% tilt radius threshold
    final oldActive = isLeft ? _leftStickActive : _rightStickActive;

    if (isMoving && !oldActive) {
      _buzz(); // Click when passing out of deadzone range
    }

    if (isLeft) {
      _leftStickActive = isMoving;
    } else {
      _rightStickActive = isMoving;
    }
  }

  // ───────────────────────── Layout customisation ─────────────────────────

  void _enterEdit() {
    HapticFeedback.selectionClick();
    _releaseAll(); // nothing stays "held" on the PC while editing
    _layout.clearUndo();
    setState(() {
      _editing = true;
      _selected = null;
    });
  }

  void _exitEdit() {
    _layout.save();
    if (widget.editorOnly) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _editing = false;
      _selected = null;
    });
    _beginAutoCal();
  }

  /// Centre of a control in pixels, kept fully inside the play area.
  Offset _clampCenter(String id, BoxConstraints c, double cx, double cy) {
    final it = _layout.of(id);
    final halfW = _layout.boxW(id) * it.scale / 2;
    final halfH = _layout.boxH(id) * it.scale / 2;
    return Offset(
      cx.clamp(halfW, math.max(halfW, c.maxWidth - halfW)).toDouble(),
      cy.clamp(halfH, math.max(halfH, c.maxHeight - halfH)).toDouble(),
    );
  }

  Offset _center(String id, BoxConstraints c) {
    final it = _layout.of(id);
    return _clampCenter(id, c, c.maxWidth * it.x, c.maxHeight * it.y);
  }

  void _drag(String id, Offset delta, BoxConstraints c) {
    var raw = (_dragRaw ?? _center(id, c)) + delta;
    raw = _clampCenter(id, c, raw.dx, raw.dy);
    _dragRaw = raw;
    var t = raw;
    _guideX = _guideY = null;
    if (_snap) {
      t = _clampCenter(id, c, (raw.dx / _grid).round() * _grid,
          (raw.dy / _grid).round() * _grid);
    } else {
      // Magnet guides: line up with the screen centre and other controls.
      const tol = 7.0;
      double bestX = tol, bestY = tol;
      double? gx, gy;
      void consider(double ox, double oy) {
        final dx = (raw.dx - ox).abs();
        final dy = (raw.dy - oy).abs();
        if (dx < bestX) {
          bestX = dx;
          gx = ox;
        }
        if (dy < bestY) {
          bestY = dy;
          gy = oy;
        }
      }

      consider(c.maxWidth / 2, c.maxHeight / 2);
      for (final s in LayoutStore.specs) {
        if (s.id == id || !_layout.of(s.id).visible) continue;
        final o = _center(s.id, c);
        consider(o.dx, o.dy);
      }
      t = Offset(gx ?? raw.dx, gy ?? raw.dy);
      _guideX = gx;
      _guideY = gy;
      t = _clampCenter(id, c, t.dx, t.dy);
    }
    _layout.setPosition(id, t.dx / c.maxWidth, t.dy / c.maxHeight);
  }

  /// Places [child] according to the saved layout. In edit mode the child is
  /// frozen and the whole box becomes draggable / selectable.
  Widget _item(String id, BoxConstraints c, Widget child) {
    final it = _layout.of(id);
    // Must stay a Positioned: a plain non-positioned child makes the Stack
    // collapse to 0x0 and every other control vanishes.
    if (!it.visible && !_editing) {
      return const Positioned(
        left: 0,
        top: 0,
        width: 0,
        height: 0,
        child: SizedBox.shrink(),
      );
    }

    final bw = _layout.boxW(id);
    final bh = _layout.boxH(id);
    final w = bw * it.scale;
    final h = bh * it.scale;
    final ctr = _center(id, c);
    final left = ctr.dx - w / 2;
    final top = ctr.dy - h / 2;

    // FittedBox scales the control AND its hit area together.
    final content = FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
          width: bw,
          height: bh,
          child: Center(
            child: KeyedSubtree(
              key: ValueKey('$id|${_layout.active}|${_tg(id)}|${_tb(id)}'),
              child: child,
            ),
          ),
        ),
    );

    if (!_editing) {
      return Positioned(
        left: left,
        top: top,
        width: w,
        height: h,
        child: Opacity(opacity: it.opacity, child: content),
      );
    }

    final selected = _selected == id;
    return Positioned(
      left: left,
      top: top,
      width: w,
      height: h,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _selected = id),
        onPanStart: (_) {
          _layout.checkpoint();
          setState(() {
            _selected = id;
            _dragRaw = _center(id, c);
          });
        },
        onPanUpdate: (d) => _drag(id, d.delta, c),
        onPanEnd: (_) {
          _dragRaw = null;
          setState(() => _guideX = _guideY = null);
          _layout.save();
        },
        onPanCancel: () {
          _dragRaw = null;
          setState(() => _guideX = _guideY = null);
        },
        child: Stack(
          children: [
            Opacity(
              opacity: it.visible ? it.opacity : 0.25,
              child: IgnorePointer(child: content),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: selected ? AppColors.activeAccent : Colors.white38,
                      width: selected ? 2.5 : 1,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                                color: AppColors.activeAccent.withOpacity(0.45),
                                blurRadius: 12)
                          ]
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Applies that stick's deadzone, curve, sensitivity and Y gain to a raw
  /// stick vector.
  List<double> _shape(double x, double y, {required bool left}) {
    final s = _layout.settings;
    final dz = left ? s.deadzoneL : s.deadzoneR;
    final gain = left ? s.sensL : s.sensR;
    final curve = left ? s.curveL : s.curveR;
    final yGain = left ? s.yScaleL : s.yScaleR;
    final m = math.sqrt(x * x + y * y);
    if (m <= dz || m == 0) return const [0.0, 0.0];
    final t = ((m - dz) / (1 - dz)).clamp(0.0, 1.0).toDouble();
    final scaled = (math.pow(t, curve).toDouble() * gain).clamp(0.0, 1.0).toDouble();
    return [
      (x / m * scaled).clamp(-1.0, 1.0).toDouble(),
      (y / m * scaled * yGain).clamp(-1.0, 1.0).toDouble(),
    ];
  }

  Future<String?> _askName(String title, String initial,
      {String hint = 'Profile name'}) async {
    final ctrl = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 40,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('OK')),
        ],
      ),
    );
    ctrl.dispose();
    return (r == null || r.isEmpty) ? null : r;
  }

  Future<void> _renamePlayer() async {
    final current = await PlayerName.load();
    final n = await _askName('Player name', current, hint: 'Your name');
    if (n == null) return;
    final name = PlayerName.clean(n);
    await PlayerName.save(name);
    widget.socket?.rename(name);
    _toast('Player name: $name');
  }

  Future<void> _copyProfile() async {
    await Clipboard.setData(ClipboardData(text: _layout.exportActive()));
    _toast('Layout "${_layout.active}" copied — paste it anywhere to share');
  }

  Future<void> _pasteProfile() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    final name = text == null ? null : _layout.importProfile(text);
    if (name == null) {
      _toast('Clipboard has no Virtual Gamepad layout');
      return;
    }
    _layout.save();
    _toast('Imported "$name"');
  }

  /// Moves the selected control by a few pixels (editor arrow buttons).
  void _nudge(double dx, double dy, BoxConstraints c) {
    final id = _selected;
    if (id == null) return;
    final ctr = _center(id, c);
    final t = _clampCenter(id, c, ctr.dx + dx, ctr.dy + dy);
    _layout.setPosition(id, t.dx / c.maxWidth, t.dy / c.maxHeight);
    _layout.save();
  }

  Offset _editButtonTopLeft(BoxConstraints c) {
    final d = _layout.of('disconnect');
    const size = 36.0;
    final ctr = _center('disconnect', c);
    final cx = ctr.dx + _layout.boxW('disconnect') * d.scale / 2 + size / 2 + 6;
    return Offset(
      (cx - size / 2).clamp(0.0, math.max(0.0, c.maxWidth - size)).toDouble(),
      (ctr.dy - size / 2).clamp(0.0, math.max(0.0, c.maxHeight - size)).toDouble(),
    );
  }

  /// Small pencil button that sits next to the Disconnect button.
  Widget _editButton(BoxConstraints c) {
    final p = _editButtonTopLeft(c);
    return Positioned(
      left: p.dx,
      top: p.dy,
      width: 36,
      height: 36,
      child: GestureDetector(
        onTap: _enterEdit,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.4),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.activeAccent.withOpacity(0.5)),
          ),
          child: const Icon(Icons.edit, color: AppColors.activeAccent, size: 18),
        ),
      ),
    );
  }

  /// Tap to set the current phone angle as "straight" (tilt steering only).
  Widget _calibChip(BoxConstraints c) {
    final p = _editButtonTopLeft(c);
    return Positioned(
      left: p.dx,
      top: p.dy + 42,
      width: 36,
      height: 36,
      child: GestureDetector(
        onTap: _calibrateTilt,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.screen_rotation, color: Colors.white70, size: 18),
        ),
      ),
    );
  }

  /// Tap to jump to the next layout profile (only shown with 2+ profiles).
  Widget _profileChip(BoxConstraints c) {
    final p = _editButtonTopLeft(c);
    return Positioned(
      left: p.dx + 42,
      top: p.dy,
      height: 36,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _releaseAll();
          _layout.nextProfile();
          _layout.save();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.35),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.layers, color: Colors.white70, size: 14),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _layout.active,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.editorOnly || !_editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _editing) _exitEdit();
      },
      child: Scaffold(
        backgroundColor: AppColors.gamepadBottom,
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.4,
              colors: [AppColors.gamepadTop, AppColors.gamepadBottom],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, c) {
                return ListenableBuilder(
                  listenable: _layout,
                  builder: (context, _) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        const Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(painter: HudGridPainter(step: 40, opacity: 0.03)),
                          ),
                        ),
                        if (_editing && _snap)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(painter: _GridPainter(_grid)),
                            ),
                          ),
                        // Tap on empty space = deselect.
                        if (_editing)
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => setState(() => _selected = null),
                            ),
                          ),
                        // LT - Left Trigger
                        _item(
                            'lt',
                            c,
                            TriggerWidget(
                              key: ValueKey('lt-${_layout.active}'),
                              label: 'LT',
                              color: _colorOf('lt'),
                              latchEnabled: _layout.settings.latchLt,
                              steerEnabled: _layout.settings.steerLt,
                              aimEnabled: _layout.settings.aimLt,
                              aimFireK: _layout.settings.aimFire,
                              turbo: _tb('lt'),
                              turboHalfMs: _turboHalfMs,
                              onPulse: (v) => _state.setLeftTrigger(v),
                              latchLevel: _layout.settings.latchLevelLt,
                              onSteer: _handleTriggerSteer,
                              onLatchChanged: (_) => HapticFeedback.mediumImpact(),
                              size: 100,
                              onChanged: (v) {
                                _handleTriggerHaptic(v, true);
                                _state.setLeftTrigger(v);
                              },
                            )),

                        // LB - Left Bumper
                        _item(
                            'lb',
                            c,
                            GamepadButtonWidget(
                              label: 'LB',
                              pill: true,
                              size: 42,
                              color: _colorOr('lb', AppColors.stickFill),
                              toggle: _tg('lb'),
                              turbo: _tb('lb'),
                              turboHalfMs: _turboHalfMs,
                              onChanged: (p) => _handleButtonPress(Protocol.bitLb, p),
                              onPulse: (p) => _state.setButton(Protocol.bitLb, p),
                            )),

                        // D-pad
                        _item(
                            'dpad',
                            c,
                            DpadWidget(
                              size: 150,
                              onChanged: ({required up, required down, required left, required right}) {
                                if ((up && !_upPressed) ||
                                    (down && !_downPressed) ||
                                    (left && !_leftPressed) ||
                                    (right && !_rightPressed)) {
                                  _buzz();
                                }
                                _upPressed = up;
                                _downPressed = down;
                                _leftPressed = left;
                                _rightPressed = right;

                                _state.setDpad(up: up, down: down, left: left, right: right);
                              },
                            )),

                        // Disconnect
                        _item(
                            'disconnect',
                            c,
                            GestureDetector(
                              onTap: _disconnect,
                              child: Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                    color: _colorOr('disconnect', AppColors.stickFill),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white.withOpacity(0.35), width: 2),
                                    boxShadow: [
                                      BoxShadow(
                                          color: AppColors.danger.withOpacity(0.35),
                                          blurRadius: 10),
                                    ]),
                                child: const Icon(Icons.close, color: Colors.white, size: 20),
                              ),
                            )),

                        // Menu / Guide / Start
                        _item(
                            'back',
                            c,
                            GamepadButtonWidget(
                              label: '',
                              icon: Icons.menu,
                              size: 56,
                              color: _colorOr('back', AppColors.stickFill),
                              toggle: _tg('back'),
                              turbo: _tb('back'),
                              turboHalfMs: _turboHalfMs,
                              onChanged: (p) => _handleButtonPress(Protocol.bitBack, p),
                              onPulse: (p) => _state.setButton(Protocol.bitBack, p),
                            )),
                        _item(
                            'guide',
                            c,
                            GamepadButtonWidget(
                              label: '',
                              icon: Icons.sports_esports,
                              size: 64,
                              color: _colorOr('guide', AppColors.stickFill),
                              toggle: _tg('guide'),
                              turbo: _tb('guide'),
                              turboHalfMs: _turboHalfMs,
                              onChanged: (p) => _handleButtonPress(Protocol.bitGuide, p),
                              onPulse: (p) => _state.setButton(Protocol.bitGuide, p),
                            )),
                        _item(
                            'start',
                            c,
                            GamepadButtonWidget(
                              label: '',
                              icon: Icons.tune,
                              size: 56,
                              color: _colorOr('start', AppColors.stickFill),
                              toggle: _tg('start'),
                              turbo: _tb('start'),
                              turboHalfMs: _turboHalfMs,
                              onChanged: (p) => _handleButtonPress(Protocol.bitStart, p),
                              onPulse: (p) => _state.setButton(Protocol.bitStart, p),
                            )),

                        // L3 / R3 stick clicks
                        _item(
                            'l3',
                            c,
                            GamepadButtonWidget(
                              label: 'LEFT',
                              pill: true,
                              size: 40,
                              color: _colorOr('l3', AppColors.stickFill),
                              toggle: _tg('l3'),
                              turbo: _tb('l3'),
                              turboHalfMs: _turboHalfMs,
                              onChanged: (p) => _handleButtonPress(Protocol.bitLsClick, p),
                              onPulse: (p) => _state.setButton(Protocol.bitLsClick, p),
                            )),
                        _item(
                            'r3',
                            c,
                            GamepadButtonWidget(
                              label: 'RIGHT',
                              pill: true,
                              size: 40,
                              color: _colorOr('r3', AppColors.stickFill),
                              toggle: _tg('r3'),
                              turbo: _tb('r3'),
                              turboHalfMs: _turboHalfMs,
                              onChanged: (p) => _handleButtonPress(Protocol.bitRsClick, p),
                              onPulse: (p) => _state.setButton(Protocol.bitRsClick, p),
                            )),

                        // Sticks
                        _item(
                            'lstick',
                            c,
                            _layout.isFloating('lstick')
                                ? FloatingJoystickWidget(
                                    width: _layout.boxW('lstick'),
                                    height: _layout.boxH('lstick'),
                                    label: 'L',
                                    color: _colorOf('lstick'),
                                    onChanged: (x, y) {
                                      _handleJoystickHaptic(x, y, true);
                                      final v = _shape(x, y, left: true);
                                      _state.setLeftStick(v[0], v[1]);
                                      _updateAutoSprint(v[0], v[1]);
                                    },
                                  )
                                : JoystickWidget(
                                    size: 160,
                                    color: _colorOf('lstick'),
                                    onChanged: (x, y) {
                                      _handleJoystickHaptic(x, y, true);
                                      final v = _shape(x, y, left: true);
                                      _state.setLeftStick(v[0], v[1]);
                                      _updateAutoSprint(v[0], v[1]);
                                    },
                                  )),
                        _item(
                            'rstick',
                            c,
                            _layout.isFloating('rstick')
                                ? FloatingJoystickWidget(
                                    width: _layout.boxW('rstick'),
                                    height: _layout.boxH('rstick'),
                                    label: 'R',
                                    color: _colorOf('rstick'),
                                    onChanged: (x, y) {
                                      _handleJoystickHaptic(x, y, false);
                                      final v = _shape(x, y, left: false);
                                      _state.setRightStick(v[0], v[1]);
                                    },
                                  )
                                : JoystickWidget(
                                    size: 160,
                                    color: _colorOf('rstick'),
                                    onChanged: (x, y) {
                                      _handleJoystickHaptic(x, y, false);
                                      final v = _shape(x, y, left: false);
                                      _state.setRightStick(v[0], v[1]);
                                    },
                                  )),

                        // RB / RT
                        _item(
                            'rb',
                            c,
                            GamepadButtonWidget(
                              label: 'RB',
                              pill: true,
                              size: 42,
                              color: _colorOr('rb', AppColors.stickFill),
                              toggle: _tg('rb'),
                              turbo: _tb('rb'),
                              turboHalfMs: _turboHalfMs,
                              onChanged: (p) => _handleButtonPress(Protocol.bitRb, p),
                              onPulse: (p) => _state.setButton(Protocol.bitRb, p),
                            )),
                        _item(
                            'rt',
                            c,
                            TriggerWidget(
                              key: ValueKey('rt-${_layout.active}'),
                              label: 'RT',
                              color: _colorOf('rt'),
                              latchEnabled: _layout.settings.latchRt,
                              steerEnabled: _layout.settings.steerRt,
                              aimEnabled: _layout.settings.aimRt,
                              aimFireK: _layout.settings.aimFire,
                              turbo: _tb('rt'),
                              turboHalfMs: _turboHalfMs,
                              onPulse: (v) => _state.setRightTrigger(v),
                              latchLevel: _layout.settings.latchLevelRt,
                              onSteer: _handleTriggerSteer,
                              onLatchChanged: (_) => HapticFeedback.mediumImpact(),
                              size: 100,
                              onChanged: (v) {
                                _handleTriggerHaptic(v, false);
                                _state.setRightTrigger(v);
                              },
                            )),

                        // A / B / X / Y — each one is its own movable control
                        _item(
                            'btn_y',
                            c,
                            GamepadButtonWidget(
                              label: 'Y',
                              size: 62,
                              color: _colorOr('btn_y', AppColors.buttonY),
                              toggle: _tg('btn_y'),
                              turbo: _tb('btn_y'),
                              turboHalfMs: _turboHalfMs,
                              onChanged: (p) => _handleButtonPress(Protocol.bitY, p),
                              onPulse: (p) => _state.setButton(Protocol.bitY, p),
                            )),
                        _item(
                            'btn_a',
                            c,
                            GamepadButtonWidget(
                              label: 'A',
                              size: 62,
                              color: _colorOr('btn_a', AppColors.buttonA),
                              toggle: _tg('btn_a'),
                              turbo: _tb('btn_a'),
                              turboHalfMs: _turboHalfMs,
                              onChanged: (p) => _handleButtonPress(Protocol.bitA, p),
                              onPulse: (p) => _state.setButton(Protocol.bitA, p),
                            )),
                        _item(
                            'btn_x',
                            c,
                            GamepadButtonWidget(
                              label: 'X',
                              size: 62,
                              color: _colorOr('btn_x', AppColors.buttonX),
                              toggle: _tg('btn_x'),
                              turbo: _tb('btn_x'),
                              turboHalfMs: _turboHalfMs,
                              onChanged: (p) => _handleButtonPress(Protocol.bitX, p),
                              onPulse: (p) => _state.setButton(Protocol.bitX, p),
                            )),
                        _item(
                            'btn_b',
                            c,
                            GamepadButtonWidget(
                              label: 'B',
                              size: 62,
                              color: _colorOr('btn_b', AppColors.buttonB),
                              toggle: _tg('btn_b'),
                              turbo: _tb('btn_b'),
                              turboHalfMs: _turboHalfMs,
                              onChanged: (p) => _handleButtonPress(Protocol.bitB, p),
                              onPulse: (p) => _state.setButton(Protocol.bitB, p),
                            )),

                        if (_editing && (_guideX != null || _guideY != null))
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(painter: _GuidePainter(_guideX, _guideY)),
                            ),
                          ),
                        if (_editing)
                          LayoutEditor(
                            layout: _layout,
                            selected: _selected,
                            onSelect: (id) => setState(() => _selected = id),
                            snap: _snap,
                            onSnap: (v) => setState(() => _snap = v),
                            onDone: _exitEdit,
                            onNudge: (dx, dy) => _nudge(dx, dy, c),
                            lastApp: _lastApp,
                            tiltPreview: _tiltPreview,
                            onCalibrate: _calibrateTilt,
                            onBeginAutoCal: _beginAutoCal,
                            onApplyAutoProfile: _applyAutoProfile,
                            onRenamePlayer: _renamePlayer,
                            onCopy: _copyProfile,
                            onPaste: _pasteProfile,
                            onAddGame: _addGame,
                            onBuzz: _buzz,
                          )
                        else ...[
                          if (widget.socket != null) _netBadge(),
                          _editButton(c),
                          if (_layout.profileNames.length > 1) _profileChip(c),
                          if (_layout.settings.tilt) _calibChip(c),
                        ],
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  final double? x, y;
  const _GuidePainter(this.x, this.y);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accent.withOpacity(0.8)
      ..strokeWidth = 1.2;
    if (x != null) canvas.drawLine(Offset(x!, 0), Offset(x!, size.height), paint);
    if (y != null) canvas.drawLine(Offset(0, y!), Offset(size.width, y!), paint);
  }

  @override
  bool shouldRepaint(covariant _GuidePainter old) => old.x != x || old.y != y;
}

class _GridPainter extends CustomPainter {
  final double step;
  const _GridPainter(this.step);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.07)
      ..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.step != step;
}
