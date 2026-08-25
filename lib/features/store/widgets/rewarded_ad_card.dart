import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/services/ad_reward_service.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/neon_button.dart';
import '../../../core/widgets/neon_panel.dart';
import '../../../data/repositories/ads_repository.dart';

/// Card "ASSISTA E GANHE 1 COIN" no TOPO da LOJA (doc 04).
///
/// - Anúncio SEMPRE iniciado pelo usuário (botão ASSISTIR);
/// - recompensa 100% validada no backend: após `onUserEarnedReward` o
///   cliente registra a INTENÇÃO (adRewardIntents/{clientRequestId}) e o
///   runner concede 1 COIN + xpBonus com limite diário/cooldown/antifraude;
/// - contador "X de Y hoje" via stream adRewards do dia;
/// - offline: intent fica pendente e o retry usa o MESMO clientRequestId
///   (nunca duplica);
/// - sem anúncio carregado: botão desabilitado com tooltip — a LOJA segue
///   funcionando normalmente.
class RewardedAdCard extends StatefulWidget {
  // Não-const: o default resolve para o singleton AdService.instance.
  // ignore: use_key_in_widget_constructors
  RewardedAdCard({
    super.key,
    required this.uid,
    AdServiceApi? ads,
    this.service,
    this.repository,
    this.fallbackDailyLimit = 10,
    String? clientVersion,
  })  : ads = ads ?? AdService.instance,
        _injectedClientVersion = clientVersion;

  final String uid;

  /// Serviço de anúncios (injetável p/ testes — fake sem SDK).
  final AdServiceApi ads;

  /// Versão do app injetável p/ testes; null ⇒ lê do PackageInfo.
  final String? _injectedClientVersion;

  /// Serviço de intenção de recompensa (injetável p/ testes).
  final AdRewardService? service;

  /// Repositório de anúncios (injetável p/ testes).
  final AdsRepositoryApi? repository;

  /// Fallback quando config/ads ainda não foi semeada (o valor REAL vem
  /// sempre do backend).
  final int fallbackDailyLimit;

  @override
  State<RewardedAdCard> createState() => _RewardedAdCardState();
}

class _RewardedAdCardState extends State<RewardedAdCard> {
  late final AdRewardService _service =
      widget.service ?? AdRewardService(repository: widget.repository);
  late final AdsRepositoryApi _repository =
      widget.repository ?? AdsRepository();

  StreamSubscription<RewardedAdState>? _stateSub;
  RewardedAdState _adState = RewardedAdState.idle;

  int? _dailyLimit;
  int _todayCount = 0;
  StreamSubscription<int?>? _limitSub;
  StreamSubscription<List<AdRewardEntry>>? _todaySub;

  /// Intent pendente aguardando conexão — retry usa o MESMO id.
  String? _pendingRequestId;
  Timer? _retryTimer;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _adState = widget.ads.state;
    _stateSub = widget.ads.stateStream.listen(
      (RewardedAdState s) {
        if (mounted) setState(() => _adState = s);
      },
      onError: (Object _) {},
    );
    // Pré-carrega o rewarded (card pronto quando o usuário chegar).
    widget.ads.loadRewarded();

    _limitSub = _repository.watchDailyLimit().listen(
      (int? limit) {
        if (mounted && limit != null) setState(() => _dailyLimit = limit);
      },
      onError: (Object _) {},
    );
    _todaySub = _repository.watchTodayRewards(widget.uid).listen(
      (List<AdRewardEntry> entries) {
        if (mounted) setState(() => _todayCount = entries.length);
      },
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _limitSub?.cancel();
    _todaySub?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }

  int get _effectiveLimit => _dailyLimit ?? widget.fallbackDailyLimit;
  bool get _limitReached => _todayCount >= _effectiveLimit;
  bool get _buttonEnabled =>
      !_submitting &&
      !_limitReached &&
      (_adState == RewardedAdState.loaded ||
          _adState == RewardedAdState.idle ||
          _adState == RewardedAdState.loading);

  Future<void> _onWatchTap() async {
    if (_submitting || _limitReached) return;
    setState(() => _submitting = true);
    try {
      await widget.ads.loadRewarded();
      final bool shown = await widget.ads.showRewarded(
        onEarnedReward: () {
          // Recompensa CONCEDIDA pelo SDK ⇒ registra a INTENÇÃO no backend.
          // Nunca credita coin no cliente.
          _registerIntent();
        },
        onDismissed: () {},
      );
      if (!shown && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.surface,
            content: Text(
              'Anúncios indisponíveis no momento. Tente novamente em instantes.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<String> _resolveClientVersion() async =>
      widget._injectedClientVersion ?? (await PackageInfo.fromPlatform()).version;

  /// Registra a intent; se estiver offline, agenda retry com o MESMO
  /// clientRequestId até conseguir (nunca duplica).
  Future<void> _registerIntent() async {
    final String requestId =
        _pendingRequestId ?? _service.generateClientRequestId();
    _pendingRequestId = requestId;
    try {
      await _service.createIntent(
        uid: widget.uid,
        clientVersion: await _resolveClientVersion(),
        clientRequestId: requestId,
      );
      _retryTimer?.cancel();
      if (!mounted) return;
      await _showValidationSheet(requestId);
    } on AdRewardException catch (e) {
      // Offline persistente: mantém pendente e tenta ao reconectar.
      _scheduleOfflineRetry();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surface,
          content: Text(e.message, style: const TextStyle(color: AppColors.gold)),
        ),
      );
    }
  }

  void _scheduleOfflineRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      final String? requestId = _pendingRequestId;
      if (requestId == null) {
        _retryTimer?.cancel();
        return;
      }
      try {
        await _service.createIntent(
          uid: widget.uid,
          clientVersion: await _resolveClientVersion(),
          clientRequestId: requestId, // MESMO id — idempotente
        );
        _retryTimer?.cancel();
        if (!mounted) return;
        await _showValidationSheet(requestId);
      } on AdRewardException catch (_) {
        // Ainda offline — próximo tick tenta de novo.
      }
    });
  }

  /// Sheet "Validando com o servidor…" — observa a intent até done/failed.
  Future<void> _showValidationSheet(String requestId) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext sheetContext) {
        return StreamBuilder<AdRewardIntentResult>(
          stream: _service.watchResult(requestId),
          builder: (
            BuildContext _,
            AsyncSnapshot<AdRewardIntentResult> snap,
          ) {
            final AdRewardIntentResult result = snap.data ??
                const AdRewardIntentResult(status: 'pending');
            Widget content;
            if (result.isDone) {
              _pendingRequestId = null;
              content = Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.monetization_on,
                      color: AppColors.gold, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    '+1 COIN',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Recompensa validada pelo servidor!',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  NeonButton(
                    label: 'COLETAR',
                    color: AppColors.gold,
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                ],
              );
            } else if (result.isFailed) {
              _pendingRequestId = null;
              content = Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.info_outline,
                      color: AppColors.error, size: 44),
                  const SizedBox(height: 12),
                  Text(
                    AdRewardService.failureMessage(result.failureCode),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 16),
                  NeonButton(
                    label: 'FECHAR',
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                ],
              );
            } else {
              content = Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CircularProgressIndicator(color: AppColors.gold),
                  const SizedBox(height: 16),
                  Text(
                    'Validando com o servidor…',
                    style: TextStyle(color: AppColors.textPrimary.withValues(alpha: 0.9)),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Isso pode levar alguns minutos.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              );
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
              child: content,
            );
          },
        );
      },
    ).then((_) {
      // Ao fechar, invalida caches para reler saldo do servidor.
      // (a LOJA observa a wallet via _load externamente)
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool unavailable = _adState == RewardedAdState.failedLoad;
    return NeonPanel(
      accent: AppColors.gold,
      padding: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.play_circle_fill,
                    color: AppColors.gold, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'ASSISTA E GANHE 1 COIN',
                        style: TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$_todayCount de $_effectiveLimit hoje',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Tooltip(
              message: unavailable
                  ? 'Anúncios indisponíveis no momento'
                  : _limitReached
                      ? 'Limite diário atingido — volte amanhã'
                      : '',
              child: NeonButton(
                label: 'ASSISTIR',
                color: AppColors.gold,
                isLoading: _submitting || _adState == RewardedAdState.loading,
                onPressed: _buttonEnabled ? _onWatchTap : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
