import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/services/machine_shop_service.dart';
import '../../core/theme/pixel_theme.dart';
import '../../core/utils/coin_format.dart';
import '../../core/utils/power_format.dart';
import '../../core/widgets/pixel_icon.dart';
import '../../core/widgets/pixel_icons.dart';
import '../../data/models/machine_catalog_model.dart';
import '../../data/models/machine_model.dart';
import '../../data/models/wallet_model.dart';

enum _LojaStatus { loading, ready, error }

class PixelLojaScreen extends ConsumerStatefulWidget {
  const PixelLojaScreen({super.key, required this.onGoToSala});

  final VoidCallback onGoToSala;

  @override
  ConsumerState<PixelLojaScreen> createState() => _PixelLojaScreenState();
}

class _PixelLojaScreenState extends ConsumerState<PixelLojaScreen> {
  _LojaStatus _status = _LojaStatus.loading;
  int _selectedCategoryIndex = 0;
  List<MachineCatalogModel> _catalog = [];
  WalletModel? _wallet;
  Map<String, MachineModel?> _ownedMachines = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _status = _LojaStatus.loading);
    try {
      final String? uid = await ref.read(currentUidProvider.future);
      if (!mounted) return;

      final results = await Future.wait([
        ref.read(machineCatalogRepositoryProvider).loadCatalog(),
        ref
            .read(walletRepositoryProvider)
            .loadWallet(uid ?? '')
            .catchError((Object _) => null),
        ref
            .read(machinesRepositoryProvider)
            .loadMachines(uid ?? '')
            .catchError((Object _) => const <MachineModel>[]),
      ]);

      if (!mounted) return;

      final List<MachineCatalogModel> catalog =
          results[0] as List<MachineCatalogModel>;
      final WalletModel? wallet = results[1] as WalletModel?;
      final List<MachineModel> owned = results[2] as List<MachineModel>;

      final Map<String, MachineModel?> ownedMap = {};
      for (final MachineModel m in owned) {
        if (m.type.isNotEmpty) {
          ownedMap[m.type] = m;
        }
      }

      setState(() {
        _catalog = catalog;
        _wallet = wallet;
        _ownedMachines = ownedMap;
        _status = _LojaStatus.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _LojaStatus.error);
    }
  }

  String _categoryLabel(MachineCatalogModel machine) {
    final String r = machine.rarity.toLowerCase();
    if (r == 'legendary') return 'PREMIUM';
    if (r == 'rare' || r == 'epic') return 'AVANÇADA';
    return 'BÁSICA';
  }

  Color _categoryColor(MachineCatalogModel machine) {
    final String cat = _categoryLabel(machine);
    switch (cat) {
      case 'AVANÇADA':
        return PixelTheme.purple;
      case 'PREMIUM':
        return PixelTheme.gold;
      default:
        return PixelTheme.cyan;
    }
  }

  String _categoryDescription(MachineCatalogModel machine) {
    final String cat = _categoryLabel(machine);
    switch (cat) {
      case 'AVANÇADA':
        return 'Mais poder, mais moedas. Para mineradores dedicados.';
      case 'PREMIUM':
        return 'Máquina de última geração. Para mineradores extremos.';
      default:
        return 'Perfeita para quem está começando a minerar.';
    }
  }

  String _ownedLevel(MachineCatalogModel machine) {
    final MachineModel? m = _ownedMachines[machine.id];
    if (m == null) return '1';
    return m.level.toString();
  }

  int _ownedCount(MachineCatalogModel machine) {
    int count = 0;
    for (final MachineModel? m in _ownedMachines.values) {
      if (m != null && m.type == machine.id) count++;
    }
    return count;
  }

  void _showConfirmation(MachineCatalogModel machine) {
    final BigInt balance = _wallet?.availableBalance ?? BigInt.zero;
    final BigInt price = machine.priceUnits;
    final BigInt after = balance - price;

    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: PixelTheme.panel,
        title: Text('Comprar ${machine.name}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Poder ${PowerFormat.format(machine.powerUnits)}',
              style: const TextStyle(color: PixelTheme.text, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              'Preço ${CoinFormat.formatMinimalUnits(price)} COIN',
              style: const TextStyle(color: PixelTheme.text, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              'Saldo atual: ${CoinFormat.formatMinimalUnits(balance)} COIN',
              style: const TextStyle(color: PixelTheme.textDim, fontSize: 11),
            ),
            Text(
              'Saldo após compra: ${CoinFormat.formatMinimalUnits(after)} COIN',
              style: TextStyle(
                color: after < BigInt.zero ? PixelTheme.red : PixelTheme.green,
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR',
                style: TextStyle(color: PixelTheme.textDim)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: PixelTheme.purple,
              foregroundColor: PixelTheme.text,
            ),
            onPressed: after < BigInt.zero
                ? null
                : () async {
                    Navigator.pop(context);
                    try {
                      final int priceCoins = (machine.priceUnits ~/
                              BigInt.from(1000000))
                          .toInt();
                      await MachineShopService.buyMachine(
                        machineId: machine.id,
                        name: machine.name,
                        priceCoins: priceCoins,
                        powerBase: machine.powerUnits,
                      );
                      if (!mounted) return;
                      await _load();
                      if (!mounted) return;
                      _showSuccessDialog(machine);
                    } on PurchaseException catch (e) {
                      if (!mounted) return;
                      _showErrorSnackBar(e.code);
                    } catch (e) {
                      if (!mounted) return;
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Erro: $e'),
                          backgroundColor: PixelTheme.red,
                        ),
                      );
                    }
                  },
            child: const Text('CONFIRMAR COMPRA'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(MachineCatalogModel machine) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: PixelTheme.panel,
        title: Text('${machine.name} adquirido!'),
        content: Text(
          'Sua nova máquina foi adicionada à sua sala de mineração.',
          style: const TextStyle(color: PixelTheme.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CONTINUAR NA LOJA',
                style: TextStyle(color: PixelTheme.textDim)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: PixelTheme.purple,
              foregroundColor: PixelTheme.text,
            ),
            onPressed: () {
              Navigator.pop(context);
              widget.onGoToSala();
            },
            child: const Text('IR PARA MINHA SALA'),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String code) {
    String message;
    switch (code) {
      case 'SALDO_INSUFICIENTE':
        message = 'Saldo insuficiente para comprar esta máquina.';
        break;
      case 'JA_POSSUIDA':
        message = 'Você já possui esta máquina na sua sala.';
        break;
      case 'SEM_LOGIN':
        message = 'Você precisa estar logado para comprar.';
        break;
      default:
        message = 'Erro na compra: $code';
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: PixelTheme.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  List<MachineCatalogModel> _filteredCatalog() {
    switch (_selectedCategoryIndex) {
      case 1: // BÁSICAS
        return _catalog
            .where((m) => _categoryLabel(m) == 'BÁSICA')
            .toList();
      case 2: // AVANÇADAS
        return _catalog
            .where((m) => _categoryLabel(m) == 'AVANÇADA')
            .toList();
      case 3: // PREMIUM
        return _catalog
            .where((m) => _categoryLabel(m) == 'PREMIUM')
            .toList();
      default:
        return _catalog;
    }
  }

  @override
  Widget build(BuildContext context) {
    final BigInt balance = _wallet?.availableBalance ?? BigInt.zero;
    int totalPower = 0;
    for (final MachineModel? m in _ownedMachines.values) {
      if (m != null) totalPower += m.power;
    }

    return Scaffold(
      backgroundColor: PixelTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Topo: saldo + poder + fechar
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 4),
                            decoration: BoxDecoration(
                              color: PixelTheme.panel,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: PixelTheme.gold),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PixelIcon(
                                  matrix: PixelIcons.coin,
                                  palette: PixelIcons.palette,
                                  size: 14,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  CoinFormat.formatMinimalUnits(balance),
                                  style: const TextStyle(
                                      color: PixelTheme.gold,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11),
                                ),
                                const SizedBox(width: 2),
                                const Text('COIN',
                                    style: TextStyle(
                                        color: PixelTheme.textDim, fontSize: 8)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 4),
                            decoration: BoxDecoration(
                              color: PixelTheme.panel,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: PixelTheme.purple),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PixelIcon(
                                  matrix: PixelIcons.bolt,
                                  palette: PixelIcons.palette,
                                  size: 14,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  PowerFormat.format(totalPower),
                                  style: const TextStyle(
                                      color: PixelTheme.purple,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: PixelTheme.panel,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: PixelTheme.border),
                      ),
                      child: const Icon(Icons.close,
                          key: Key('close-button'),
                          color: PixelTheme.text,
                          size: 16),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const SizedBox(height: 16),
              // Header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'LOJA',
                          style: TextStyle(
                              color: PixelTheme.text,
                              fontWeight: FontWeight.bold,
                              fontSize: 28,
                              letterSpacing: 2),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Compre novas máquinas e aumente seu poder de mineração.',
                          style: TextStyle(
                              color: PixelTheme.textDim, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  PixelIcon(
                    matrix: PixelIcons.shop,
                    palette: PixelIcons.palette,
                    size: 84,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Filtros
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _filterChip('TODAS', 0),
                  _filterChip('BÁSICAS', 1),
                  _filterChip('AVANÇADAS', 2),
                  _filterChip('PREMIUM', 3),
                ],
              ),
              const SizedBox(height: 16),
              // Lista ou estados
              if (_status == _LojaStatus.loading)
                const Center(
                    child: CircularProgressIndicator(color: PixelTheme.purple))
              else if (_status == _LojaStatus.error)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Erro ao carregar catálogo',
                          style: TextStyle(color: PixelTheme.red)),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _load,
                        child: const Text('TENTAR NOVAMENTE'),
                      ),
                    ],
                  ),
                )
              else if (_filteredCatalog().isEmpty)
                const Center(
                  child: Text('Nenhuma máquina encontrada.',
                      style: TextStyle(color: PixelTheme.textDim)),
                )
              else
                Column(
                  children: _filteredCatalog()
                      .map((MachineCatalogModel machine) =>
                          _buildMachineCard(machine))
                      .toList(),
                ),
              const SizedBox(height: 24),
              // Rodapé
              Row(
                children: [
                  PixelIcon(
                    matrix: PixelIcons.cart,
                    palette: PixelIcons.palette,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cada máquina trabalha 24h por dia, gerando coins automaticamente.',
                      style: const TextStyle(
                          color: PixelTheme.textDim, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String label, int index) {
    final bool selected = _selectedCategoryIndex == index;
    return FilterChip(
      label: Text(label,
          style: TextStyle(
              color: selected ? PixelTheme.text : PixelTheme.textDim,
              fontSize: 12)),
      selected: selected,
      selectedColor: PixelTheme.purple,
      backgroundColor: PixelTheme.panel,
      checkmarkColor: PixelTheme.text,
      onSelected: (bool v) => setState(() => _selectedCategoryIndex = index),
      side: BorderSide(color: selected ? PixelTheme.purple : PixelTheme.border),
    );
  }

  Widget _buildMachineCard(MachineCatalogModel machine) {
    final bool owned = _ownedMachines[machine.id] != null;
    final int ownedCount = _ownedCount(machine);
    final String level = _ownedLevel(machine);
    final String cat = _categoryLabel(machine);
    final Color catColor = _categoryColor(machine);
    final String estReward = CoinFormat.formatMinimalUnits(
        BigInt.from((machine.powerUnits * 0.001).toInt()));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: PixelTheme.panel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: PixelTheme.border),
        ),
        child: Column(
          children: [
            Row(
              children: [
                PixelIcon(
                  matrix: PixelIcons.machineA,
                  palette: PixelIcons.palette,
                  size: 56,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        machine.name,
                        style: const TextStyle(
                            color: PixelTheme.text,
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: catColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border:
                              Border.all(color: catColor.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          cat,
                          style: TextStyle(
                              color: catColor, fontSize: 10),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _categoryDescription(machine),
                        style: const TextStyle(
                            color: PixelTheme.textDim, fontSize: 11),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          PixelIcon(
                            matrix: PixelIcons.bolt,
                            palette: PixelIcons.palette,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              PowerFormat.format(machine.powerUnits),
                              style: const TextStyle(
                                  color: PixelTheme.purple,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          PixelIcon(
                            matrix: PixelIcons.coin,
                            palette: PixelIcons.palette,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '≈ $estReward coin / 5 min estimado',
                              style: const TextStyle(
                                  color: PixelTheme.gold, fontSize: 10),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 90),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'NÍVEL $level',
                        style: const TextStyle(
                            color: PixelTheme.purple, fontSize: 10),
                      ),
                      const SizedBox(height: 2),
                      const Text('PODER',
                          style: TextStyle(
                              color: PixelTheme.textDim, fontSize: 8)),
                      Text(
                        PowerFormat.format(machine.powerUnits),
                        style: const TextStyle(
                            color: PixelTheme.purple,
                            fontWeight: FontWeight.bold,
                            fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      const Text('QTD. POSSUÍDA',
                          style: TextStyle(
                              color: PixelTheme.textDim, fontSize: 8)),
                      Text(
                        ownedCount.toString(),
                        style: const TextStyle(
                            color: PixelTheme.cyan,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('PREÇO',
                    style: TextStyle(color: PixelTheme.textDim, fontSize: 10)),
                const SizedBox(width: 2),
                PixelIcon(
                  matrix: PixelIcons.coin,
                  palette: PixelIcons.palette,
                  size: 14,
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    CoinFormat.formatMinimalUnits(machine.priceUnits),
                    style: const TextStyle(
                        color: PixelTheme.gold,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                owned
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: PixelTheme.textDim.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'NA SUA SALA',
                          style:
                              TextStyle(color: PixelTheme.textDim, fontSize: 11),
                        ),
                      )
                    : SizedBox(
                        width: 110,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: PixelTheme.purple,
                              foregroundColor: PixelTheme.text,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                            ),
                            onPressed: () => _showConfirmation(machine),
                            child: const Text('COMPRAR',
                                style: TextStyle(fontSize: 11)),
                          ),
                        ),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
