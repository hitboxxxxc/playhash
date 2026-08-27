import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/navigation/loja_notifier.dart';
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
import '../../core/services/machine_shop_service.dart';

enum _SalaStatus { loading, ready, error }

/// Tela DEDICADA DAS MÁQUINAS (SALA) - Sala de mineração do jogador (só possuídas + cena + detalhes + aprimorar).
class PixelSalaScreen extends ConsumerStatefulWidget {
  const PixelSalaScreen({super.key});

  @override
  ConsumerState<PixelSalaScreen> createState() => _PixelSalaScreenState();
}

class _PixelSalaScreenState extends ConsumerState<PixelSalaScreen> {
  _SalaStatus _status = _SalaStatus.loading;
  List<MachineCatalogModel> _catalog = const <MachineCatalogModel>[];
  List<MachineModel> _ownedMachines = const <MachineModel>[];
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

      setState(() {
        _uid = uid;
        _catalog = catalogData;
        _ownedMachines = ownedData;
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

  int _calculateUpgradeCost(MachineCatalogModel machine, int currentLevel) {
    final int price = machine.priceUnits.toInt();
    final double factor = machine.upgradeCostFactor;
    return (price * factor * currentLevel).round();
  }

  int _calculatePower(MachineCatalogModel machine, int level) {
    final int basePower = machine.powerUnits;
    final double step = machine.levelPowerStep;
    return (basePower * (1 + step * (level - 1))).toInt();
  }

  String _formatPurchasedDate(dynamic purchasedAt) {
    if (purchasedAt == null) return '—';
    if (purchasedAt is Timestamp) {
      final dt = purchasedAt.toDate();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    }
    if (purchasedAt is DateTime) {
      return '${purchasedAt.day.toString().padLeft(2, '0')}/${purchasedAt.month.toString().padLeft(2, '0')}/${purchasedAt.year}';
    }
    return '—';
  }

  Future<void> _onUpgradeMachine(MachineCatalogModel machine, int currentLevel) async {
    final String? uid = _uid;
    if (uid == null) return;

    final powerBeforeModel = ref.read(powerStreamProvider).value;
    final int totalAntesT = powerBeforeModel?.totalPower ?? 0;
    final int powerAntes = _calculatePower(machine, currentLevel);

    try {
      await MachineShopService.upgradeMachine(
        machineId: machine.id,
        priceCoins: (machine.priceUnits ~/ BigInt.from(1000000)).toInt(),
        powerBase: machine.powerUnits,
        maxLevel: machine.maxLevel,
      );
      if (!mounted) return;

      await _loadData();
      if (!mounted) return;

      final powerAfterModel = ref.read(powerStreamProvider).value;
      final int totalDepoisT = powerAfterModel?.totalPower ?? totalAntesT;
      final int powerDepois = _calculatePower(machine, currentLevel + 1);

      showDialog(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          backgroundColor: PixelTheme.panel,
          title: const Text(
            'APRIMORAMENTO CONCLUÍDO!',
            style: TextStyle(color: PixelTheme.green, fontSize: 14, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '⚡ Poder da máquina: $powerAntes → $powerDepois KH/s',
                style: const TextStyle(color: PixelTheme.text, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Text(
                    'PODER TOTAL: ',
                    style: TextStyle(color: PixelTheme.textDim, fontSize: 12),
                  ),
                  Text(
                    '$totalAntesT → ',
                    style: const TextStyle(color: PixelTheme.textDim, fontSize: 12),
                  ),
                  Text(
                    '$totalDepoisT',
                    style: const TextStyle(color: PixelTheme.green, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK', style: TextStyle(color: PixelTheme.purple)),
            ),
          ],
        ),
      );
    } on PurchaseException catch (e) {
      if (!mounted) return;
      final String msg = switch (e.code) {
        'SALDO_INSUFICIENTE' => 'Saldo insuficiente',
        'NAO_POSSUIDA' => 'Máquina não possui',
        'NIVEL_MAX' => 'Nível máximo',
        'SEM_LOGIN' => 'Entre na conta',
        _ => e.code,
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            msg,
            style: const TextStyle(color: PixelTheme.red),
          ),
        ),
      );
    }
  }

  void _showMachineDetailSheet(MachineCatalogModel machine, MachineModel owned) {
    final int level = owned.level;
    final int maxLevel = machine.maxLevel;
    final int currentPower = _calculatePower(machine, level);
    final int nextPower = level < maxLevel ? _calculatePower(machine, level + 1) : currentPower;
    final int upgradeCost = level < maxLevel ? _calculateUpgradeCost(machine, level) : 0;
    final String estReward = _formatEstimatedReward(currentPower);
    final String acquiredDate = _formatPurchasedDate(owned.purchasedAt);

    showModalBottomSheet(
      context: context,
      backgroundColor: PixelTheme.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  PixelIcon(
                    matrix: machine.id.hashCode.isEven ? PixelIcons.machineA : PixelIcons.machineB,
                    palette: PixelIcons.palette,
                    size: 36,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          machine.name,
                          style: const TextStyle(
                            color: PixelTheme.text,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Row(
                          children: [
                            ContainerDot(color: PixelTheme.green, size: 8),
                            SizedBox(width: 4),
                            Text('ATIVA', style: TextStyle(color: PixelTheme.green, fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(color: PixelTheme.border, height: 20),
              _DetailRow(label: 'Nível:', value: 'NÍVEL $level'),
              const SizedBox(height: 6),
              _DetailRow(label: 'Poder atual:', value: '${_formatPowerText(currentPower)} ${_formatPowerUnit(currentPower)}'),
              const SizedBox(height: 6),
              _DetailRow(label: 'Produção ≈:', value: '≈ $estReward coin / 5 min'),
              const SizedBox(height: 6),
              _DetailRow(label: 'Adquirido em:', value: acquiredDate),
              const SizedBox(height: 10),
              if (level < maxLevel)
                Text(
                  'PRÓXIMO NÍVEL: ${_formatPowerText(currentPower)} → ${_formatPowerText(nextPower)} ${_formatPowerUnit(nextPower)}',
                  style: const TextStyle(color: PixelTheme.purple, fontSize: 11, fontWeight: FontWeight.bold),
                )
              else
                const Text(
                  'NÍVEL MÁXIMO ATINGIDO',
                  style: TextStyle(color: PixelTheme.gold, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              const SizedBox(height: 16),
              if (level < maxLevel) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        PixelIcon(matrix: PixelIcons.coin, palette: PixelIcons.palette, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          CoinFormat.formatMinimalUnits(BigInt.from(upgradeCost)),
                          style: const TextStyle(color: PixelTheme.gold, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ),
                    SizedBox(
                      width: 140,
                      child: PixelButton(
                        label: 'APRIMORAR',
                        style: PixelButtonStyle.purple,
                        full: false,
                        onPressed: () {
                          Navigator.of(context).pop();
                          _onUpgradeMachine(machine, level);
                        },
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: PixelTheme.panel,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'NÍVEL MÁX',
                    style: TextStyle(color: PixelTheme.textDim, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PowerModel?> powerAsync = ref.watch(powerStreamProvider);
    final int? totalPower = powerAsync.value?.totalPower;

    final Map<String, MachineCatalogModel> catalogMap = <String, MachineCatalogModel>{};
    for (final MachineCatalogModel m in _catalog) {
      catalogMap[m.id] = m;
    }

    final List<MapEntry<MachineCatalogModel, MachineModel>> ownedList = <MapEntry<MachineCatalogModel, MachineModel>>[];
    for (final MachineModel owned in _ownedMachines) {
      final MachineCatalogModel? cat = catalogMap[owned.type];
      if (cat != null) {
        ownedList.add(MapEntry<MachineCatalogModel, MachineModel>(cat, owned));
      }
    }

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
                                size: 28,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'PODER TOTAL',
                                      style: TextStyle(
                                        color: PixelTheme.purple,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        Flexible(
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              _formatPowerText(totalPower),
                                              style: PixelTheme.bigValue,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          _formatPowerUnit(totalPower),
                                          style: const TextStyle(
                                            color: PixelTheme.purple,
                                            fontSize: 11,
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
                        width: 105,
                        child: InkWell(
                          onTap: () => LojaNav.abrirLoja(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                            decoration: BoxDecoration(
                              color: PixelTheme.purple,
                              border: Border.all(color: PixelTheme.purpleDark, width: 2),
                              borderRadius: BorderRadius.circular(PixelTheme.radius),
                            ),
                            child: Row(
                              children: [
                                PixelIcon(
                                  matrix: PixelIcons.cart,
                                  palette: PixelIcons.palette,
                                  size: 20,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        'LOJA',
                                        style: TextStyle(
                                          color: PixelTheme.text,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        'Comprar',
                                        style: TextStyle(
                                          color: PixelTheme.text.withValues(alpha: 0.8),
                                          fontSize: 9,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 2. PixelCard 'SUA SALA'
                  PixelCard(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            PixelIcon(
                              matrix: PixelIcons.monitor,
                              palette: PixelIcons.palette,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'SUA SALA',
                                    style: PixelTheme.title,
                                  ),
                                  const SizedBox(height: 2),
                                  RichText(
                                    text: const TextSpan(
                                      text: 'Suas máquinas estão minerando ',
                                      style: TextStyle(color: PixelTheme.textDim, fontSize: 10),
                                      children: [
                                        TextSpan(
                                          text: '24h por dia',
                                          style: TextStyle(color: PixelTheme.purple, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 170,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFF1A2130), Color(0xFF0B0E1A)],
                            ),
                            border: Border.all(color: PixelTheme.border, width: 1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF05070D),
                                    border: Border.all(color: PixelTheme.cyan.withValues(alpha: 0.5), width: 1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        'MINERANDO...',
                                        style: TextStyle(color: PixelTheme.green, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 2),
                                      const Text(
                                        'PODER TOTAL',
                                        style: TextStyle(color: PixelTheme.textDim, fontSize: 9),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${_formatPowerText(totalPower)} ${_formatPowerUnit(totalPower)}',
                                        style: const TextStyle(color: PixelTheme.text, fontSize: 14, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Center(
                                child: ownedList.isEmpty
                                    ? Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Text(
                                            'Você ainda não possui máquinas',
                                            style: TextStyle(color: PixelTheme.textDim, fontSize: 12),
                                          ),
                                          const SizedBox(height: 8),
                                          PixelButton(
                                            label: 'IR PARA LOJA',
                                            style: PixelButtonStyle.purple,
                                            full: false,
                                            onPressed: () => LojaNav.abrirLoja(),
                                          ),
                                        ],
                                      )
                                    : Padding(
                                        padding: const EdgeInsets.only(top: 40),
                                        child: Wrap(
                                          alignment: WrapAlignment.center,
                                          spacing: 12,
                                          runSpacing: 12,
                                          children: List<Widget>.generate(ownedList.length, (int index) {
                                            final bool useA = index % 2 == 0;
                                            return Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                PixelIcon(
                                                  matrix: useA ? PixelIcons.machineA : PixelIcons.machineB,
                                                  palette: PixelIcons.palette,
                                                  size: 56,
                                                ),
                                                const SizedBox(height: 4),
                                                Container(
                                                  height: 6,
                                                  width: 64,
                                                  decoration: BoxDecoration(
                                                    color: PixelTheme.purpleDark,
                                                    borderRadius: BorderRadius.circular(2),
                                                  ),
                                                ),
                                              ],
                                            );
                                          }),
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 3. Lista de máquinas POSSUÍDAS
                  if (ownedList.isEmpty)
                    const SizedBox.shrink()
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: ownedList.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final entry = ownedList[index];
                        final MachineCatalogModel machine = entry.key;
                        final MachineModel owned = entry.value;
                        final bool useA = index % 2 == 0;
                        final int level = owned.level;
                        final int maxLevel = machine.maxLevel;
                        final int powerAtLevel = _calculatePower(machine, level);
                        final int upgradeCost = _calculateUpgradeCost(machine, level);

                        return GestureDetector(
                          onTap: () => _showMachineDetailSheet(machine, owned),
                          child: PixelCard(
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                PixelIcon(
                                  matrix: useA ? PixelIcons.machineA : PixelIcons.machineB,
                                  palette: PixelIcons.palette,
                                  size: 48,
                                ),
                                const SizedBox(width: 8),
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
                                          fontSize: 14,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: const BoxDecoration(
                                              color: PixelTheme.green,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Text(
                                            'ATIVA',
                                            style: TextStyle(
                                              color: PixelTheme.green,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          PixelIcon(
                                            matrix: PixelIcons.bolt,
                                            palette: PixelIcons.palette,
                                            size: 14,
                                          ),
                                          const SizedBox(width: 2),
                                          Flexible(
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    _formatPowerText(powerAtLevel),
                                                    style: const TextStyle(
                                                      color: PixelTheme.purple,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 11,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 2),
                                                Text(
                                                  _formatPowerUnit(powerAtLevel),
                                                  style: const TextStyle(
                                                    color: PixelTheme.purple,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          PixelIcon(
                                            matrix: PixelIcons.coin,
                                            palette: PixelIcons.palette,
                                            size: 14,
                                          ),
                                          const SizedBox(width: 2),
                                          Expanded(
                                            child: Text(
                                              '≈ ${_formatEstimatedReward(powerAtLevel)} c/5m',
                                              style: const TextStyle(
                                                color: PixelTheme.gold,
                                                fontSize: 10,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 110,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'NÍVEL $level',
                                        style: const TextStyle(
                                          color: PixelTheme.purple,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 2),
                                      LinearProgressIndicator(
                                        value: (level / maxLevel).clamp(0.0, 1.0),
                                        color: PixelTheme.purple,
                                        backgroundColor: PixelTheme.border,
                                      ),
                                      const SizedBox(height: 6),
                                      if (level < maxLevel)
                                        SizedBox(
                                          height: 36,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: PixelButton(
                                              label: 'APRIMORAR',
                                              style: PixelButtonStyle.purple,
                                              full: false,
                                              onPressed: () => _onUpgradeMachine(machine, level),
                                            ),
                                          ),
                                        )
                                      else
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: PixelTheme.panel,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          alignment: Alignment.center,
                                          child: const Text(
                                            'NÍVEL MÁX',
                                            style: TextStyle(
                                              color: PixelTheme.textDim,
                                              fontSize: 8,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          PixelIcon(
                                            matrix: PixelIcons.coin,
                                            palette: PixelIcons.palette,
                                            size: 12,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              level < maxLevel
                                                  ? CoinFormat.formatMinimalUnits(BigInt.from(upgradeCost))
                                                  : '—',
                                              style: const TextStyle(
                                                color: PixelTheme.gold,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
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
                        );
                      },
                    ),
                  const SizedBox(height: 12),

                  // 4. Card tracejado / MAIS MÁQUINAS / IR PARA LOJA
                  PixelCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        PixelIcon(
                          matrix: PixelIcons.cart,
                          palette: PixelIcons.palette,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'MAIS MÁQUINAS',
                                style: TextStyle(
                                  color: PixelTheme.text,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Adquira novas máquinas e aumente seu poder de mineração.',
                                style: TextStyle(
                                  color: PixelTheme.textDim,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 130,
                          child: PixelButton(
                            label: 'IR PARA LOJA',
                            style: PixelButtonStyle.purple,
                            full: false,
                            onPressed: () => LojaNav.abrirLoja(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        },
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: PixelTheme.textDim, fontSize: 12)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: PixelTheme.text, fontWeight: FontWeight.bold, fontSize: 12),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class ContainerDot extends StatelessWidget {
  final Color color;
  final double size;

  const ContainerDot({super.key, required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
