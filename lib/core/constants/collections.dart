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

  // Configs públicas: catálogo de máquinas (config/catalog/machines — 4
  // segmentos, par obrigatório p/ docs) e economia (config/economy — somente
  // leitura de campos públicos como machineSlots).
  static const String config = 'config';
  static const String configMachines = 'config/catalog/machines';

  // Configs públicas de bloco e histórico de recompensas — backend AINDA
  // ausente (P4): leitura tolerante a doc ausente/permissão negada; as
  // rules correspondentes serão adicionadas quando o backend existir.
  static const String blocks = 'blocks';
  static const String rewards = 'rewards';
  static const String withdrawals = 'withdrawals';
  static const String auditLogs = 'auditLogs';
}
