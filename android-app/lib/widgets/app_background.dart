import 'package:flutter/material.dart';

import '../theme.dart';

/// Shared menu background: deep gradient with two soft colour glows.
class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

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
          Positioned(
              top: -90,
              right: -70,
              child: _Glow(size: 260, color: AppColors.accent.withOpacity(0.20))),
          Positioned(
              bottom: -120,
              left: -90,
              child: _Glow(
                  size: 300, color: AppColors.activeAccent.withOpacity(0.14))),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
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
