import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/services/purchase_intent_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/chamfered_border.dart';
import '../../../core/utils/coin_format.dart';
import '../../../core/utils/power_format.dart';
import '../../../core/widgets/machine_sprite.dart';
import '../../../core/widgets/neon_button.dart';
import '../../../core/widgets/neon_icons.dart';
import '../../../data/models/machine_catalog_model.dart';
import 'machine_card.dart' show RarityChip;

enum _PurchasePhase { confirm, sending, waiting, success, failed }

/// Bottom sheet de detalhes da máquina: nome, raridade, poder permanente,
/// preço, limite próprio, descrição curta e CONFIRMAR COMPRA.
///
/// Fluxo: cria intent (purchase_intent_service) → estado "Pedido enviado —
/// validação em até 5 min" → observa a intent até done (toast + refresh) ou
/// failed (mensagem segura por código). Nada econômico é decidido aqui.
class MachineDetailSheet extends StatefulWidget {
  const MachineDetailSheet({
    super.key,
    required this.machine,
    required this.ownedCount,
    required this.canAfford,
    required this.uid,
    required this.service,
    required this.onPurchased,
  });

  final MachineCatalogModel machine;
  final int ownedCount;
  final bool canAfford;
  final String uid;
  final PurchaseIntentService service;
  final VoidCallback onPurchased;

  static Future<void> show(
    BuildContext context, {
    required MachineCatalogModel machine,
    required int ownedCount,
    required bool canAfford,
    required String uid,
    required PurchaseIntentService service,
    required VoidCallback onPurchased,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext sheetContext) => MachineDetailSheet(
        machine: machine,
        ownedCount: ownedCount,
        canAfford: canAfford,
        uid: uid,
        service: service,
        onPurchased: onPurchased,
      ),
    );
  }

  @override
  State<MachineDetailSheet> createState() => _MachineDetailSheetState();
}

class _MachineDetailSheetState extends State<MachineDetailSheet> {
  _PurchasePhase _phase = _PurchasePhase.confirm;
  String? _failureMessage;
  StreamSubscription<PurchaseIntentResult>? _subscription;

  bool get _maxReached =>
      widget.machine.maxPerUser > 0 &&
      widget.ownedCount >= widget.machine.maxPerUser;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _confirmPurchase() async {
    if (_maxReached || !widget.canAfford) return;
    setState(() => _phase = _PurchasePhase.sending);
    final String clientRequestId;
    try {
      clientRequestId = await widget.service.createIntent(
        uid: widget.uid,
        machineId: widget.machine.id,
      );
    } on PurchaseIntentException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _PurchasePhase.failed;
        _failureMessage = e.message;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _PurchasePhase.failed;
        _failureMessage =
            'Não foi possível enviar a compra. Tente novamente.';
      });
      return;
    }

    if (!mounted) return;
    setState(() => _phase = _PurchasePhase.waiting);
    _subscription = widget.service.watchResult(clientRequestId).listen(
      (PurchaseIntentResult result) {
        if (!mounted) return;
        if (result.isDone) {
          setState(() => _phase = _PurchasePhase.success);
          widget.onPurchased();
        } else if (result.isFailed) {
          setState(() {
            _phase = _PurchasePhase.failed;
            _failureMessage =
                PurchaseIntentService.failureMessage(result.failureCode);
          });
        }
      },
      onError: (Object _) {
        if (!mounted) return;
        // Erro de stream (rede): mantém "aguardando" — a intent continua
        // válida no servidor e o usuário pode reabrir a loja depois.
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final MachineCatalogModel machine = widget.machine;
    final Color accent = MachineSpriteArt.accentFor(machine.rarity);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                MachineSprite(rarity: machine.rarity, size: 72),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        machine.name.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      RarityChip(rarity: machine.rarity),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _DetailRow(
              icon: Icons.bolt,
              iconColor: accent,
              label: 'Poder permanente',
              value: '+${PowerFormat.format(machine.powerUnits)}',
              valueColor: accent,
            ),
            const SizedBox(height: 8),
            _DetailRow(
              label: 'Limite próprio',
              value: machine.maxPerUser > 0
                  ? '${widget.ownedCount}/${machine.maxPerUser}'
                  : '—',
            ),
            const SizedBox(height: 8),
            const _DetailRow(
              label: 'Duração',
              value: 'PERMANENTE',
              valueColor: AppColors.gold,
            ),
            const SizedBox(height: 12),
            Container(
              height: 1,
              color: AppColors.textSecondary.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const Text(
                  'Preço:',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                SvgPicture.string(
                  NeonIcons.coin,
                  width: 16,
                  colorFilter: const ColorFilter.mode(
                    AppColors.gold,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${CoinFormat.formatMinimalUnits(machine.priceUnits)} COIN',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.gold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'A compra é validada pelo servidor em até 5 minutos. '
              'O saldo só é debitado quando o pedido é aprovado.',
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            switch (_phase) {
              _PurchasePhase.confirm => NeonButton(
                  label: 'CONFIRMAR COMPRA',
                  onPressed:
                      (_maxReached || !widget.canAfford) ? null : _confirmPurchase,
                ),
              _PurchasePhase.sending ||
              _PurchasePhase.waiting =>
                Column(
                  children: <Widget>[
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: AppColors.cyan,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _phase == _PurchasePhase.sending
                          ? 'Enviando pedido…'
                          : 'Pedido enviado — validação em até 5 min',
                      textAlign: TextAlign.center,
                      style: AppTheme.neonLabel(
                        fontSize: 12,
                        color: AppColors.cyan,
                      ),
                    ),
                  ],
                ),
              _PurchasePhase.success => Column(
                  children: <Widget>[
                    const Icon(Icons.check_circle,
                        color: AppColors.green, size: 30),
                    const SizedBox(height: 8),
                    const Text(
                      'COMPRA APROVADA',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        color: AppColors.green,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Sua máquina foi instalada na sala.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    NeonButton(
                      label: 'OK',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              _PurchasePhase.failed => Column(
                  children: <Widget>[
                    const Icon(Icons.error_outline,
                        color: AppColors.error, size: 30),
                    const SizedBox(height: 8),
                    Text(
                      _failureMessage ??
                          'A compra não pôde ser concluída.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    NeonButton(
                      label: 'FECHAR',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
            },
          ],
        ),
      ),
    );
  }
}

/// Linha de detalhe (rótulo + valor).
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.icon,
    this.iconColor,
    this.valueColor = AppColors.textPrimary,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? iconColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 15, color: iconColor ?? AppColors.textSecondary),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: ShapeDecoration(
            shape: ChamferedBorder(
              cut: 6,
              side: BorderSide(
                color: valueColor.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }
}
