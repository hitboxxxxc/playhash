import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/empty_state_panel.dart';
import '../../core/widgets/neon_icons.dart';

/// Aba LOJA — estrutura de categorias (máquinas / boosters / itens).
/// Catálogo e preços virão do backend; cliente nunca inventa valores.
class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});

  static const List<String> _categories = <String>[
    'Máquinas',
    'Boosters',
    'Itens',
  ];

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen>
    with AutomaticKeepAliveClientMixin {
  int _selectedCategory = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(title: const Text('LOJA')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  height: 56,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    scrollDirection: Axis.horizontal,
                    itemCount: StoreScreen._categories.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (BuildContext context, int index) {
                      final bool selected = index == _selectedCategory;
                      return FilterChip(
                        label: Text(
                          StoreScreen._categories[index].toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? AppColors.background
                                : AppColors.textSecondary,
                          ),
                        ),
                        selected: selected,
                        selectedColor: AppColors.cyan,
                        backgroundColor: AppColors.surface,
                        side: BorderSide(
                          color: selected
                              ? AppColors.cyan
                              : AppColors.purple.withValues(alpha: 0.5),
                        ),
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _selectedCategory = index),
                      );
                    },
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: EmptyStatePanel(
                        icon: NeonIcons.cart,
                        title:
                            '${StoreScreen._categories[_selectedCategory]} indisponíveis',
                        message:
                            'O catálogo da loja será publicado em breve pelo '
                            'servidor. Nenhum preço é exibido até lá.',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
