import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

/// A circular pressure-style analog trigger for LT/RT. The finger's vertical
/// position inside the circle sets the pressure (top = 0, bottom = 1);
/// releasing snaps back to 0 like a spring-loaded trigger.
///
/// Optional extras:
///  * [latchEnabled] – a quick double-tap locks the trigger at [latchLevel];
///    touching it again releases the lock.
///  * [steerEnabled] – slide-to-steer: while touched the trigger is fully
///    pressed and the finger's offset from where it landed is reported via
///    [onSteer] as x/y in [-1, 1] (y up).
///  * [aimEnabled] – aim & fire: touching does NOT press the trigger; sliding
///    aims (via [onSteer]) and pulling further than [aimFireK] aim-radii
///    presses it fully (fire).
class TriggerWidget extends StatefulWidget {
  final String label;
  final double size;
  final void Function(double value) onChanged;
  final Color? color;

  final bool latchEnabled;
  final double latchLevel;
  final void Function(bool latched)? onLatchChanged;

  final bool steerEnabled;
  final bool aimEnabled;
  final double aimFireK;

  /// Rapid fire for aim & fire: while the pull is held past the fire distance
  /// the trigger is pulsed on/off ~12 times a second instead of staying
  /// pressed (for semi-automatic weapons that need a fresh press per shot).
  final bool turbo;

  /// Half of one turbo press/release cycle in ms (40 = ~12 presses/s).
  final int turboHalfMs;

  /// Receives the automatic on/off pulses of turbo, so the owner can skip
  /// per-press feedback such as haptics. Falls back to [onChanged].
  final void Function(double value)? onPulse;

  /// [active] is false when the finger lifts.
  final void Function(double x, double y, bool active)? onSteer;

  const TriggerWidget({
    super.key,
    required this.label,
    required this.onChanged,
    this.size = 90,
    this.color,
    this.latchEnabled = false,
    this.latchLevel = 1.0,
    this.onLatchChanged,
    this.steerEnabled = false,
    this.aimEnabled = false,
    this.aimFireK = 1.8,
    this.turbo = false,
    this.turboHalfMs = 40,
    this.onPulse,
    this.onSteer,
  });

  @override
  State<TriggerWidget> createState() => _TriggerWidgetState();
}

class _TriggerWidgetState extends State<TriggerWidget> {
  static const _doubleTapWindow = Duration(milliseconds: 350);
  static const _maxTapDuration = Duration(milliseconds: 250);
  static const _maxTapTravel = 24.0;
  Timer? _turboTimer;
  bool _turboOut = false; // what turbo is currently sending

  double _value = 0;
  bool _latched = false;

  int? _pointer; // the one finger we follow
  DateTime? _downAt;
  Offset? _downPos;
  bool _movedFar = false;
  DateTime? _lastTapUp; // when the previous short tap ended

  bool _steering = false;
  bool _firing = false;
  Offset _origin = Offset.zero;
  Offset _dot = Offset.zero; // finger offset shown while aiming

  bool get _steerOn => widget.steerEnabled || widget.aimEnabled;
  double get _radius => widget.aimEnabled ? widget.size * 0.25 : widget.size * 0.45;

  void _set(double v) {
    if (_value == v) return;
    setState(() => _value = v);
    widget.onChanged(v);
  }

  void _startTurbo() {
    _turboTimer?.cancel();
    _turboOut = true; // _set(1.0) has just sent the first press
    _turboTimer = Timer.periodic(Duration(milliseconds: widget.turboHalfMs), (_) {
      _turboOut = !_turboOut;
      (widget.onPulse ?? widget.onChanged)(_turboOut ? 1.0 : 0.0);
    });
  }

  void _stopTurbo() {
    _turboTimer?.cancel();
    _turboTimer = null;
    _turboOut = false;
  }

  void _setLatched(bool v) {
    if (_latched == v) return;
    setState(() => _latched = v);
    widget.onLatchChanged?.call(v);
  }

  double _pressureAt(Offset local) {
    if (widget.aimEnabled) return 0.0; // aim mode fires by pulling further
    if (widget.steerEnabled) return 1.0;
    return (local.dy / widget.size).clamp(0.0, 1.0).toDouble();
  }

  void _steerTo(Offset local) {
    final r = _radius;
    final raw = local - _origin;
    var d = raw / r;
    if (d.distance > 1) d = d / d.distance;
    widget.onSteer?.call(d.dx, -d.dy, true);

    if (widget.aimEnabled) {
      final lim = widget.size * 0.4;
      var dot = raw;
      if (dot.distance > lim) dot = dot / dot.distance * lim;
      setState(() => _dot = dot);

      final fireDist = r * widget.aimFireK;
      if (!_firing && raw.distance >= fireDist) {
        _firing = true;
        if (!_latched) {
          _set(1.0);
          if (widget.turbo) _startTurbo();
        }
      } else if (_firing && raw.distance < fireDist * 0.85) {
        _firing = false;
        _stopTurbo();
        if (!_latched) _set(0.0);
      }
    }
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _stopTurbo();
    final now = DateTime.now();
    _downAt = now;
    _downPos = e.localPosition;
    _movedFar = false;
    _steering = _steerOn;
    _firing = false;
    _origin = e.localPosition;
    _dot = Offset.zero;
    if (_steering) widget.onSteer?.call(0, 0, true);

    if (_latched) {
      // Touch while locked: release the lock, finger takes over.
      _setLatched(false);
      _lastTapUp = null;
      _set(_pressureAt(e.localPosition));
      return;
    }

    final last = _lastTapUp;
    if (widget.latchEnabled && last != null && now.difference(last) <= _doubleTapWindow) {
      // Second quick tap → lock.
      _lastTapUp = null;
      _setLatched(true);
      _set(widget.latchLevel);
      return;
    }
    _set(_pressureAt(e.localPosition));
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final start = _downPos;
    if (start != null && (e.localPosition - start).distance > _maxTapTravel) {
      _movedFar = true;
    }
    if (_steering) _steerTo(e.localPosition);
    if (_latched) return; // locked: pressure stays where it is
    if (widget.aimEnabled) return; // pressure handled by _steerTo
    _set(_pressureAt(e.localPosition));
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (_steering) {
      _steering = false;
      widget.onSteer?.call(0, 0, false);
      if (_dot != Offset.zero) setState(() => _dot = Offset.zero);
    }
    _firing = false;
    _stopTurbo();
    final down = _downAt;
    final wasShortTap = e is PointerUpEvent &&
        !_movedFar &&
        down != null &&
        DateTime.now().difference(down) <= _maxTapDuration;
    _lastTapUp = wasShortTap ? DateTime.now() : null;
    if (_latched) return; // stays pressed
    _set(0);
  }

  @override
  void dispose() {
    _turboTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TriggerWidget old) {
    super.didUpdateWidget(old);
    if (!widget.turbo && _turboTimer != null) {
      // Turbo switched off mid-pull: go back to a plain held press.
      _stopTurbo();
      if (_firing && !_latched) widget.onChanged(1.0);
    }
    if (!widget.latchEnabled && _latched) {
      // Latch feature switched off while locked: let go.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _latched = false;
        _set(0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fill = _latched ? AppColors.activeAccent : Colors.white;
    final aiming = _steering && widget.aimEnabled;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: Container(
        width: widget.size,
        height: widget.size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              Color.lerp(widget.color ?? AppColors.stickFill, Colors.black, 0.4)!,
              widget.color ?? AppColors.stickFill,
              Color.lerp(widget.color ?? AppColors.stickFill, Colors.white, 0.12)!,
            ],
            stops: const [0.0, 0.7, 1.0],
          ),
          border: Border.all(
            color: _latched ? AppColors.activeAccent : Colors.white.withOpacity(0.28),
            width: _latched ? 3 : 2,
          ),
          boxShadow: [
            BoxShadow(
                color: (_latched ? AppColors.activeAccent : Colors.black)
                    .withOpacity(_latched ? 0.45 : 0.35),
                blurRadius: 12),
          ],
        ),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            FractionallySizedBox(
              heightFactor: _value.clamp(0.06, 1.0),
              widthFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      fill.withOpacity(_latched ? 0.8 : 0.65),
                      fill.withOpacity(_latched ? 0.5 : 0.3),
                    ],
                  ),
                  // Bright edge marks the current pressure level.
                  border: Border(
                    top: BorderSide(color: fill.withOpacity(0.9), width: 2),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_latched) const Icon(Icons.lock, color: Colors.white, size: 18),
                  Text(
                    widget.label,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ],
              ),
            ),
            if (aiming)
              Positioned(
                left: _origin.dx + _dot.dx - 8,
                top: _origin.dy + _dot.dy - 8,
                width: 16,
                height: 16,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _firing ? const Color(0xFFFF1744) : Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
