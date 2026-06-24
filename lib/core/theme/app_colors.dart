import 'package:flutter/material.dart';

class AppColors {
  // Brand Colors
  static const Color gold = Color(0xFFEDA900);
  static const Color navy = Color(0xFF1B2A49);
  
  // Neutral Colors
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color grey = Color(0xFF9E9E9E);
  static const Color lightGrey = Color(0xFFF5F5F5);
  static const Color darkGrey = Color(0xFF212121);

  // Status Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color error = Color(0xFFF44336);
  static const Color warning = Color(0xFFFFC107);
  static const Color info = Color(0xFF2196F3);

  // Derived Colors for Theme
  static Color get scaffoldBackgroundLight => white;
  static Color get scaffoldBackgroundDark => navy;
  
  static Color get cardBackgroundLight => white;
  static Color get cardBackgroundDark => navy.withOpacity(0.8);
}
