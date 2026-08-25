import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/coin_format.dart';

/// Entrada unificada do histórico da carteira (mescla de rewards/{uid}/items
/// com saques). Destino SEMPRE mascarado ([destinationMasked] — e-mail
/// FaucetPay no fluxo v3) — nunca o valor completo.
class WalletHistoryItem {
  const WalletHistoryItem({
    required this.title,
    required this.amount,
    this.date,
    this.status, // apenas p/ saques: processing | completed | failed
    this.destinationMasked,
  });

  final String title;
  final BigInt amount; // negativo = saída
  final DateTime? date;
  final String? status;

  /// Máscara do destino (ex.: 'ow***@example.com') — NUNCA o completo.
  final String? destinationMasked;

  bool get isWithdrawal => status != null;
}

/// Lista do histórico da CARTEIRA: mescla entradas/saídas de recompensas
/// com os saques (chip de status processando/concluído/falhado).
class WalletHistoryList extends StatelessWidget {
  const WalletHistoryList({super.key, required this.items});

  final List<WalletHistoryItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'Sem movimentações ainda.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return Column(
      children: <Widget>[
        for (int i = 0; i < items.length; i++) ...<Widget>[
          _HistoryTile(item: items[i]),
          if (i < items.length - 1)
            Divider(
              height: 1,
              indent: 12,
              endIndent: 12,
              color: AppColors.textSecondary.withValues(alpha: 0.12),
            ),
        ],
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item});

  final WalletHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final bool out = item.amount < BigInt.zero;
    final Color amountColor = out ? AppColors.error : AppColors.green;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        item.title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (item.isWithdrawal) ...<Widget>[
                      const SizedBox(width: 8),
                      _StatusChip(status: item.status!),
                    ],
                  ],
                ),
                if (item.destinationMasked != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      item.destinationMasked!, // SEMPRE mascarado
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                if (item.date != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _formatDate(item.date!),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textSecondary.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${out ? '-' : '+'}${CoinFormat.formatMinimalUnits(item.amount.abs())}',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: amountColor,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

/// Chip de status do saque: processando (ciano) / concluído (verde) /
/// falhado (vermelho).
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final Color color;
    switch (status) {
      case 'completed':
        label = 'CONCLUÍDO';
        color = AppColors.green;
      case 'failed':
        label = 'FALHADO';
        color = AppColors.error;
      default:
        label = 'PROCESSANDO';
        color = AppColors.cyan;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
