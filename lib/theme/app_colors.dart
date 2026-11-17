import 'package:flutter/material.dart';

/// Brand constants — unchanged so existing code keeps compiling while
/// we migrate screens to the semantic tokens below.
class AppColors {
  static const Color primary      = Color(0xFF2757AA);
  static const Color surfaceLight = Color(0xFFECF4FC);
  static const Color primaryDark  = Color.fromRGBO(26, 63, 122, 1);
  static Color primaryFaint       = primary.withOpacity(0.08);
  static Color primaryLight       = primary.withOpacity(0.10);
  static Color primaryBorder      = primary.withOpacity(0.35);
  static const Color filledBorder = Color(0xFF2757AA);
  static const Color filledFill   = Color(0xFFECF4FC);
}

/// Semantic tokens that flip with the theme. Read via `context.colors`.
@immutable
class AppColorsExtension extends ThemeExtension<AppColorsExtension> {
  final Color surface;            // scaffold background
  final Color surfaceElevated;    // cards, sheets, dialogs
  final Color surfaceSunken;      // inputs, section header backgrounds
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color divider;
  final Color border;
  final Color inputFill;
  final Color inputBorder;
  final Color appBarBackground;
  final Color appBarForeground;
  final Color scrim;
  final Color shadow;
  final Color brand;              // theme-aware primary accent
  final Color brandTint;          // brand @ ~8%
  final Color brandTintStrong;    // brand @ ~15%
  final Color successSurface;
  final Color successBorder;
  final Color successText;
  final Color warningSurface;
  final Color warningBorder;
  final Color warningText;
  final Color dangerSurface;
  final Color dangerBorder;
  final Color dangerText;

  const AppColorsExtension({
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceSunken,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.divider,
    required this.border,
    required this.inputFill,
    required this.inputBorder,
    required this.appBarBackground,
    required this.appBarForeground,
    required this.scrim,
    required this.shadow,
    required this.brand,
    required this.brandTint,
    required this.brandTintStrong,
    required this.successSurface,
    required this.successBorder,
    required this.successText,
    required this.warningSurface,
    required this.warningBorder,
    required this.warningText,
    required this.dangerSurface,
    required this.dangerBorder,
    required this.dangerText,
  });

  /// Light — mirrors the current app look exactly.
  static const light = AppColorsExtension(
    surface:           Color(0xFFECF4FC),
    surfaceElevated:   Color(0xFFFFFFFF),
    surfaceSunken:     Color(0xFFF3F8FD),
    textPrimary:       Color(0xFF1A1A1A),
    textSecondary:     Color(0xFF6B7280),
    textTertiary:      Color(0xFF9CA3AF),
    divider:           Color(0xFFE5E7EB),
    border:            Color(0xFFD1D5DB),
    inputFill:         Color(0xFFECF4FC),
    inputBorder:       Color(0xFFD1D5DB),
    appBarBackground:  Color(0xFF2757AA),
    appBarForeground:  Color(0xFFFFFFFF),
    scrim:             Color(0x8A000000),
    shadow:            Color(0x14000000),
    brand:             Color(0xFF2757AA),
    brandTint:         Color(0x142757AA),
    brandTintStrong:   Color(0x262757AA),
    successSurface:    Color(0xFFECFDF5),
    successBorder:     Color(0xFFA7F3D0),
    successText:       Color(0xFF065F46),
    warningSurface:    Color(0xFFFEF3C7),
    warningBorder:     Color(0xFFFCD34D),
    warningText:       Color(0xFF92400E),
    dangerSurface:     Color(0xFFFEF2F2),
    dangerBorder:      Color(0xFFFECACA),
    dangerText:        Color(0xFF991B1B),
  );

  /// Dark — near-black, charcoal-blue surfaces. Text is #F1F4F9, not pure
  /// white (Apple HIG). Brand blue is brightened so it reads as an accent.
  static const dark = AppColorsExtension(
    surface:           Color(0xFF0B0F1A),
    surfaceElevated:   Color(0xFF151A26),
    surfaceSunken:     Color(0xFF0F131E),
    textPrimary:       Color(0xFFF1F4F9),
    textSecondary:     Color(0xFF9CA6B8),
    textTertiary:      Color(0xFF6B7280),
    divider:           Color(0xFF232A3A),
    border:            Color(0xFF2C3346),
    inputFill:         Color(0xFF0F131E),
    inputBorder:       Color(0xFF2C3346),
    appBarBackground:  Color(0xFF121824),
    appBarForeground:  Color(0xFFF1F4F9),
    scrim:             Color(0xB3000000),
    shadow:            Color(0x66000000),
    brand:             Color(0xFF5B8DEF),
    brandTint:         Color(0x1F5B8DEF),
    brandTintStrong:   Color(0x335B8DEF),
    successSurface:    Color(0xFF0F2419),
    successBorder:     Color(0xFF1E5A3A),
    successText:       Color(0xFF86EFAC),
    warningSurface:    Color(0xFF2A1F0A),
    warningBorder:     Color(0xFF6B4F12),
    warningText:       Color(0xFFFCD34D),
    dangerSurface:     Color(0xFF2A1112),
    dangerBorder:      Color(0xFF6B2023),
    dangerText:        Color(0xFFFCA5A5),
  );

  @override
  AppColorsExtension copyWith({
    Color? surface, Color? surfaceElevated, Color? surfaceSunken,
    Color? textPrimary, Color? textSecondary, Color? textTertiary,
    Color? divider, Color? border, Color? inputFill, Color? inputBorder,
    Color? appBarBackground, Color? appBarForeground, Color? scrim,
    Color? shadow, Color? brand, Color? brandTint, Color? brandTintStrong,
    Color? successSurface, Color? successBorder, Color? successText,
    Color? warningSurface, Color? warningBorder, Color? warningText,
    Color? dangerSurface, Color? dangerBorder, Color? dangerText,
  }) {
    return AppColorsExtension(
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      divider: divider ?? this.divider,
      border: border ?? this.border,
      inputFill: inputFill ?? this.inputFill,
      inputBorder: inputBorder ?? this.inputBorder,
      appBarBackground: appBarBackground ?? this.appBarBackground,
      appBarForeground: appBarForeground ?? this.appBarForeground,
      scrim: scrim ?? this.scrim,
      shadow: shadow ?? this.shadow,
      brand: brand ?? this.brand,
      brandTint: brandTint ?? this.brandTint,
      brandTintStrong: brandTintStrong ?? this.brandTintStrong,
      successSurface: successSurface ?? this.successSurface,
      successBorder: successBorder ?? this.successBorder,
      successText: successText ?? this.successText,
      warningSurface: warningSurface ?? this.warningSurface,
      warningBorder: warningBorder ?? this.warningBorder,
      warningText: warningText ?? this.warningText,
      dangerSurface: dangerSurface ?? this.dangerSurface,
      dangerBorder: dangerBorder ?? this.dangerBorder,
      dangerText: dangerText ?? this.dangerText,
    );
  }

  @override
  AppColorsExtension lerp(ThemeExtension<AppColorsExtension>? other, double t) {
    if (other is! AppColorsExtension) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColorsExtension(
      surface: l(surface, other.surface),
      surfaceElevated: l(surfaceElevated, other.surfaceElevated),
      surfaceSunken: l(surfaceSunken, other.surfaceSunken),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      divider: l(divider, other.divider),
      border: l(border, other.border),
      inputFill: l(inputFill, other.inputFill),
      inputBorder: l(inputBorder, other.inputBorder),
      appBarBackground: l(appBarBackground, other.appBarBackground),
      appBarForeground: l(appBarForeground, other.appBarForeground),
      scrim: l(scrim, other.scrim),
      shadow: l(shadow, other.shadow),
      brand: l(brand, other.brand),
      brandTint: l(brandTint, other.brandTint),
      brandTintStrong: l(brandTintStrong, other.brandTintStrong),
      successSurface: l(successSurface, other.successSurface),
      successBorder: l(successBorder, other.successBorder),
      successText: l(successText, other.successText),
      warningSurface: l(warningSurface, other.warningSurface),
      warningBorder: l(warningBorder, other.warningBorder),
      warningText: l(warningText, other.warningText),
      dangerSurface: l(dangerSurface, other.dangerSurface),
      dangerBorder: l(dangerBorder, other.dangerBorder),
      dangerText: l(dangerText, other.dangerText),
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColorsExtension get colors =>
      Theme.of(this).extension<AppColorsExtension>() ?? AppColorsExtension.light;
}