import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static final ThemeData darkCinematicTheme = ThemeData.dark().copyWith(
    scaffoldBackgroundColor: const Color(0xFF0D0D12),
    primaryColor: const Color(0xFFE94560),
    colorScheme: const ColorScheme.dark().copyWith(
      primary: const Color(0xFFE94560),
      secondary: const Color(0xFF533483),
      surface: const Color(0xFF16213E),
      background: const Color(0xFF0D0D12),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: const Color(0xFF0D0D12),
      elevation: 0,
      centerTitle: true,
      titleTextStyle: GoogleFonts.cinzel(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.bold,
        letterSpacing: 2.0,
      ),
      iconTheme: const IconThemeData(color: Colors.white70),
    ),
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
      bodyLarge: const TextStyle(color: Colors.white, fontSize: 16),
      bodyMedium: const TextStyle(color: Colors.white70, fontSize: 14),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1E1E28),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30.0),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      hintStyle: const TextStyle(color: Colors.white38),
    ),
  );
}
