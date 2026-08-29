// WariMesh — shared color palette + ThemeData.
import 'package:flutter/material.dart';

class AppColors {
  static const Color sos = Color(0xFFCC4125); // warm red — emergency
  static const Color lostPerson = Color(0xFF2E6BA3); // blue — search & care
  static const Color relayed = Color(0xFF1D9E75); // green — mesh working
  static const Color warning = Color(0xFFBA7517); // amber
  static const Color demo = Color(0xFF6B4EA0); // purple — simulated activity
  static const Color neutral = Color(0xFF6B6B66);

  static Color forLogKind(String kind) {
    switch (kind) {
      case 'Sent':
        return sos;
      case 'Received':
        return lostPerson;
      case 'Relayed':
        return relayed;
      case 'Final hop':
        return neutral;
      case 'Advisory':
        return demo;
      default:
        return warning;
    }
  }
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.sos,
    brightness: Brightness.light,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFFFAF7F5),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 2,
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}
