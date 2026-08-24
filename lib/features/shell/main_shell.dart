import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/app_bottom_nav.dart';
import '../../core/widgets/neon_icons.dart';

/// Shell principal do app: corpo com 5 branches preservados (IndexedStack)
/// + barra de navegação inferior própria.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const List<BottomNavItem> _items = <BottomNavItem>[
    BottomNavItem(label: 'Home', icon: NeonIcons.home),
    BottomNavItem(label: 'Jogar', icon: NeonIcons.gamepad),
    BottomNavItem(label: 'Mineração', icon: NeonIcons.pickaxe),
    BottomNavItem(label: 'Loja', icon: NeonIcons.cart),
    BottomNavItem(label: 'Perfil', icon: NeonIcons.person),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: AppBottomNav(
        items: _items,
        currentIndex: navigationShell.currentIndex,
        onTap: (int index) => navigationShell.goBranch(
          index,
          // Toque na aba já ativa volta para a raiz da branch.
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}
