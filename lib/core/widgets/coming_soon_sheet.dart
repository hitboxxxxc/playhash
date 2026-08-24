import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/chamfered_border.dart';

/// Bottom sheet informativo "EM BREVE" — usado para funcionalidades ainda
/// não liberadas (adicionar saldo, editar sala, organizar, notificações).
Future<void> showComingSoonSheet(
  BuildContext context, {
  required String feature,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (BuildContext sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'EM BREVE',
                textAlign: TextAlign.center,
                style: AppTheme.neonLabel(fontSize: 16, color: AppColors.cyan),
              ),
              const SizedBox(height: 12),
              Text(
                '$feature estará disponível em uma próxima atualização.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Semantics(
                button: true,
                child: SizedBox(
                  height: 48,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      shape: ChamferedBorder(
                        cut: 10,
                        side: BorderSide(
                          color: AppColors.cyan.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    child: TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text(
                        'OK',
                        style: TextStyle(
                          color: AppColors.cyan,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
