import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";

/// Tactical HUD theme — all UI colors must reference these constants only.
class AppTheme {
  AppTheme._();

  static const Color kBg = Color(0xFF070B0F);
  static const Color kSurface = Color(0xFF0D1117);
  static const Color kPanel = Color(0xFF111820);
  static const Color kBorder = Color(0xFF1E2D3D);
  static const Color kAccent = Color(0xFF00C8FF);
  static const Color kGo = Color(0xFF00FF94);
  static const Color kRev = Color(0xFF4B9EFF);
  static const Color kStop = Color(0xFFFF3B3B);
  static const Color kRecord = Color(0xFFFF6B00);
  static const Color kWarn = Color(0xFFFFB800);
  static const Color kDim = Color(0xFF1A2535);
  static const Color kTextPri = Color(0xFFE8F4FF);
  static const Color kTextSec = Color(0xFF5A7A9A);
  static const Color kTextNum = Color(0xFF00C8FF);
  /// Subtle glow tint (accent @ ~10% alpha) for panel washes.
  static const Color kGlow = Color(0x1A00C8FF);

  static TextStyle displayNum(double size, {FontWeight? weight, Color? color}) =>
      GoogleFonts.orbitron(
        fontSize: size,
        fontWeight: weight ?? FontWeight.w600,
        color: color ?? kTextNum,
        letterSpacing: 0.5,
      );

  static TextStyle labelUi(double size, {FontWeight? weight, Color? color}) =>
      GoogleFonts.exo2(
        fontSize: size,
        fontWeight: weight ?? FontWeight.w500,
        color: color ?? kTextPri,
        letterSpacing: 0.4,
      );

  static TextStyle monoData(double size, {FontWeight? weight, Color? color}) =>
      GoogleFonts.shareTechMono(
        fontSize: size,
        fontWeight: weight ?? FontWeight.w400,
        color: color ?? kTextNum,
      );

  static TextTheme get _textTheme => TextTheme(
        displayLarge: displayNum(28, weight: FontWeight.w700),
        displayMedium: displayNum(22, weight: FontWeight.w600),
        displaySmall: displayNum(18, weight: FontWeight.w600),
        headlineMedium: labelUi(16, weight: FontWeight.w700),
        titleLarge: labelUi(15, weight: FontWeight.w600),
        titleMedium: labelUi(13, weight: FontWeight.w600),
        bodyLarge: labelUi(13),
        bodyMedium: monoData(12),
        bodySmall: monoData(11),
        labelLarge: labelUi(12, weight: FontWeight.w600),
        labelMedium: monoData(10),
      );

  static ThemeData get themeData {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: kBg,
      canvasColor: kBg,
      primaryColor: kAccent,
      textTheme: _textTheme,
      colorScheme: const ColorScheme.dark(
        primary: kAccent,
        secondary: kGo,
        error: kStop,
        surface: kSurface,
      ),
      dividerColor: kBorder,
      iconTheme: const IconThemeData(color: kTextPri),
      splashColor: kAccent.withValues(alpha: 0.12),
      highlightColor: kAccent.withValues(alpha: 0.08),
      cardTheme: CardThemeData(
        color: kSurface,
        elevation: 0,
        shape: const RoundedRectangleBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: kPanel,
        labelStyle: labelUi(11, color: kTextSec),
        hintStyle: monoData(11, color: kTextSec),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderSide: const BorderSide(color: kBorder),
          borderRadius: BorderRadius.zero,
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: kBorder),
          borderRadius: BorderRadius.zero,
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: kAccent, width: 1.5),
          borderRadius: BorderRadius.zero,
        ),
      ),
    );
  }
}
