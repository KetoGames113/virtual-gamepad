import 'dart:async'; // Added to handle stream subscriptions
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/gamepad_state.dart';
import '../models/layout_store.dart';
import '../network/gamepad_socket.dart';
import '../network/protocol.dart';
import '../theme.dart';
import '../widgets/dpad_widget.dart';
import '../widgets/floating_joystick_widget.dart';
import '../widgets/gamepad_button_widget.dart';
import '../widgets/joystick_widget.dart';
import '../widgets/trigger_widget.dart';

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
  int _panelTab = 0; // 0 = general, 1 = tilt

  // Tilt steering
  StreamSubscription<AccelerometerEvent>? _accelSub;
  final ValueNotifier<double> _tiltPreview = ValueNotifier(0);
  double _fx = 0, _fy = 0; // smoothed accelerometer x / y
  bool _fInit = false;
  double _orient = 1; // +1 / -1: landscape-left vs landscape-right
  double _tiltAngle = 0; // current wheel angle in degrees (+ = clockwise)

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

  /// Releases everything held on the PC and resets local haptic trackers.
  void _releaseAll() {
    _state.releaseAll();
    _leftTriggerStep = _rightTriggerStep = 0;
    _leftStickActive = _rightStickActive = false;
  }

  // ───────────────────────── Tilt steering ─────────────────────────

  void _syncTilt() {
    final want = _layout.settings.tilt;
    if (want && _accelSub == null) {
      _fInit = false;
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
      _fInit = true;
    } else {
      final k = 1.0 - st.tiltSmooth;
      _fx += (e.x - _fx) * k;
      _fy += (e.y - _fy) * k;
    }

    double steer = 0;
    // If the phone lies flat there is no wheel angle to read.
    if (math.sqrt(_fx * _fx + _fy * _fy) > 3.0) {
      if (_fx.abs() > 4.0) _orient = _fx >= 0 ? 1.0 : -1.0; // landscape L/R
      final deg = math.atan2(_fy * _orient, _fx * _orient) * 180 / math.pi;
      _tiltAngle = deg;

      var d = deg - st.tiltCenter;
      if (d > 180) d -= 360;
      if (d < -180) d += 360;
      if (st.tiltInvert) d = -d;

      final dz = st.tiltDeadzone;
      var full = 45.0 / st.tiltSens; // degrees for full lock
      if (full < dz + 1) full = dz + 1;
      final m = d.abs();
      if (m > dz) {
        steer = ((m - dz) / (full - dz)).clamp(0.0, 1.0).toDouble() * (d < 0 ? -1.0 : 1.0);
      }
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
    if (_snap) {
      t = _clampCenter(id, c, (raw.dx / _grid).round() * _grid,
          (raw.dy / _grid).round() * _grid);
    }
    _layout.setPosition(id, t.dx / c.maxWidth, t.dy / c.maxHeight);
  }

  /// Places [child] according to the saved layout. In edit mode the child is
  /// frozen and the whole box becomes draggable / selectable.
  Widget _item(String id, BoxConstraints c, Widget child) {
    final it = _layout.of(id);
    if (!it.visible && !_editing) return const SizedBox.shrink();

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
      child: SizedBox(width: bw, height: bh, child: Center(child: child)),
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
        onPanStart: (_) => setState(() {
          _selected = id;
          _dragRaw = _center(id, c);
        }),
        onPanUpdate: (d) => _drag(id, d.delta, c),
        onPanEnd: (_) {
          _dragRaw = null;
          _layout.save();
        },
        onPanCancel: () => _dragRaw = null,
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
                      width: selected ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Applies that stick's deadzone + sensitivity to a raw stick vector.
  List<double> _shape(double x, double y, {required bool left}) {
    final s = _layout.settings;
    final dz = left ? s.deadzoneL : s.deadzoneR;
    final gain = left ? s.sensL : s.sensR;
    final m = math.sqrt(x * x + y * y);
    if (m <= dz || m == 0) return const [0.0, 0.0];
    final scaled = (((m - dz) / (1 - dz)) * gain).clamp(0.0, 1.0).toDouble();
    return [x / m * scaled, y / m * scaled];
  }

  Future<String?> _askName(String title, String initial) async {
    final ctrl = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(hintText: 'Profile name'),
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

  Future<void> _confirmDeleteProfile() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${_layout.active}"?'),
        content: const Text('This profile and its layout will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      _layout.deleteActive();
      _layout.save();
    }
  }

  Widget _sliderRow(String label, double value, double min, double max,
      ValueChanged<double> onChanged,
      {String Function(double v)? fmt, double labelWidth = 52, double valueWidth = 40}) {
    return Row(
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              onChanged: onChanged,
              onChangeEnd: (_) => _layout.save(),
            ),
          ),
        ),
        SizedBox(
          width: valueWidth,
          child: Text(fmt != null ? fmt(value) : '${(value * 100).round()}%',
              textAlign: TextAlign.end,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ),
      ],
    );
  }

  Future<void> _confirmResetAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset this profile?'),
        content: const Text('All controls and stick settings in this profile go back to the defaults.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset all')),
        ],
      ),
    );
    if (ok == true) {
      _layout.resetAll();
      _layout.save();
    }
  }

  Widget _profileRow() {
    return Row(
      children: [
        const Text('Profile', style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(width: 8),
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _layout.active,
            isDense: true,
            dropdownColor: const Color(0xFF1E1E2A),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            items: [
              for (final n in _layout.profileNames)
                DropdownMenuItem(value: n, child: Text(n)),
            ],
            onChanged: (n) {
              if (n == null) return;
              _layout.switchTo(n);
              _layout.save();
            },
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'New profile (copy of this one)',
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          color: Colors.white70,
          icon: const Icon(Icons.add),
          onPressed: () async {
            final n = await _askName('New profile (copy of current)', '');
            if (n == null) return;
            _layout.createProfile(n);
            _layout.save();
          },
        ),
        IconButton(
          tooltip: 'Rename',
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          color: Colors.white70,
          icon: const Icon(Icons.drive_file_rename_outline),
          onPressed: () async {
            final n = await _askName('Rename profile', _layout.active);
            if (n == null) return;
            _layout.renameActive(n);
            _layout.save();
          },
        ),
        if (_layout.canDeleteActive)
          IconButton(
            tooltip: 'Delete profile',
            visualDensity: VisualDensity.compact,
            iconSize: 20,
            color: Colors.white70,
            icon: const Icon(Icons.delete_outline),
            onPressed: _confirmDeleteProfile,
          ),
      ],
    );
  }

  static const List<int> _palette = [
    0xFF8A2BE2, 0xFF00BFFF, 0xFF00FF85, 0xFFFF1744, 0xFFFFD600,
    0xFFFF9100, 0xFFFF00E5, 0xFF546E7A, 0xFF212121, 0xFFFFFFFF,
  ];

  Widget _swatch(String id, int? argb, ItemLayout it) {
    final selected = it.color == argb;
    return GestureDetector(
      onTap: () {
        _layout.setColor(id, argb);
        _layout.save();
      },
      child: Container(
        width: 26,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: argb == null ? Colors.transparent : Color(argb),
          border: Border.all(
            color: selected ? Colors.white : Colors.white24,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: argb == null
            ? const Icon(Icons.block, size: 14, color: Colors.white54)
            : null,
      ),
    );
  }

  Widget _colorRow(String id, ItemLayout it) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          const Text('Color', style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(width: 8),
          _swatch(id, null, it), // default colour
          for (final c in _palette) _swatch(id, c, it),
        ],
      ),
    );
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

  Widget _globalRow() {
    const small = TextStyle(color: Colors.white70, fontSize: 12);
    return Wrap(
      spacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Grid', style: small),
        Switch(value: _snap, onChanged: (v) => setState(() => _snap = v)),
        const SizedBox(width: 4),
        const Text('Vibration', style: small),
        for (final e in const [(0, 'Off'), (1, 'Light'), (2, 'Strong')])
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: ChoiceChip(
              label: Text(e.$2, style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              selected: _layout.settings.haptics == e.$1,
              onSelected: (_) {
                _layout.setHaptics(e.$1);
                _layout.save();
                _buzz(); // feel the new strength right away
              },
            ),
          ),
        TextButton.icon(
          onPressed: _copyProfile,
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Copy'),
        ),
        TextButton.icon(
          onPressed: _pasteProfile,
          icon: const Icon(Icons.paste, size: 16),
          label: const Text('Paste'),
        ),
      ],
    );
  }

  /// Live indicator of the steering value coming from the tilt sensor.
  Widget _tiltMeter() {
    return ValueListenableBuilder<double>(
      valueListenable: _tiltPreview,
      builder: (context, v, _) => SizedBox(
        height: 14,
        child: LayoutBuilder(
          builder: (context, bc) {
            final w = bc.maxWidth;
            return Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                ),
                Positioned(
                  left: w / 2 - 1,
                  top: 0,
                  bottom: 0,
                  width: 2,
                  child: const ColoredBox(color: Colors.white38),
                ),
                Positioned(
                  left: (w - 14) * ((v.clamp(-1.0, 1.0) + 1) / 2),
                  top: 0,
                  width: 14,
                  height: 14,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.activeAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _tiltRow() {
    final st = _layout.settings;
    const small = TextStyle(color: Colors.white70, fontSize: 12);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Tilt steering', style: small),
            Switch(
              value: st.tilt,
              onChanged: (v) {
                _layout.tweak((s) => s.tilt = v);
                _layout.save();
              },
            ),
            const Text('Controls', style: small),
            for (final e in const [(false, 'Left stick X'), (true, 'Right stick X')])
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: ChoiceChip(
                  label: Text(e.$2, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  selected: st.tiltRightStick == e.$1,
                  onSelected: (_) {
                    _layout.tweak((s) => s.tiltRightStick = e.$1);
                    _layout.save();
                  },
                ),
              ),
            const SizedBox(width: 4),
            const Text('Invert', style: small),
            Switch(
              value: st.tiltInvert,
              onChanged: (v) {
                _layout.tweak((s) => s.tiltInvert = v);
                _layout.save();
              },
            ),
            TextButton.icon(
              onPressed: st.tilt ? _calibrateTilt : null,
              icon: const Icon(Icons.my_location, size: 16),
              label: const Text('Set center'),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _sliderRow(
                'Sensitivity',
                st.tiltSens,
                LayoutStore.minTiltSens,
                LayoutStore.maxTiltSens,
                (v) => _layout.tweak((s) => s.tiltSens = v),
                fmt: (v) => '${(45 / v).round()}°',
                labelWidth: 74,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _sliderRow(
                'Deadzone',
                st.tiltDeadzone,
                0,
                LayoutStore.maxTiltDeadzone,
                (v) => _layout.tweak((s) => s.tiltDeadzone = v),
                fmt: (v) => '${v.round()}°',
                labelWidth: 74,
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _sliderRow(
                'Smoothing',
                st.tiltSmooth,
                0,
                0.9,
                (v) => _layout.tweak((s) => s.tiltSmooth = v),
                labelWidth: 74,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: st.tilt ? _tiltMeter() : const SizedBox.shrink()),
          ],
        ),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Hold the phone like a steering wheel. The degrees next to '
            'Sensitivity = how far you turn for full steering lock.',
            style: TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ),
      ],
    );
  }

  Widget _editPanel() {
    final id = _selected;
    final spec = id == null ? null : _layout.spec(id);
    final it = id == null ? null : _layout.of(id);
    final isStick = id == 'lstick' || id == 'rstick';
    final isTrigger = id == 'lt' || id == 'rt';
    final st = _layout.settings;
    // Keep the panel away from the control being edited.
    final atTop = it != null && it.y > 0.5;
    const small = TextStyle(color: Colors.white70, fontSize: 12);

    final panel = Material(
      color: Colors.black.withOpacity(0.85),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    spec?.title ?? 'Edit layout — drag a control, tap to adjust',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                if (id != null)
                  TextButton(
                    onPressed: () {
                      _layout.resetItem(id);
                      _layout.save();
                    },
                    child: const Text('Reset'),
                  ),
                TextButton(onPressed: _confirmResetAll, child: const Text('Reset all')),
                FilledButton(onPressed: _exitEdit, child: const Text('Done')),
              ],
            ),
            _profileRow(),
            if (id != null && it != null && spec != null) ...[
              Row(
                children: [
                  Expanded(
                    child: _sliderRow('Size', it.scale, LayoutStore.minScale,
                        LayoutStore.maxScale, (v) => _layout.setScale(id, v)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _sliderRow('Opacity', it.opacity, LayoutStore.minOpacity, 1.0,
                        (v) => _layout.setOpacity(id, v)),
                  ),
                  if (isStick) ...[
                    const SizedBox(width: 4),
                    const Text('Float', style: small),
                    Switch(
                      value: _layout.isFloating(id),
                      onChanged: (v) {
                        _layout.setFloating(id, v);
                        _layout.save();
                      },
                    ),
                  ],
                  if (spec.canHide) ...[
                    const SizedBox(width: 4),
                    const Text('Show', style: small),
                    Switch(
                      value: it.visible,
                      onChanged: (v) {
                        _layout.setVisible(id, v);
                        _layout.save();
                      },
                    ),
                  ],
                ],
              ),
              if (isStick)
                Row(
                  children: [
                    Expanded(
                      child: _sliderRow(
                        'Sensitivity',
                        id == 'lstick' ? st.sensL : st.sensR,
                        LayoutStore.minSensitivity,
                        LayoutStore.maxSensitivity,
                        (v) => _layout.setSensitivity(id == 'lstick', v),
                        labelWidth: 74,
                        valueWidth: 44,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _sliderRow(
                        'Deadzone',
                        id == 'lstick' ? st.deadzoneL : st.deadzoneR,
                        0,
                        LayoutStore.maxDeadzone,
                        (v) => _layout.setDeadzone(id == 'lstick', v),
                        labelWidth: 74,
                      ),
                    ),
                  ],
                ),
              if (isTrigger)
                Row(
                  children: [
                    const Text('Double-tap to lock fully pressed', style: small),
                    const SizedBox(width: 6),
                    Switch(
                      value: id == 'lt' ? st.latchLt : st.latchRt,
                      onChanged: (v) {
                        _layout.setLatch(id == 'lt', v);
                        _layout.save();
                      },
                    ),
                    const Expanded(
                      child: Text('tap again to release',
                          style: TextStyle(color: Colors.white38, fontSize: 10)),
                    ),
                  ],
                ),
              if (isTrigger)
                Row(
                  children: [
                    const Text('Slide to steer (moves right stick)', style: small),
                    const SizedBox(width: 6),
                    Switch(
                      value: id == 'lt' ? st.steerLt : st.steerRt,
                      onChanged: (v) {
                        _layout.setSteer(id == 'lt', v);
                        _layout.save();
                      },
                    ),
                    const Expanded(
                      child: Text('press = full, slide finger = stick',
                          style: TextStyle(color: Colors.white38, fontSize: 10)),
                    ),
                  ],
                ),
            ] else ...[
              Row(
                children: [
                  for (final e in const [(0, 'General'), (1, 'Tilt steering')])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(e.$2, style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        selected: _panelTab == e.$1,
                        onSelected: (_) => setState(() => _panelTab = e.$1),
                      ),
                    ),
                ],
              ),
              if (_panelTab == 0) _globalRow() else _tiltRow(),
            ],
            if (id != null && it != null && spec != null && spec.canColor)
              _colorRow(id, it),
          ],
        ),
      ),
    );

    return Positioned(
      top: atTop ? 6 : null,
      bottom: atTop ? null : 6,
      left: 0,
      right: 0,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 680,
            maxHeight: MediaQuery.of(context).size.height - 12,
          ),
          // Absorb touches so they don't fall through to controls underneath.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: SingleChildScrollView(child: panel),
          ),
        ),
      ),
    );
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
            color: Colors.black.withOpacity(0.35),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.edit, color: Colors.white70, size: 18),
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
                      children: [
                        if (_editing && _snap)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(painter: _GridPainter(_grid)),
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
                              onSteer: _handleTriggerSteer,
                              onLatchChanged: (_) => HapticFeedback.mediumImpact(),
                              size: 112,
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
                              size: 70,
                              color: _colorOr('lb', AppColors.stickFill),
                              onChanged: (p) => _handleButtonPress(Protocol.bitLb, p),
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
                                width: 50,
                                height: 50,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                    color: _colorOr('disconnect', AppColors.stickFill),
                                    shape: BoxShape.circle),
                                child: const Icon(Icons.close, color: Colors.white, size: 22),
                              ),
                            )),

                        // Menu / Guide / Start
                        _item(
                            'back',
                            c,
                            GamepadButtonWidget(
                              label: '',
                              icon: Icons.menu,
                              size: 60,
                              color: _colorOr('back', AppColors.stickFill),
                              onChanged: (p) => _handleButtonPress(Protocol.bitBack, p),
                            )),
                        _item(
                            'guide',
                            c,
                            GamepadButtonWidget(
                              label: '',
                              icon: Icons.sports_esports,
                              size: 68,
                              color: _colorOr('guide', AppColors.stickFill),
                              onChanged: (p) => _handleButtonPress(Protocol.bitGuide, p),
                            )),
                        _item(
                            'start',
                            c,
                            GamepadButtonWidget(
                              label: '',
                              icon: Icons.tune,
                              size: 60,
                              color: _colorOr('start', AppColors.stickFill),
                              onChanged: (p) => _handleButtonPress(Protocol.bitStart, p),
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
                              onChanged: (p) => _handleButtonPress(Protocol.bitLsClick, p),
                            )),
                        _item(
                            'r3',
                            c,
                            GamepadButtonWidget(
                              label: 'RIGHT',
                              pill: true,
                              size: 40,
                              color: _colorOr('r3', AppColors.stickFill),
                              onChanged: (p) => _handleButtonPress(Protocol.bitRsClick, p),
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
                                    },
                                  )
                                : JoystickWidget(
                                    size: 160,
                                    color: _colorOf('lstick'),
                                    onChanged: (x, y) {
                                      _handleJoystickHaptic(x, y, true);
                                      final v = _shape(x, y, left: true);
                                      _state.setLeftStick(v[0], v[1]);
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
                              size: 70,
                              color: _colorOr('rb', AppColors.stickFill),
                              onChanged: (p) => _handleButtonPress(Protocol.bitRb, p),
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
                              onSteer: _handleTriggerSteer,
                              onLatchChanged: (_) => HapticFeedback.mediumImpact(),
                              size: 112,
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
                              color: _colorOr('btn_y', AppColors.buttonY),
                              onChanged: (p) => _handleButtonPress(Protocol.bitY, p),
                            )),
                        _item(
                            'btn_a',
                            c,
                            GamepadButtonWidget(
                              label: 'A',
                              color: _colorOr('btn_a', AppColors.buttonA),
                              onChanged: (p) => _handleButtonPress(Protocol.bitA, p),
                            )),
                        _item(
                            'btn_x',
                            c,
                            GamepadButtonWidget(
                              label: 'X',
                              color: _colorOr('btn_x', AppColors.buttonX),
                              onChanged: (p) => _handleButtonPress(Protocol.bitX, p),
                            )),
                        _item(
                            'btn_b',
                            c,
                            GamepadButtonWidget(
                              label: 'B',
                              color: _colorOr('btn_b', AppColors.buttonB),
                              onChanged: (p) => _handleButtonPress(Protocol.bitB, p),
                            )),

                        if (_editing)
                          _editPanel()
                        else ...[
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
