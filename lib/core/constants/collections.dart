/// Nomes das coleções do Firestore — fonte única de verdade.
/// As regras de acesso vivem em `firestore.rules` (menor privilégio).
abstract final class Collections {
  static const String users = 'users';
  static const String wallets = 'wallets';
  static const String power = 'power';
  static const String machines = 'machines';
  static const String games = 'games';
  static const String gameSessions = 'gameSessions';
  static const String missions = 'missions';
  static const String userMissions = 'userMissions';
  static const String achievements = 'achievements';
  static const String userAchievements = 'userAchievements';
  static const String leagues = 'leagues';
  static const String userLeagues = 'userLeagues';
  static const String seasons = 'seasons';
  static const String seasonProgress = 'seasonProgress';

  // Intenções de compra (cliente SÓ cria; validação 100% no runner).
  static const String purchaseIntents = 'purchaseIntents';

  // Intenções de resgate de missões/conquistas (cliente SÓ cria a intenção;
  // a recompensa é concedida EXCLUSIVAMENTE pelo runner — doc 05 §42).
  static const String claims = 'claims';

  // Configs públicas: catálogo de máquinas (config/catalog/machines — 4
  // segmentos, par obrigatório p/ docs) e economia (config/economy — somente
  // leitura de campos públicos como machineSlots).
  static const String config = 'config';
  static const String configMachines = 'config/catalog/machines';

  // Intenções de SAQUE (cliente SÓ cria; validação/reserva/payout/estorno
  // são 100% do runner — doc 05 §26/§51).
  static const String withdrawalIntents = 'withdrawalIntents';

  // Intenções de recompensa por ANÚNCIO (cliente SÓ registra a intenção
  // após onUserEarnedReward; a concessão é EXCLUSIVAMENTE do runner).
  static const String adRewardIntents = 'adRewardIntents';

  // Recompensas de anúncio CONCEDIDAS pelo runner (leitura do dono — usado
  // pelo contador diário "X de Y hoje" da LOJA).
  static const String adRewards = 'adRewards';

  // Config pública de anúncios (config/ads): dailyLimit/cooldown/reward.
  static const String configAds = 'config/ads';

  // Config pública de saques (config/payouts): ativos habilitados, mínimos
  // e taxas — somente leitura ("valores definidos pelo servidor").
  static const String configPayouts = 'config/payouts';

  // Configs públicas de bloco e histórico de recompensas — backend AINDA
  // ausente (P4): leitura tolerante a doc ausente/permissão negada; as
  // rules correspondentes serão adicionadas quando o backend existir.
  static const String blocks = 'blocks';
  static const String rewards = 'rewards';
  static const String withdrawals = 'withdrawals';
  static const String auditLogs = 'auditLogs';
}
