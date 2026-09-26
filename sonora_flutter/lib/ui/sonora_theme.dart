import 'package:flutter/material.dart';

abstract final class SonoraColors {
  static const background = Color(0xFF090B0A);
  static const surface = Color(0xFF151816);
  static const surfaceHigh = Color(0xFF202420);

  /// Hairlines and dividers, kept here so a border does not become a literal
  /// hex value in a widget.
  static const outline = Color(0xFF2A302C);

  /// The tint behind the selected row in a list or the drawer.
  static const selected = Color(0xFF213129);

  /// A faint brand wash, for a header or a banner rather than a control.
  static const brandWash = Color(0xFF16201A);
  static const green = Color(0xFF63E69D);
  static const coral = Color(0xFFFF8066);
  static const lilac = Color(0xFFA58CFF);
  static const text = Color(0xFFF5F6F2);
  static const muted = Color(0xFF9DA39D);
}

/// Corner radii, so a card, a control and a chip do not each pick their own.
abstract final class SonoraRadius {
  static const chip = BorderRadius.all(Radius.circular(11));
  static const control = BorderRadius.all(Radius.circular(15));
  static const card = BorderRadius.all(Radius.circular(18));
  static const panel = BorderRadius.horizontal(right: Radius.circular(24));
}

abstract final class SonoraTheme {
  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: SonoraColors.green,
      brightness: Brightness.dark,
      surface: SonoraColors.surface,
    );
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: SonoraColors.background,
      colorScheme: scheme.copyWith(
        primary: SonoraColors.green,
        surface: SonoraColors.surface,
        onSurface: SonoraColors.text,
      ),
      fontFamily: 'Arial',
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontSize: 38,
          height: 1.02,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
        headlineMedium: TextStyle(
          fontSize: 26,
          height: 1.1,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        bodyLarge: TextStyle(fontSize: 16, letterSpacing: 0),
        bodyMedium: TextStyle(fontSize: 14, letterSpacing: 0),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Color(0xFF0D100E),
        indicatorColor: Color(0xFF26392D),
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: SonoraColors.text,
        inactiveTrackColor: Color(0xFF4A4E4A),
        thumbColor: SonoraColors.text,
        trackHeight: 3,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SonoraColors.surfaceHigh,
        hintStyle: const TextStyle(color: SonoraColors.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}
