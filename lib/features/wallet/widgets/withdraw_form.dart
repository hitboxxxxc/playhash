import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/config/payout_config.dart';
import '../../../core/services/withdrawal_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/coin_format.dart';
import '../../../core/widgets/neon_button.dart';
import '../../../core/widgets/neon_text_field.dart';

/// Dados do ativo selecionado que o form precisa (desacoplado p/ testes).
/// 12.18: parâmetros vêm da CONFIG LOCAL ([kMinWithdrawCoins],
/// [kMaxPerWithdrawalCoins], [kFeeCoins]) — mínimo 3 COIN, teto 100.000
/// COIN, taxa 2 COIN, conversão fixa 1 COIN = 0,000001 LTC.
class WithdrawAssetInfo {
  const WithdrawAssetInfo({
    required this.id,
    required this.network,
    required this.minWithdrawUnits,
    required this.feeUnits,
    this.maxPerWithdrawalUnits,
    this.litoshiPerCoin = kLitoshiPerCoin,
    this.displayRate = kDisplayRate,
  });

  final String id;
  final String network;
  final BigInt minWithdrawUnits;

  /// Teto por saque (null = sem teto além do saldo).
  final BigInt? maxPerWithdrawalUnits;
  final BigInt feeUnits;

  /// Conversão FIXA: 1 COIN = [litoshiPerCoin] litoshi.
  final int litoshiPerCoin;

  /// Rótulo de exibição da conversão.
  final String displayRate;
}

/// Formulário de SAQUE (12.18/12.22):
/// - campo "E-mail ou endereço LTC da FaucetPay" com validação LOCAL leve
///   (destino DUPLO: e-mail OU linked address) e AVISO fixo;
/// - valor em COINS INTEIRAS (teclado numérico) com botão MÁX. e
///   notifier de coins p/ a conversão EM TEMPO REAL no sheet;
/// - mínimo/teto SEMPRE visíveis; SEM qualquer menção a cooldown;
/// - card de taxa + CTA chanfrado SOLICITAR SAQUE.
class WithdrawForm extends StatefulWidget {
  const WithdrawForm({
    super.key,
    required this.asset,
    required this.availableBalance,
    required this.onSubmit,
    this.amountCoins,
    this.submitting = false,
  });

  final WithdrawAssetInfo asset;
  final BigInt availableBalance;

  /// Disparado no submit com o valor (units, múltiplo exato de 1 COIN) e o
  /// E-MAIL FaucetPay digitado.
  final void Function(BigInt amountUnits, String destinationEmail) onSubmit;

  /// Notifier opcional (form → sheet): COINS inteiras digitadas.
  final ValueNotifier<int>? amountCoins;

  final bool submitting;

  @override
  State<WithdrawForm> createState() => _WithdrawFormState();
}

class _WithdrawFormState extends State<WithdrawForm> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  /// Parse SEGURO das COINS inteiras digitadas; vazio/inválido = 0.
  int _parseAmountCoins(String text) {
    final String normalized = text.trim().replaceAll('.', '');
    if (normalized.isEmpty) return 0;
    return int.tryParse(normalized) ?? 0;
  }

  BigInt get _amountUnits =>
      BigInt.from(_parseAmountCoins(_amountController.text)) *
      BigInt.from(1000000);

  void _onAmountChanged(String text) {
    widget.amountCoins?.value = _parseAmountCoins(text);
  }

  /// MÁX. = menor entre saldo disponível e o teto por saque.
  void _applyMax() {
    BigInt max = widget.availableBalance;
    final BigInt? cap = widget.asset.maxPerWithdrawalUnits;
    if (cap != null && cap < max) max = cap;
    if (max <= BigInt.zero) return;
    setState(() {
      _amountController.text =
          CoinFormat.formatMinimalUnits(max).replaceAll('.', '');
    });
    _onAmountChanged(_amountController.text);
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final BigInt amount = _amountUnits;
    if (amount <= BigInt.zero) return;
    widget.onSubmit(amount, _emailController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final BigInt min = widget.asset.minWithdrawUnits;
    final BigInt? cap = widget.asset.maxPerWithdrawalUnits;

    String? validateAmount(String? v) {
      final int coins = _parseAmountCoins(v ?? '');
      if (coins <= 0) return 'Informe um valor válido.';
      final BigInt amount = BigInt.from(coins) * BigInt.from(1000000);
      if (amount < min) {
        return 'Abaixo do mínimo (${CoinFormat.formatMinimalUnits(min)} COIN).';
      }
      if (cap != null && amount > cap) {
        return 'Teto por saque: ${CoinFormat.formatMinimalUnits(cap)} COIN.';
      }
      if (amount > widget.availableBalance) {
        return 'Saldo disponível insuficiente.';
      }
      return null;
    }

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Destino DUPLO (12.22): e-mail OU endereço LTC vinculado
          NeonTextField(
            controller: _emailController,
            labelText: 'E-mail ou endereço LTC da FaucetPay',
            hintText: 'E-mail da conta ou endereço LTC vinculado a ela',
            keyboardType: TextInputType.emailAddress,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.deny(RegExp(r'\s')),
            ],
            validator: (String? v) {
              final String value = (v ?? '').trim();
              if (value.isEmpty) {
                return 'Informe o e-mail ou o endereço LTC da FaucetPay.';
              }
              switch (detectDestinationType(value)) {
                case DestinationType.email:
                  if (!isValidDestinationEmail(value)) {
                    return 'E-mail inválido.';
                  }
                  return null;
                case DestinationType.ltcAddress:
                  return null; // regex LTC já validou o formato
                case null:
                  return 'Destino inválido: use um e-mail FaucetPay ou '
                      'um endereço LTC.';
              }
            },
          ),
          const SizedBox(height: 6),
          // AVISO FIXO — destino duplo (e-mail OU linked address)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.info_outline,
                  size: 13, color: AppColors.gold.withValues(alpha: 0.9)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Use o e-mail da sua conta FaucetPay OU o endereço LTC '
                  'vinculado (linked address) dela.',
                  key: const ValueKey<String>('destination_notice'),
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: AppColors.textSecondary.withValues(alpha: 0.95),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Valor + MÁX. — COINS INTEIRAS, mínimo/teto visíveis
          Stack(
            alignment: Alignment.centerRight,
            children: <Widget>[
              NeonTextField(
                controller: _amountController,
                labelText: 'Valor (COIN)',
                hintText:
                    'Mínimo $kMinWithdrawCoins · Máximo $kMaxPerWithdrawalCoins',
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: _onAmountChanged,
                validator: validateAmount,
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: TextButton(
                  key: const ValueKey<String>('max_button'),
                  onPressed: _applyMax,
                  child: const Text(
                    'MÁX.',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Mínimo/teto SEMPRE visíveis (12.18)
          Text(
            'Mínimo: $kMinWithdrawCoins COIN · Teto por saque: '
            '$kMaxPerWithdrawalCoins COIN',
            key: const ValueKey<String>('min_max_line'),
            style: TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary.withValues(alpha: 0.95),
            ),
          ),
          const SizedBox(height: 8),
          // Card de TAXA — config local (2 COIN)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(
                color: AppColors.textSecondary.withValues(alpha: 0.2),
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Taxa: $kFeeCoins COIN',
                  key: const ValueKey<String>('fee_line'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Você recebe em LTC via FaucetPay.',
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: AppColors.textSecondary.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          NeonButton(
            key: const ValueKey<String>('submit_withdraw'),
            label: 'SOLICITAR SAQUE',
            isLoading: widget.submitting,
            color: AppColors.gold,
            onPressed: _submit,
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              const Icon(Icons.security, size: 14, color: AppColors.cyan),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Pagamento processado via FaucetPay para o seu e-mail '
                 'ou endereço LTC vinculado.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
