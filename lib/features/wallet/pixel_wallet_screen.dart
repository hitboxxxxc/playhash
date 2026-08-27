import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/payout_config.dart';
import '../../core/providers.dart';
import '../../core/services/withdrawal_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/pixel_theme.dart';
import '../../core/utils/coin_format.dart';
import '../../core/widgets/pixel_card.dart';
import '../../core/widgets/pixel_icon.dart';
import '../../core/widgets/pixel_icons.dart';
import '../../core/widgets/section_title.dart';
import '../../data/models/wallet_model.dart';
import '../../data/repositories/mining_repository.dart';
import '../../data/repositories/payouts_repository.dart'
    show PayoutAsset, RewardHistoryEntry, WithdrawalModel;
import 'widgets/wallet_history_list.dart';
import 'widgets/withdraw_confirm_sheet.dart';
import 'widgets/withdraw_form.dart';

/// CARTEIRA PIXEL — saldo 2 casas, equivalente LTC, ativos "em breve", saque FaucetPay (sem PIX).
class PixelWalletScreen extends ConsumerStatefulWidget {
  const PixelWalletScreen({super.key});

  @override
  ConsumerState<PixelWalletScreen> createState() => _PixelWalletScreenState();
}

class _PixelWalletScreenState extends ConsumerState<PixelWalletScreen> {
  bool _submitting = false;
  final ValueNotifier<int> _amountCoins = ValueNotifier<int>(0);
  StreamSubscription<BlockSnapshot?>? _blockSub;

  @override
  void initState() {
    super.initState();
    _subscribeBlock();
  }

  @override
  void dispose() {
    _amountCoins.dispose();
    _blockSub?.cancel();
    super.dispose();
  }

  void _subscribeBlock() {
    try {
      _blockSub ??= ref
          .read(miningRepositoryProvider)
          .watchBlockSnapshot()
          .listen(
            (BlockSnapshot? _) {
              if (!mounted) return;
              setState(() {});
            },
            onError: (Object _) {},
          );
    } catch (_) {}
  }

  Future<void> _submit({
    required BigInt amountUnits,
    required String destination,
  }) async {
    if (!mounted) return;

    final bool confirmed = await WithdrawConfirmSheet.show(
      context,
      assetId: 'LTC',
      destinationMasked: maskDestination(destination),
      amountUnits: amountUnits,
      feeUnits: BigInt.from(kFeeCoins) * BigInt.from(1000000),
      litoshiPerCoin: kLitoshiPerCoin,
      displayRate: kDisplayRate,
      minWithdrawUnits:
          BigInt.from(kMinWithdrawCoins) * BigInt.from(1000000),
      availableBalance:
          ref.read(walletStreamProvider).value?.availableBalance ??
              BigInt.zero,
      amountCoins: _amountCoins,
    );
    if (!confirmed || !mounted) return;

    final String? uid = await ref.read(currentUidProvider.future);
    if (uid == null || !mounted) return;

    final int amountCoins =
        (amountUnits ~/ BigInt.from(1000000)).toInt();
    final WithdrawalService service = ref.read(withdrawalServiceProvider);
    setState(() => _submitting = true);

    final Future<WithdrawalOutcome> pending = service.withdraw(
      uid: uid,
      amountCoins: amountCoins,
      destination: destination,
    );
    WithdrawalOutcome outcome;
    try {
      outcome = await pending.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A confirmação está demorando. Aguarde — o resultado aparece '
            'em instantes.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      try {
        outcome = await pending;
      } on Exception {
        if (!mounted) return;
        setState(() => _submitting = false);
        return;
      }
    } on WithdrawalException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _submitting = false);
    _showResultSheet(outcome);
  }

  void _showResultSheet(WithdrawalOutcome result) {
    final bool ok = result.isCompleted;
    final bool pending = result.isPending;
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
              ok
                  ? Icons.check_circle
                  : pending
                      ? Icons.hourglass_top
                      : Icons.error_outline,
              color: ok
                  ? AppColors.green
                  : pending
                      ? AppColors.gold
                      : AppColors.error,
              size: 44,
            ),
            const SizedBox(height: 12),
            Text(
              ok
                  ? 'SAQUE CONCLUÍDO'
                  : pending
                      ? 'AGUARDANDO PAGAMENTO'
                      : 'SAQUE NÃO CONCLUÍDO',
              style: AppTheme.neonLabel(
                fontSize: 15,
                color: ok
                    ? AppColors.green
                    : pending
                        ? AppColors.gold
                        : AppColors.error,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              ok
                  ? 'Pagamento enviado via FaucetPay.\n'
                      'Referência: ${result.reference ?? '—'}'
                  : pending
                      ? 'Aguardando pagamento manual do operador.\n'
                          'O valor fica RESERVADO (pendente) e o histórico '
                          'atualiza em instantes após a definição do status.'
                      : '${withdrawalErrorMessage(result.errorCode)}\n'
                          'O valor foi estornado ao saldo disponível.',
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
    ref.watch(manualPayoutWatchProvider);
    final AsyncValue<WalletModel?> wallet = ref.watch(walletStreamProvider);
    final int saldoUnits = wallet.value?.availableBalance.toInt() ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 1. PixelCard header
          const PixelCard(
            padding: EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                PixelIcon(matrix: PixelIcons.wallet, palette: PixelIcons.palette, size: 40),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'CARTEIRA',
                        style: TextStyle(
                          color: PixelTheme.purple,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Acompanhe seu saldo e saque suas recompensas.',
                        style: PixelTheme.label,
                      ),
                    ],
                  ),
                ),
                PixelIcon(matrix: PixelIcons.safe, palette: PixelIcons.palette, size: 64),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 2. PixelCard SEU SALDO
          PixelCard(
            borderColor: PixelTheme.purple,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                const SectionTitle(text: 'SEU SALDO'),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const PixelIcon(matrix: PixelIcons.coin, palette: PixelIcons.palette, size: 40),
                    const SizedBox(width: 8),
                    Text(
                      fmtCoins2(saldoUnits),
                      style: PixelTheme.bigValue,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'COIN',
                      style: TextStyle(
                        color: PixelTheme.gold,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('Equivale a', style: PixelTheme.label),
                const SizedBox(height: 4),
                Text(
                  '${fmtLtc(saldoUnits)} LTC',
                  style: const TextStyle(
                    color: PixelTheme.green,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 12),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: PixelTheme.background,
                      border: Border.all(color: PixelTheme.border),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const PixelIcon(matrix: PixelIcons.coin, palette: PixelIcons.palette, size: 16),
                        const SizedBox(width: 6),
                        const Text('1 COIN', style: TextStyle(color: PixelTheme.text, fontSize: 12, fontWeight: FontWeight.bold)),
                        const Text(' = ', style: TextStyle(color: PixelTheme.textDim, fontSize: 12)),
                        const Text('0,000001 LTC', style: TextStyle(color: PixelTheme.green, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 3. Seletor de ativos (Row 5 chips)
          Row(
            children: <Widget>[
              _buildAssetChip('LTC', true, null),
              const SizedBox(width: 6),
              _buildAssetChip('BTC', false, () => _showComingSoon('BTC')),
              const SizedBox(width: 6),
              _buildAssetChip('DOGE', false, () => _showComingSoon('DOGE')),
              const SizedBox(width: 6),
              _buildAssetChip('DGB', false, () => _showComingSoon('DGB')),
              const SizedBox(width: 6),
              _buildAssetChip('POL', false, () => _showComingSoon('POL')),
            ],
          ),
          const SizedBox(height: 12),

          // 4. PixelCard SACAR VIA FAUCETPAY (LTC)
          PixelCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Column(
                  children: <Widget>[
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'SACAR VIA FAUCETPAY (LTC)',
                          style: PixelTheme.title.copyWith(color: PixelTheme.text),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints constraints) {
                        return SizedBox(
                          height: 6,
                          width: constraints.maxWidth,
                          child: CustomPaint(
                            painter: _WalletDashPainter(),
                            size: Size(constraints.maxWidth, 6),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const PixelIcon(matrix: PixelIcons.safe, palette: PixelIcons.palette, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'Converta seus coins em LTC e receba na sua conta FaucetPay.',
                  textAlign: TextAlign.center,
                  style: PixelTheme.label,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _buildForm(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: PixelTheme.cyan.withValues(alpha: 0.1),
                      border: Border.all(color: PixelTheme.cyan.withValues(alpha: 0.4)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(Icons.info_outline, size: 16, color: PixelTheme.cyan),
                            SizedBox(width: 6),
                            Text(
                              'COMO FUNCIONA',
                              style: TextStyle(
                                color: PixelTheme.cyan,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Seus coins são convertidos em LTC na proporção de 1 COIN = 0,000001 LTC. O valor é enviado via FaucetPay para o seu e-mail ou endereço LTC vinculado.',
                          style: TextStyle(
                            color: PixelTheme.text,
                            fontSize: 11.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 5. HISTÓRICO DE SAQUES
          const SectionTitle(text: 'HISTÓRICO DE SAQUES'),
          const SizedBox(height: 8),
          WalletHistoryList(items: _mergedHistory(ref)),
        ],
      ),
    );
  }

  Widget _buildAssetChip(String name, bool active, VoidCallback? onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? PixelTheme.cyan.withValues(alpha: 0.15) : PixelTheme.panel,
            border: Border.all(
              color: active ? PixelTheme.cyan : PixelTheme.border,
              width: active ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                name,
                style: TextStyle(
                  color: active ? PixelTheme.cyan : PixelTheme.textDim,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              if (!active) ...<Widget>[
                const SizedBox(height: 2),
                const Text(
                  'EM BREVE',
                  style: TextStyle(
                    color: PixelTheme.textDim,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showComingSoon(String asset) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$asset: Disponível em breve'),
        backgroundColor: PixelTheme.purple,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildForm() {
    final AsyncValue<WalletModel?> walletAsync = ref.watch(walletStreamProvider);
    final BigInt available = walletAsync.value?.availableBalance ?? BigInt.zero;
    final AsyncValue<PayoutAsset?> ltcAsset = ref.watch(ltcPayoutAssetProvider);
    return ltcAsset.when(
      data: (asset) {
        final BigInt minWithdraw = asset?.minWithdrawUnits ??
            (BigInt.from(kMinWithdrawCoins) * BigInt.from(1000000));
        final BigInt maxWithdraw = available; // saldo disponível como teto
        final BigInt fee = asset?.feeUnits ??
            (BigInt.from(kFeeCoins) * BigInt.from(1000000));
        final int litoshiPerCoin = asset?.litoshiPerCoin ?? kLitoshiPerCoin;
        final String displayRate = asset?.displayRate ?? kDisplayRate;
        return WithdrawForm(
          key: const ValueKey<String>('form_LTC'),
          asset: WithdrawAssetInfo(
            id: 'LTC',
            network: 'FaucetPayEmail',
            minWithdrawUnits: minWithdraw,
            maxPerWithdrawalUnits: maxWithdraw,
            feeUnits: fee,
            litoshiPerCoin: litoshiPerCoin,
            displayRate: displayRate,
          ),
          availableBalance: available,
          amountCoins: _amountCoins,
          submitting: _submitting,
          onSubmit: (BigInt amount, String destination) => _submit(
            amountUnits: amount,
            destination: destination,
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, stack) => WithdrawForm(
        key: const ValueKey<String>('form_LTC'),
        asset: WithdrawAssetInfo(
          id: 'LTC',
          network: 'FaucetPayEmail',
          minWithdrawUnits:
              BigInt.from(kMinWithdrawCoins) * BigInt.from(1000000),
          maxPerWithdrawalUnits:
              BigInt.from(kMaxPerWithdrawalCoins) * BigInt.from(1000000),
          feeUnits: BigInt.from(kFeeCoins) * BigInt.from(1000000),
          litoshiPerCoin: kLitoshiPerCoin,
          displayRate: kDisplayRate,
        ),
        availableBalance: available,
        amountCoins: _amountCoins,
        submitting: _submitting,
        onSubmit: (BigInt amount, String destination) => _submit(
          amountUnits: amount,
          destination: destination,
        ),
      ),
    );
  }
}

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
        destinationMasked: w.destinationMasked,
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

class _WalletDashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = PixelTheme.purple;
    double x = 0;
    bool on = true;
    while (x < size.width) {
      if (on) canvas.drawRect(Rect.fromLTWH(x, 1.5, 6, 3), paint);
      x += on ? 11 : 5;
      on = !on;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
