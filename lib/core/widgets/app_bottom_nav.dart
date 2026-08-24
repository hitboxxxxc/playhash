import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_colors.dart';
import '../theme/chamfered_border.dart';

/// Item da barra de navegação inferior.
class BottomNavItem {
  const BottomNavItem({required this.label, required this.icon});

  final String label;
  final String icon;
}

/// Barra de navegação inferior própria do PlayHash.
///
/// Identidade visual (doc 02): aba ativa em ciano com glow e chanfro próprio;
/// inativas em roxo suave; labels em caixa alta; áreas de toque >= 48dp;
/// semântica acessível (botão + estado selecionado).
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<BottomNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: SafeArea(
        top: false,
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: AppColors.cyan.withValues(alpha: 0.22),
              ),
            ),
          ),
          child: Row(
            children: <Widget>[
              for (int i = 0; i < items.length; i++)
                Expanded(
                  child: _NavItem(
                    item: items[i],
                    active: i == currentIndex,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final BottomNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color tint = active
        ? AppColors.cyan
        : AppColors.purple.withValues(alpha: 0.8);

    return Semantics(
      button: true,
      selected: active,
      label: item.label.toUpperCase(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 68, // área de toque total >= 48dp
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // Ícone dentro de placa chanfrada quando ativa (glow ciano).
              Container(
                width: 46,
                height: 30,
                decoration: active
                    ? ShapeDecoration(
                        color: AppColors.cyan.withValues(alpha: 0.12),
                        shape: ChamferedBorder(
                          cut: 8,
                          side: BorderSide(
                            color: AppColors.cyan.withValues(alpha: 0.6),
                          ),
                        ),
                        shadows: <BoxShadow>[
                          BoxShadow(
                            color: AppColors.cyan.withValues(alpha: 0.35),
                            blurRadius: 12,
                          ),
                        ],
                      )
                    : null,
                child: Center(
                  child: SvgPicture.string(
                    item.icon,
                    width: 22,
                    height: 22,
                    colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: tint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
