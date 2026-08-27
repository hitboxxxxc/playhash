import 'package:flutter/material.dart';
import '../theme/pixel_theme.dart';

class PixelCard extends StatelessWidget {
  final Widget child;
  final Color borderColor;
  final EdgeInsetsGeometry padding;

  const PixelCard({
    super.key,
    required this.child,
    this.borderColor = PixelTheme.border,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: PixelTheme.panel,
        border: Border.all(color: borderColor, width: PixelTheme.borderWidth),
        borderRadius: BorderRadius.circular(PixelTheme.radius),
      ),
      child: child,
    );
  }
}
