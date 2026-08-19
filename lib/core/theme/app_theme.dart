import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Colors
  static const Color background = Color(
    0xFF121212,
  ); // Koyu grafit / Siyaha yakın
  static const Color surface = Color(0xFF1E1E1E); // Çok koyu gri
  static const Color surfaceVariant = Color(
    0xFF2C2C2C,
  ); // Biraz daha açık yüzey

  static const Color textPrimary = Color(0xFFF5F5F5); // Kırık beyaz
  static const Color textSecondary = Color(0xFFAAAAAA); // Gri

  static const Color statusNormal = Color(0xFF4CAF50); // Yeşil
  static const Color statusUpcoming = Color(0xFFFFB300); // Amber/Turuncu
  static const Color statusOverdue = Color(0xFFF44336); // Kırmızı
  static const Color infoWarranty = Color(0xFF29B6F6); // Mavi/Cyan

  static const Color primaryAction = Color(
    0xFF3F51B5,
  ); // Indigo veya referanstaki lacivert tonları (ana buton için)

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: primaryAction,
        surface: surface,
        error: statusOverdue,
        onPrimary: textPrimary,
        onSurface: textPrimary,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme)
          .copyWith(
            displayLarge: GoogleFonts.inter(
              color: textPrimary,
              fontWeight: FontWeight.bold,
            ),
            displayMedium: GoogleFonts.inter(
              color: textPrimary,
              fontWeight: FontWeight.bold,
            ),
            titleLarge: GoogleFonts.inter(
              color: textPrimary,
              fontWeight: FontWeight.w600,
            ),
            titleMedium: GoogleFonts.inter(
              color: textPrimary,
              fontWeight: FontWeight.w500,
            ),
            bodyLarge: GoogleFonts.inter(color: textPrimary),
            bodyMedium: GoogleFonts.inter(color: textSecondary),
          ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: background,
        selectedItemColor: textPrimary,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryAction,
          foregroundColor: textPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        ),
      ),
    );
  }
}
