import 'package:flutter/material.dart';

class NewtvColors {
  const NewtvColors._();

  static const primary = Color(0xFF3B82F6);
  static const primaryDim = Color(0xFF2563EB);
  static const accent = Color(0xFF22D3EE);
  static const lightBackground = Color(0xFFF5F7FA);
  static const lightSurfaceSolid = Color(0xFFFFFFFF);
  static const lightText = Color(0xFF0F172A);
  static const lightSecondaryText = Color(0xFF64748B);
  static const darkBackground = Color(0xFF0B0F14);
  static const darkSurfaceSolid = Color(0xFF161C24);
  static const darkText = Color(0xFFE8EDF3);
  static const darkSecondaryText = Color(0xFF94A3B8);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
}

@immutable
class GlassTokens extends ThemeExtension<GlassTokens> {
  const GlassTokens({
    required this.surface,
    required this.border,
    required this.elevatedSurface,
    required this.elevatedBorder,
    required this.playerSurface,
  });

  final Color surface;
  final Color border;
  final Color elevatedSurface;
  final Color elevatedBorder;
  final Color playerSurface;

  static const light = GlassTokens(
    surface: Color(0xB8FFFFFF),
    border: Color(0x99FFFFFF),
    elevatedSurface: Color(0xD9FFFFFF),
    elevatedBorder: Color(0xB8FFFFFF),
    playerSurface: Color(0x99161C24),
  );

  static const dark = GlassTokens(
    surface: Color(0xA8161C24),
    border: Color(0x24FFFFFF),
    elevatedSurface: Color(0xC2161C24),
    elevatedBorder: Color(0x2EFFFFFF),
    playerSurface: Color(0xB80B0F14),
  );

  @override
  GlassTokens copyWith({
    Color? surface,
    Color? border,
    Color? elevatedSurface,
    Color? elevatedBorder,
    Color? playerSurface,
  }) {
    return GlassTokens(
      surface: surface ?? this.surface,
      border: border ?? this.border,
      elevatedSurface: elevatedSurface ?? this.elevatedSurface,
      elevatedBorder: elevatedBorder ?? this.elevatedBorder,
      playerSurface: playerSurface ?? this.playerSurface,
    );
  }

  @override
  GlassTokens lerp(ThemeExtension<GlassTokens>? other, double t) {
    if (other is! GlassTokens) return this;
    return GlassTokens(
      surface: Color.lerp(surface, other.surface, t)!,
      border: Color.lerp(border, other.border, t)!,
      elevatedSurface: Color.lerp(elevatedSurface, other.elevatedSurface, t)!,
      elevatedBorder: Color.lerp(elevatedBorder, other.elevatedBorder, t)!,
      playerSurface: Color.lerp(playerSurface, other.playerSurface, t)!,
    );
  }
}

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: NewtvColors.primary,
      secondary: NewtvColors.accent,
      surface: NewtvColors.lightSurfaceSolid,
      error: NewtvColors.danger,
      onPrimary: Colors.white,
      onSecondary: NewtvColors.lightText,
      onSurface: NewtvColors.lightText,
      onError: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: NewtvColors.lightBackground,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      textTheme: _textTheme(scheme, NewtvColors.lightText),
      extensions: const [GlassTokens.light],
      cardTheme: const CardThemeData(
        color: Color(0xB8FFFFFF),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
    );
  }

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: NewtvColors.primary,
      secondary: NewtvColors.accent,
      surface: NewtvColors.darkSurfaceSolid,
      error: NewtvColors.danger,
      onPrimary: Colors.white,
      onSecondary: NewtvColors.darkText,
      onSurface: NewtvColors.darkText,
      onError: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: NewtvColors.darkBackground,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      textTheme: _textTheme(scheme, NewtvColors.darkText),
      extensions: const [GlassTokens.dark],
      cardTheme: const CardThemeData(
        color: Color(0xA8161C24),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
    );
  }

  static TextTheme _textTheme(ColorScheme scheme, Color color) {
    return TextTheme(
      displaySmall: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: color),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color),
      titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: color),
      bodyLarge: TextStyle(fontSize: 15, height: 1.45, color: color),
      bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: color),
      bodySmall: TextStyle(fontSize: 13, height: 1.35, color: color.withValues(alpha: 0.72)),
      labelSmall: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.62)),
    );
  }
}
