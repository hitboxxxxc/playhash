import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/providers.dart';
import '../../core/theme/app_assets.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/neon_panel.dart';
import '../../core/widgets/skeleton_box.dart';
import '../../data/models/achievement_model.dart';
import 'widgets/achievement_card.dart';

/// Tela CONQUISTAS: contador "X de Y desbloqueadas", abas de categoria e
/// grade 2 colunas (desbloqueada/claimable em ciano; bloqueada esmaecida com
/// cadeado). Dados 100% oficiais do runner; claim via [ClaimService].
class AchievementsScreen extends ConsumerStatefulWidget {
  const AchievementsScreen({super.key});

  @override
  ConsumerState<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends ConsumerState<AchievementsScreen> {
  String _category = AchievementCategory.all;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<AchievementView>> achievements =
        ref.watch(achievementsStreamProvider);

    final int unlocked =
        achievements.maybeWhen(data: _countUnlocked, orElse: () => 0);
    final int total =
        achievements.maybeWhen(data: (List<AchievementView> l) => l.length, orElse: () => 0);

    return Scaffold(
      appBar: AppBar(title: const Text('CONQUISTAS')),
      body: SafeArea(
        child: achievements.when(
          loading: () => _buildLoading(),
          error: (_, _) => _buildError(),
          data: (List<AchievementView> list) {
            final List<AchievementView> filtered = _category ==
                    AchievementCategory.all
                ? list
                : list
                    .where((AchievementView v) =>
                        v.achievement.category == _category)
                    .toList(growable: false);
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: <Widget>[
                Text(
                  '$unlocked de $total desbloqueadas',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                _CategoryTabs(
                  selected: _category,
                  onSelected: (String c) => setState(() => _category = c),
                ),
                const SizedBox(height: 16),
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: Column(
                      children: <Widget>[
                        SvgPicture.string(AppAssets.trophyIconSvg,
                            width: 48, height: 48),
                        const SizedBox(height: 12),
                        const Text(
                          'Nenhuma conquista nesta categoria.',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                else
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.82,
                    children: <Widget>[
                      for (final AchievementView v in filtered)
                        AchievementCard(view: v),
                    ],
                  ),
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }

  static int _countUnlocked(List<AchievementView> list) =>
      list.where((AchievementView v) => v.isUnlocked).length;

  Widget _buildLoading() => ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: const <Widget>[
          Center(child: SkeletonBox(width: 160, height: 18)),
          SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(child: SkeletonBox(height: 180, borderRadius: 14)),
              SizedBox(width: 14),
              Expanded(child: SkeletonBox(height: 180, borderRadius: 14)),
            ],
          ),
          SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(child: SkeletonBox(height: 180, borderRadius: 14)),
              SizedBox(width: 14),
              Expanded(child: SkeletonBox(height: 180, borderRadius: 14)),
            ],
          ),
        ],
      );

  Widget _buildError() => Center(
        child: NeonPanel(
          accent: AppColors.error,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'Não foi possível carregar suas conquistas.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => ref.invalidate(achievementsStreamProvider),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('TENTAR NOVAMENTE'),
              ),
            ],
          ),
        ),
      );
}

class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  static const Map<String, String> _labels = <String, String>{
    AchievementCategory.all: 'TODAS',
    AchievementCategory.games: 'JOGOS',
    AchievementCategory.mining: 'MINERAÇÃO',
    AchievementCategory.collection: 'COLEÇÃO',
    AchievementCategory.missions: 'MISSÕES',
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final MapEntry<String, String> entry in _labels.entries)
          _Tab(
            label: entry.value,
            selected: selected == entry.key,
            onTap: () => onSelected(entry.key),
          ),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: ShapeDecoration(
              color: selected
                  ? AppColors.cyan.withValues(alpha: 0.14)
                  : AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: selected ? AppColors.cyan : AppColors.textSecondary,
                ),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.cyan : AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      );
}
