import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/empty_state_panel.dart';
import '../../core/widgets/neon_icons.dart';
import '../../data/models/machine_catalog_model.dart';
import '../../data/models/machine_model.dart';
import '../../data/models/wallet_model.dart';
import 'widgets/category_tabs.dart';
import 'widgets/machine_card.dart';
import 'widgets/machine_detail_sheet.dart';
import 'widgets/store_header.dart';

enum _StoreStatus { loading, ready, error }

/// Aba LOJA — catálogo de máquinas lido de `config/machines` (cache-first).
/// Preço/poder/limite vêm SEMPRE do backend; compra = intenção
/// (purchaseIntents) validada pelo runner em até ~5 min.
/// Boosters/Itens/Visuais: "EM BREVE" (conteúdo vazio informativo).
class StoreScreen extends ConsumerStatefulWidget {
  const StoreScreen({super.key});

  static const List<({String label, bool comingSoon})> categories =
      <({String label, bool comingSoon})>[
    (label: 'Máquinas', comingSoon: false),
    (label: 'Boosters', comingSoon: true),
    (label: 'Itens', comingSoon: true),
    (label: 'Visuais', comingSoon: true),
  ];

  @override
  ConsumerState<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends ConsumerState<StoreScreen>
    with AutomaticKeepAliveClientMixin {
  _StoreStatus _status = _StoreStatus.loading;
  int _selectedCategory = 0;

  List<MachineCatalogModel> _catalog = const <MachineCatalogModel>[];
  WalletModel? _wallet;
  Map<String, int> _ownedByMachine = const <String, int>{};
  String? _uid;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _status = _StoreStatus.loading);
    try {
      final String? uid =
          await ref.read(currentUidProvider.future);
      if (!mounted) return;

      // Catálogo é essencial (erro => retry); saldo/owned são tolerantes.
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
      ]);
      if (!mounted) return;

      final List<dynamic> data = results as List<dynamic>;
      final List<MachineCatalogModel> catalog =
          data[0] as List<MachineCatalogModel>;
      final List<MachineModel> owned = data[2] as List<MachineModel>;
      final Map<String, int> counts = <String, int>{};
      for (final MachineModel m in owned) {
        if (m.type.isEmpty) continue;
        counts[m.type] = (counts[m.type] ?? 0) + 1;
      }

      setState(() {
        _uid = uid;
        _catalog = catalog;
        _wallet = data[1] as WalletModel?;
        _ownedByMachine = counts;
        _status = _StoreStatus.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _StoreStatus.error);
    }
  }

  Future<void> _refreshAfterPurchase() async {
    // Invalida caches de saldo/máquinas/poder para reler do servidor.
    ref.read(cachePolicyProvider).clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface,
        content: Text(
          'Compra aprovada! Sua máquina foi instalada na sala.',
          style: TextStyle(color: AppColors.green),
        ),
      ),
    );
    await _load();
  }

  Future<void> _openDetails(MachineCatalogModel machine) async {
    final String? uid = _uid;
    if (uid == null) return;
    final BigInt? balance = _wallet?.availableBalance;
    await MachineDetailSheet.show(
      context,
      machine: machine,
      ownedCount: _ownedByMachine[machine.id] ?? 0,
      canAfford: balance != null && balance >= machine.priceUnits,
      uid: uid,
      service: ref.read(purchaseIntentServiceProvider),
      onPurchased: _refreshAfterPurchase,
    );
  }

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
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: StoreHeader(
                    availableBalance: _wallet?.availableBalance,
                    loading: _status == _StoreStatus.loading,
                    onAddTap: null,
                  ),
                ),
                CategoryTabs(
                  categories: StoreScreen.categories,
                  selectedIndex: _selectedCategory,
                  onSelected: (int index) =>
                      setState(() => _selectedCategory = index),
                ),
                Expanded(
                  child: switch (_selectedCategory) {
                    0 => _buildMachinesTab(),
                    _ => _buildComingSoonTab(),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMachinesTab() {
    return switch (_status) {
      _StoreStatus.loading => const Center(
          child: CircularProgressIndicator(color: AppColors.cyan),
        ),
      _StoreStatus.error => _ErrorPanel(onRetry: _load),
      _StoreStatus.ready when _catalog.isEmpty => const EmptyStatePanel(
          icon: NeonIcons.cart,
          title: 'Catálogo vazio',
          message:
              'Nenhuma máquina está publicada no catálogo do servidor agora. '
              'Volte mais tarde.',
        ),
      _StoreStatus.ready => RefreshIndicator(
          color: AppColors.cyan,
          backgroundColor: AppColors.surface,
          onRefresh: _load,
          child: GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.62,
            ),
            itemCount: _catalog.length,
            itemBuilder: (BuildContext context, int index) {
              final MachineCatalogModel machine = _catalog[index];
              final BigInt? balance = _wallet?.availableBalance;
              return MachineCard(
                machine: machine,
                ownedCount: _ownedByMachine[machine.id] ?? 0,
                canAfford: balance != null && balance >= machine.priceUnits,
                onBuy: () => _openDetails(machine),
                onOpenDetails: () => _openDetails(machine),
              );
            },
          ),
        ),
    };
  }

  Widget _buildComingSoonTab() {
    final String label = StoreScreen.categories[_selectedCategory].label;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: EmptyStatePanel(
        icon: NeonIcons.cart,
        title: '$label em breve',
        message:
            'Esta categoria será publicada pelo servidor em uma próxima '
            'atualização. Nenhum item é exibido até lá.',
      ),
    );
  }
}

/// Painel de erro com retry (catálogo é essencial).
class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const EmptyStatePanel(
              icon: NeonIcons.cart,
              title: 'Não foi possível carregar a loja',
              message: 'Verifique sua conexão e tente novamente.',
            ),
            const SizedBox(height: 12),
            Semantics(
              button: true,
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('TENTAR NOVAMENTE'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
