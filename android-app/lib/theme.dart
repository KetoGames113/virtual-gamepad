import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Menu / splash background
  static const gradientTop = Color(0xFF060913);
  static const gradientBottom = Color(0xFF1B0F45);

  static const accent = Color(0xFFFF2ED1); // neon magenta
  static const accentLight = Color(0xFF32DBFF);

  static const iconBg = Color(0xFF7C3AED); // electric violet

  static const Color stickBorder = Color(0xFF2C2F33);
  static const Color activeAccent = Color(0xFF00F0FF); // neon cyan

  static const gamepadTop = Color(0xFF070A18);
  static const gamepadBottom = Color(0xFF1A1245);

  static const buttonA = Color(0xFF00FF85);
  static const buttonB = Color(0xFFFF1744);
  static const buttonX = Color(0xFF00BFFF);
  static const buttonY = Color(0xFFFFD600);

  static const stickFill = Color(0xFF3B1B7A);

  // Glass-style surfaces used by the menu
  static const card = Color(0x14FFFFFF); // 8% white
  static const cardBorder = Color(0x3300F0FF); // faint neon edge
  static const success = Color(0xFF00E676);
  static const danger = Color(0xFFFF5252);
  static const warning = Color(0xFFFFC107);
  static const textDim = Color(0xB3FFFFFF);

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF7C3AED), Color(0xFFFF2ED1)],
  );
}

/// Fonts. Headings use a techy display face, everything else a condensed
/// gaming sans. To use your own font instead: put the .ttf in
/// `assets/fonts/`, declare it in pubspec.yaml (see assets/fonts/README.md)
/// and set [custom] to its family name.
class AppFonts {
  static const String? custom = 'KhebratMusamim';

  static TextStyle display([TextStyle? base]) {
    final b = base ?? const TextStyle();
    return custom != null
        ? b.copyWith(fontFamily: custom)
        : GoogleFonts.orbitron(textStyle: b);
  }

  static TextTheme body(TextTheme t) =>
      custom != null ? t.apply(fontFamily: custom) : GoogleFonts.rajdhaniTextTheme(t);
}

/// The chamfered-corner shape used by cards and panels (gaming look).
OutlinedBorder hudShape({Color? border, double cut = 16, double width = 1}) {
  return BeveledRectangleBorder(
    borderRadius: BorderRadius.only(
      topLeft: Radius.circular(cut),
      bottomRight: Radius.circular(cut),
    ),
    side: BorderSide(color: border ?? AppColors.cardBorder, width: width),
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
      surface: const Color(0xFF0B0F1E),
    );

    final base = ThemeData(brightness: Brightness.dark);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      textTheme: AppFonts.body(base.textTheme),
      scaffoldBackgroundColor: AppColors.gradientTop,
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.activeAccent,
        thumbColor: AppColors.activeAccent,
        inactiveTrackColor: Colors.white24,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.activeAccent : Colors.white70),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? AppColors.activeAccent.withOpacity(0.35)
            : Colors.white12),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF141036),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: hudShape(border: AppColors.activeAccent.withOpacity(0.4), cut: 10),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.iconBg,
          foregroundColor: Colors.white,
          shape: hudShape(border: Colors.transparent, cut: 10),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.activeAccent),
      ),
    );
  }
}
