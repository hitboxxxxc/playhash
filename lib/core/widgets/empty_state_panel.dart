import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'neon_panel.dart';
import 'neon_icons.dart';

/// Estado vazio estrutural padrão do PlayHash: painel chanfrado com ícone,
/// título e mensagem. NUNCA exibe valores econômicos inventados.
class EmptyStatePanel extends StatelessWidget {
  const EmptyStatePanel({
    super.key,
    required this.message,
    this.title,
    this.icon = NeonIcons.home,
    this.compact = false,
  });

  final String message;
  final String? title;
  final String icon;

  /// Versão reduzida para uso dentro de outros painéis.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return NeonPanel(
      padding: EdgeInsets.symmetric(
        horizontal: 20,
        vertical: compact ? 18 : 32,
      ),
      accent: AppColors.purple,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SvgPicture.string(
            icon,
            width: compact ? 28 : 40,
            colorFilter: const ColorFilter.mode(
              AppColors.purple,
              BlendMode.srcIn,
            ),
          ),
          SizedBox(height: compact ? 10 : 16),
          if (title != null) ...<Widget>[
            Text(
              title!.toUpperCase(),
              textAlign: TextAlign.center,
              style: AppTheme.neonLabel(
                fontSize: compact ? 13 : 15,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
