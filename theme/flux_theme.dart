import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class FluxTheme {
  static const pink = Color(0xFFFF375F);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: pink,
      brightness: brightness,
      surface: isDark ? const Color(0xFF161618) : const Color(0xFFF8F8FA),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: GoogleFonts.interTextTheme().apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          color: scheme.onSurface,
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.1,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? const Color(0xFF242428) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: pink,
        inactiveTrackColor: scheme.onSurface.withValues(alpha: .12),
        thumbColor: pink,
        overlayColor: pink.withValues(alpha: .12),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xE61C1C1E) : const Color(0xE6FFFFFF),
        indicatorColor: pink.withValues(alpha: .14),
        labelTextStyle: WidgetStatePropertyAll(GoogleFonts.inter(fontSize: 11)),
      ),
    );
  }
}
