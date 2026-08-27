import 'package:flutter/material.dart';
import '../theme/pixel_theme.dart';

enum PixelButtonStyle { green, purple, gold, gray }

class PixelButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final PixelButtonStyle style;
  final bool full;
  final String disabledText;

  const PixelButton({
    super.key,
    required this.label,
    this.onPressed,
    this.style = PixelButtonStyle.green,
    this.full = true,
    this.disabledText = 'EM BREVE',
  });

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;

    Color bg;
    Color border;
    Color fg;
    switch (style) {
      case PixelButtonStyle.green:
        bg = PixelTheme.green;
        border = const Color(0xFF2A6E2A);
        fg = const Color(0xFF0B0E1A);
        break;
      case PixelButtonStyle.purple:
        bg = PixelTheme.purple;
        border = PixelTheme.purpleDark;
        fg = PixelTheme.text;
        break;
      case PixelButtonStyle.gold:
        bg = PixelTheme.gold;
        border = const Color(0xFF8A6D1F);
        fg = const Color(0xFF0B0E1A);
        break;
      case PixelButtonStyle.gray:
        bg = const Color(0xFF3A4054);
        border = PixelTheme.border;
        fg = PixelTheme.textDim;
        break;
    }
    if (!enabled) {
      bg = const Color(0xFF3A4054);
      border = PixelTheme.border;
      fg = PixelTheme.textDim;
    }

    final Widget button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border, width: 2),
            borderRadius: BorderRadius.circular(PixelTheme.radius),
          ),
          alignment: Alignment.center,
          child: Text(
            (enabled ? label : disabledText).toUpperCase(),
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: 14,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );

    if (full) return SizedBox(width: double.infinity, child: button);
    return button;
  }
}
