import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

/// Configuración centralizada de theming con Material 3 y FlexColorScheme.
/// Diseñado exclusivamente en Modo Oscuro con paleta Cyberpunk / Synthwave:
/// - Violeta / Púrpura Neón como color principal.
/// - Cian / Azul Eléctrico como secundario.
/// - Magenta / Rosa Neón como acento terciario.
class AppTheme {
  static const FlexSchemeColor _cyberpunkDark = FlexSchemeColor(
    primary: Color(0xFFA855F7), // Neon Violet / Purple
    primaryContainer: Color(0xFF581C87),
    secondary: Color(0xFF38BDF8), // Electric Cyan / Neon Sky Blue
    secondaryContainer: Color(0xFF0369A1),
    tertiary: Color(0xFFF472B6), // Neon Rose / Magenta
    tertiaryContainer: Color(0xFF831843),
    appBarColor: Color(0xFF0B0F19),
    error: Color(0xFFF87171),
  );

  /// Gradiente Cyberpunk Neón para Video y Acciones Primarias (Púrpura Neón -> Azul Cobalto)
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [
      Color(0xFF8B5CF6),
      Color(0xFF2563EB),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Gradiente Cyberpunk para Audio (Cian Eléctrico -> Azul Neón)
  static const LinearGradient audioGradient = LinearGradient(
    colors: [
      Color(0xFF06B6D4),
      Color(0xFF3B82F6),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Gradiente para Análisis de Enlaces (Púrpura Vibrante -> Azul Neón)
  static const LinearGradient analyzeGradient = LinearGradient(
    colors: [
      Color(0xFF9333EA),
      Color(0xFF3B82F6),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Tema de la aplicación fijado en modo oscuro
  static ThemeData get darkTheme {
    return FlexThemeData.dark(
      colors: _cyberpunkDark,
      useMaterial3: true,
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: 8,
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 12,
        useMaterial3Typography: true,
        useM2StyleDividerInM3: false,
        defaultRadius: 14.0,
        cardRadius: 18.0,
        cardElevation: 1.0,
        inputDecoratorBorderType: FlexInputBorderType.outline,
        inputDecoratorUnfocusedBorderIsColored: false,
        tooltipRadius: 8,
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }
}
