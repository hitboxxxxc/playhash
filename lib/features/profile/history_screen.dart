import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/coin_format.dart';
import '../../core/widgets/neon_panel.dart';
import '../../data/repositories/payouts_repository.dart';

/// Linha unificada do histórico: uma entrada de recompensa OU um saque.
class _HistoryRow {
  const _HistoryRow.reward(RewardHistoryEntry entry)
      : reward = entry,
        withdrawal = null;

  const _HistoryRow.withdrawal(this.withdrawal) : reward = null;

  final RewardHistoryEntry? reward;
  final WithdrawalModel? withdrawal;

  DateTime? get date => reward?.createdAt ?? withdrawal?.createdAt;
}

/// Tela HISTÓRICO: junta o espelho de recompensas (`rewards/{uid}/items`,
/// orderBy createdAt desc limit 50) com os saques (`withdrawals` onde
/// uid == auth.uid) e exibe em ordem decrescente de data. Valores são
/// sempre os oficiais do backend — nada é calculado aqui.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<String?> uidValue = ref.watch(currentUidProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('HISTÓRICO')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: uidValue.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.cyan),
              ),
              error: (_, _) => _ErrorState(
                onRetry: () => ref.invalidate(currentUidProvider),
              ),
              data: (String? uid) => uid == null
                  ? const _EmptyState()
                  : _HistoryList(uid: uid),
            ),
          ),
        ),
      ),
    );
  }
}

/// Conteúdo com os dois StreamBuilders; um UniqueKey permite remontar as
/// streams no botão "repetir" após erro.
class _HistoryList extends ConsumerStatefulWidget {
  const _HistoryList({required this.uid});

  final String uid;

  @override
  ConsumerState<_HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends ConsumerState<_HistoryList> {
  Key _contentKey = UniqueKey();

  void _retry() => setState(() => _contentKey = UniqueKey());

  @override
  Widget build(BuildContext context) {
    final PayoutsRepositoryApi repo = ref.read(payoutsRepositoryProvider);
    return KeyedSubtree(
      key: _contentKey,
      child: StreamBuilder<List<RewardHistoryEntry>>(
        stream: repo.watchRewardItems(widget.uid),
        builder: (
          BuildContext context,
          AsyncSnapshot<List<RewardHistoryEntry>> rewards,
        ) {
          return StreamBuilder<List<WithdrawalModel>>(
            stream: repo.watchUserWithdrawals(widget.uid),
            builder: (
              BuildContext context,
              AsyncSnapshot<List<WithdrawalModel>> withdrawals,
            ) {
              if (rewards.hasError || withdrawals.hasError) {
                return _ErrorState(onRetry: _retry);
              }
              if (!rewards.hasData || !withdrawals.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.cyan),
                );
              }

              final List<_HistoryRow> rows = <_HistoryRow>[
                for (final RewardHistoryEntry e in rewards.data!)
                  _HistoryRow.reward(e),
                for (final WithdrawalModel w in withdrawals.data!)
                  _HistoryRow.withdrawal(w),
              ]..sort((_HistoryRow a, _HistoryRow b) {
                  final DateTime da = a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
                  final DateTime db = b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
                  return db.compareTo(da);
                });

              if (rows.isEmpty) return const _EmptyState();

              return ListView.separated(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (BuildContext context, int index) =>
                    _HistoryTile(row: rows[index]),
              );
            },
          );
        },
      ),
    );
  }
}

/// Card de uma linha do histórico.
class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.row});

  final _HistoryRow row;

  /// "dd/MM HH:mm" sem dependências externas.
  static String _formatDate(DateTime d) {
    final DateTime local = d.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  (IconData, String) get _iconAndTitle {
    final RewardHistoryEntry? reward = row.reward;
    if (reward != null) {
      return switch (reward.type) {
        'REWARD_BLOCK' => (Icons.bolt_outlined, 'Bloco de mineração'),
        'MACHINE_PURCHASE' => (Icons.memory_outlined, 'Compra'),
        'GAME_REWARD' => (Icons.sports_esports_outlined, 'Recompensa'),
        'LEAGUE_REWARD' => (Icons.leaderboard_outlined, 'Recompensa'),
        'AD_REWARD' => (Icons.smart_display_outlined, 'Recompensa'),
        'WITHDRAWAL' => (Icons.payments_outlined, 'Saque'),
        _ => (Icons.redeem_outlined, 'Recompensa'),
      };
    }
    return (Icons.payments_outlined, 'Saque');
  }

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String title) = _iconAndTitle;
    final RewardHistoryEntry? reward = row.reward;
    final WithdrawalModel? withdrawal = row.withdrawal;

    // Valor oficial: entrada (+) verde, saída (−) vermelho. No rewards
    // mirror o sinal já vem do backend; no saque o montante é saída.
    final BigInt amountUnits =
        reward?.amount ?? -(withdrawal?.amountUnits ?? BigInt.zero);
    final bool isCredit = amountUnits >= BigInt.zero;
    final String amountLabel =
        '${isCredit ? '+' : '−'}${CoinFormat.formatWithTicker(amountUnits.abs())}';

    final DateTime? date = row.date;

    return NeonPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: AppColors.cyan),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  date == null ? '—' : _formatDate(date),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                // Saque: chip de status + destino mascarado (nunca completo).
                if (withdrawal != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      _StatusChip(status: withdrawal.status),
                      if (withdrawal.destinationMasked.isNotEmpty)
                        Text(
                          withdrawal.destinationMasked,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            amountLabel,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: isCredit ? AppColors.green : AppColors.error,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip de status do saque (processing/completed/failed).
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = switch (status) {
      'completed' => ('Concluído', AppColors.green),
      'failed' => ('Falhou', AppColors.error),
      _ => ('Processando', AppColors.gold),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

/// Estado vazio honesto (sem movimentações registradas).
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Nenhuma movimentação ainda',
        style: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}

/// Estado de erro com botão de repetir.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: NeonPanel(
          accent: AppColors.error,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'Não foi possível carregar o histórico.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('TENTAR NOVAMENTE'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
