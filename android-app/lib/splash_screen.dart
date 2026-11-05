import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/connect_screen.dart';
import 'theme.dart';
import 'widgets/app_background.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    Timer(const Duration(milliseconds: 1300), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 350),
            pageBuilder: (_, __, ___) => const ConnectScreen(),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: Center(
          // Logo + wordmark ease in together.
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutBack,
            builder: (context, v, child) => Opacity(
              opacity: v.clamp(0.0, 1.0).toDouble(),
              child: Transform.scale(scale: 0.8 + 0.2 * v, child: child),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    gradient: AppColors.accentGradient,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.accent.withOpacity(0.35),
                          blurRadius: 36,
                          offset: const Offset(0, 10)),
                    ],
                  ),
                  child: const Icon(Icons.sports_esports,
                      color: Colors.white, size: 76),
                ),
                const SizedBox(height: 28),
                // Approximation of the script "Virtual" wordmark from the design -
                // swap in the exact font if you share the Canva font name.
                Text(
                  'Virtual',
                  style: GoogleFonts.inspiration(
                    textStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 80,
                      fontStyle: FontStyle.italic,
                      fontFamily: 'cursive',
                      fontWeight: FontWeight.w500,
                      height: 1,
                    ),
                  ),
                ),
                const Text(
                  'GAMEPAD',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Free forever',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.75), fontSize: 15),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
