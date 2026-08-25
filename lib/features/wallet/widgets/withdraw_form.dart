import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/withdrawal_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/coin_format.dart';
import '../../../core/widgets/neon_button.dart';
import '../../../core/widgets/neon_text_field.dart';

/// Dados do ativo selecionado que o form precisa (desacoplado p/ testes).
/// v3: destino = E-MAIL da conta FaucetPay; conversão FIXA em litoshi/coin
/// (1 COIN = 100 litoshi = 0,000001 LTC) — EXIBIÇÃO derivada da config do
/// servidor (nunca autoridade).
class WithdrawAssetInfo {
  const WithdrawAssetInfo({
    required this.id,
    required this.network,
    required this.minWithdrawUnits,
    required this.feeUnits,
    this.litoshiPerCoin = 100,
    this.displayRate = '1 COIN = 0,000001 LTC',
  });

  final String id;
  final String network;
  final BigInt minWithdrawUnits;
  final BigInt feeUnits;

  /// Conversão FIXA: 1 COIN = [litoshiPerCoin] litoshi (config/payouts v3).
  final int litoshiPerCoin;

  /// Rótulo de exibição da conversão (definido pelo servidor).
  final String displayRate;
}

/// Converte units de coin → litoshi (aritmética INTEIRA; espelha o backend:
/// litoshi = (coins − feeCoins) × litoshiPerCoin). Retorna null se negativo.
BigInt? receivedLitoshi(BigInt amountUnits, WithdrawAssetInfo asset) {
  final BigInt scale = BigInt.from(1000000);
  final BigInt coins = amountUnits ~/ scale;
  final BigInt feeCoins = asset.feeUnits ~/ scale;
  final BigInt net = coins - feeCoins;
  if (net <= BigInt.zero) return null;
  return net * BigInt.from(asset.litoshiPerCoin);
}

/// Formata litoshi como decimal LTC pt-BR (ex.: 5800 → "0,000058").
String formatLitoshi(BigInt litoshi) {
  final BigInt whole = litoshi ~/ BigInt.from(100000000);
  final BigInt frac = litoshi % BigInt.from(100000000);
  String fracStr = frac.toString().padLeft(8, '0');
  fracStr = fracStr.replaceFirst(RegExp(r'0+$'), '');
  if (fracStr.isEmpty) return '$whole';
  return '$whole,$fracStr';
}

/// Formulário de SAQUE (v3):
/// - campo "E-mail da FaucetPay" com validação LOCAL leve (a autoridade é o
///   runner + rules) e AVISO fixo sob o campo;
/// - valor com botão MÁX. (= saldo disponível);
/// - taxa e recebido EXIBIDOS a partir da config do servidor ("valores
///   definidos pelo servidor") — nada calculado/decidido pelo cliente;
/// - CTA chanfrado SOLICITAR SAQUE + aviso de segurança.
class WithdrawForm extends StatefulWidget {
  const WithdrawForm({
    super.key,
    required this.asset,
    required this.availableBalance,
    required this.onSubmit,
    this.submitting = false,
  });

  final WithdrawAssetInfo asset;
  final BigInt availableBalance;

  /// Disparado no submit com o valor (units) e o E-MAIL FaucetPay digitado.
  final void Function(BigInt amountUnits, String destinationEmail) onSubmit;
  final bool submitting;

  @override
  State<WithdrawForm> createState() => _WithdrawFormState();
}

class _WithdrawFormState extends State<WithdrawForm> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  static final RegExp _amountRe = RegExp(r'^\d+([.,]\d{1,6})?$');

  @override
  void dispose() {
    _emailController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  /// Converte o texto digitado em units inteiros (1 coin = 1e6 units).
  BigInt? _parseAmountUnits(String text) {
    final String normalized = text.trim().replaceAll(',', '.');
    if (!_amountRe.hasMatch(normalized)) return null;
    final List<String> parts = normalized.split('.');
    final BigInt whole = BigInt.parse(parts[0]);
    final String frac = (parts.length > 1 ? parts[1] : '').padRight(6, '0');
    return whole * BigInt.from(1000000) + BigInt.parse(frac);
  }

  BigInt get _fee => widget.asset.feeUnits;

  /// Valor base p/ a linha de exibição: digitado (≥ mínimo) ou o mínimo.
  BigInt get _displayAmount {
    final BigInt? typed = _parseAmountUnits(_amountController.text);
    if (typed == null || typed < widget.asset.minWithdrawUnits) {
      return widget.asset.minWithdrawUnits;
    }
    return typed;
  }

  void _applyMax() {
    final BigInt max = widget.availableBalance;
    if (max <= BigInt.zero) return;
    setState(() {
      _amountController.text = CoinFormat.formatMinimalUnits(max);
    });
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final BigInt? amount = _parseAmountUnits(_amountController.text);
    if (amount == null || amount <= BigInt.zero) return;
    widget.onSubmit(amount, _emailController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final BigInt min = widget.asset.minWithdrawUnits;
    final BigInt? receiveLitoshi = receivedLitoshi(_displayAmount, widget.asset);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // E-mail da conta FaucetPay (destino v3 — transferência interna)
          NeonTextField(
            controller: _emailController,
            labelText: 'E-mail da FaucetPay',
            hintText: 'Digite o e-mail da sua conta FaucetPay',
            keyboardType: TextInputType.emailAddress,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.deny(RegExp(r'\s')),
            ],
            validator: (String? v) {
              final String value = (v ?? '').trim();
              if (value.isEmpty) return 'Informe o e-mail da FaucetPay.';
              if (!isValidDestinationEmail(value)) {
                return 'E-mail inválido.';
              }
              return null;
            },
          ),
          const SizedBox(height: 6),
          // AVISO FIXO — destino é SEMPRE o e-mail FaucetPay (interno)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.info_outline,
                  size: 13, color: AppColors.gold.withValues(alpha: 0.9)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'O saque é enviado para o seu e-mail da FaucetPay — '
                  'não use endereço externo de carteira.',
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
          // Valor + MÁX.
          Stack(
            alignment: Alignment.centerRight,
            children: <Widget>[
              NeonTextField(
                controller: _amountController,
                labelText: 'Valor',
                hintText:
                    'Mínimo ${CoinFormat.formatMinimalUnits(min)} COIN',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
                onChanged: (_) => setState(() {}),
                validator: (String? v) {
                  final BigInt? amount = _parseAmountUnits(v ?? '');
                  if (amount == null || amount <= BigInt.zero) {
                    return 'Informe um valor válido.';
                  }
                  if (amount < min) {
                    return 'Abaixo do mínimo (${CoinFormat.formatMinimalUnits(min)}).';
                  }
                  if (amount > widget.availableBalance) {
                    return 'Saldo disponível insuficiente.';
                  }
                  return null;
                },
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
          const SizedBox(height: 8),
          // Taxa e recebido — SEMPRE derivados da config do servidor.
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
                  'Taxa: ${CoinFormat.formatMinimalUnits(_fee)} COIN · '
                  'Você recebe: '
                  '${receiveLitoshi == null ? '—' : formatLitoshi(receiveLitoshi)} LTC',
                  key: const ValueKey<String>('fee_line'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.asset.displayRate} · Valores e conversão '
                  'definidos pelo servidor.',
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
                  'Saques passam por validação e podem levar até 5 minutos.',
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
