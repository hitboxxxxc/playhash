import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_router.dart';
import '../../core/providers.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_assets.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/coming_soon_sheet.dart';
import '../../core/widgets/neon_panel.dart';
import '../../core/widgets/skeleton_box.dart';
import '../../data/models/machine_model.dart';
import '../../data/models/power_model.dart';
import '../../data/models/wallet_model.dart';
import 'widgets/home_header.dart';
import 'widgets/machine_room_grid.dart';
import 'widgets/power_summary_card.dart';
import 'widgets/quick_stats_row.dart';

enum _HomeStatus { loading, ready, error }

/// Aba HOME — header do jogador, card "MEU PODER", sala de máquinas e
/// stats rápidos. Lê SOMENTE dados oficiais do Firestore via repositórios
/// cache-first; sem dados => "—"/vazio. Nada econômico é fabricado aqui.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  _HomeStatus _status = _HomeStatus.loading;
  String _displayName = '';
  WalletModel? _wallet;
  PowerModel? _power;
  List<MachineModel> _machines = const <MachineModel>[];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _status = _HomeStatus.loading);
    try {
      final AuthServiceApi auth = ref.read(authServiceProvider);
      final String? uid = (await auth.currentUser())?.uid;
      if (!mounted) return;
      if (uid == null) {
        setState(() => _status = _HomeStatus.ready);
        return;
      }

      // Perfil é essencial (erro => retry); dados econômicos são
      // tolerantes: falha => null => "—" (nunca bloqueia a tela).
      final Object results = await Future.wait<dynamic>(<Future<dynamic>>[
        ref.read(profileRepositoryProvider).loadOwnProfile(uid),
        ref
            .read(walletRepositoryProvider)
            .loadWallet(uid)
            .catchError((Object _) => null),
        ref
            .read(powerRepositoryProvider)
            .loadPower(uid)
            .catchError((Object _) => null),
        ref
            .read(machinesRepositoryProvider)
            .loadMachines(uid)
            .catchError((Object _) => const <MachineModel>[]),
      ]);
      if (!mounted) return;

      final List<dynamic> data = results as List<dynamic>;
      final Map<String, dynamic>? profile = data[0] as Map<String, dynamic>?;
      setState(() {
        _displayName = (profile?['displayName'] as String?)?.trim() ?? '';
        _wallet = data[1] as WalletModel?;
        _power = data[2] as PowerModel?;
        _machines = data[3] as List<MachineModel>;
        _status = _HomeStatus.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _HomeStatus.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(title: SvgPicture.string(AppAssets.logoSvg, width: 72)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: RefreshIndicator(
              color: AppColors.cyan,
              backgroundColor: AppColors.surface,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                children: <Widget>[
                  switch (_status) {
                    _HomeStatus.loading => _buildLoading(),
                    _HomeStatus.error => _buildError(),
                    _HomeStatus.ready => _buildReady(),
                  },
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() => Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              const SkeletonBox(width: 52, height: 52, borderRadius: 12),
              const SizedBox(width: 12),
              const Expanded(child: SkeletonBox(height: 18)),
              const SizedBox(width: 12),
              const SkeletonBox(width: 120, height: 48, borderRadius: 10),
            ],
          ),
          const SizedBox(height: 20),
          const SkeletonBox(height: 120),
          const SizedBox(height: 20),
          const SkeletonBox(height: 320),
          const SizedBox(height: 20),
          const SkeletonBox(height: 110),
        ],
      );

  Widget _buildError() => NeonPanel(
        accent: AppColors.error,
        child: Column(
          children: <Widget>[
            const Text(
              'Não foi possível carregar sua home.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Semantics(
              button: true,
              child: TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('TENTAR NOVAMENTE'),
              ),
            ),
          ],
        ),
      );

  Widget _buildReady() {
    // Poder das máquinas = soma OFICIAL das máquinas ativas (servidor).
    final int machinesPower = _machines
        .where((MachineModel m) => m.active)
        .fold<int>(0, (int sum, MachineModel m) => sum + m.power);

    // Poder dos jogos = restante do total oficial (apresentação).
    int? gamesPower;
    if (_power != null) {
      gamesPower = (_power!.totalPower - machinesPower).clamp(0, 1 << 62);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        HomeHeader(
          displayName: _displayName,
          availableBalance: _wallet?.availableBalance,
          onAddTap: () => showComingSoonSheet(
            context,
            feature: 'Adicionar saldo',
          ),
          onNotificationsTap: () => showComingSoonSheet(
            context,
            feature: 'Notificações',
          ),
          onSettingsTap: () => context.push(RoutePaths.settings),
        ),
        const SizedBox(height: 20),
        PowerSummaryCard(totalPower: _power?.totalPower),
        const SizedBox(height: 20),
        MachineRoomGrid(
          machines: _machines,
          onEditRoomTap: () => showComingSoonSheet(
            context,
            feature: 'Editar sala',
          ),
          onOrganizeTap: () => showComingSoonSheet(
            context,
            feature: 'Organizar máquinas',
          ),
        ),
        const SizedBox(height: 20),
        QuickStatsRow(
          machinesPower: _power == null ? null : machinesPower,
          gamesPower: gamesPower,
          // Sem schedule de blocos no backend => sempre "—" por enquanto.
          nextRewardLabel: null,
          // Ranking ainda sem fonte oficial => "—".
          ranking: null,
        ),
      ],
    );
  }
}
