import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/providers.dart';
import '../../core/theme/app_assets.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/empty_state_panel.dart';
import '../../core/widgets/neon_icons.dart';
import '../../core/widgets/skeleton_box.dart';
import '../../data/models/league_model.dart';
import 'widgets/league_card.dart';
import 'widgets/league_daily_card.dart';
import 'widgets/league_row.dart';
import 'widgets/leaderboard_list.dart';

/// Tela LIGAS: fileira dos 5 escudos, card da liga atual com progresso,
/// ranking da liga (top 100, maskedName) e recompensa diária. Tudo espelho
/// de dados oficiais do backend — atribuição/promoção/diária são do runner.
class LeaguesScreen extends ConsumerWidget {
  const LeaguesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<LeagueModel>> catalog = ref.watch(leaguesCatalogProvider);
    final AsyncValue<UserLeagueModel?> userLeague = ref.watch(userLeagueStreamProvider);
    final String? uid = ref.watch(currentUidProvider).value;
    final UserLeagueModel? myLeague = userLeague.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SUAS LIGAS'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: catalog.when(
              loading: () => _buildLoading(),
              error: (_, _) => _buildError(ref),
              data: (List<LeagueModel> leagues) {
                if (leagues.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.all(20),
                    children: const <Widget>[
                      EmptyStatePanel(
                        icon: NeonIcons.trophy,
                        title: 'LIGAS',
                        message: 'Ligas indisponíveis no momento.',
                      ),
                    ],
                  );
                }
                final LeagueModel? current = leagues
                    .where((LeagueModel l) => l.id == myLeague?.leagueId)
                    .firstOrNull;
                final LeagueModel? next = current == null
                    ? null
                    : leagues.where((LeagueModel l) => l.tier > current.tier).firstOrNull;

                final int myPower =
                    ref.watch(powerStreamProvider).value?.totalPower ?? 0;
                return RefreshIndicator(
                  color: AppColors.cyan,
                  backgroundColor: AppColors.surface,
                  onRefresh: () async => ref.invalidate(leaguesCatalogProvider),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    children: <Widget>[
                      LeagueRow(leagues: leagues, currentLeagueId: myLeague?.leagueId),
                      const SizedBox(height: 20),
                      if (current != null)
                        LeagueCard(
                          league: current,
                          nextLeague: next,
                          totalPower: myPower,
                        )
                      else
                        const LeagueCardEmpty(),
                      const SizedBox(height: 20),
                      Builder(
                        builder: (BuildContext context) {
                          if (current == null) return const SizedBox.shrink();
                          final AsyncValue<List<LeaderboardEntry>> board =
                              ref.watch(leaderboardProvider(current.id));
                          return LeaderboardList(
                            entries: board.value ?? const <LeaderboardEntry>[],
                            uid: uid ?? '',
                            myPower: myPower,
                            isLoading: board.isLoading,
                            hasError: board.hasError,
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      if (current != null)
                        LeagueDailyCard(
                          league: current,
                          lastDailyGrant: myLeague?.lastDailyGrant,
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() => ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: const <Widget>[
          SkeletonBox(height: 120),
          SizedBox(height: 20),
          SkeletonBox(height: 140),
          SizedBox(height: 20),
          SkeletonBox(height: 260),
        ],
      );

  Widget _buildError(WidgetRef ref) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SvgPicture.string(AppAssets.logoSvg, width: 48),
            const SizedBox(height: 12),
            const Text(
              'Não foi possível carregar suas ligas.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => ref.invalidate(leaguesCatalogProvider),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('TENTAR NOVAMENTE'),
            ),
          ],
        ),
      );
}
