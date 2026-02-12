import 'package:flutter/material.dart';

class KillagramTheme {
  static const _primary = Color(0xFF4C8DFF);
  static const _surface = Color(0xFFF5F7FB);
  static const _darkSurface = Color(0xFF0F1115);

  static final ThemeData light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _primary,
      primary: _primary,
      surface: _surface,
    ),
    scaffoldBackgroundColor: _surface,
    appBarTheme: const AppBarTheme(
      backgroundColor: _surface,
      elevation: 0,
      centerTitle: false,
    ),
  );

  static final ThemeData dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _primary,
      brightness: Brightness.dark,
      primary: _primary,
      surface: _darkSurface,
    ),
    scaffoldBackgroundColor: _darkSurface,
  );
}
