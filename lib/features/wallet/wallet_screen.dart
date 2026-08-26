import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/payout_config.dart';
import '../../core/providers.dart';
import '../../core/services/withdrawal_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/wallet_model.dart';
import '../../data/repositories/payouts_repository.dart'
    show RewardHistoryEntry, WithdrawalModel;
import 'widgets/wallet_header.dart';
import 'widgets/wallet_history_list.dart';
import 'widgets/withdraw_confirm_sheet.dart';
import 'widgets/withdraw_form.dart';

/// CARTEIRA — saldos (disponível/pendente/vitalício), saque com destino =
/// E-MAIL FaucetPay, histórico mesclado com status.
///
/// 12.18: o payout roda NO CLIENTE (reserva → FaucetPay → conclusão OU
/// estorno integral). SEM cooldown 24h. Mínimo/taxa/teto vêm da config local
/// ([kMinWithdrawCoins]/[kFeeCoins]/[kMaxPerWithdrawalCoins]).
class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  bool _submitting = false;

  /// COINS inteiras digitadas no form (atualizadas a cada dígito) — alimenta
  /// a conversão EM TEMPO REAL do sheet de confirmação (apresentação).
  final ValueNotifier<int> _amountCoins = ValueNotifier<int>(0);

  @override
  void dispose() {
    _amountCoins.dispose();
    super.dispose();
  }

  void _showDepositInfoSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'SEM DEPÓSITOS',
              style: AppTheme.neonLabel(fontSize: 14, color: AppColors.gold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Ganhe moedas jogando, em missões e na liga. '
              'Este app não aceita depósitos.',
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// CONFIRMAÇÃO EXPLÍCITA → executa o saque NO CLIENTE (12.18).
  ///
  /// TIMEOUT de UI 10s: após 10s avisa "ainda processando" mas CONTINUA
  /// aguardando o resultado real (o botão nunca fica em loop; o estorno/
  /// conclusão acontece de qualquer forma no serviço).
  Future<void> _submit({
    required BigInt amountUnits,
    required String destination,
  }) async {
    if (!mounted) return;

    // Sheet de confirmação OBRIGATÓRIA antes do payout.
    final bool confirmed = await WithdrawConfirmSheet.show(
      context,
      assetId: 'LTC',
      destinationMasked: maskDestination(destination),
      amountUnits: amountUnits,
      feeUnits: BigInt.from(kFeeCoins) * BigInt.from(1000000),
      litoshiPerCoin: kLitoshiPerCoin,
      displayRate: kDisplayRate,
      minWithdrawUnits:
          BigInt.from(kMinWithdrawCoins) * BigInt.from(1000000),
      availableBalance:
          ref.read(walletStreamProvider).value?.availableBalance ??
              BigInt.zero,
      amountCoins: _amountCoins,
    );
    if (!confirmed || !mounted) return; // CANCELAR ⇒ NADA acontece

    final String? uid = await ref.read(currentUidProvider.future);
    if (uid == null || !mounted) return;

    final int amountCoins =
        (amountUnits ~/ BigInt.from(1000000)).toInt();
    final WithdrawalService service = ref.read(withdrawalServiceProvider);
    setState(() => _submitting = true);

    final Future<WithdrawalOutcome> pending = service.withdraw(
      uid: uid,
      amountCoins: amountCoins,
      destination: destination,
    );
    WithdrawalOutcome outcome;
    try {
      outcome = await pending.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A confirmação está demorando. Aguarde — o resultado aparece '
            'em instantes.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      try {
        outcome = await pending;
      } on Exception {
        if (!mounted) return;
        setState(() => _submitting = false);
        return;
      }
    } on WithdrawalException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _submitting = false);
    _showResultSheet(outcome);
  }

  void _showResultSheet(WithdrawalOutcome result) {
    final bool ok = result.isCompleted;
    final bool pending = result.isPending;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              ok
                  ? Icons.check_circle
                  : pending
                      ? Icons.hourglass_top
                      : Icons.error_outline,
              color: ok
                  ? AppColors.green
                  : pending
                      ? AppColors.gold
                      : AppColors.error,
              size: 44,
            ),
            const SizedBox(height: 12),
            Text(
              ok
                  ? 'SAQUE CONCLUÍDO'
                  : pending
                      ? 'AGUARDANDO PAGAMENTO'
                      : 'SAQUE NÃO CONCLUÍDO',
              style: AppTheme.neonLabel(
                fontSize: 15,
                color: ok
                    ? AppColors.green
                    : pending
                        ? AppColors.gold
                        : AppColors.error,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              ok
                  ? 'Pagamento enviado via FaucetPay.\n'
                      'Referência: ${result.reference ?? '—'}'
                  : pending
                      ? 'Aguardando pagamento manual do operador.\n'
                          'O valor fica RESERVADO (pendente) e o histórico '
                          'atualiza em instantes após a definição do status.'
                      : '${withdrawalErrorMessage(result.errorCode)}\n'
                          'O valor foi estornado ao saldo disponível.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: AppColors.textPrimary,
              ),
            ),
            if (!ok && !pending && (result.detail?.isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  result.detail!,
                  key: const ValueKey<String>('withdraw_error_detail'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: AppColors.textSecondary.withValues(alpha: 0.9),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Ativa o observador do MODO MANUAL (no-op quando kPayoutMode != manual):
    // finaliza/estorna sozinho quando o operador define o status no Console.
    ref.watch(manualPayoutWatchProvider);
    final AsyncValue<WalletModel?> wallet = ref.watch(walletStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('CARTEIRA')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: <Widget>[
                wallet.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(color: AppColors.cyan),
                    ),
                  ),
                  error: (_, _) => WalletHeader(
                    availableBalance: BigInt.zero,
                    pendingBalance: BigInt.zero,
                    lifetimeEarned: BigInt.zero,
                  ),
                  data: (WalletModel? w) => WalletHeader(
                    availableBalance: w?.availableBalance ?? BigInt.zero,
                    pendingBalance: w?.pendingBalance ?? BigInt.zero,
                    lifetimeEarned: w?.lifetimeEarned ?? BigInt.zero,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _showDepositInfoSheet,
                    child: const Text(
                      'Como ganhar moedas?',
                      style: TextStyle(fontSize: 12, color: AppColors.cyan),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text('SACAR', style: AppTheme.neonLabel(fontSize: 12)),
                const SizedBox(height: 8),
                _buildForm(),
                const SizedBox(height: 24),
                Text('HISTÓRICO', style: AppTheme.neonLabel(fontSize: 12)),
                const SizedBox(height: 4),
                WalletHistoryList(items: _mergedHistory(ref)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    final BigInt available =
        ref.watch(walletStreamProvider).value?.availableBalance ?? BigInt.zero;
    return WithdrawForm(
      key: const ValueKey<String>('form_LTC'),
      asset: WithdrawAssetInfo(
        id: 'LTC',
        network: 'FaucetPayEmail',
        minWithdrawUnits:
            BigInt.from(kMinWithdrawCoins) * BigInt.from(1000000),
        maxPerWithdrawalUnits:
            BigInt.from(kMaxPerWithdrawalCoins) * BigInt.from(1000000),
        feeUnits: BigInt.from(kFeeCoins) * BigInt.from(1000000),
        litoshiPerCoin: kLitoshiPerCoin,
        displayRate: kDisplayRate,
      ),
      availableBalance: available,
      amountCoins: _amountCoins,
      submitting: _submitting,
      onSubmit: (BigInt amount, String destination) => _submit(
        amountUnits: amount,
        destination: destination,
      ),
    );
  }
}

/// Mescla rewards/{uid}/items (entradas/saídas) com os saques.
List<WalletHistoryItem> _mergedHistory(WidgetRef ref) {
  final List<RewardHistoryEntry> rewards =
      ref.watch(rewardItemsStreamProvider).value ??
          const <RewardHistoryEntry>[];
  final List<WithdrawalModel> withdrawals =
      ref.watch(withdrawalsStreamProvider).value ??
          const <WithdrawalModel>[];

  final List<WalletHistoryItem> items = <WalletHistoryItem>[
    for (final RewardHistoryEntry r in rewards)
      WalletHistoryItem(
        title: _rewardTitle(r.type),
        amount: r.amount,
        date: r.createdAt,
      ),
    for (final WithdrawalModel w in withdrawals)
      WalletHistoryItem(
        title: 'Saque ${w.asset}',
        amount: -w.amountUnits,
        date: w.createdAt,
        status: w.status,
        destinationMasked: w.destinationMasked, // e-mail SEMPRE mascarado
      ),
  ];
  items.sort((WalletHistoryItem a, WalletHistoryItem b) {
    final DateTime da = a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
    final DateTime db = b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
    return db.compareTo(da);
  });
  return items;
}

String _rewardTitle(String type) {
  switch (type) {
    case 'GAME_REWARD':
      return 'Recompensa de partida';
    case 'REWARD_BLOCK':
      return 'Bloco de mineração';
    case 'MISSION_REWARD':
      return 'Missão concluída';
    case 'ACHIEVEMENT_REWARD':
      return 'Conquista';
    case 'LEAGUE_REWARD':
      return 'Liga diária';
    case 'SEASON_REWARD':
      return 'Temporada';
    case 'WITHDRAWAL':
      return 'Saque';
    case 'MACHINE_PURCHASE':
      return 'Compra de máquina';
    default:
      return type.isEmpty ? 'Movimentação' : type;
  }
}
