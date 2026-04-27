// lib/theme/app_colors.dart
import 'package:flutter/material.dart';

class AppColors {
  static const Color primary      = Color(0xFF2757AA);
  static const Color surfaceLight = Color(0xFFECF4FC);

  // Derived — used throughout the app
  static const Color primaryDark  = Color(0xFF1A3F7A); // for appBar, splash bg
  static Color primaryFaint       = primary.withOpacity(0.08); // icon bg tints
  static Color primaryLight       = primary.withOpacity(0.10); // section headers
  static Color primaryBorder      = primary.withOpacity(0.35); // scrollbar thumb

  // Form field "filled" state (was 0xFF2563EB / 0xFFF0F6FF)
  static const Color filledBorder = Color(0xFF2757AA); // same as primary
  static const Color filledFill   = Color(0xFFECF4FC); // same as surfaceLight
}