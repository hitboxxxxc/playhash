import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cache_policy.dart';
import '../data/models/achievement_model.dart';
import '../data/models/game_model.dart';
import '../data/models/mission_model.dart';
import '../data/models/power_model.dart';
import '../data/repositories/achievements_repository.dart';
import '../data/repositories/economy_repository.dart';
import '../data/repositories/leagues_repository.dart';
import '../data/repositories/leaderboard_repository.dart';
import '../data/repositories/season_repository.dart';
import '../data/models/league_model.dart';
import '../data/models/season_model.dart';
import '../data/repositories/game_sessions_repository.dart';
import '../data/repositories/games_repository.dart';
import '../data/repositories/machine_catalog_repository.dart';
import '../data/repositories/machines_repository.dart';
import '../data/repositories/missions_repository.dart';
import '../data/repositories/mining_repository.dart';
import '../data/repositories/power_repository.dart';
import '../data/repositories/profile_repository.dart';
import '../data/models/wallet_model.dart';
import '../data/repositories/payouts_repository.dart';
import '../data/repositories/wallet_repository.dart';
import 'config/payout_config.dart' show kPayoutMode;
import 'services/withdrawal_service.dart';
import 'services/auth_service.dart';
import 'services/claim_service.dart';
import 'services/cloud_functions_service.dart';
import 'services/game_session_service.dart';
import 'services/purchase_intent_service.dart';
import '../data/repositories/payouts_repository.dart' show PayoutAsset;

/// Provider único do serviço de autenticação (Riverpod é o state management
/// exclusivo do projeto). Em testes, as telas aceitam override deste provider
/// ou injeção direta via construtor.
final Provider<AuthServiceApi> authServiceProvider =
    Provider<AuthServiceApi>((Ref ref) => FirebaseAuthService());

/// Política de cache compartilhada da camada de dados.
final Provider<CachePolicy> cachePolicyProvider =
    Provider<CachePolicy>((Ref ref) => CachePolicy());

/// Repositório de perfil próprio (`users/{uid}`), cache-first.
final Provider<ProfileRepositoryApi> profileRepositoryProvider =
    Provider<ProfileRepositoryApi>(
  (Ref ref) => ProfileRepository(ref.watch(cachePolicyProvider)),
);

/// Serviço de chamadas ao backend via Cloud Functions (stub até o deploy).
final Provider<CloudFunctionsServiceApi> cloudFunctionsServiceProvider =
    Provider<CloudFunctionsServiceApi>((Ref ref) => CloudFunctionsService());

/// Repositório de poder próprio (`power/{uid}`), cache-first, só leitura.
final Provider<PowerRepositoryApi> powerRepositoryProvider =
    Provider<PowerRepositoryApi>(
  (Ref ref) => PowerRepository(ref.watch(cachePolicyProvider)),
);

/// Repositório de carteira própria (`wallets/{uid}`), cache-first, só leitura.
final Provider<WalletRepositoryApi> walletRepositoryProvider =
    Provider<WalletRepositoryApi>(
  (Ref ref) => WalletRepository(ref.watch(cachePolicyProvider)),
);

/// Repositório de máquinas (`machines/{uid}/items`), cache-first, só leitura.
final Provider<MachinesRepositoryApi> machinesRepositoryProvider =
    Provider<MachinesRepositoryApi>(
  (Ref ref) => MachinesRepository(ref.watch(cachePolicyProvider)),
);

/// Repositório de mineração (blocos/ligas/histórico), tolerante a ausência
/// de backend: toda falha vira estado vazio — nunca valor inventado.
final Provider<MiningRepositoryApi> miningRepositoryProvider =
    Provider<MiningRepositoryApi>(
  (Ref ref) => MiningRepository(ref.watch(cachePolicyProvider)),
);

/// Stream do poder próprio (`power/{uid}`) em tempo real. Tolerante a
/// falhas: erro ⇒ null (estado vazio — nunca valor inventado).
final StreamProvider<PowerModel?> powerStreamProvider =
    StreamProvider<PowerModel?>((Ref ref) async* {
      try {
        final String? uid = await ref.watch(currentUidProvider.future);
        if (uid == null) {
          yield null;
          return;
        }
        yield* ref.watch(powerRepositoryProvider).watchPower(uid);
      } catch (_) {
        yield null;
      }
    });

/// Stream do perfil próprio (`users/{uid}`) para consumo nas telas.
///
/// Tolerante a falhas: qualquer erro (Firebase indisponível, sessão ausente)
/// resulta em `null` — estado vazio, nunca crash. Atualiza em tempo real se
/// o usuário editar o displayName em outra tela.
final StreamProvider<Map<String, dynamic>?> profileStreamProvider =
    StreamProvider<Map<String, dynamic>?>((Ref ref) async* {
      try {
        final dynamic user = await ref.watch(authServiceProvider).currentUser();
        if (user == null) {
          yield null;
          return;
        }
        yield* ref.watch(profileRepositoryProvider).watchOwnProfile(user.uid as String);
      } catch (_) {
        yield null; // fallback seguro: perfil vazio, sem quebrar a tela
      }
    });

/// Uid do usuário autenticado (ou `null`). Tolerante a falhas para uso em
/// telas que precisam salvar preferências.
final FutureProvider<String?> currentUidProvider =
    FutureProvider<String?>((Ref ref) async {
      try {
        final dynamic user = await ref.watch(authServiceProvider).currentUser();
        return user?.uid as String?;
      } catch (_) {
        return null;
      }
    });

/// Repositório do catálogo de jogos (`games/*`), cache-first.
final Provider<GamesRepositoryApi> gamesRepositoryProvider =
    Provider<GamesRepositoryApi>(
  (Ref ref) => GamesRepository(ref.watch(cachePolicyProvider)),
);

/// Repositório do catálogo de máquinas (`config/machines`), cache-first.
final Provider<MachineCatalogRepositoryApi> machineCatalogRepositoryProvider =
    Provider<MachineCatalogRepositoryApi>(
  (Ref ref) => MachineCatalogRepository(ref.watch(cachePolicyProvider)),
);

/// Repositório de config econômica pública (`config/economy`), cache-first.
final Provider<EconomyRepositoryApi> economyRepositoryProvider =
    Provider<EconomyRepositoryApi>(
  (Ref ref) => EconomyRepository(ref.watch(cachePolicyProvider)),
);

/// Serviço de intenções de compra da LOJA (idempotente por clientRequestId).
final Provider<PurchaseIntentService> purchaseIntentServiceProvider =
    Provider<PurchaseIntentService>((Ref ref) => PurchaseIntentService());

/// Catálogo de games habilitados (cache-first; vazio em caso de falha).
final FutureProvider<List<GameModel>> gamesCatalogProvider =
    FutureProvider<List<GameModel>>((Ref ref) async {
      try {
        return await ref.watch(gamesRepositoryProvider).loadGames();
      } catch (_) {
        return const <GameModel>[]; // estado vazio, nunca crash
      }
    });

/// Repositório de sessões de partida (intenções open/finished).
final Provider<GameSessionsRepositoryApi> gameSessionsRepositoryProvider =
    Provider<GameSessionsRepositoryApi>(
  (Ref ref) => GameSessionsRepository(),
);

/// Serviço de sessão de partida (abrir/fechar/observar processamento).
final Provider<GameSessionService> gameSessionServiceProvider =
    Provider<GameSessionService>((Ref ref) => GameSessionService(
          repository: ref.watch(gameSessionsRepositoryProvider),
        ));

/// Maior score finished próprio no game — "Melhor:" do catálogo.
// ignore: provider_type_args
final bestScoreProvider =
    FutureProvider.family<int, String>((Ref ref, String gameId) async {
      try {
        final String? uid = await ref.watch(currentUidProvider.future);
        if (uid == null) return 0;
        return await ref
            .watch(gameSessionsRepositoryProvider)
            .bestScore(uid: uid, gameId: gameId);
      } catch (_) {
        return 0; // sem dado confiável ⇒ 0, nunca valor inventado
      }
    });

/// Repositório de missões (catálogo + progresso do usuário), cache-first.
final Provider<MissionsRepositoryApi> missionsRepositoryProvider =
    Provider<MissionsRepositoryApi>(
  (Ref ref) => MissionsRepository(ref.watch(cachePolicyProvider)),
);

/// Repositório de conquistas (catálogo + progresso do usuário), cache-first.
final Provider<AchievementsRepositoryApi> achievementsRepositoryProvider =
    Provider<AchievementsRepositoryApi>(
  (Ref ref) => AchievementsRepository(ref.watch(cachePolicyProvider)),
);

/// Serviço de resgate de missões/conquistas (idempotente por clientRequestId).
final Provider<ClaimService> claimServiceProvider =
    Provider<ClaimService>((Ref ref) => ClaimService());

/// Missões combinadas (catálogo + progresso) em tempo real. Tolerante a
/// falhas: qualquer erro vira stream vazio — estado vazio, nunca crash.
final StreamProvider<List<MissionView>> missionsStreamProvider =
    StreamProvider<List<MissionView>>((Ref ref) async* {
      try {
        final String? uid = await ref.watch(currentUidProvider.future);
        if (uid == null) {
          yield const <MissionView>[];
          return;
        }
        yield* ref.watch(missionsRepositoryProvider).watchMissions(uid);
      } catch (_) {
        yield const <MissionView>[];
      }
    });

/// Conquistas combinadas (catálogo + progresso) em tempo real. Tolerante.
final StreamProvider<List<AchievementView>> achievementsStreamProvider =
    StreamProvider<List<AchievementView>>((Ref ref) async* {
      try {
        final String? uid = await ref.watch(currentUidProvider.future);
        if (uid == null) {
          yield const <AchievementView>[];
          return;
        }
        yield* ref.watch(achievementsRepositoryProvider).watchAchievements(uid);
      } catch (_) {
        yield const <AchievementView>[];
      }
    });

/// Quantidade de recompensas PRONTAS para resgate (missões + conquistas) —
/// badge do atalho da HOME. Tolerante a falhas (0 sem dado confiável).
final Provider<int> claimablesCountProvider = Provider<int>((Ref ref) {
  int count = 0;
  final AsyncValue<List<MissionView>> missions = ref.watch(missionsStreamProvider);
  missions.whenData((List<MissionView> list) {
    for (final MissionView m in list) {
      if (m.isClaimable) count += 1;
    }
  });
  final AsyncValue<List<AchievementView>> achievements =
      ref.watch(achievementsStreamProvider);
  achievements.whenData((List<AchievementView> list) {
    for (final AchievementView a in list) {
      if (a.isClaimable) count += 1;
    }
  });
  return count;
});

/// Repositório de ligas (catálogo + liga do usuário), cache-first, só leitura.
final Provider<LeaguesRepositoryApi> leaguesRepositoryProvider =
    Provider<LeaguesRepositoryApi>(
  (Ref ref) => LeaguesRepository(ref.watch(cachePolicyProvider)),
);

/// Repositório do ranking de ligas (maskedName — sem dados pessoais).
final Provider<LeaderboardRepositoryApi> leaderboardRepositoryProvider =
    Provider<LeaderboardRepositoryApi>(
  (Ref ref) => LeaderboardRepository(),
);

/// Repositório de temporada (doc oficial + progresso), cache-first, só leitura.
final Provider<SeasonRepositoryApi> seasonRepositoryProvider =
    Provider<SeasonRepositoryApi>(
  (Ref ref) => SeasonRepository(ref.watch(cachePolicyProvider)),
);

/// Catálogo de ligas ordenado por tier (vazio em caso de falha).
final FutureProvider<List<LeagueModel>> leaguesCatalogProvider =
    FutureProvider<List<LeagueModel>>((Ref ref) async {
      try {
        return await ref.watch(leaguesRepositoryProvider).loadLeagues();
      } catch (_) {
        return const <LeagueModel>[]; // estado vazio, nunca crash
      }
    });

/// Liga atual do usuário em tempo real (null = sem liga ainda). Tolerante.
final StreamProvider<UserLeagueModel?> userLeagueStreamProvider =
    StreamProvider<UserLeagueModel?>((Ref ref) async* {
      try {
        final String? uid = await ref.watch(currentUidProvider.future);
        if (uid == null) {
          yield null;
          return;
        }
        yield* ref.watch(leaguesRepositoryProvider).watchUserLeague(uid);
      } catch (_) {
        yield null;
      }
    });

/// Ranking da liga atual do usuário (top 100 por poder). Tolerante: sem
/// liga ou com falha ⇒ stream vazio (estado vazio na tela, nunca crash).
// ignore: provider_type_args
final leaderboardProvider =
    StreamProvider.family<List<LeaderboardEntry>, String>((Ref ref, String leagueId) {
      return ref.watch(leaderboardRepositoryProvider).watchLeaderboard(leagueId);
    });

/// Doc oficial da temporada (null em caso de falha — estado vazio).
final FutureProvider<SeasonModel?> seasonProvider =
    FutureProvider<SeasonModel?>((Ref ref) async {
      try {
        return await ref.watch(seasonRepositoryProvider).loadSeason();
      } catch (_) {
        return null;
      }
    });

/// Progresso da temporada do usuário em tempo real (null = sem progresso).
final StreamProvider<SeasonProgressModel?> seasonProgressStreamProvider =
    StreamProvider<SeasonProgressModel?>((Ref ref) async* {
      try {
        final String? uid = await ref.watch(currentUidProvider.future);
        if (uid == null) {
          yield null;
          return;
        }
        yield* ref.watch(seasonRepositoryProvider).watchSeasonProgress(uid);
      } catch (_) {
        yield null;
      }
    });

/// Missões de TEMPORADA (kind='season') + progresso em tempo real. Tolerante.
final StreamProvider<List<MissionView>> seasonMissionsStreamProvider =
    StreamProvider<List<MissionView>>((Ref ref) async* {
      try {
        final String? uid = await ref.watch(currentUidProvider.future);
        if (uid == null) {
          yield const <MissionView>[];
          return;
        }
        yield* ref.watch(seasonRepositoryProvider).watchSeasonMissions(uid);
      } catch (_) {
        yield const <MissionView>[];
      }
    });

// ---- CARTEIRA / SAQUES (doc 05 §26/§51) -------------------------------------

/// Repositório de payouts/saques (config/payouts + withdrawals), só leitura.
final Provider<PayoutsRepositoryApi> payoutsRepositoryProvider =
    Provider<PayoutsRepositoryApi>((Ref ref) => PayoutsRepository());

/// Serviço de saque NO CLIENTE (12.18): reserva → payout FaucetPay →
/// conclusão/estorno. Chave via --dart-define ou config local gitignored.
/// 12.20: o provider escolhido depende de [kPayoutMode] ('auto'|'manual').
final Provider<WithdrawalService> withdrawalServiceProvider =
    Provider<WithdrawalService>((Ref ref) => WithdrawalService());

/// Observador do MODO MANUAL (12.20): liquida sozinho (conclusão/estorno)
/// quando o operador define o status do doc `withdrawals/{id}` no Console.
final Provider<ManualPayoutWatcher> manualPayoutWatcherProvider =
    Provider<ManualPayoutWatcher>((Ref ref) => ManualPayoutWatcher());

/// ATIVAÇÃO do observador manual: só conecta ao Firestore quando
/// [kPayoutMode] == 'manual' E houver ouvinte vivo (shell/carteira).
/// Em 'auto' (default, inclusive testes) não toca no Firestore.
final StreamProvider<void> manualPayoutWatchProvider =
    StreamProvider<void>((Ref ref) async* {
      if (kPayoutMode != 'manual') return;
      try {
        final String? uid = await ref.watch(currentUidProvider.future);
        if (uid == null) return;
        yield* ref.watch(manualPayoutWatcherProvider).watch(uid);
      } catch (_) {
        // Tolerante a falhas: sem sessão/Firestore ⇒ observador inativo.
      }
    });

/// Config de saques (ativos habilitados, mínimos, taxas) — "valores definidos
/// pelo servidor". Tolerante: doc ausente/erro ⇒ null (estado vazio).
final FutureProvider<PayoutsConfigModel?> payoutsConfigProvider =
    FutureProvider<PayoutsConfigModel?>((Ref ref) async {
      try {
        return await ref.watch(payoutsRepositoryProvider).loadConfig();
      } catch (_) {
        return null;
      }
    });

/// Stream da carteira própria (`wallets/{uid}`) em tempo real. Tolerante.
final StreamProvider<WalletModel?> walletStreamProvider =
    StreamProvider<WalletModel?>((Ref ref) async* {
      try {
        final String? uid = await ref.watch(currentUidProvider.future);
        if (uid == null) {
          yield null;
          return;
        }
        yield* ref.watch(walletRepositoryProvider).watchWallet(uid);
      } catch (_) {
        yield null;
      }
    });

/// Histórico de saques do usuário em tempo real. Tolerante a falhas.
final StreamProvider<List<WithdrawalModel>> withdrawalsStreamProvider =
    StreamProvider<List<WithdrawalModel>>((Ref ref) async* {
      try {
        final String? uid = await ref.watch(currentUidProvider.future);
        if (uid == null) {
          yield const <WithdrawalModel>[];
          return;
        }
        
        yield* ref.watch(payoutsRepositoryProvider).watchUserWithdrawals(uid);
      } catch (_) {
        yield const <WithdrawalModel>[];
      }
    });

/// Espelho de recompensas (`rewards/{uid}/items`) em tempo real. Tolerante.
final StreamProvider<List<RewardHistoryEntry>> rewardItemsStreamProvider =
    StreamProvider<List<RewardHistoryEntry>>((Ref ref) async* {
      try {
        final String? uid = await ref.watch(currentUidProvider.future);
        if (uid == null) {
          yield const <RewardHistoryEntry>[];
          return;
        }
        yield* ref.watch(payoutsRepositoryProvider).watchRewardItems(uid);
      } catch (_) {
        yield const <RewardHistoryEntry>[];
      }
    });


/// Provider do ativo LTC (config/payouts) — expõe minWithdrawCoins, feeCoins,
/// litoshiPerCoin, subscriber, providerMinLitoshi vindos do backend.
final FutureProvider<PayoutAsset?> ltcPayoutAssetProvider =
    FutureProvider<PayoutAsset?>((Ref ref) async {
  final config = await ref.watch(payoutsConfigProvider.future);
  if (config == null) return null;
  for (final asset in config.assets) {
    if (asset.id == 'LTC') return asset;
  }
  return null;
});

/// Provider premium do usuário (users/{uid}.premium == true).
final StreamProvider<bool> userPremiumProvider =
    StreamProvider<bool>((Ref ref) async* {
  try {
    final String? uid = await ref.watch(currentUidProvider.future);
    if (uid == null) {
      yield false;
      return;
    }
    yield* ref
        .watch(profileRepositoryProvider)
        .watchOwnProfile(uid)
        .map((profile) => profile?['premium'] == true);
  } catch (_) {
    yield false;
  }
});
