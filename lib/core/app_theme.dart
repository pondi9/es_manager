import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand Colors
  static const Color esBlue = Color(0xFF007BFF);
  static const Color esGreen = Color(0xFF00C853);
  static const Color esOrange = Color(0xFFF59E0B);
  static const Color esRed = Color(0xFFEF4444);

  // Legacy Compatibility Colors - REQUIRED for some screens
  static const Color primaryNavy = Color(0xFF001A2C);
  static const Color bgLight = Color(0xFFF1F5F9);
  static const Color accentBlue = Color(0xFF007BFF);
  static const Color accentGreen = Color(0xFF00C853);
  static const Color accentOrange = Color(0xFFF59E0B);
  static const Color accentPurple = Color(0xFF6366F1);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textBlack = Color(0xFF1E293B);
  static const Color textMuted = Color(0xFF64748B);

  // Dark Theme Colors (Classic ES CRM)
  static const Color darkBg = Color(0xFF001220);
  static const Color darkSurface = Color(0xFF001A2C);
  static const Color darkBorder = Color(0xFF003366);

  // Light Theme Colors (Modern CRM)
  static const Color lightBg = Color(0xFFF1F5F9);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE2E8F0);

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: lightBg,
    colorScheme: const ColorScheme.light(
      primary: esBlue,
      onPrimary: Colors.white,
      secondary: esBlue,
      onSecondary: Colors.white,
      surface: lightSurface,
      onSurface: Color(0xFF0F172A),
      surfaceVariant: Color(0xFFF8FAFC),
      onSurfaceVariant: Color(0xFF64748B),
      outline: lightBorder,
      error: esRed,
    ),
    textTheme: GoogleFonts.montserratTextTheme().apply(
      bodyColor: const Color(0xFF0F172A),
      displayColor: const Color(0xFF0F172A),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF001A2C),
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dividerTheme: const DividerThemeData(color: lightBorder, thickness: 1),
    iconTheme: const IconThemeData(color: Color(0xFF475569)),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: darkBg,
    colorScheme: ColorScheme.dark(
      primary: esBlue,
      onPrimary: Colors.white,
      secondary: esBlue,
      onSecondary: Colors.white,
      surface: darkSurface,
      onSurface: Colors.white,
      surfaceVariant: const Color(0xFF002B4D),
      onSurfaceVariant: Colors.white70,
      outline: darkBorder.withOpacity(0.5),
      error: esRed,
    ),
    textTheme: GoogleFonts.montserratTextTheme().apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF001A2C),
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: darkSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withOpacity(0.05)),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Colors.white10, thickness: 1),
    iconTheme: const IconThemeData(color: Colors.white70),
    popupMenuTheme: PopupMenuThemeData(
      color: darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: const BorderSide(color: Colors.white10),
      ),
    ),
  );
}
