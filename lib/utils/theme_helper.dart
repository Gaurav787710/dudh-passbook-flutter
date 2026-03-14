import 'package:flutter/material.dart';

/// Centralized theme-aware color helper for Dudh Passbook
/// Use these methods for dark mode support in screens
class TH {
  TH._();
  
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
  
  // Card / Surface colors
  static Color cardColor(BuildContext context) =>
      isDark(context) ? const Color(0xFF1E1E2E) : Colors.white;
  
  // Text colors
  static Color textColor(BuildContext context) =>
      isDark(context) ? Colors.white : const Color(0xFF1A1A1A);
  
  static Color textLightColor(BuildContext context) =>
      isDark(context) ? Colors.white70 : const Color(0xFF666666);
  
  // Primary colors
  static Color primaryColor(BuildContext context) =>
      isDark(context) ? const Color(0xFF5C6BC0) : const Color(0xFF2E7D32);

  static Color primaryDarkColor(BuildContext context) =>
      isDark(context) ? const Color(0xFF1A237E) : const Color(0xFF1B5E20);

  // Input / field background
  static Color fieldBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF2A2A3E) : const Color(0xFFF5F7FA);
  
  // Border / divider
  static Color borderColor(BuildContext context) =>
      isDark(context) ? Colors.white12 : Colors.grey.shade200;
  
  // Gradient for primary buttons/headers
  static List<Color> primaryGradient(BuildContext context) =>
      isDark(context) 
          ? [const Color(0xFF5C6BC0), const Color(0xFF1A237E)]
          : [const Color(0xFF2E7D32), const Color(0xFF1B5E20)];
}
