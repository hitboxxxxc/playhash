import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/chamfered_border.dart';
import '../../../core/utils/coin_format.dart';
import '../../../core/utils/power_format.dart';
import '../../../core/widgets/machine_sprite.dart';
import '../../../core/widgets/neon_icons.dart';
import '../../../data/models/machine_catalog_model.dart';

/// Card do catálogo de máquinas: sprite pixel próprio por raridade, nome,
/// +X H/s (power_format), preço dourado (coin_format), chip de raridade e
/// "owned x/max". Botão COMPRAR chanfrado ciano — desabilitado se limite
/// atingido ou saldo insuficiente (aviso discreto, preço sempre visível).
class MachineCard extends StatelessWidget {
  const MachineCard({
    super.key,
    required this.machine,
    required this.ownedCount,
    required this.canAfford,
    this.onBuy,
    this.onOpenDetails,
  });

  final MachineCatalogModel machine;
  final int ownedCount;
  final bool canAfford;
  final void Function()? onBuy;
  final void Function()? onOpenDetails;

  bool get _maxReached =>
      machine.maxPerUser > 0 && ownedCount >= machine.maxPerUser;
  bool get _buyEnabled => onBuy != null && !_maxReached && canAfford;

  @override
  Widget build(BuildContext context) {
    final Color accent = MachineSpriteArt.accentFor(machine.rarity);

    return NeonPanelLike(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              RarityChip(rarity: machine.rarity),
              const Spacer(),
              if (machine.maxPerUser > 0)
                Flexible(
                  child: Text(
                    'owned $ownedCount/${machine.maxPerUser}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      letterSpacing: 0.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onOpenDetails,
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: MachineSprite(rarity: machine.rarity, size: 84),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            machine.name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Semantics(
            label: 'Poder permanente',
            value: PowerFormat.format(machine.powerUnits),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.bolt, size: 14, color: accent),
                const SizedBox(width: 4),
                Text(
                  '+${PowerFormat.format(machine.powerUnits)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Preço SEMPRE visível (mesmo sem saldo).
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              SvgPicture.string(
                NeonIcons.coin,
                width: 14,
                colorFilter: const ColorFilter.mode(
                  AppColors.gold,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                CoinFormat.formatMinimalUnits(machine.priceUnits),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: ChamferedBorder(
                  cut: 8,
                  side: BorderSide(
                    color: _buyEnabled
                        ? AppColors.cyan
                        : AppColors.cyan.withValues(alpha: 0.25),
                  ),
                ),
                color: _buyEnabled
                    ? AppColors.cyan.withValues(alpha: 0.12)
                    : Colors.transparent,
              ),
              child: TextButton(
                onPressed: _buyEnabled ? onBuy : null,
                style: TextButton.styleFrom(
                  foregroundColor: _buyEnabled
                      ? AppColors.cyan
                      : AppColors.textSecondary,
                ),
                child: Text(
                  'COMPRAR',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: _buyEnabled
                        ? AppColors.cyan
                        : AppColors.textSecondary.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          ),
          // Aviso discreto (sem esconder o preço).
          if (!_buyEnabled) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              _maxReached ? 'Limite atingido' : 'Saldo insuficiente',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.5,
                color: AppColors.textSecondary.withValues(alpha: 0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Painel chanfrado local (mesma linguagem visual do NeonPanel).
class NeonPanelLike extends StatelessWidget {
  const NeonPanelLike({super.key, required this.child, this.accent = AppColors.cyan});

  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: AppColors.surface,
        shape: ChamferedBorder(
          cut: 12,
          side: BorderSide(color: accent.withValues(alpha: 0.45)),
        ),
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}

/// Chip de raridade colorido.
class RarityChip extends StatelessWidget {
  const RarityChip({super.key, required this.rarity});

  final String rarity;

  @override
  Widget build(BuildContext context) {
    final Color accent = MachineSpriteArt.accentFor(rarity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: accent.withValues(alpha: 0.7)),
      ),
      child: Text(
        MachineSpriteArt.rarityLabel(rarity),
        style: TextStyle(
          fontSize: 9,
          letterSpacing: 1,
          fontWeight: FontWeight.w800,
          color: accent,
        ),
      ),
    );
  }
}
