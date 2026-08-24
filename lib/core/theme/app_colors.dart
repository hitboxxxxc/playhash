import 'package:flutter/material.dart';

/// Tokens de cor do tema dark-neon do PlayHash.
/// Fonte única de verdade — nunca usar cores literais fora daqui.
abstract final class AppColors {
  // Fundos
  static const Color background = Color(0xFF05060E);
  static const Color surface = Color(0xFF0B0E1A);

  // Neons
  static const Color cyan = Color(0xFF00E5FF);
  static const Color purple = Color(0xFF7C4DFF);
  static const Color gold = Color(0xFFFFC400);

  // Semânticas
  static const Color green = Color(0xFF3DDC84);
  static const Color error = Color(0xFFFF5252);

  // Texto
  static const Color textPrimary = Color(0xFFF2F4FF);
  static const Color textSecondary = Color(0xFF9AA3C0);
}
