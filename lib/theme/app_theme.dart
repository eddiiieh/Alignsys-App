import 'package:flutter/material.dart';
import 'app_colors.dart';

ThemeData buildLightTheme() => _build(AppColorsExtension.light, Brightness.light);
ThemeData buildDarkTheme()  => _build(AppColorsExtension.dark,  Brightness.dark);

ThemeData _build(AppColorsExtension c, Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: c.brand,
    primary: c.brand,
    brightness: brightness,
    surface: c.surface,
  ).copyWith(
    surface: c.surface,
    onSurface: c.textPrimary,
    onSurfaceVariant: c.textSecondary,
    outline: c.border,
    outlineVariant: c.divider,
    error: c.dangerText,
    errorContainer: c.dangerSurface,
    onErrorContainer: c.dangerText,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.surface,
    canvasColor: c.surface,
    dividerColor: c.divider,
    extensions: [c],

    popupMenuTheme: PopupMenuThemeData(
    color: c.surfaceElevated,
    textStyle: TextStyle(color: c.textPrimary),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
  ),

    appBarTheme: AppBarTheme(
      backgroundColor: c.appBarBackground,
      foregroundColor: c.appBarForeground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: c.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: c.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: brightness == Brightness.dark
          ? const Color(0xFF1F2533)
          : const Color(0xFF1F2937),
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    dividerTheme: DividerThemeData(
      color: c.divider,
      thickness: 1,
      space: 1,
    ),

    iconTheme: IconThemeData(color: c.textPrimary),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: c.brand,
        foregroundColor: Colors.white,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.brand,
        foregroundColor: Colors.white,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: c.brand),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.brand,
        side: BorderSide(color: c.border),
      ),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.brand,
      foregroundColor: Colors.white,
      elevation: 2,
    ),

    scrollbarTheme: ScrollbarThemeData(
      thumbVisibility: const WidgetStatePropertyAll(true),
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(8),
      thumbColor: WidgetStatePropertyAll(c.brand.withOpacity(0.35)),
      interactive: true,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.inputFill,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.inputBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.brand, width: 2),
      ),
      hintStyle: TextStyle(color: c.textTertiary),
      labelStyle: TextStyle(color: c.textSecondary),
    ),

    textTheme: TextTheme(
    // ADDED THIS to be safe for anything else using labelLarge
    labelLarge: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600),
    titleLarge:  TextStyle(color: c.textPrimary,   fontWeight: FontWeight.w700),
    titleMedium: TextStyle(color: c.textPrimary,   fontWeight: FontWeight.w600),
    bodyLarge:   TextStyle(color: c.textPrimary),
    bodyMedium:  TextStyle(color: c.textPrimary),
    bodySmall:   TextStyle(color: c.textSecondary),
    ),
  );
}