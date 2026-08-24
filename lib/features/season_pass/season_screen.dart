import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/mission_model.dart';
import '../../core/widgets/empty_state_panel.dart';
import '../../core/widgets/neon_icons.dart';
import '../../core/widgets/skeleton_box.dart';
import '../../data/models/season_model.dart';
import 'widgets/pass_track.dart';
import 'widgets/season_header.dart';
import 'widgets/season_missions_list.dart';

/// Tela TEMPORADA: header (nome + countdown + nível/XP oficiais), trilha do
/// passe (gratuita claimable / premium travada) e missões da temporada.
/// XP, nível e claimed são 100% do backend — o cliente apenas exibe.
class SeasonScreen extends ConsumerWidget {
  const SeasonScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<SeasonModel?> season = ref.watch(seasonProvider);
    final AsyncValue<SeasonProgressModel?> progress =
        ref.watch(seasonProgressStreamProvider);
    final AsyncValue<List<MissionView>> missions =
        ref.watch(seasonMissionsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('TEMPORADA')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: season.when(
              loading: () => _buildLoading(),
              error: (_, _) => _buildError(ref),
              data: (SeasonModel? doc) {
                if (doc == null) {
                  return ListView(
                    padding: const EdgeInsets.all(20),
                    children: const <Widget>[
                      EmptyStatePanel(
                        icon: NeonIcons.clock,
                        title: 'TEMPORADA',
                        message: 'Nenhuma temporada ativa no momento.',
                      ),
                    ],
                  );
                }
                final SeasonProgressModel? p = progress.value;
                return RefreshIndicator(
                  color: AppColors.cyan,
                  backgroundColor: AppColors.surface,
                  onRefresh: () async => ref.invalidate(seasonProvider),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    children: <Widget>[
                      SeasonHeader(
                        season: doc,
                        level: p?.level ?? 1,
                        xp: p?.xp ?? 0,
                      ),
                      const SizedBox(height: 20),
                      PassTrack(
                        season: doc,
                        level: p?.level ?? 1,
                        claimedFree: p?.claimedFree ?? const <int>{},
                        claimedPremium: p?.claimedPremium ?? const <int>{},
                        premiumActive: p?.premiumActive ?? false,
                      ),
                      const SizedBox(height: 20),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'MISSÕES DA TEMPORADA',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SeasonMissionsList(views: missions.value ?? const <MissionView>[]),
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
          SkeletonBox(height: 300),
          SizedBox(height: 20),
          SkeletonBox(height: 110),
        ],
      );

  Widget _buildError(WidgetRef ref) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'Não foi possível carregar a temporada.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => ref.invalidate(seasonProvider),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('TENTAR NOVAMENTE'),
            ),
          ],
        ),
      );
}
