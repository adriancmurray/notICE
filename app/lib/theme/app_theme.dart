import 'package:flutter/material.dart';

/// notICE design system tokens.
/// 
/// Centralizes colors, typography, and component themes.
abstract final class AppTheme {
  // ─────────────────────────────────────────────────────────────
  // Color Palette
  // ─────────────────────────────────────────────────────────────
  
  /// Primary accent (Electric Cyan)
  static const Color primary = Color(0xFF00E5FF);
  
  /// Background (Deep Cyber Navy)
  static const Color background = Color(0xFF05101A);
  
  /// Surface/card color (Slightly lighter navy)
  static const Color surface = Color(0xFF0F2639);
  
  /// Danger red (for alerts)
  static const Color danger = Color(0xFFE53935);
  
  /// Warning orange
  static const Color warning = Color(0xFFFFA726);
  
  /// Safe green
  static const Color safe = Color(0xFF66BB6A);

  // ─────────────────────────────────────────────────────────────
  // Theme Data
  // ─────────────────────────────────────────────────────────────
  
  /// Dark theme for the app.
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: background,
      cardTheme: CardThemeData(
        color: surface,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: primary.withValues(alpha: 0.3),
        labelStyle: const TextStyle(fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
