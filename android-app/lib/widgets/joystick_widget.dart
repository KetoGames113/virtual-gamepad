import 'package:flutter/material.dart';

import '../theme.dart';

/// A self-contained analog joystick. Reports normalized (x, y) in [-1, 1]
/// via [onChanged], with y positive = up (already flipped from screen
/// coordinates) to match typical gamepad axis conventions.
class JoystickWidget extends StatefulWidget {
  final double size;
  final void Function(double x, double y) onChanged;
  final String? label;
  final Color? color;

  const JoystickWidget({
    super.key,
    required this.onChanged,
    this.size = 140,
    this.label,
    this.color,
  });

  @override
  State<JoystickWidget> createState() => _JoystickWidgetState();
}

class _JoystickWidgetState extends State<JoystickWidget> {
  Offset _knob = Offset.zero; // relative to center, in [-1,1] * radius

  void _updateFromLocal(Offset localPos, double radius) {
    final center = Offset(radius, radius);
    var delta = localPos - center;
    final maxLen = radius - 26; // leave room so knob doesn't clip
    if (delta.distance > maxLen) {
      delta = Offset.fromDirection(delta.direction, maxLen);
    }
    setState(() => _knob = delta);
    final nx = (delta.dx / maxLen).clamp(-1.0, 1.0);
    final ny = (-delta.dy / maxLen).clamp(-1.0, 1.0); // flip: up = positive
    widget.onChanged(nx, ny);
  }

  void _reset() {
    setState(() => _knob = Offset.zero);
    widget.onChanged(0, 0);
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.size / 2;
    final base = widget.color ?? AppColors.stickFill;
    final active = _knob != Offset.zero;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onPanStart: (d) => _updateFromLocal(d.localPosition, radius),
          onPanUpdate: (d) => _updateFromLocal(d.localPosition, radius),
          onPanEnd: (_) => _reset(),
          onPanCancel: _reset,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Color.lerp(base, Colors.black, 0.45)!,
                  base,
                  Color.lerp(base, Colors.white, 0.12)!,
                ],
                stops: const [0.0, 0.7, 1.0],
              ),
              border: Border.all(
                  color: Colors.white.withOpacity(active ? 0.55 : 0.25), width: 2),
              boxShadow: [
                BoxShadow(
                    color: AppColors.activeAccent.withOpacity(active ? 0.28 : 0.08),
                    blurRadius: 18),
                BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Inner guide ring.
                Container(
                  width: widget.size * 0.78,
                  height: widget.size * 0.78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.10), width: 1.5),
                  ),
                ),
                // Knob: glossy sphere that lights up while held.
                Transform.translate(
                  offset: _knob,
                  child: Container(
                    width: widget.size * 0.5,
                    height: widget.size * 0.5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        center: Alignment(-0.3, -0.4),
                        radius: 1.0,
                        colors: [Colors.white, Color(0xFFD9D2FF), Color(0xFF8E7CFF)],
                        stops: [0.0, 0.5, 1.0],
                      ),
                      border: Border.all(color: Colors.white.withOpacity(0.7), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.activeAccent.withOpacity(active ? 0.6 : 0.0),
                            blurRadius: 16),
                        BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 3)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.label != null) ...[
          const SizedBox(height: 4),
          Text(widget.label!, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
        ]
      ],
    );
  }
}
