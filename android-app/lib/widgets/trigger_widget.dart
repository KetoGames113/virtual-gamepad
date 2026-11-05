import 'package:flutter/material.dart';

import '../theme.dart';

/// A circular pressure-style analog trigger for LT/RT. The finger's vertical
/// position inside the circle sets the pressure (top = 0, bottom = 1);
/// releasing snaps back to 0 like a spring-loaded trigger.
///
/// With [latchEnabled], a quick double-tap locks the trigger fully pressed
/// (value 1.0). It stays locked until the trigger is touched again, which
/// releases the lock and returns to normal analog control.
class TriggerWidget extends StatefulWidget {
  final String label;
  final double size;
  final void Function(double value) onChanged;
  final Color? color;
  final bool latchEnabled;

  /// Slide-to-steer: while touched the trigger is fully pressed and the
  /// finger's offset from where it landed is reported through [onSteer]
  /// as x/y in [-1, 1] (y up). [active] is false when the finger lifts.
  final bool steerEnabled;
  final void Function(double x, double y, bool active)? onSteer;

  /// Called when the lock engages / releases (for haptics).
  final void Function(bool latched)? onLatchChanged;

  const TriggerWidget({
    super.key,
    required this.label,
    required this.onChanged,
    this.size = 90,
    this.color,
    this.latchEnabled = false,
    this.steerEnabled = false,
    this.onSteer,
    this.onLatchChanged,
  });

  @override
  State<TriggerWidget> createState() => _TriggerWidgetState();
}

class _TriggerWidgetState extends State<TriggerWidget> {
  static const _doubleTapWindow = Duration(milliseconds: 350);
  static const _maxTapDuration = Duration(milliseconds: 250);
  static const _maxTapTravel = 24.0;

  double _value = 0;
  bool _latched = false;

  int? _pointer; // the one finger we follow
  DateTime? _downAt;
  Offset? _downPos;
  bool _movedFar = false;
  bool _steering = false;
  Offset _steerOrigin = Offset.zero;
  DateTime? _lastTapUp; // when the previous short tap ended

  void _set(double v) {
    if (_value == v) return;
    setState(() => _value = v);
    widget.onChanged(v);
  }

  void _setLatched(bool v) {
    if (_latched == v) return;
    setState(() => _latched = v);
    widget.onLatchChanged?.call(v);
  }

  void _fromLocal(Offset local) => _set(widget.steerEnabled
      ? 1.0
      : (local.dy / widget.size).clamp(0.0, 1.0).toDouble());

  void _steerTo(Offset local) {
    final r = widget.size * 0.45;
    var d = (local - _steerOrigin) / r;
    if (d.distance > 1) d = d / d.distance;
    widget.onSteer?.call(d.dx, -d.dy, true);
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    final now = DateTime.now();
    _downAt = now;
    _downPos = e.localPosition;
    _movedFar = false;
    _steering = widget.steerEnabled;
    _steerOrigin = e.localPosition;
    if (_steering) widget.onSteer?.call(0, 0, true);

    if (_latched) {
      // Touch while locked: release the lock, finger takes over.
      _setLatched(false);
      _lastTapUp = null;
      _fromLocal(e.localPosition);
      return;
    }

    final last = _lastTapUp;
    if (widget.latchEnabled && last != null && now.difference(last) <= _doubleTapWindow) {
      // Second quick tap → lock at full pressure.
      _lastTapUp = null;
      _setLatched(true);
      _set(1.0);
      return;
    }
    _fromLocal(e.localPosition);
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final start = _downPos;
    if (start != null && (e.localPosition - start).distance > _maxTapTravel) {
      _movedFar = true;
    }
    if (_steering) _steerTo(e.localPosition);
    if (_latched) return; // locked: ignore the finger until it lifts
    _fromLocal(e.localPosition);
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (_steering) {
      _steering = false;
      widget.onSteer?.call(0, 0, false);
    }
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
  void didUpdateWidget(covariant TriggerWidget old) {
    super.didUpdateWidget(old);
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
          color: widget.color ?? AppColors.stickFill,
          border: _latched ? Border.all(color: AppColors.activeAccent, width: 3) : null,
        ),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            FractionallySizedBox(
              heightFactor: _value.clamp(0.06, 1.0),
              widthFactor: 1,
              child: Container(color: fill.withOpacity(_latched ? 0.7 : 0.55)),
            ),
            Align(
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_latched)
                    const Icon(Icons.lock, color: Colors.white, size: 18),
                  Text(
                    widget.label,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
