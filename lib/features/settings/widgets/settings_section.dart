import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/chamfered_border.dart';

/// Card chanfrado de uma seção da tela de Configurações
/// (Conta, Notificações, Aplicativo, Privacidade, Suporte...).
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.accent = AppColors.cyan,
  });

  final String title;
  final List<Widget> children;

  /// Cor de destaque do contorno (ex.: vermelho para Privacidade).
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: AppColors.surface,
        shape: ChamferedBorder(
          cut: 12,
          side: BorderSide(color: accent.withValues(alpha: 0.4)),
        ),
      ),
      // Material transparente: permite ink splashes dos ListTiles sobre o
      // fundo do card (evita assertion do Material).
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title.toUpperCase(),
                style: AppTheme.neonLabel(
                  fontSize: 11,
                  color: accent,
                ),
              ),
              const SizedBox(height: 4),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
