import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';


class GamepadButtonWidget extends StatefulWidget {
  final String label;
  final Color color;
  final double size;
  final void Function(bool pressed) onChanged;
  final bool pill;
  final bool solid;
  final IconData? icon;

  /// Toggle mode: tap once = pressed (stays), tap again = released.
  final bool toggle;

  /// Rapid fire: while held, the button is pressed and released repeatedly.
  final bool turbo;

  /// Receives the automatic press/release pulses of turbo mode (so the owner
  /// can skip vibration on each pulse). Falls back to [onChanged].
  final void Function(bool pressed)? onPulse;

  const GamepadButtonWidget({
    super.key,
    required this.label,
    required this.onChanged,
    this.color = Colors.white,
    this.size = 56,
    this.pill = false,
    this.solid = true,
    this.icon,
    this.toggle = false,
    this.turbo = false,
    this.onPulse,
  });

  @override
  State<GamepadButtonWidget> createState() => _GamepadButtonWidgetState();
}

class _GamepadButtonWidgetState extends State<GamepadButtonWidget> {
  static const _turboHalfPeriod = Duration(milliseconds: 40); // ~12 presses/s

  bool _pressed = false; // what the finger / toggle says
  bool _out = false; // what is actually sent (differs from _pressed in turbo)
  Timer? _turboTimer;

  void _set(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
    if (v) {
      _out = true;
      widget.onChanged(true);
      if (widget.turbo) {
        _turboTimer?.cancel();
        _turboTimer = Timer.periodic(_turboHalfPeriod, (_) {
          _out = !_out;
          (widget.onPulse ?? widget.onChanged)(_out);
        });
      }
    } else {
      _turboTimer?.cancel();
      _turboTimer = null;
      _out = false;
      widget.onChanged(false);
    }
  }

  @override
  void dispose() {
    _turboTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    final lit = _pressed;
    final round = !widget.pill;
    final light = Color.lerp(c, Colors.white, 0.5)!;
    final dark = Color.lerp(c, Colors.black, 0.5)!;

    // Glossy sphere (round) or glassy capsule (pill).
    Gradient? fill;
    if (widget.solid) {
      fill = round
          ? RadialGradient(
              center: const Alignment(-0.25, -0.5),
              radius: 1.05,
              colors: lit
                  ? [Color.lerp(c, Colors.white, 0.8)!, Color.lerp(c, Colors.white, 0.3)!, c]
                  : [light, c, dark],
              stops: const [0.0, 0.55, 1.0],
            )
          : LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: lit
                  ? [Color.lerp(c, Colors.white, 0.6)!, Color.lerp(c, Colors.white, 0.15)!]
                  : [light.withOpacity(0.9), dark],
            );
    }

    final rim = Color.lerp(c, Colors.white, 0.65)!.withOpacity(lit ? 0.95 : 0.5);
    final w = widget.pill ? widget.size * 1.8 : widget.size;
    final labelColor = widget.solid
        ? Colors.white
        : (lit ? Colors.black : Colors.white.withOpacity(0.85));

    return GestureDetector(
      onTapDown: (_) => _set(widget.toggle ? !_pressed : true),
      onTapUp: (_) {
        if (!widget.toggle) _set(false);
      },
      onTapCancel: () {
        if (!widget.toggle) _set(false);
      },
      child: AnimatedScale(
        scale: lit ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          width: w,
          height: widget.size,
          decoration: BoxDecoration(
            gradient: fill,
            color: fill == null ? (lit ? c.withOpacity(0.9) : c.withOpacity(0.18)) : null,
            borderRadius: BorderRadius.circular(widget.size / 2),
            border: Border.all(color: rim, width: 2),
            boxShadow: lit
                ? [BoxShadow(color: c.withOpacity(0.65), blurRadius: 22, spreadRadius: 1)]
                : [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 3)),
                    BoxShadow(color: c.withOpacity(widget.solid ? 0.20 : 0.10), blurRadius: 14),
                  ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Soft highlight on top of round buttons.
              if (round && widget.solid)
                Positioned(
                  top: widget.size * 0.07,
                  left: widget.size * 0.2,
                  right: widget.size * 0.2,
                  height: widget.size * 0.3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(widget.size * 0.2),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.white.withOpacity(0.32), Colors.white.withOpacity(0.0)],
                      ),
                    ),
                  ),
                ),
              if (widget.icon != null)
                Icon(widget.icon, color: Colors.white, size: widget.size * 0.5)
              else
                Text(
                  widget.label,
                  style: AppFonts.display(TextStyle(
                    color: labelColor,
                    fontWeight: FontWeight.bold,
                    fontSize: widget.pill ? 12 : widget.size * 0.36,
                    shadows: [Shadow(color: Colors.black.withOpacity(0.45), blurRadius: 4)],
                  )),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
