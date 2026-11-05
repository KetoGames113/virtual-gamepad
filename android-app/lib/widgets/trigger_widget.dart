import 'package:flutter/material.dart';

import '../theme.dart';

/// A circular pressure-style analog trigger for LT/RT, matching the design's
/// large round trigger buttons. Drag down within the circle = more
/// pressure; releasing snaps back to 0, matching a spring-loaded analog
/// trigger. The fill rises from the bottom like a gauge.
/// 
class TriggerWidget extends StatefulWidget {
  final String label;
  final double size;
  final void Function(double value) onChanged;
  final Color? color;

  const TriggerWidget({
    super.key,
    required this.label,
    required this.onChanged,
    this.size = 90,
    this.color,
  });

  @override
  State<TriggerWidget> createState() => _TriggerWidgetState();
}

class _TriggerWidgetState extends State<TriggerWidget> {
  double _value = 0;

  void _update(Offset local) {
    final v = (local.dy / widget.size).clamp(0.0, 1.0);
    setState(() => _value = v);
    widget.onChanged(v);
  }

  void _reset() {
    setState(() => _value = 0);
    widget.onChanged(0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (d) => _update(d.localPosition),
      onPanUpdate: (d) => _update(d.localPosition),
      onPanEnd: (_) => _reset(),
      onPanCancel: _reset,
      child: Container(
        width: widget.size,
        height: widget.size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color ?? AppColors.stickFill,
        ),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            FractionallySizedBox(
              heightFactor: _value.clamp(0.06, 1.0),
              widthFactor: 1,
              child: Container(color: Colors.white.withOpacity(0.55)),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 0),
              child: Align(
                alignment: Alignment.center,
                child: Text(
                  widget.label,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
