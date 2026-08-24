import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Seletor de ATIVO para saque — chips gerados a partir de `config/payouts`
/// (apenas enabled). Ícones GEOMÉTRICOS próprios em código (símbolo textual/
/// simples) — nunca logos oficiais de marcas.
class AssetSelector extends StatelessWidget {
  const AssetSelector({
    super.key,
    required this.assets,
    required this.selectedId,
    required this.onSelected,
  });

  /// Ativos habilitados vindos da config do servidor.
  final List<WalletAssetChip> assets;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (assets.isEmpty) {
      return Text(
        'Nenhum ativo disponível para saque no momento.',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final WalletAssetChip asset in assets)
          _AssetChip(
            asset: asset,
            selected: asset.id == selectedId,
            onTap: () => onSelected(asset.id),
          ),
      ],
    );
  }
}

/// Dados exibidos por chip (desacoplado do repositório p/ testes).
class WalletAssetChip {
  const WalletAssetChip({
    required this.id,
    required this.network,
    required this.symbol,
  });

  final String id;
  final String network;

  /// Símbolo textual/geométrico simples (ex.: '₿'→'B', 'Ł', 'Ð', '₮').
  final String symbol;
}

class _AssetChip extends StatelessWidget {
  const _AssetChip({
    required this.asset,
    required this.selected,
    required this.onTap,
  });

  final WalletAssetChip asset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = selected ? AppColors.cyan : AppColors.textSecondary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.cyan.withValues(alpha: 0.12)
                : AppColors.surface,
            border: Border.all(
              color: selected ? AppColors.cyan : AppColors.textSecondary.withValues(alpha: 0.3),
              width: selected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _AssetGlyph(symbol: asset.symbol, color: accent),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    asset.id,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected ? AppColors.textPrimary : accent,
                    ),
                  ),
                  Text(
                    asset.network,
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 0.5,
                      color: AppColors.textSecondary.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Glifo geométrico próprio por ativo (círculo + símbolo textual).
class _AssetGlyph extends StatelessWidget {
  const _AssetGlyph({required this.symbol, required this.color});

  final String symbol;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.4),
      ),
      alignment: Alignment.center,
      child: Text(
        symbol,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}
