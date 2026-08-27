import 'package:flutter/material.dart';

class PixelTheme {
  PixelTheme._();

  static const Color background = Color(0xFF0B0E1A);
  static const Color panel = Color(0xFF141827);
  static const Color border = Color(0xFF2A2F45);
  static const Color purple = Color(0xFF7C4DFF);
  static const Color purpleDark = Color(0xFF4A2B7A);
  static const Color green = Color(0xFF3FA63F);
  static const Color greenLight = Color(0xFF59D059);
  static const Color gold = Color(0xFFF5C542);
  static const Color cyan = Color(0xFF35E0E0);
  static const Color red = Color(0xFFE05555);
  static const Color text = Color(0xFFEDEFF7);
  static const Color textDim = Color(0xFF9AA3B8);

  static const double borderWidth = 2.0;
  static const double radius = 4.0;
  static const double spacingS = 8.0;
  static const double spacingM = 12.0;
  static const double spacingL = 16.0;

  static const TextStyle title = TextStyle(
    color: text,
    fontWeight: FontWeight.w800,
    fontSize: 16,
    letterSpacing: 1.1,
  );

  static const TextStyle bigValue = TextStyle(
    color: text,
    fontWeight: FontWeight.w800,
    fontSize: 28,
  );

  static const TextStyle label = TextStyle(color: textDim, fontSize: 12);
}
