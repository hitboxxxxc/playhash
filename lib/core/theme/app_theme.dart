import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Tema dark-neon do PlayHash.
/// Tipografia: caixa alta em rótulos/botões + letterSpacing generoso.
abstract final class AppTheme {
  /// Estilo padrão para textos em caixa alta com espaçamento.
  static TextStyle neonLabel({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w700,
    Color color = AppColors.textPrimary,
  }) =>
      TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: 1.6,
        color: color,
      );

  static ThemeData dark() {
    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.cyan,
        secondary: AppColors.purple,
        error: AppColors.error,
        surface: AppColors.surface,
        onPrimary: AppColors.background,
        onSecondary: AppColors.textPrimary,
        onError: AppColors.background,
        onSurface: AppColors.textPrimary,
      ),
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 2.0,
          color: AppColors.textPrimary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surface,
        contentTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      dividerColor: AppColors.textSecondary.withValues(alpha: 0.2),
    );
  }
}
