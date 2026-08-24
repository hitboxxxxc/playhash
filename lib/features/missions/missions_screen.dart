import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/app_assets.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/neon_panel.dart';
import '../../core/widgets/skeleton_box.dart';
import '../../data/models/mission_model.dart';
import 'widgets/mission_card.dart';

/// Tela MISSÕES: abas DIÁRIAS / SEMANAIS / EVENTOS ("EM BREVE").
/// Dados 100% oficiais: catálogo `missions/*` + progresso
/// `userMissions/{uid}/items` escrito pelo runner. Estados loading/erro/
/// offline/vazio cobertos; resgate via [ClaimService] (intenção validada
/// pelo backend — o cliente nunca concede recompensa).
class MissionsScreen extends ConsumerWidget {
  const MissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<MissionView>> missions =
        ref.watch(missionsStreamProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: SvgPicture.string(AppAssets.logoSvg, width: 56),
          bottom: const TabBar(
            indicatorColor: AppColors.cyan,
            labelColor: AppColors.cyan,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            tabs: <Widget>[
              Tab(text: 'DIÁRIAS'),
              Tab(text: 'SEMANAIS'),
              Tab(text: 'EVENTOS'),
            ],
          ),
        ),
        body: SafeArea(
          child: missions.when(
            loading: () => _buildLoading(),
            error: (_, _) => _buildError(ref),
            data: (List<MissionView> list) => TabBarView(
              children: <Widget>[
                _MissionsList(
                  views: list
                      .where((MissionView v) => v.mission.kind == 'daily')
                      .toList(growable: false),
                ),
                _MissionsList(
                  views: list
                      .where((MissionView v) => v.mission.kind == 'weekly')
                      .toList(growable: false),
                ),
                const _EventsComingSoon(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() => ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: const <Widget>[
          SkeletonBox(height: 110),
          SizedBox(height: 16),
          SkeletonBox(height: 110),
          SizedBox(height: 16),
          SkeletonBox(height: 110),
        ],
      );

  Widget _buildError(WidgetRef ref) => Center(
        child: NeonPanel(
          accent: AppColors.error,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'Não foi possível carregar suas missões.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => ref.invalidate(missionsStreamProvider),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('TENTAR NOVAMENTE'),
              ),
            ],
          ),
        ),
      );
}

class _MissionsList extends StatelessWidget {
  const _MissionsList({required this.views});

  final List<MissionView> views;

  @override
  Widget build(BuildContext context) {
    if (views.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SvgPicture.string(AppAssets.gamepadIconSvg, width: 48, height: 48),
            const SizedBox(height: 12),
            const Text(
              'Nenhuma missão disponível agora.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.cyan,
      backgroundColor: AppColors.surface,
      onRefresh: () async {},
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        itemCount: views.length,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (_, int i) => MissionCard(
          view: views[i],
          onPlay: () => context.push(RoutePaths.games),
        ),
      ),
    );
  }
}

class _EventsComingSoon extends StatelessWidget {
  const _EventsComingSoon();

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SvgPicture.string(AppAssets.giftIconSvg, width: 48, height: 48),
            const SizedBox(height: 12),
            const Text(
              'EVENTOS',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'EM BREVE',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      );
}
