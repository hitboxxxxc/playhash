import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/ads_config.dart';

/// Estados do rewarded no cliente (ciclo de vida do ANÚNCIO — a RECOMPENSA
/// em si é 100% validada pelo backend via adRewardIntents → runner).
enum RewardedAdState { idle, loading, loaded, failedLoad, showing }

/// Contrato do serviço de anúncios — permite fakes nos testes/widget tests
/// (o SDK google_mobile_ads não roda em ambientes de teste).
abstract interface class AdServiceApi {
  Stream<RewardedAdState> get stateStream;

  RewardedAdState get state;

  bool get isLoaded;

  Future<void> initialize();

  Future<void> loadRewarded();

  Future<bool> showRewarded({
    required VoidCallback onEarnedReward,
    required VoidCallback onDismissed,
  });
}

/// Serviço de anúncios (AdMob) do PlayHash.
///
/// - `MobileAds.initialize()` uma única vez;
/// - RequestConfiguration com testDevices SOMENTE em debug (proteção da
///   conta AdMob — builds debug nunca servem anúncios reais);
/// - load/show de RewardedAd com listeners completos e RECARGA automática
///   após dismiss;
/// - falha de load ⇒ estado `failedLoad` (a UI desabilita o botão com
///   tooltip "anúncios indisponíveis no momento").
///
/// O cliente NUNCA concede recompensa: `onUserEarnedReward` apenas sinaliza
/// para o chamador registrar a INTENÇÃO no backend (ad_reward_service).
class AdService implements AdServiceApi {
  AdService._();

  static final AdService instance = AdService._();

  bool _initialized = false;
  Future<void>? _initFuture;

  RewardedAd? _rewardedAd;
  RewardedAdState _state = RewardedAdState.idle;
  Timer? _retryTimer;
  int _retryAttempt = 0;

  final StreamController<RewardedAdState> _stateController =
      StreamController<RewardedAdState>.broadcast();

  /// Stream de estados para a UI reagir (botão habilitado/desabilitado etc).
  @override
  Stream<RewardedAdState> get stateStream => _stateController.stream;

  @override
  RewardedAdState get state => _state;

  @override
  bool get isLoaded => _state == RewardedAdState.loaded;

  void _setState(RewardedAdState s) {
    _state = s;
    if (!_stateController.isClosed) {
      _stateController.add(s);
    }
  }

  /// Inicializa o SDK (idempotente) e aplica testDevices em debug.
  /// Tolerante a ambientes SEM o plugin (ex.: widget tests) — nunca crasha.
  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initFuture ??= () async {
      try {
        await MobileAds.instance.initialize();
        await MobileAds.instance.updateRequestConfiguration(
          RequestConfiguration(testDeviceIds: AdsConfig.testDevices),
        );
        _initialized = true;
      } catch (e) {
        debugPrint('[ads] initialize unavailable: $e');
      }
    }();
    await _initFuture;
  }

  /// Carrega o rewarded (idempotente enquanto já carregado/carregando).
  @override
  Future<void> loadRewarded() async {
    if (_state == RewardedAdState.loaded ||
        _state == RewardedAdState.loading ||
        _state == RewardedAdState.showing) {
      return;
    }
    await initialize();
    _setState(RewardedAdState.loading);
    try {
      await RewardedAd.load(
        adUnitId: AdsConfig.rewardedUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (RewardedAd ad) {
            _retryAttempt = 0;
            _rewardedAd?.dispose();
            _rewardedAd = ad;
            _setState(RewardedAdState.loaded);
          },
          onAdFailedToLoad: (LoadAdError error) {
            // Log SEM dados sensíveis (apenas código/mensagem curta).
            debugPrint('[ads] rewarded load failed code=${error.code}');
            _rewardedAd = null;
            _setState(RewardedAdState.failedLoad);
            _scheduleRetry();
          },
        ),
      );
    } catch (e) {
      // Plugin ausente/indisponível ⇒ falha segura + retry com backoff.
      debugPrint('[ads] rewarded load error: $e');
      _rewardedAd = null;
      _setState(RewardedAdState.failedLoad);
    }
  }

  /// Recarga com backoff simples (evita martelar o SDK em offline).
  void _scheduleRetry() {
    _retryTimer?.cancel();
    final int delaySeconds = (_retryAttempt < 3 ? 15 : 60);
    _retryAttempt += 1;
    _retryTimer = Timer(Duration(seconds: delaySeconds), () {
      loadRewarded();
    });
  }

  /// Exibe o rewarded carregado. Retorna false se não houver anúncio pronto.
  ///
  /// Callbacks:
  /// - [onEarnedReward]: disparado pelo SDK quando o usuário COMPLETA o
  ///   vídeo (o chamador registra a intent no backend — nunca concede coin);
  /// - [onDismissed]: fechou o anúncio (com ou sem recompensa); recarrega.
  @override
  Future<bool> showRewarded({
    required VoidCallback onEarnedReward,
    required VoidCallback onDismissed,
  }) async {
    final RewardedAd? ad = _rewardedAd;
    if (ad == null || _state != RewardedAdState.loaded) return false;
    _setState(RewardedAdState.showing);

    bool earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdShowedFullScreenContent: (_) {},
      onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
        debugPrint('[ads] rewarded show failed code=${error.code}');
        ad.dispose();
        _rewardedAd = null;
        onDismissed();
        _setState(RewardedAdState.failedLoad);
        _scheduleRetry();
      },
      onAdDismissedFullScreenContent: (RewardedAd ad) {
        ad.dispose();
        _rewardedAd = null;
        onDismissed();
        // Recarga automática imediata após dismiss (próximo vídeo pronto).
        _setState(RewardedAdState.idle);
        loadRewarded();
      },
    );

    await ad.show(onUserEarnedReward: (AdWithoutView _, RewardItem reward) {
      earned = true;
      onEarnedReward();
    });
    return earned || true; // exibiu com sucesso
  }

  /// Libera recursos (chamado em testes/teardown).
  void dispose() {
    _retryTimer?.cancel();
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _stateController.close();
  }
}
