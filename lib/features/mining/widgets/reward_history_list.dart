import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/coin_format.dart';
import '../../../core/widgets/empty_state_panel.dart';
import '../../../core/widgets/neon_icons.dart';
import '../../../core/widgets/neon_panel.dart';
import '../../../data/repositories/mining_repository.dart';

/// "HISTÓRICO DE RECOMPENSAS" — lista via [MiningRepository].
/// Vazio (ou backend ausente) => empty state. Nada inventado.
class RewardHistoryList extends StatelessWidget {
  const RewardHistoryList({
    super.key,
    required this.entries,
    this.loading = false,
  });

  final List<RewardEntry> entries;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: Text(
            'HISTÓRICO DE RECOMPENSAS',
            style: AppTheme.neonLabel(fontSize: 14),
          ),
        ),
        const SizedBox(height: 12),
        if (loading)
          const NeonPanel(
            accent: AppColors.purple,
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(
                  color: AppColors.cyan,
                  strokeWidth: 2,
                ),
              ),
            ),
          )
        else if (entries.isEmpty)
          const EmptyStatePanel(
            icon: NeonIcons.coin,
            title: 'Nenhuma recompensa ainda',
            message:
                'Suas recompensas de bloco aparecerão aqui quando o '
                'servidor começar a distribuí-las.',
            compact: true,
          )
        else
          NeonPanel(
            accent: AppColors.purple,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < entries.length; i++) ...<Widget>[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: AppColors.textSecondary.withValues(alpha: 0.15),
                    ),
                  _HistoryRow(entry: entries[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Formatação própria (sem dependência externa): "dd/MM HH:mm".
String _formatDateTime(DateTime value) {
  final DateTime local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)} '
      '${two(local.hour)}:${two(local.minute)}';
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final RewardEntry entry;

  @override
  Widget build(BuildContext context) {
    final DateTime? createdAt = entry.createdAt;
    final String time = createdAt == null ? '—' : _formatDateTime(createdAt);

    return Semantics(
      label: 'Recompensa recebida',
      value: CoinFormat.formatWithTicker(entry.amountMinimalUnits),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: <Widget>[
            SvgPicture.string(
              NeonIcons.coin,
              width: 20,
              colorFilter: const ColorFilter.mode(
                AppColors.gold,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 10),
            SvgPicture.string(
              NeonIcons.clock,
              width: 16,
              colorFilter: const ColorFilter.mode(
                AppColors.textSecondary,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              time,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            Text(
              '+${CoinFormat.formatWithTicker(entry.amountMinimalUnits)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.gold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
