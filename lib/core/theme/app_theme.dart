import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

/// Configuración centralizada de theming con Material 3 y FlexColorScheme (DeepBlue).
/// Define superficies tonales de alto contraste, bordes redondeados ergonómicos
/// y adaptación dinámica tanto para temas claros como oscuros.
class AppTheme {
  static const FlexScheme _usedScheme = FlexScheme.deepBlue;

  static ThemeData get lightTheme {
    return FlexThemeData.light(
      scheme: _usedScheme,
      useMaterial3: true,
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: 6,
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 10,
        blendOnColors: false,
        useMaterial3Typography: true,
        useM2StyleDividerInM3: false,
        defaultRadius: 14.0,
        cardRadius: 18.0,
        cardElevation: 0.5,
        elevatedButtonSchemeColor: SchemeColor.onPrimaryContainer,
        elevatedButtonSecondarySchemeColor: SchemeColor.primaryContainer,
        segmentedButtonSchemeColor: SchemeColor.primary,
        inputDecoratorBorderType: FlexInputBorderType.outline,
        inputDecoratorUnfocusedBorderIsColored: false,
        chipSchemeColor: SchemeColor.primary,
        tooltipRadius: 8,
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  static ThemeData get darkTheme {
    return FlexThemeData.dark(
      scheme: _usedScheme,
      useMaterial3: true,
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: 12,
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 18,
        useMaterial3Typography: true,
        useM2StyleDividerInM3: false,
        defaultRadius: 14.0,
        cardRadius: 18.0,
        cardElevation: 0.5,
        elevatedButtonSchemeColor: SchemeColor.onPrimaryContainer,
        elevatedButtonSecondarySchemeColor: SchemeColor.primaryContainer,
        segmentedButtonSchemeColor: SchemeColor.primary,
        inputDecoratorBorderType: FlexInputBorderType.outline,
        inputDecoratorUnfocusedBorderIsColored: false,
        chipSchemeColor: SchemeColor.primary,
        tooltipRadius: 8,
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }
}
