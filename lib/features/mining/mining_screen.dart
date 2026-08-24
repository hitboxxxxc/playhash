import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/neon_panel.dart';
import '../../core/widgets/skeleton_box.dart';
import '../../data/models/machine_model.dart';
import '../../data/models/power_model.dart';
import '../../data/repositories/mining_repository.dart';
import 'widgets/block_panel.dart';
import 'widgets/league_progress_card.dart';
import 'widgets/power_distribution_chart.dart';
import 'widgets/power_header.dart';
import 'widgets/reward_history_list.dart';

enum _MiningStatus { loading, ready, error }

/// Aba MINERAÇÃO — "MEU PODER", próxima liga, distribuição do poder,
/// painel de recompensa e histórico. Lê SOMENTE dados oficiais do
/// Firestore via repositórios cache-first; sem backend => "—"/vazio.
/// NENHUM valor econômico é fabricado no cliente.
class MiningScreen extends ConsumerStatefulWidget {
  const MiningScreen({super.key});

  @override
  ConsumerState<MiningScreen> createState() => _MiningScreenState();
}

class _MiningScreenState extends ConsumerState<MiningScreen>
    with AutomaticKeepAliveClientMixin {
  _MiningStatus _status = _MiningStatus.loading;
  PowerModel? _power;
  BlockSnapshot? _block;
  RewardEstimate? _estimate;
  List<RewardEntry> _history = const <RewardEntry>[];
  Map<String, dynamic>? _league;
  int? _machinesPower;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _status = _MiningStatus.loading);
    try {
      final AuthServiceApi auth = ref.read(authServiceProvider);
      final String? uid = (await auth.currentUser())?.uid;
      if (!mounted) return;
      if (uid == null) {
        setState(() => _status = _MiningStatus.ready);
        return;
      }

      final MiningRepositoryApi mining = ref.read(miningRepositoryProvider);
      final Object results = await Future.wait<dynamic>(<Future<dynamic>>[
        ref.read(powerRepositoryProvider).loadPower(uid),
        mining.loadBlockSnapshot(),
        mining.loadRewardHistory(uid),
        mining.loadUserLeague(uid),
        ref.read(machinesRepositoryProvider).loadMachines(uid),
      ]);
      if (!mounted) return;

      final List<dynamic> data = results as List<dynamic>;
      final PowerModel? power = data[0] as PowerModel?;
      final BlockSnapshot? block = data[1] as BlockSnapshot?;
      final List<RewardEntry> history = data[2] as List<RewardEntry>;
      final Map<String, dynamic>? league = data[3] as Map<String, dynamic>?;
      final List<MachineModel> machines = data[4] as List<MachineModel>;

      // Poder das máquinas = soma OFICIAL das máquinas ativas (servidor).
      final int machinesPower = machines
          .where((MachineModel m) => m.active)
          .fold<int>(0, (int sum, MachineModel m) => sum + m.power);

      // Poder dos jogos = restante do total oficial (apresentação).
      // Sem total oficial => null => "—".
      int? gamesPower;
      if (power != null) {
        gamesPower = power.totalPower - machinesPower;
        if (gamesPower < 0) gamesPower = 0;
      }

      setState(() {
        _power = power;
        _block = block;
        _history = history;
        _league = league;
        _machinesPower = power == null ? null : machinesPower;
        _gamesPower = gamesPower;
        _estimate = mining.estimateReward(
          yourPower: power?.totalPower ?? 0,
          block: block,
        );
        _status = _MiningStatus.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _MiningStatus.error);
    }
  }

  int? _gamesPower;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(title: const Text('MINERAÇÃO')),
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
                    _MiningStatus.loading => _buildLoading(),
                    _MiningStatus.error => _buildError(),
                    _MiningStatus.ready => _buildReady(),
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
          const SizedBox(height: 8),
          const SkeletonBox(width: 160, height: 20),
          const SizedBox(height: 12),
          const SkeletonBox(width: 240, height: 40),
          const SizedBox(height: 20),
          const SkeletonBox(height: 110),
          const SizedBox(height: 16),
          const SkeletonBox(height: 200),
          const SizedBox(height: 16),
          const SkeletonBox(height: 240),
          const SizedBox(height: 16),
          const SkeletonBox(height: 120),
        ],
      );

  Widget _buildError() => NeonPanel(
        accent: AppColors.error,
        child: Column(
          children: <Widget>[
            const Text(
              'Não foi possível carregar seus dados de mineração.',
              textAlign: TextAlign.center,
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
    final Map<String, dynamic>? league = _league;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PowerHeader(totalPower: _power?.totalPower),
        const SizedBox(height: 16),
        LeagueProgressCard(
          currentLeagueName: league?['leagueName'] as String?,
          nextLeagueName: league?['nextLeagueName'] as String?,
          currentPower: _toInt(league?['power'] ?? league?['currentPower']),
          nextThreshold:
              _toInt(league?['nextLeagueThreshold'] ?? league?['threshold']),
        ),
        const SizedBox(height: 16),
        PowerDistributionChart(
          machinesPower: _machinesPower,
          gamesPower: _gamesPower,
        ),
        const SizedBox(height: 16),
        BlockPanel(
          block: _block,
          yourPower: _power?.totalPower,
          estimate: _estimate,
        ),
        const SizedBox(height: 20),
        RewardHistoryList(entries: _history),
      ],
    );
  }

  static int? _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

