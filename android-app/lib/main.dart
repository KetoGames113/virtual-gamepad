import 'package:flutter/material.dart';

import 'splash_screen.dart';
import 'theme.dart';

void main() {
  runApp(const VirtualGamepadApp());
}

class VirtualGamepadApp extends StatelessWidget {
  const VirtualGamepadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Virtual Gamepad',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const SplashScreen(),
    );
  }
}
