import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/chamfered_border.dart';
import '../../../core/utils/coin_format.dart';
import '../../../core/widgets/neon_icons.dart';
import '../../../core/widgets/skeleton_box.dart';

/// Header da LOJA: saldo disponível oficial (wallet_repository, cache-first)
/// formatado com [CoinFormat] + rótulo COIN provisório. Sem saldo => "—".
/// Nada econômico é calculado aqui — apenas espelho de leitura.
class StoreHeader extends StatelessWidget {
  const StoreHeader({
    super.key,
    this.availableBalance,
    this.loading = false,
    this.onAddTap,
  });

  final BigInt? availableBalance;
  final bool loading;
  final void Function()? onAddTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: ShapeDecoration(
        color: AppColors.surface,
        shape: ChamferedBorder(
          cut: 10,
          side: BorderSide(color: AppColors.gold.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: <Widget>[
          SvgPicture.string(
            NeonIcons.coin,
            width: 22,
            colorFilter: const ColorFilter.mode(
              AppColors.gold,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (loading)
                  const SkeletonBox(width: 90, height: 16)
                else
                  Semantics(
                    label: 'Saldo disponível',
                    value: availableBalance == null
                        ? 'indisponível'
                        : CoinFormat.formatMinimalUnits(availableBalance!),
                    child: Text(
                      availableBalance == null
                          ? '—'
                          : CoinFormat.formatMinimalUnits(availableBalance!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.gold,
                      ),
                    ),
                  ),
                const Text(
                  'COIN',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (onAddTap != null)
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                onPressed: onAddTap,
                icon: const Icon(Icons.add, size: 22, color: AppColors.green),
                tooltip: 'Adicionar saldo (em breve)',
              ),
            ),
        ],
      ),
    );
  }
}
