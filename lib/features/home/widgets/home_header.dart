import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/chamfered_border.dart';
import '../../../core/utils/coin_format.dart';
import '../../../core/widgets/neon_icons.dart';
import '../../../core/widgets/skeleton_box.dart';

/// Header da HOME: avatar SVG próprio + displayName + nível ("—" até o
/// backend prover progressão) + saldo disponível oficial ou "—" + botão "+"
/// (informativo) + atalhos de notificações/configurações.
class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.displayName,
    this.availableBalance,
    this.loading = false,
    required this.onAddTap,
    required this.onNotificationsTap,
    required this.onSettingsTap,
  });

  final String displayName;
  final BigInt? availableBalance;
  final bool loading;
  final VoidCallback onAddTap;
  final VoidCallback onNotificationsTap;
  final VoidCallback onSettingsTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        // Avatar placeholder — identidade própria, sem arte externa.
        Container(
          width: 52,
          height: 52,
          decoration: ShapeDecoration(
            color: AppColors.surface,
            shape: ChamferedBorder(
              cut: 12,
              side: BorderSide(
                color: AppColors.cyan.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Center(
            child: SvgPicture.string(
              NeonIcons.person,
              width: 26,
              colorFilter: const ColorFilter.mode(
                AppColors.cyan,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                displayName.isEmpty ? 'JOGADOR' : displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.neonLabel(fontSize: 16),
              ),
              const SizedBox(height: 2),
              Text(
                'NÍVEL —',
                style: AppTheme.neonLabel(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Flexible: o chip encolhe (com ellipsis) em telas estreitas.
        Flexible(
          child: _BalanceChip(
            availableBalance: availableBalance,
            loading: loading,
            onAddTap: onAddTap,
          ),
        ),
        const SizedBox(width: 6),
        _HeaderShortcut(
          icon: NeonIcons.bell,
          tooltip: 'Notificações',
          onTap: onNotificationsTap,
        ),
        const SizedBox(width: 6),
        _HeaderShortcut(
          icon: NeonIcons.gear,
          tooltip: 'Configurações',
          onTap: onSettingsTap,
        ),
      ],
    );
  }
}

/// Chip de saldo com botão "+" (bottom sheet informativo "em breve").
class _BalanceChip extends StatelessWidget {
  const _BalanceChip({
    required this.availableBalance,
    required this.loading,
    required this.onAddTap,
  });

  final BigInt? availableBalance;
  final bool loading;
  final VoidCallback onAddTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: ShapeDecoration(
        color: AppColors.surface,
        shape: ChamferedBorder(
          cut: 10,
          side: BorderSide(color: AppColors.gold.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SvgPicture.string(
            NeonIcons.coin,
            width: 18,
            colorFilter: const ColorFilter.mode(
              AppColors.gold,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Builder(builder: (BuildContext context) {
              final BigInt? balance = availableBalance;
              if (loading) return const SkeletonBox(width: 56, height: 14);
              return Semantics(
                label: 'Saldo disponível',
                value: balance == null
                    ? 'indisponível'
                    : CoinFormat.formatWithTicker(balance),
                child: Text(
                  balance == null
                      ? '—'
                      : CoinFormat.formatWithTicker(balance),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.gold,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 36,
            height: 36,
            child: IconButton(
              onPressed: onAddTap,
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.add, size: 20, color: AppColors.green),
              tooltip: 'Adicionar saldo (em breve)',
            ),
          ),
        ],
      ),
    );
  }
}

/// Atalho circular do header (≥48dp de toque).
class _HeaderShortcut extends StatelessWidget {
  const _HeaderShortcut({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final String icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        onPressed: onTap,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        icon: SvgPicture.string(
          icon,
          width: 22,
          colorFilter: const ColorFilter.mode(
            AppColors.textSecondary,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}
