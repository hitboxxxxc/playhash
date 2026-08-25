import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/coin_format.dart';

/// Conversão de APRESENTAÇÃO (doc 05 §47 — o cálculo oficial é do backend):
///   receivedLitoshi = max(0, amountCoins − feeCoins) × litoshiPerCoin
/// Aritmética inteira; nunca float; nunca negativa.
BigInt computeReceivedLitoshi(
  int amountCoins,
  int feeCoins,
  int litoshiPerCoin,
) {
  final int net = amountCoins - feeCoins;
  if (net <= 0) return BigInt.zero;
  return BigInt.from(net) * BigInt.from(litoshiPerCoin);
}

/// Sheet de CONFIRMAÇÃO EXPLÍCITA do saque (v3) — OBRIGATÓRIA antes de criar
/// a withdrawalIntent. Resumo completo (ativo, e-mail MASCARADO, valor, taxa,
/// conversão fixa e "Você recebe" EM TEMPO REAL via [amountCoins]) + botões
/// CANCELAR / CONFIRMAR SAQUE. Só com CONFIRMAR o fluxo segue para a criação
/// do intent. Se valor ≤ taxa ⇒ "Você recebe 0" e CONFIRMAR desabilitado.
class WithdrawConfirmSheet extends StatelessWidget {
  const WithdrawConfirmSheet({
    super.key,
    required this.assetId,
    required this.destinationMasked,
    required this.amountUnits,
    required this.feeUnits,
    required this.litoshiPerCoin,
    required this.displayRate,
    required this.minWithdrawUnits,
    required this.availableBalance,
    required this.amountCoins,
  });

  final String assetId;

  /// E-mail FaucetPay JÁ MASCARADO (nunca o e-mail completo).
  final String destinationMasked;
  final BigInt amountUnits;
  final BigInt feeUnits;
  final int litoshiPerCoin;
  final String displayRate;
  final BigInt minWithdrawUnits;
  final BigInt availableBalance;

  /// COINS inteiras digitadas no form (atualizadas a cada dígito). A sheet
  /// ESCUTA este notifier enquanto aberta — conversão em tempo real.
  final ValueListenable<int> amountCoins;

  /// Abre a sheet e retorna true SOMENTE se o usuário confirmar.
  static Future<bool> show(
    BuildContext context, {
    required String assetId,
    required String destinationMasked,
    required BigInt amountUnits,
    required BigInt feeUnits,
    required int litoshiPerCoin,
    required String displayRate,
    required BigInt minWithdrawUnits,
    required BigInt availableBalance,
    required ValueListenable<int> amountCoins,
  }) async {
    final bool? confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) => WithdrawConfirmSheet(
        assetId: assetId,
        destinationMasked: destinationMasked,
        amountUnits: amountUnits,
        feeUnits: feeUnits,
        litoshiPerCoin: litoshiPerCoin,
        displayRate: displayRate,
        minWithdrawUnits: minWithdrawUnits,
        availableBalance: availableBalance,
        amountCoins: amountCoins,
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    final int feeCoins = (feeUnits ~/ BigInt.from(1000000)).toInt();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'CONFIRMAR SAQUE',
                key: const ValueKey<String>('confirm_title'),
                style:
                    AppTheme.neonLabel(fontSize: 15, color: AppColors.gold),
              ),
              const SizedBox(height: 16),
              _row('Ativo', assetId),
              _row('E-mail FaucetPay', destinationMasked),
              // Valor/Taxa/Conversão/Você recebe EM TEMPO REAL (notifier).
              ValueListenableBuilder<int>(
                valueListenable: amountCoins,
                builder: (BuildContext context, int coins, _) {
                  final BigInt received =
                      computeReceivedLitoshi(coins, feeCoins, litoshiPerCoin);
                  final bool belowMinAfterFee = coins < feeCoins ||
                      BigInt.from(coins) * BigInt.from(1000000) <
                          minWithdrawUnits;
                  final bool insufficient = BigInt.from(coins) *
                              BigInt.from(1000000) >
                          availableBalance ||
                          BigInt.from(coins) * BigInt.from(1000000) <
                              minWithdrawUnits;
                  return Column(
                    children: <Widget>[
                      _row('Valor', '$coins COIN',
                          valueKey: const ValueKey<String>('confirm_amount')),
                      _row('Taxa', '${CoinFormat.formatMinimalUnits(feeUnits)} COIN'),
                      _row('Conversão', displayRate),
                      _row(
                        'Você recebe',
                        '${CoinFormat.formatLitoshi(received)} LTC',
                        valueKey: const ValueKey<String>('confirm_receive'),
                      ),
                      if (belowMinAfterFee || insufficient)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, bottom: 6),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'Mínimo '
                              '${CoinFormat.formatMinimalUnits(minWithdrawUnits)} '
                              'COIN (após taxa de '
                              '${CoinFormat.formatMinimalUnits(feeUnits)})',
                              key: const ValueKey<String>('confirm_min_hint'),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppColors.error.withValues(alpha: 0.95),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.4),
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.info_outline,
                        size: 14, color: AppColors.gold.withValues(alpha: 0.9)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'O pagamento é enviado para o SEU e-mail da FaucetPay '
                        '(transferência interna). Validação em até 5 minutos; '
                        'após concluir, novo saque somente após o intervalo de '
                        '24h.',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color:
                              AppColors.textSecondary.withValues(alpha: 0.95),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              ValueListenableBuilder<int>(
                valueListenable: amountCoins,
                builder: (BuildContext context, int coins, _) {
                  final BigInt received =
                      computeReceivedLitoshi(coins, feeCoins, litoshiPerCoin);
                  final bool invalid = received <= BigInt.zero ||
                      BigInt.from(coins) * BigInt.from(1000000) <
                          minWithdrawUnits ||
                      BigInt.from(coins) * BigInt.from(1000000) >
                          availableBalance;
                  return Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton(
                          key: const ValueKey<String>('cancel_withdraw'),
                          onPressed: () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: AppColors.textSecondary
                                  .withValues(alpha: 0.5),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            'CANCELAR',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          key: const ValueKey<String>('confirm_withdraw'),
                          onPressed:
                              invalid ? null : () => Navigator.of(context).pop(true),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: invalid
                                  ? AppColors.textSecondary.withValues(alpha: 0.3)
                                  : AppColors.green,
                              width: invalid ? 1 : 1.5,
                            ),
                            backgroundColor: invalid
                                ? Colors.transparent
                                : AppColors.green.withValues(alpha: 0.1),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(
                            'CONFIRMAR SAQUE',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                              color: invalid
                                  ? AppColors.textSecondary.withValues(alpha: 0.5)
                                  : AppColors.green,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {Key? valueKey}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary.withValues(alpha: 0.9),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              key: valueKey,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
