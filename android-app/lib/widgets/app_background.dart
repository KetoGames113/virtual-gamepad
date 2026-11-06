import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Shared menu background: deep gradient, drifting neon orbs, a slow
/// synthwave floor grid and floating particles. Purely decorative and drawn
/// in a single repaint-isolated layer.
class AppBackground extends StatefulWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 30))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.gradientTop, AppColors.gradientBottom],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) => CustomPaint(painter: _SceneFx(_c.value)),
                ),
              ),
            ),
          ),
          Positioned.fill(child: widget.child),
        ],
      ),
    );
  }
}

class _Particle {
  final double x, y, size, speed, phase;
  const _Particle(this.x, this.y, this.size, this.speed, this.phase);
}

class _SceneFx extends CustomPainter {
  final double t; // 0..1, loops every 30 s
  _SceneFx(this.t);

  static final List<_Particle> _particles = () {
    final r = math.Random(7);
    return List.generate(
      28,
      (_) => _Particle(r.nextDouble(), r.nextDouble(), 0.8 + r.nextDouble() * 1.8,
          1 + r.nextInt(3).toDouble(), r.nextDouble()),
    );
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final a = t * 2 * math.pi;

    // Drifting neon orbs.
    void orb(Offset c, double r, Color col) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [col, col.withOpacity(0)])
              .createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    orb(Offset(w * (0.88 + 0.05 * math.sin(a)), h * (0.07 + 0.03 * math.cos(a))), 170,
        AppColors.accent.withOpacity(0.22));
    orb(Offset(w * (0.10 + 0.05 * math.cos(a)), h * (0.93 - 0.03 * math.sin(a))), 200,
        AppColors.activeAccent.withOpacity(0.15));
    orb(Offset(w * (0.5 + 0.12 * math.sin(a + 1.2)), h * 0.42), 150,
        AppColors.iconBg.withOpacity(0.10));

    // Synthwave floor: converging verticals + horizontals that glide closer.
    final horizon = h * 0.64;
    final cx = w / 2;
    final line = Paint()..strokeWidth = 1;
    for (var i = -9; i <= 9; i++) {
      line.color = AppColors.activeAccent.withOpacity(0.07);
      canvas.drawLine(Offset(cx + i * 18, horizon), Offset(cx + i * w * 0.17, h), line);
    }
    for (var k = 0; k < 9; k++) {
      final p = ((k + t * 9) % 9) / 9;
      final y = horizon + (h - horizon) * p * p;
      line.color = AppColors.accent.withOpacity(0.03 + 0.10 * p);
      canvas.drawLine(Offset(0, y), Offset(w, y), line);
    }

    // Floating particles.
    final dot = Paint();
    for (final p in _particles) {
      final y = ((p.y - t * 0.06 * p.speed) % 1 + 1) % 1;
      final x = p.x + 0.015 * math.sin(a * p.speed + p.phase * 6);
      final twinkle = 0.5 + 0.5 * math.sin(a * 3 * p.speed + p.phase * 9);
      dot.color = (p.phase > 0.5 ? AppColors.activeAccent : Colors.white)
          .withOpacity(0.10 + 0.22 * twinkle);
      canvas.drawCircle(Offset(x * w, y * h), p.size, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _SceneFx old) => old.t != t;
}

/// Very faint grid + a few diagonal accents: a "game HUD" texture.
class HudGridPainter extends CustomPainter {
  final double step;
  final double opacity;
  const HudGridPainter({this.step = 36, this.opacity = 0.035});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.activeAccent.withOpacity(opacity)
      ..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant HudGridPainter old) =>
      old.step != step || old.opacity != opacity;
}

class _Glow extends StatelessWidget {
  final double size;
  final Color color;
  const _Glow({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withOpacity(0)]),
        ),
      ),
    );
  }
}
