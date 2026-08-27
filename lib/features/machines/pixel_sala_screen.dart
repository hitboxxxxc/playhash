import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/pixel_theme.dart';
import '../../core/utils/coin_format.dart';
import '../../core/utils/power_format.dart';
import '../../core/widgets/pixel_button.dart';
import '../../core/widgets/pixel_card.dart';
import '../../core/widgets/pixel_icon.dart';
import '../../core/widgets/pixel_icons.dart';
import '../../data/models/machine_catalog_model.dart';
import '../../data/models/machine_model.dart';
import '../../data/models/power_model.dart';
import '../../data/repositories/mining_repository.dart';
import '../../core/services/purchase_intent_service.dart';

enum _SalaStatus { loading, ready, error }

/// Tela DEDICADA DAS MÁQUINAS (SALA) - Poder total, loja e lista de máquinas.
class PixelSalaScreen extends ConsumerStatefulWidget {
  const PixelSalaScreen({super.key});

  @override
  ConsumerState<PixelSalaScreen> createState() => _PixelSalaScreenState();
}

class _PixelSalaScreenState extends ConsumerState<PixelSalaScreen> {
  _SalaStatus _status = _SalaStatus.loading;
  List<MachineCatalogModel> _catalog = const <MachineCatalogModel>[];
  Map<String, MachineModel> _ownedMachinesMap = const <String, MachineModel>{};
  String? _uid;
  BlockSnapshot? _block;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _status = _SalaStatus.loading);
    try {
      final String? uid = await ref.read(currentUidProvider.future);
      if (!mounted) return;

      final Object results = await Future.wait<dynamic>(<Future<dynamic>>[
        ref.read(machineCatalogRepositoryProvider).loadCatalog(),
        ref
            .read(walletRepositoryProvider)
            .loadWallet(uid ?? '')
            .catchError((Object _) => null),
        ref
            .read(machinesRepositoryProvider)
            .loadMachines(uid ?? '')
            .catchError((Object _) => const <MachineModel>[]),
        ref
            .read(miningRepositoryProvider)
            .loadBlockSnapshot()
            .catchError((Object _) => null),
      ]);

      if (!mounted) return;

      final List<dynamic> data = results as List<dynamic>;
      final List<MachineCatalogModel> catalogData =
          data[0] as List<MachineCatalogModel>;
      final List<MachineModel> ownedData = data[2] as List<MachineModel>;

      final Map<String, MachineModel> ownedMap = <String, MachineModel>{};
      for (final MachineModel m in ownedData) {
        if (m.type.isNotEmpty) {
          ownedMap[m.type] = m;
        }
      }

      setState(() {
        _uid = uid;
        _catalog = catalogData;
        _ownedMachinesMap = ownedMap;
        _block = data[3] as BlockSnapshot?;
        _status = _SalaStatus.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _SalaStatus.error);
    }
  }

  String _formatPowerText(int? totalPower) {
    if (totalPower == null || totalPower <= 0) return '0';
    final String formatted = PowerFormat.format(totalPower);
    final int spaceIdx = formatted.indexOf(' ');
    return spaceIdx > 0 ? formatted.substring(0, spaceIdx) : formatted;
  }

  String _formatPowerUnit(int? totalPower) {
    if (totalPower == null || totalPower <= 0) return 'H/s';
    final String formatted = PowerFormat.format(totalPower);
    final int spaceIdx = formatted.indexOf(' ');
    return spaceIdx > 0 ? formatted.substring(spaceIdx + 1) : 'H/s';
  }

  String _formatEstimatedReward(int machinePower) {
    final int networkPower = _block?.networkPower ?? 0;
    if (networkPower == 0 || machinePower <= 0) return '0,00';
    final RewardEstimate? estimate = ref
        .read(miningRepositoryProvider)
        .estimateReward(yourPower: machinePower, block: _block);
    final BigInt? units = estimate?.estimatedRewardMinimalUnits;
    if (units == null || units == BigInt.zero) return '0,00';
    return CoinFormat.formatMinimalUnits(units);
  }

  Future<void> _onUnlockMachine(MachineCatalogModel machine) async {
    final String? uid = _uid;
    if (uid == null) return;
    try {
      final String requestId = await ref
          .read(purchaseIntentServiceProvider)
          .createIntent(uid: uid, machineId: machine.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Solicitação de compra enviada (${machine.name})! ID: ${requestId.substring(0, 8)}...',
            style: const TextStyle(color: PixelTheme.gold),
          ),
        ),
      );

      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            e.toString(),
            style: const TextStyle(color: PixelTheme.red),
          ),
        ),
      );
    }
  }

  /// Calcula o custo de upgrade para o nível atual.
  /// Custo = price * upgradeCostFactor * currentLevel
  int _calculateUpgradeCost(MachineCatalogModel machine, int currentLevel) {
    final int price = machine.priceUnits.toInt();
    final double factor = machine.upgradeCostFactor;
    return (price * factor * currentLevel).round();
  }

  /// Calcula o poder no nível especificado.
  /// Power = basePower * (1 + levelPowerStep * (level - 1))
  int _calculatePower(MachineCatalogModel machine, int level) {
    final int basePower = machine.powerUnits;
    final double step = machine.levelPowerStep;
    return (basePower * (1 + step * (level - 1))).toInt();
  }

  Future<void> _onUpgradeMachine(MachineCatalogModel machine, int currentLevel) async {
    final String? uid = _uid;
    if (uid == null) return;
    try {
      final String requestId = await ref
          .read(purchaseIntentServiceProvider)
          .createUpgradeIntent(uid: uid, machineId: machine.id);

      if (!mounted) return;

      // Escuta o resultado da intent
      ref.read(purchaseIntentServiceProvider).watchUpgradeResult(requestId).listen(
        (result) {
          if (!mounted) return;
          if (result.isDone) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text(
                  'Máquina melhorada para nível ${currentLevel + 1}!',
                  style: const TextStyle(color: PixelTheme.green),
                ),
              ),
            );
            _loadData();
          } else if (result.isFailed) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text(
                  PurchaseIntentService.failureMessage(result.failureCode),
                  style: const TextStyle(color: PixelTheme.red),
                ),
              ),
            );
          }
        },
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Solicitação de upgrade enviada!',
            style: const TextStyle(color: PixelTheme.gold),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            e.toString(),
            style: const TextStyle(color: PixelTheme.red),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PowerModel?> powerAsync = ref.watch(powerStreamProvider);
    final int? totalPower = powerAsync.value?.totalPower;

    return Scaffold(
      body: SafeArea(
        child: switch (_status) {
          _SalaStatus.loading => const Center(
              child: CircularProgressIndicator(color: PixelTheme.purple),
            ),
          _SalaStatus.error => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Erro ao carregar a Sala',
                    style: TextStyle(color: PixelTheme.textDim),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loadData,
                    child: const Text('TENTAR NOVAMENTE'),
                  ),
                ],
              ),
            ),
          _SalaStatus.ready => SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Header Row (Poder Total + Botão Loja)
                  Row(
                    children: [
                      Expanded(
                        child: PixelCard(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            children: [
                              PixelIcon(
                                matrix: PixelIcons.bolt,
                                palette: PixelIcons.palette,
                                size: 32,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'PODER TOTAL',
                                      style: TextStyle(
                                        color: PixelTheme.purple,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          _formatPowerText(totalPower),
                                          style: PixelTheme.bigValue,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _formatPowerUnit(totalPower),
                                          style: const TextStyle(
                                            color: PixelTheme.purple,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        child: PixelButton(
                          label: 'LOJA',
                          style: PixelButtonStyle.purple,
                          full: false,
                          onPressed: () => context.push(RoutePaths.store),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 2. Title Section SALA
                  PixelCard(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        PixelIcon(
                          matrix: PixelIcons.monitor,
                          palette: PixelIcons.palette,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'SALA',
                          style: PixelTheme.title,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            height: 3,
                            color: PixelTheme.purpleDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 3. Banner da Sala com sprites das máquinas
                  PixelCard(
                    padding: const EdgeInsets.all(8),
                    child: Container(
                      height: 110,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF1A2130), Color(0xFF0B0E1A)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          PixelIcon(
                            matrix: PixelIcons.machineA,
                            palette: PixelIcons.palette,
                            size: 72,
                          ),
                          PixelIcon(
                            matrix: PixelIcons.machineB,
                            palette: PixelIcons.palette,
                            size: 72,
                          ),
                          PixelIcon(
                            matrix: PixelIcons.machineA,
                            palette: PixelIcons.palette,
                            size: 72,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 4. Lista de Máquinas (catálogo completo)
                  if (_catalog.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Nenhuma máquina disponível',
                          style: TextStyle(color: PixelTheme.textDim),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _catalog.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final machine = _catalog[index];
                        final bool useMachineA = index % 2 == 0;
                        final MachineModel? owned = _ownedMachinesMap[machine.id];
                        final bool isOwned = owned != null;
                        final int level = owned?.level ?? 1;
                        final int maxLevel = machine.maxLevel;
                        final int powerAtLevel = _calculatePower(machine, level);

                        return PixelCard(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Machine Sprite Thumbnail (código puro)
                              PixelIcon(
                                matrix: useMachineA ? PixelIcons.machineA : PixelIcons.machineB,
                                palette: PixelIcons.palette,
                                size: 56,
                              ),
                              const SizedBox(width: 8),
                              // Machine Info Column
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      machine.name,
                                      style: const TextStyle(
                                        color: PixelTheme.text,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: isOwned
                                                ? PixelTheme.green
                                                : PixelTheme.textDim,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            isOwned ? 'ATIVA' : 'INATIVA',
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: isOwned
                                                  ? PixelTheme.green
                                                  : PixelTheme.textDim,
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    if (isOwned) ...[
                                      Flexible(
                                        child: Row(
                                          children: [
                                            PixelIcon(
                                              matrix: PixelIcons.bolt,
                                              palette: PixelIcons.palette,
                                              size: 12,
                                            ),
                                            const SizedBox(width: 2),
                                            Expanded(
                                              child: Text(
                                                '${_formatPowerText(powerAtLevel)} ${_formatPowerUnit(powerAtLevel)}',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: PixelTheme.purple,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          PixelIcon(
                                            matrix: PixelIcons.coin,
                                            palette: PixelIcons.palette,
                                            size: 12,
                                          ),
                                          const SizedBox(width: 2),
                                          Expanded(
                                            child: Text(
                                              '≈${_formatEstimatedReward(powerAtLevel)} coin / 5 min',
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: PixelTheme.gold,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ] else ...[
                                      Flexible(
                                        child: Row(
                                          children: [
                                            PixelIcon(
                                              matrix: PixelIcons.bolt,
                                              palette: PixelIcons.palette,
                                              size: 12,
                                            ),
                                            const SizedBox(width: 2),
                                            Expanded(
                                              child: Text(
                                                '${_formatPowerText(machine.powerUnits)} ${_formatPowerUnit(machine.powerUnits)}',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: PixelTheme.purple,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          PixelIcon(
                                            matrix: PixelIcons.coin,
                                            palette: PixelIcons.palette,
                                            size: 12,
                                          ),
                                          const SizedBox(width: 2),
                                          Expanded(
                                            child: Text(
                                              '≈${_formatEstimatedReward(machine.powerUnits)} coin / 5 min',
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: PixelTheme.gold,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              // Action Column
                              SizedBox(
                                width: 100,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: PixelTheme.panel,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        isOwned ? 'NÍVEL $level' : '—',
                                        style: const TextStyle(
                                          color: PixelTheme.textDim,
                                          fontSize: 9,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    if (isOwned && level < maxLevel)
                                      SizedBox(
                                        height: 36,
                                        child: PixelButton(
                                          label: 'APRIMORAR',
                                          style: PixelButtonStyle.green,
                                          full: true,
                                          onPressed: () =>
                                              _onUpgradeMachine(machine, level),
                                        ),
                                      )
                                    else if (isOwned && level >= maxLevel)
                                      Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF000000).withValues(alpha: 0.3),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'NÍVEL MÁX',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: PixelTheme.textDim,
                                            fontSize: 8,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      )
                                    else
                                      SizedBox(
                                        height: 36,
                                        child: PixelButton(
                                          label: 'COMPRAR',
                                          style: PixelButtonStyle.purple,
                                          full: true,
                                          onPressed: () =>
                                              _onUnlockMachine(machine),
                                        ),
                                      ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        PixelIcon(
                                          matrix: PixelIcons.coin,
                                          palette: PixelIcons.palette,
                                          size: 10,
                                        ),
                                        const SizedBox(width: 4),
                                        if (isOwned && level < maxLevel)
                                        Text(
                                          CoinFormat.formatMinimalUnits(
                                              BigInt.from(_calculateUpgradeCost(machine, level))),
                                          style: const TextStyle(
                                            color: PixelTheme.gold,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      else
                                        Text(
                                          CoinFormat.formatMinimalUnits(machine.priceUnits),
                                          style: const TextStyle(
                                            color: PixelTheme.gold,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
        },
      ),
    );
  }
}
