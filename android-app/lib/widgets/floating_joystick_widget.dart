import 'package:flutter/material.dart';

import '../theme.dart';

/// A joystick that appears under the finger: touch anywhere inside the zone
/// and the stick base is drawn there, so you never have to look for it.
/// Reports normalized (x, y) in [-1, 1] with y positive = up, like
/// [JoystickWidget].
class FloatingJoystickWidget extends StatefulWidget {
  final double width;
  final double height;
  final double stickSize;
  final String? label;
  final Color? color;
  final void Function(double x, double y) onChanged;

  const FloatingJoystickWidget({
    super.key,
    required this.onChanged,
    this.width = 260,
    this.height = 220,
    this.stickSize = 140,
    this.label,
    this.color,
  });

  @override
  State<FloatingJoystickWidget> createState() => _FloatingJoystickWidgetState();
}

class _FloatingJoystickWidgetState extends State<FloatingJoystickWidget> {
  Offset? _origin; // where the finger first landed (stick centre)
  Offset _knob = Offset.zero; // knob offset from the origin

  double get _radius => widget.stickSize / 2;
  double get _maxLen => _radius - 20;

  void _start(Offset local) {
    final r = _radius;
    final ox = local.dx.clamp(r, widget.width < 2 * r ? r : widget.width - r).toDouble();
    final oy = local.dy.clamp(r, widget.height < 2 * r ? r : widget.height - r).toDouble();
    setState(() {
      _origin = Offset(ox, oy);
      _knob = Offset.zero;
    });
  }

  void _move(Offset local) {
    final origin = _origin;
    if (origin == null) return;
    var delta = local - origin;
    if (delta.distance > _maxLen) {
      delta = Offset.fromDirection(delta.direction, _maxLen);
    }
    setState(() => _knob = delta);
    final nx = (delta.dx / _maxLen).clamp(-1.0, 1.0).toDouble();
    final ny = (-delta.dy / _maxLen).clamp(-1.0, 1.0).toDouble(); // up = positive
    widget.onChanged(nx, ny);
  }

  void _end() {
    if (_origin == null) return;
    setState(() {
      _origin = null;
      _knob = Offset.zero;
    });
    widget.onChanged(0, 0);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stickSize;
    final active = _origin != null;
    final o = _origin ?? Offset(widget.width / 2, widget.height / 2);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanDown: (d) => _start(d.localPosition),
      onPanUpdate: (d) => _move(d.localPosition),
      onPanEnd: (_) => _end(),
      onPanCancel: _end,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Stack(
          children: [
            // Faint hint of the touch zone while idle.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  color: Colors.white.withOpacity(active ? 0.0 : 0.05),
                ),
              ),
            ),
            // Stick base.
            Positioned(
              left: o.dx - s / 2,
              top: o.dy - s / 2,
              width: s,
              height: s,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (widget.color ?? AppColors.stickFill).withOpacity(active ? 0.85 : 0.35),
                ),
                child: (!active && widget.label != null)
                    ? Text(widget.label!,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontWeight: FontWeight.w700,
                            fontSize: 16))
                    : null,
              ),
            ),
            // Knob.
            if (active)
              Positioned(
                left: o.dx + _knob.dx - s * 0.25,
                top: o.dy + _knob.dy - s * 0.25,
                width: s * 0.5,
                height: s * 0.5,
                child: const DecoratedBox(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
