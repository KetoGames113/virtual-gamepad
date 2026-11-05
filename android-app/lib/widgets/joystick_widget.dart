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
              color: widget.color ?? AppColors.stickFill,
            ),
            child: Center(
              child: Transform.translate(
                offset: _knob,
                child: Container(
                  width: widget.size * 0.5,
                  height: widget.size * 0.5,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                ),
              ),
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
