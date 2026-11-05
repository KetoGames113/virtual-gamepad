import 'package:flutter/material.dart';

class AppColors {
  // Menu / splash background
  static const gradientTop = Color(0xFF0B0820);
  static const gradientBottom = Color(0xFF2A1E6B);

  static const accent = Color(0xFFFF00E5);
  static const accentLight = Color(0xFF32DBFF);

  static const iconBg = Color(0xFF8A2BE2);

  static const Color stickBorder = Color(0xFF2C2F33);
  static const Color activeAccent = Color(0xFF00E6FF);

  static const gamepadTop = Color(0xFF0F0C29);
  static const gamepadBottom = Color(0xFF302B63);

  static const buttonA = Color(0xFF00FF85);
  static const buttonB = Color(0xFFFF1744);
  static const buttonX = Color(0xFF00BFFF);
  static const buttonY = Color(0xFFFFD600);

  static const stickFill = Color(0xFF4B0082);

  // Glass-style surfaces used by the menu
  static const card = Color(0x14FFFFFF); // 8% white
  static const cardBorder = Color(0x1FFFFFFF); // 12% white
  static const success = Color(0xFF00E676);
  static const danger = Color(0xFFFF5252);
  static const warning = Color(0xFFFFC107);
  static const textDim = Color(0xB3FFFFFF);

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF8A2BE2), Color(0xFFD500F9)],
  );
}

class AppTheme {
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.iconBg,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.activeAccent,
      secondary: AppColors.accent,
      surface: const Color(0xFF15122F),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.gradientTop,
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.activeAccent,
        thumbColor: AppColors.activeAccent,
        inactiveTrackColor: Colors.white24,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF241E52),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.iconBg,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.activeAccent),
      ),
    );
  }
}
