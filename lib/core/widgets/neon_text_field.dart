import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Campo de texto do PlayHash com borda neon no foco.
/// Sempre usado dentro de um [Form] para validação centralizada.
class NeonTextField extends StatelessWidget {
  const NeonTextField({
    super.key,
    this.controller,
    this.labelText,
    this.hintText,
    this.obscureText = false,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.onFieldSubmitted,
    this.enabled = true,
    this.autofillHints,
  });

  final TextEditingController? controller;
  final String? labelText;
  final String? hintText;
  final bool obscureText;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final bool enabled;
  final List<String>? autofillHints;

  OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      enabled: enabled,
      autofillHints: autofillHints,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: TextStyle(
          color: AppColors.textSecondary.withValues(alpha: 0.6),
        ),
        errorStyle: const TextStyle(color: AppColors.error, fontSize: 12.5),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: _border(AppColors.textSecondary.withValues(alpha: 0.25)),
        enabledBorder: _border(AppColors.textSecondary.withValues(alpha: 0.25)),
        focusedBorder: _border(AppColors.cyan, width: 1.4),
        errorBorder: _border(AppColors.error),
        focusedErrorBorder: _border(AppColors.error, width: 1.4),
      ),
    );
  }
}
