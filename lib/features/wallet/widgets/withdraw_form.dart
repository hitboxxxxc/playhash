import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/withdrawal_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/coin_format.dart';
import '../../../core/widgets/neon_button.dart';
import '../../../core/widgets/neon_text_field.dart';

/// Dados do ativo selecionado que o form precisa (desacoplado p/ testes).
class WithdrawAssetInfo {
  const WithdrawAssetInfo({
    required this.id,
    required this.network,
    required this.minWithdrawUnits,
    required this.feeUnits,
  });

  final String id;
  final String network;
  final BigInt minWithdrawUnits;
  final BigInt feeUnits;
}

/// Formulário de SAQUE:
/// - endereço com colar da área de transferência + validação LOCAL leve
///   (apenas aviso — a autoridade é o runner);
/// - valor com botão MÁX. (= saldo disponível);
/// - taxa e valor recebido EXIBIDOS a partir da config do servidor
///   ("valores definidos pelo servidor") — nada calculado pelo cliente;
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

  /// Disparado no submit com o valor (units) e o endereço digitado.
  final void Function(BigInt amountUnits, String address) onSubmit;
  final bool submitting;

  @override
  State<WithdrawForm> createState() => _WithdrawFormState();
}

class _WithdrawFormState extends State<WithdrawForm> {
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _addressWarningShown = false;

  static final RegExp _amountRe = RegExp(r'^\d+([.,]\d{1,6})?$');

  @override
  void dispose() {
    _addressController.dispose();
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

  Future<void> _pasteAddress() async {
    final ClipboardData? data = await Clipboard.getData('text/plain');
    final String? text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      _addressController.text = text;
      _checkAddressWarning(text);
    }
  }

  void _checkAddressWarning(String address) {
    final bool valid =
        looksLikeValidAddress(widget.asset.network, address.trim());
    if (!valid && !_addressWarningShown && address.trim().length >= 20) {
      _addressWarningShown = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Atenção: o endereço não parece válido para esta rede. '
            'Confira antes de enviar.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
    if (valid) _addressWarningShown = false;
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
    widget.onSubmit(amount, _addressController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final BigInt min = widget.asset.minWithdrawUnits;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Endereço
          Row(
            children: <Widget>[
              Expanded(
                child: NeonTextField(
                  controller: _addressController,
                  labelText: 'Endereço ${widget.asset.network}',
                  hintText: 'Cole o endereço da carteira',
                  onChanged: _checkAddressWarning,
                  validator: (String? v) {
                    final String value = (v ?? '').trim();
                    if (value.isEmpty) return 'Informe o endereço.';
                    if (value.length < 20 || value.length > 128) {
                      return 'Endereço inválido.';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const ValueKey<String>('paste_address'),
                tooltip: 'Colar',
                onPressed: _pasteAddress,
                icon: const Icon(Icons.content_paste, color: AppColors.cyan),
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
          // Taxa e recebido — SEMPRE da config do servidor.
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
                  '${CoinFormat.formatMinimalUnits(
                        widget.availableBalance >= min
                            ? (min - _fee)
                            : BigInt.zero,
                      )} COIN',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Valores definidos pelo servidor.',
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
