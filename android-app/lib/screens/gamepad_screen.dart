import 'dart:async'; // Added to handle stream subscriptions
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final GamepadSocket socket;
  const GamepadScreen({super.key, required this.socket});

  @override
  State<GamepadScreen> createState() => _GamepadScreenState();
}

class _GamepadScreenState extends State<GamepadScreen> {
  late final GamepadState _state;
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

  @override
  void initState() {
    super.initState();
    _state = GamepadState(widget.socket);
    _state.start();
    _layout.load();
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Listen for disconnections automatically from the socket network manager
    _connectionSubscription = widget.socket.connectionStream.listen((isConnected) {
      if (!isConnected) {
        _handleConnectionLoss();
      }
    });
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel(); // Cancel network listeners to prevent memory leaks
    _state.stop();
    _layout.save();
    _layout.dispose();
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

  /// Light vibration, unless the active profile turned vibration off.
  void _buzz() {
    if (_layout.settings.haptics) HapticFeedback.lightImpact();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  void _disconnect() {
    _buzz();
    widget.socket.disconnect();
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
    _state.releaseAll(); // nothing stays "held" on the PC while editing
    setState(() {
      _editing = true;
      _selected = null;
    });
  }

  void _exitEdit() {
    _layout.save();
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

  /// Applies the profile's deadzone + sensitivity to a raw stick vector.
  List<double> _shape(double x, double y) {
    final s = _layout.settings;
    final m = math.sqrt(x * x + y * y);
    if (m <= s.deadzone || m == 0) return const [0.0, 0.0];
    final scaled =
        (((m - s.deadzone) / (1 - s.deadzone)) * s.sensitivity).clamp(0.0, 1.0).toDouble();
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
      ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 52,
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
          width: 40,
          child: Text('${(value * 100).round()}%',
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
    return Row(
      children: [
        const Text('Grid', style: small),
        Switch(value: _snap, onChanged: (v) => setState(() => _snap = v)),
        const SizedBox(width: 4),
        const Text('Vibration', style: small),
        Switch(
          value: _layout.settings.haptics,
          onChanged: (v) {
            _layout.setHaptics(v);
            _layout.save();
          },
        ),
        const Spacer(),
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

  Widget _editPanel() {
    final id = _selected;
    final spec = id == null ? null : _layout.spec(id);
    final it = id == null ? null : _layout.of(id);
    final isStick = id == 'lstick' || id == 'rstick';
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
            if (id != null && it != null && spec != null)
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
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: _sliderRow('Deadzone', st.deadzone, 0, LayoutStore.maxDeadzone,
                        _layout.setDeadzone),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _sliderRow('Sensitivity', st.sensitivity,
                        LayoutStore.minSensitivity, LayoutStore.maxSensitivity,
                        _layout.setSensitivity),
                  ),
                ],
              ),
              _globalRow(),
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
          constraints: const BoxConstraints(maxWidth: 680),
          // Absorb touches so they don't fall through to controls underneath.
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () {}, child: panel),
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
          _state.releaseAll();
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
      canPop: !_editing,
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
                              label: 'LT',
                              color: _colorOf('lt'),
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
                                      final v = _shape(x, y);
                                      _state.setLeftStick(v[0], v[1]);
                                    },
                                  )
                                : JoystickWidget(
                                    size: 160,
                                    color: _colorOf('lstick'),
                                    onChanged: (x, y) {
                                      _handleJoystickHaptic(x, y, true);
                                      final v = _shape(x, y);
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
                                      final v = _shape(x, y);
                                      _state.setRightStick(v[0], v[1]);
                                    },
                                  )
                                : JoystickWidget(
                                    size: 160,
                                    color: _colorOf('rstick'),
                                    onChanged: (x, y) {
                                      _handleJoystickHaptic(x, y, false);
                                      final v = _shape(x, y);
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
                              label: 'RT',
                              color: _colorOf('rt'),
                              size: 112,
                              onChanged: (v) {
                                _handleTriggerHaptic(v, false);
                                _state.setRightTrigger(v);
                              },
                            )),

                        // ABXY diamond
                        _item('face', c,
                            _FaceButtons(onButtonPressed: _handleButtonPress, size: 150)),

                        if (_editing)
                          _editPanel()
                        else ...[
                          _editButton(c),
                          if (_layout.profileNames.length > 1) _profileChip(c),
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

class _FaceButtons extends StatelessWidget {
  final void Function(int buttonBit, bool isPressed) onButtonPressed;
  final double size;
  const _FaceButtons({required this.onButtonPressed, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 0,
            child: GamepadButtonWidget(
              label: 'Y',
              color: AppColors.buttonY,
              onChanged: (p) => onButtonPressed(Protocol.bitY, p),
            ),
          ),
          Positioned(
            bottom: 0,
            child: GamepadButtonWidget(
              label: 'A',
              color: AppColors.buttonA,
              onChanged: (p) => onButtonPressed(Protocol.bitA, p),
            ),
          ),
          Positioned(
            left: 0,
            child: GamepadButtonWidget(
              label: 'X',
              color: AppColors.buttonX,
              onChanged: (p) => onButtonPressed(Protocol.bitX, p),
            ),
          ),
          Positioned(
            right: 0,
            child: GamepadButtonWidget(
              label: 'B',
              color: AppColors.buttonB,
              onChanged: (p) => onButtonPressed(Protocol.bitB, p),
            ),
          ),
        ],
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
