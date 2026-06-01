import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // THEME LOCK: light+dark — source: domain signal (field tool, outdoor readability)

  static const Color primary = Color(0xFF2563EB);
  static const Color primaryContainer = Color(0xFFDBEAFE);
  static const Color secondary = Color(0xFF0891B2);
  static const Color secondaryContainer = Color(0xFFCFFAFE);

  static const Color success = Color(0xFF16A34A);
  static const Color successContainer = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFFD97706);
  static const Color warningContainer = Color(0xFFFEF3C7);
  static const Color errorColor = Color(0xFFDC2626);
  static const Color errorContainer = Color(0xFFFEE2E2);

  static const Color surfaceLight = Color(0xFFF8FAFC);
  static const Color backgroundLight = Color(0xFFF1F5F9);
  static const Color cardLight = Color(0xFFFFFFFF);

  static const Color surfaceDark = Color(0xFF1E293B);
  static const Color backgroundDark = Color(0xFF0F172A);
  static const Color cardDark = Color(0xFF1E293B);

  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.light(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: primaryContainer,
      onPrimaryContainer: Color(0xFF1E3A8A),
      secondary: secondary,
      onSecondary: Colors.white,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: Color(0xFF0C4A6E),
      surface: cardLight,
      onSurface: Color(0xFF1E293B),
      surfaceContainerHighest: Color(0xFFE2E8F0),
      onSurfaceVariant: Color(0xFF64748B),
      error: errorColor,
      onError: Colors.white,
      errorContainer: errorContainer,
      outline: Color(0xFFCBD5E1),
      outlineVariant: Color(0xFFE2E8F0),
    ),
    scaffoldBackgroundColor: backgroundLight,
    textTheme: GoogleFonts.plusJakartaSansTextTheme().copyWith(
      displayLarge: GoogleFonts.plusJakartaSans(
        fontSize: 32,
        fontWeight: FontWeight.w700,
      ),
      displayMedium: GoogleFonts.plusJakartaSans(
        fontSize: 28,
        fontWeight: FontWeight.w700,
      ),
      displaySmall: GoogleFonts.plusJakartaSans(
        fontSize: 24,
        fontWeight: FontWeight.w600,
      ),
      headlineLarge: GoogleFonts.plusJakartaSans(
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      bodyLarge: GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: GoogleFonts.plusJakartaSans(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
      ),
    ),
    appBarTheme: AppBarThemeData(
      backgroundColor: cardLight,
      foregroundColor: Color(0xFF1E293B),
      elevation: 0,
      scrolledUnderElevation: 2,
      centerTitle: false,
      titleTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1E293B),
      ),
    ),
    cardTheme: CardThemeData(
      color: cardLight,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: Color(0xFFF1F5F9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Color(0xFFCBD5E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Color(0xFFCBD5E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: errorColor),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: BorderSide(color: primary),
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),
    dividerTheme: DividerThemeData(color: Color(0xFFE2E8F0), thickness: 1),
  );

  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.dark(
      primary: Color(0xFF60A5FA),
      onPrimary: Color(0xFF1E3A8A),
      primaryContainer: Color(0xFF1D4ED8),
      onPrimaryContainer: Color(0xFFDBEAFE),
      secondary: Color(0xFF22D3EE),
      onSecondary: Color(0xFF0C4A6E),
      secondaryContainer: Color(0xFF0E7490),
      onSecondaryContainer: Color(0xFFCFFAFE),
      surface: surfaceDark,
      onSurface: Color(0xFFE2E8F0),
      surfaceContainerHighest: Color(0xFF334155),
      onSurfaceVariant: Color(0xFF94A3B8),
      error: Color(0xFFF87171),
      onError: Color(0xFF7F1D1D),
      errorContainer: Color(0xFF991B1B),
      outline: Color(0xFF475569),
      outlineVariant: Color(0xFF334155),
    ),
    scaffoldBackgroundColor: backgroundDark,
    textTheme: GoogleFonts.plusJakartaSansTextTheme().copyWith(
      displayLarge: GoogleFonts.plusJakartaSans(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: Color(0xFFE2E8F0),
      ),
      displayMedium: GoogleFonts.plusJakartaSans(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: Color(0xFFE2E8F0),
      ),
      headlineLarge: GoogleFonts.plusJakartaSans(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: Color(0xFFE2E8F0),
      ),
      headlineMedium: GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Color(0xFFE2E8F0),
      ),
      titleLarge: GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Color(0xFFE2E8F0),
      ),
      titleMedium: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xFFE2E8F0),
      ),
      bodyLarge: GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: Color(0xFFCBD5E1),
      ),
      bodyMedium: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: Color(0xFFCBD5E1),
      ),
      bodySmall: GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: Color(0xFF94A3B8),
      ),
      labelLarge: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFFE2E8F0),
      ),
      labelMedium: GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: Color(0xFFCBD5E1),
      ),
      labelSmall: GoogleFonts.plusJakartaSans(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: Color(0xFF94A3B8),
        letterSpacing: 0.2,
      ),
    ),
    appBarTheme: AppBarThemeData(
      backgroundColor: surfaceDark,
      foregroundColor: Color(0xFFE2E8F0),
      elevation: 0,
      scrolledUnderElevation: 2,
      centerTitle: false,
      titleTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Color(0xFFE2E8F0),
      ),
    ),
    cardTheme: CardThemeData(
      color: surfaceDark,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: Color(0xFF334155),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Color(0xFF475569)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Color(0xFF475569)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Color(0xFF60A5FA), width: 2),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Color(0xFF94A3B8),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Color(0xFF2563EB),
        foregroundColor: Colors.white,
        elevation: 0,
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    dividerTheme: DividerThemeData(color: Color(0xFF334155), thickness: 1),
  );

  // Semantic color helpers
  static Color statusColor(bool isOnline) => isOnline ? success : errorColor;
  static Color statusContainerColor(bool isOnline) =>
      isOnline ? successContainer : errorContainer;
  static Color motionColor(bool isMoving) => isMoving ? primary : warning;
  static Color mqttHealthColor(String health) {
    switch (health) {
      case 'good':
        return success;
      case 'idle':
        return warning;
      default:
        return errorColor;
    }
  }
}
