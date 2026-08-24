import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/services/withdrawal_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/wallet_model.dart';
import '../../data/repositories/payouts_repository.dart';
import 'widgets/asset_selector.dart';
import 'widgets/wallet_header.dart';
import 'widgets/wallet_history_list.dart';
import 'widgets/withdraw_form.dart';

/// CARTEIRA — saldos (disponível/pendente/vitalício), saque com seletor de
/// ativo + endereço + valor/taxa, histórico mesclado com status.
///
/// O cliente SÓ SOLICITA o saque (withdrawalIntents); validação, reserva,
/// pagamento e estorno são 100% do runner (≤5 min). Overlay "processando"
/// observa `withdrawals/{clientRequestId}` até completed/failed.
class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  String _selectedAssetId = '';
  bool _submitting = false;
  StreamSubscription<WithdrawalResult>? _watchSub;

  @override
  void dispose() {
    _watchSub?.cancel();
    super.dispose();
  }

  void _showDepositInfoSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'SEM DEPÓSITOS',
              style: AppTheme.neonLabel(fontSize: 14, color: AppColors.gold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Ganhe moedas jogando, em missões e na liga. '
              'Este app não aceita depósitos.',
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Envia a intent e observa o resultado do runner.
  Future<void> _submit({
    required PayoutAsset asset,
    required BigInt amountUnits,
    required String address,
  }) async {
    final String? uid = await ref.read(currentUidProvider.future);
    if (uid == null || !mounted) return;

    final WithdrawalService service = ref.read(withdrawalServiceProvider);
    setState(() => _submitting = true);
    final String requestId;
    try {
      // Retry offline usa o MESMO clientRequestId (idempotência).
      requestId = await service.requestWithdrawal(
        uid: uid,
        asset: asset.id,
        network: asset.network,
        amountUnits: amountUnits,
        address: address,
      );
    } on WithdrawalException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
      return;
    }
    if (!mounted) return;
    _listenResult(requestId);
  }

  /// Observa o resultado do runner e mostra overlay verde/vermelho.
  void _listenResult(String requestId) {
    _watchSub?.cancel();
    _watchSub = ref
        .read(withdrawalServiceProvider)
        .watchWithdrawal(requestId)
        .listen((WithdrawalResult result) {
      if (!result.isCompleted && !result.isFailed) return; // ainda processando
      _watchSub?.cancel();
      if (!mounted) return;
      setState(() => _submitting = false);
      _showResultSheet(result);
    });
  }

  void _showResultSheet(WithdrawalResult result) {
    final bool ok = result.isCompleted;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              ok ? Icons.check_circle : Icons.error_outline,
              color: ok ? AppColors.green : AppColors.error,
              size: 44,
            ),
            const SizedBox(height: 12),
            Text(
              ok ? 'SAQUE CONCLUÍDO' : 'SAQUE NÃO CONCLUÍDO',
              style: AppTheme.neonLabel(
                fontSize: 15,
                color: ok ? AppColors.green : AppColors.error,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              ok
                  ? 'Referência: ${result.reference ?? '—'}'
                  : withdrawalErrorMessage(result.errorCode),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PayoutsConfigModel?> config =
        ref.watch(payoutsConfigProvider);
    final AsyncValue<WalletModel?> wallet = ref.watch(walletStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('CARTEIRA')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: <Widget>[
                wallet.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(color: AppColors.cyan),
                    ),
                  ),
                  error: (_, _) => WalletHeader(
                    availableBalance: BigInt.zero,
                    pendingBalance: BigInt.zero,
                    lifetimeEarned: BigInt.zero,
                  ),
                  data: (WalletModel? w) => WalletHeader(
                    availableBalance: w?.availableBalance ?? BigInt.zero,
                    pendingBalance: w?.pendingBalance ?? BigInt.zero,
                    lifetimeEarned: w?.lifetimeEarned ?? BigInt.zero,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _showDepositInfoSheet,
                    child: const Text(
                      'Como ganhar moedas?',
                      style: TextStyle(fontSize: 12, color: AppColors.cyan),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text('SACAR', style: AppTheme.neonLabel(fontSize: 12)),
                const SizedBox(height: 8),
                config.maybeWhen(
                  data: (PayoutsConfigModel? cfg) {
                    final List<PayoutAsset> assets =
                        cfg?.assets.where((PayoutAsset a) => a.enabled).toList() ??
                            const <PayoutAsset>[];
                    if (_selectedAssetId.isEmpty && assets.isNotEmpty) {
                      _selectedAssetId = assets.first.id;
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        AssetSelector(
                          assets: assets
                              .map((PayoutAsset a) => WalletAssetChip(
                                    id: a.id,
                                    network: a.network,
                                    symbol: _symbolFor(a.id),
                                  ))
                              .toList(growable: false),
                          selectedId: _selectedAssetId,
                          onSelected: (String id) =>
                              setState(() => _selectedAssetId = id),
                        ),
                        const SizedBox(height: 16),
                        if (_selectedAssetId.isNotEmpty && assets.isNotEmpty)
                          _buildForm(assets),
                      ],
                    );
                  },
                  orElse: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Carregando configurações de saque…',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text('HISTÓRICO', style: AppTheme.neonLabel(fontSize: 12)),
                const SizedBox(height: 4),
                WalletHistoryList(items: _mergedHistory(ref)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(List<PayoutAsset> assets) {
    final PayoutAsset asset =
        assets.firstWhere((PayoutAsset a) => a.id == _selectedAssetId);
    final BigInt available =
        ref.watch(walletStreamProvider).value?.availableBalance ?? BigInt.zero;
    return WithdrawForm(
      key: ValueKey<String>('form_${asset.id}'),
      asset: WithdrawAssetInfo(
        id: asset.id,
        network: asset.network,
        minWithdrawUnits: asset.minWithdrawUnits,
        feeUnits: asset.feeUnits,
      ),
      availableBalance: available,
      submitting: _submitting,
      onSubmit: (BigInt amount, String address) => _submit(
        asset: asset,
        amountUnits: amount,
        address: address,
      ),
    );
  }
}

/// Símbolo textual/geométrico simples por ativo (nunca logos oficiais).
String _symbolFor(String assetId) {
  switch (assetId.toUpperCase()) {
    case 'BTC':
      return 'B';
    case 'LTC':
      return 'L';
    case 'DOGE':
      return 'D';
    case 'USDT':
      return 'T';
    default:
      return assetId.isNotEmpty ? assetId[0] : '?';
  }
}

/// Mescla rewards/{uid}/items (entradas/saídas) com os saques.
List<WalletHistoryItem> _mergedHistory(WidgetRef ref) {
  final List<RewardHistoryEntry> rewards =
      ref.watch(rewardItemsStreamProvider).value ??
          const <RewardHistoryEntry>[];
  final List<WithdrawalModel> withdrawals =
      ref.watch(withdrawalsStreamProvider).value ??
          const <WithdrawalModel>[];

  final List<WalletHistoryItem> items = <WalletHistoryItem>[
    for (final RewardHistoryEntry r in rewards)
      WalletHistoryItem(
        title: _rewardTitle(r.type),
        amount: r.amount,
        date: r.createdAt,
      ),
    for (final WithdrawalModel w in withdrawals)
      WalletHistoryItem(
        title: 'Saque ${w.asset}',
        amount: -w.amountUnits,
        date: w.createdAt,
        status: w.status,
        addressMasked: w.addressMasked,
      ),
  ];
  items.sort((WalletHistoryItem a, WalletHistoryItem b) {
    final DateTime da = a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
    final DateTime db = b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
    return db.compareTo(da);
  });
  return items;
}

String _rewardTitle(String type) {
  switch (type) {
    case 'GAME_REWARD':
      return 'Recompensa de partida';
    case 'REWARD_BLOCK':
      return 'Bloco de mineração';
    case 'MISSION_REWARD':
      return 'Missão concluída';
    case 'ACHIEVEMENT_REWARD':
      return 'Conquista';
    case 'LEAGUE_REWARD':
      return 'Liga diária';
    case 'SEASON_REWARD':
      return 'Temporada';
    case 'WITHDRAWAL':
      return 'Saque';
    case 'MACHINE_PURCHASE':
      return 'Compra de máquina';
    default:
      return type.isEmpty ? 'Movimentação' : type;
  }
}
