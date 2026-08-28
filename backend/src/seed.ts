/**
 * Seed DEV — cria config/economy, config/catalog/machines/* (legado),
 * config/machines/* (catálogo v2) e games/* SOMENTE se não existirem.
 * Nunca sobrescreve dados existentes (upgrades são MERGE idempotente).
 * Bloqueado em produção (NODE_ENV=production).
 *
 * Catálogo v2 (LOJA): docs em config/catalog/machines/{id} — caminho lido
 * pelas security rules na criação de purchaseIntents e pelo processador.
 */
import { initAdmin } from './admin';

/**
 * DECISÃO DO DONO (12.23): BLOCK_REWARD = 5 COIN por bloco de 5 minutos.
 * 5 COIN = 5.000.000 units (coinPrecision = 1.000.000). Instalações novas já
 * nascem nesta versão; instalações existentes recebem MERGE idempotente via
 * upgradeEconomyBlockRewardV2 (bump de economicRuleVersion preservando o
 * ruleVersion das transações antigas — doc 05 §44).
 */
const ECONOMY = {
  blockRewardUnits: 5_000_000, // 5 coins por bloco (coinPrecision = 6 casas)
  blockIntervalMs: 300_000, // 5 minutos
  coinPrecision: 1_000_000,
  powerBasePerHs: 1_000,
  residueUnits: 0,
  economicRuleVersion: 2,
  maxGamePowerPerSession: 200000,
  maxGameSessionsPerDay: 30,
  limits: {
    maxSessionsPerDay: 50,
    maxPurchaseIntentsPerDay: 20,
    minSessionDurationMs: 5_000,
    maxSessionDurationMs: 3_600_000,
    maxScorePerSecond: 100,
    tempGrantDurationMs: 86_400_000, // 24h
    maxBatchSize: 100,
    maxUsersPerBlock: 2_000,
  },
};

/**
 * Catálogo v2 de MÁQUINAS (LOJA) — config/catalog/machines/{id} (4 segmentos:
 * caminhos de DOCUMENTO exigem nº PAR de segmentos no Firestore).
 * Preços = sinks de longo payback (doc 05 §34); powerBasePerHs = 1000;
 * coinPrecision = 1_000_000 (1 coin = 1e6 units).
 * Campos: {name, rarity, powerUnits, priceUnits, maxPerUser, enabled, version}.
 * Fórmulas UPGRADE v2 (14.10): custo = 60% × preço × 1.6^(n-1), power = base × (9+n)/10, maxLevel=10.
 */
const MACHINES_V2: Record<string, Record<string, unknown>> = {
  'rig-scrap': {
    name: 'RIG SCRAP',
    rarity: 'common',
    powerUnits: 10, // +10 H/s
    priceUnits: 400_000_000, // 400 coins
    maxPerUser: 5,
    currencyId: 'coins',
    enabled: true,
    version: 4,
    maxLevel: 10,
    levelPowerStep: 0.25,
    upgradeCostFactor: 0.75,
  },
  'rig-volt': {
    name: 'RIG VOLT',
    rarity: 'common',
    powerUnits: 30, // +30 H/s
    priceUnits: 1_100_000_000, // 1.100 coins
    maxPerUser: 4,
    currencyId: 'coins',
    enabled: true,
    version: 4,
    maxLevel: 10,
    levelPowerStep: 0.25,
    upgradeCostFactor: 0.75,
  },
  'rig-pulse': {
    name: 'RIG PULSE',
    rarity: 'rare',
    powerUnits: 80, // +80 H/s
    priceUnits: 2_600_000_000, // 2.600 coins
    maxPerUser: 3,
    currencyId: 'coins',
    enabled: true,
    version: 4,
    maxLevel: 10,
    levelPowerStep: 0.25,
    upgradeCostFactor: 0.75,
  },
  'rig-quantum': {
    name: 'RIG QUANTUM',
    rarity: 'epic',
    powerUnits: 200, // +200 H/s
    priceUnits: 6_000_000_000, // 6.000 coins
    maxPerUser: 2,
    currencyId: 'coins',
    enabled: true,
    version: 4,
    maxLevel: 10,
    levelPowerStep: 0.25,
    upgradeCostFactor: 0.75,
  },
  'rig-nova': {
    name: 'RIG NOVA',
    rarity: 'legendary',
    powerUnits: 500, // +500 H/s
    priceUnits: 15_000_000_000, // 15.000 coins
    maxPerUser: 1,
    currencyId: 'coins',
    enabled: true,
    version: 4,
    maxLevel: 10,
    levelPowerStep: 0.25,
    upgradeCostFactor: 0.75,
  },
};

/** Catálogo LEGADO (v1) — mantido por compatibilidade; nunca removido. */
const MACHINES: Record<string, Record<string, unknown>> = {
  'asic-mini': {
    name: 'ASIC Mini',
    priceUnits: 10_000_000, // 10 coins
    powerAmount: 500,
    currencyId: 'coins',
    enabled: true,
  },
  'asic-pro': {
    name: 'ASIC Pro',
    priceUnits: 50_000_000, // 50 coins
    powerAmount: 3_000,
    currencyId: 'coins',
    enabled: true,
  },
  'asic-hyper': {
    name: 'ASIC Hyper',
    priceUnits: 200_000_000, // 200 coins
    powerAmount: 15_000,
    currencyId: 'coins',
    enabled: true,
  },
};

// Config v2 de gameplay do NOVA SWARM (autoridade de validação do backend).
// Campos econômicos (maxScore/maxScorePerSecond/maxExpectedScore/power*) são
// PRESERVADOS da v1 — a economia continua 100% autorizada pelo backend.
const NOVA_SWARM_V2_CONFIGURATION: Record<string, unknown> = {
  durationSeconds: 60,
  baseEnemies: 8,
  enemiesPerWaveStep: 4,
  enemyHp: 2,
  lives: 3,
  pointsPerKill: 150,
  pointsPerHit: 25,
  waveBonus: 500,
  diverKillBonus: 50,
  coinBonus: 250,
  maxScore: 30_000,
  maxScorePerSecond: 500,
  minDurationSeconds: 5,
  maxExpectedScore: 12_000,
  powerCapPerSessionBaseUnits: 100_000,
  powerFormula: 'linear_cap',
  // Mergulhos: intervalo base com rampa por wave até o mínimo.
  diveIntervalSeconds: 3.0,
  diveIntervalMinSeconds: 1.2,
  diveRampPerWave: 0.05,
  // Tiros da formação: intervalo base (cliente aplica ±2s aleatório).
  formationShotIntervalSeconds: 4.0,
  enemyBulletSpeed: 220,
  diverSpeed: 260,
  // Power-ups: chance por abate e duração dos temporários.
  powerupChances: { shield: 0.08, double: 0.1, coin: 0.12 },
  powerupDurations: { shieldSeconds: 6, doubleSeconds: 8 },
};

// Config v1 de gameplay do NEON HOPPER (plataforma 2D — MÉDIO, 45s, 3 vidas).
// Score OFICIAL calculado NO SERVIDOR a partir do breakdown do cliente:
//   score = stomps×pointsPerStomp + coins×pointsPerCoin + flagReached×flagBonus
// Tantos anti-flood (espelhados nas security rules): maxStomps/maxCoins.
// Fórmula de poder: linear_cap
//   power = floor(min(score / maxExpectedScore, 1) × powerCapPerSessionBaseUnits)
// powerCapPerSessionBaseUnits = 150_000 units = 150 H/s (powerBasePerHs = 1_000).
const NEON_HOPPER_V1_CONFIGURATION: Record<string, unknown> = {
  durationSeconds: 45,
  lives: 3,
  pointsPerStomp: 100,
  pointsPerCoin: 50,
  flagBonus: 500,
  maxStomps: 60,
  maxCoins: 40,
  maxScore: 20_000,
  maxScorePerSecond: 300,
  maxExpectedScore: 6_000,
  powerCapPerSessionBaseUnits: 150_000,
  powerFormula: 'linear_cap',
};

/**
 * Catálogo de MISSÕES v1 — missions/{id} (create-if-absent; nunca sobrescreve).
 * metric: plays (partidas) · max_score (máx da partida) · kills (acumulado) ·
 * buys (compras). rewardConfig.amountUnits em UNITS (1 coin = 1e6 units).
 */
const MISSIONS: Record<string, Record<string, unknown>> = {
  'm_daily_play3': {
    kind: 'daily',
    title: 'Jogue 3 partidas',
    description: 'Complete 3 partidas hoje.',
    metric: 'plays',
    target: 3,
    rewardConfig: { type: 'coins', amountUnits: 100_000_000 }, // 100 coins
    enabled: true,
    version: 1,
  },
  'm_daily_points2k': {
    kind: 'daily',
    title: 'Faça 2.000 pontos em uma partida',
    description: 'Alcance 2.000 pontos em uma única partida.',
    metric: 'max_score',
    target: 2_000,
    rewardConfig: { type: 'coins', amountUnits: 150_000_000 }, // 150 coins
    enabled: true,
    version: 1,
  },
  'm_daily_kills30': {
    kind: 'daily',
    title: 'Destrua 30 inimigos',
    description: 'Destrua 30 inimigos (acumulado do dia).',
    metric: 'kills',
    target: 30,
    rewardConfig: { type: 'coins', amountUnits: 200_000_000 }, // 200 coins
    enabled: true,
    version: 1,
  },
  'm_weekly_play20': {
    kind: 'weekly',
    title: 'Complete 20 partidas na semana',
    description: 'Complete 20 partidas nesta semana.',
    metric: 'plays',
    target: 20,
    rewardConfig: { type: 'coins', amountUnits: 500_000_000 }, // 500 coins
    enabled: true,
    version: 1,
  },
  'm_weekly_buy1': {
    kind: 'weekly',
    title: 'Compre 1 máquina na semana',
    description: 'Adquira 1 máquina na loja esta semana.',
    metric: 'buys',
    target: 1,
    rewardConfig: { type: 'coins', amountUnits: 300_000_000 }, // 300 coins
    enabled: true,
    version: 1,
  },
};

/**
 * Catálogo de LIGAS v1 — leagues/{id} (create-if-absent / merge por versão).
 * Atribuição 100% no backend (league_sweep): liga = maior tier com
 * minPowerUnits ≤ totalPower. Unidades BASE (powerBasePerHs = 1.000):
 * minPowerUnits = limiar H/s × 1.000. dailyRewardUnits em units de coin
 * (1 coin = 1e6 units) — concedida 1×/dia pelo runner (idempotente).
 */
const LEAGUES: Record<string, Record<string, unknown>> = {
  bronze: {
    name: 'BRONZE',
    tier: 1,
    minPowerUnits: 100 * 1_000, // 100 H/s
    dailyRewardUnits: 50 * 1_000_000, // 50 coins
    color: '#B0713B',
    version: 1,
  },
  prata: {
    name: 'PRATA',
    tier: 2,
    minPowerUnits: 500 * 1_000, // 500 H/s
    dailyRewardUnits: 100 * 1_000_000, // 100 coins
    color: '#C0C8D4',
    version: 1,
  },
  ouro: {
    name: 'OURO',
    tier: 3,
    minPowerUnits: 1_500 * 1_000, // 1.500 H/s
    dailyRewardUnits: 250 * 1_000_000, // 250 coins
    color: '#F5C542',
    version: 1,
  },
  platina: {
    name: 'PLATINA',
    tier: 4,
    minPowerUnits: 10_000 * 1_000, // 10.000 H/s
    dailyRewardUnits: 500 * 1_000_000, // 500 coins
    color: '#7FE3DE',
    version: 1,
  },
  diamante: {
    name: 'DIAMANTE',
    tier: 5,
    minPowerUnits: 100_000 * 1_000, // 100.000 H/s
    dailyRewardUnits: 1_000 * 1_000_000, // 1.000 coins
    color: '#5AA7FF',
    version: 1,
  },
};

/** Trilhas do passe (níveis 1..20) — recompensas em coins (× 1e6 = units). */
function seasonTrack(coinsByLevel: number[]): Record<string, unknown>[] {
  return coinsByLevel.map((coins, i) => ({
    level: i + 1,
    reward: {
      type: 'coins',
      amountUnits: coins * 1_000_000,
    },
  }));
}

/** Valores OFICIAIS da TEMPORADA 01 (v2) — COIN por nível 1..20. */
const SEASON_FREE_COINS = [
  50, 75, 100, 125, 150, 175, 200, 225, 250, 300,
  350, 400, 450, 500, 600, 700, 800, 900, 1000, 1200,
];
const SEASON_PREMIUM_COINS = [
  100, 150, 200, 250, 300, 350, 400, 450, 500, 600,
  700, 800, 900, 1000, 1200, 1400, 1600, 1800, 2000, 2500,
];

/**
 * TEMPORADA 01 — seasons/season-01 (create-if-absent). XP real calculado
 * SOMENTE pelo backend (season_progress): partida = floor(score/divisor);
 * claim de missão/conquista = bônus fixo. Nível derivado (linear, 1200 XP).
 */
function seasonDoc(): Record<string, unknown> {
  const startAt = new Date();
  const endAt = new Date(startAt.getTime() + 30 * 86_400_000);
  return {
    name: 'TEMPORADA 01',
    startAt,
    endAt,
    economicRuleVersion: 1,
    xpConfig: { matchScoreDivisor: 10, missionClaimXp: 50, achievementXp: 100 },
    levelXp: 1200,
    tracks: {
      free: seasonTrack(SEASON_FREE_COINS),
      premium: seasonTrack(SEASON_PREMIUM_COINS),
    },
    version: 2,
  };
}

/**
 * Missões de TEMPORADA — missions/{id} kind='season' com periodKey fixo da
 * temporada (não reiniciam por dia/semana). create-if-absent.
 */
const SEASON_MISSIONS: Record<string, Record<string, unknown>> = {
  s01_play50: {
    kind: 'season',
    periodKey: 'season-01',
    title: 'Jogue 50 partidas na temporada',
    description: 'Complete 50 partidas durante a TEMPORADA 01.',
    metric: 'plays',
    target: 50,
    rewardConfig: { type: 'coins', amountUnits: 300_000_000 }, // 300 coins
    enabled: true,
    version: 1,
  },
  s01_kills500: {
    kind: 'season',
    periodKey: 'season-01',
    title: 'Destrua 500 inimigos na temporada',
    description: 'Destrua 500 inimigos durante a TEMPORADA 01.',
    metric: 'kills',
    target: 500,
    rewardConfig: { type: 'coins', amountUnits: 400_000_000 }, // 400 coins
    enabled: true,
    version: 1,
  },
  s01_claims10: {
    kind: 'season',
    periodKey: 'season-01',
    title: 'Resgate 10 recompensas na temporada',
    description: 'Resgate 10 recompensas de missões/conquistas na temporada.',
    metric: 'claims',
    target: 10,
    rewardConfig: { type: 'coins', amountUnits: 250_000_000 }, // 250 coins
    enabled: true,
    version: 1,
  },
};

/**
 * Config de ANÚNCIOS v1 — config/ads (create-if-absent; autoridade do
 * runner processAdRewards). 1 COIN = 1e6 units por vídeo rewarded;
 * dailyLimit/cooldown aplicados SOMENTE no backend (doc 04/05 §31).
 */
const ADS_V1: Record<string, unknown> = {
  rewarded: {
    dailyLimit: 10,
    cooldownMinutes: 5,
    reward: { type: 'coins', amountUnits: 1_000_000 }, // 1 COIN
    xpBonus: 25,
  },
  version: 1,
};

/**
 * Catálogo de CONQUISTAS v1 — achievements/{id} (create-if-absent).
 * category: games | mining | collection | missions. Sem período (sem reset).
 */
const ACHIEVEMENTS: Record<string, Record<string, unknown>> = {
  'a_first_match': {
    category: 'games',
    title: 'Primeira Partida',
    description: 'Jogue sua primeira partida.',
    metric: 'plays',
    target: 1,
    rewardConfig: { type: 'coins', amountUnits: 50_000_000 }, // 50 coins
    enabled: true,
    version: 1,
  },
  'a_kills_100': {
    category: 'games',
    title: '100 Abates',
    description: 'Destrua 100 inimigos no total.',
    metric: 'kills',
    target: 100,
    rewardConfig: { type: 'coins', amountUnits: 200_000_000 }, // 200 coins
    enabled: true,
    version: 1,
  },
  'a_score_10k': {
    category: 'games',
    title: '10.000 Pontos',
    description: 'Faça 10.000 pontos em uma única partida.',
    metric: 'max_score',
    target: 10_000,
    rewardConfig: { type: 'coins', amountUnits: 300_000_000 }, // 300 coins
    enabled: true,
    version: 1,
  },
  'a_power_100': {
    category: 'mining',
    title: '100 H/s',
    description: 'Alcance 100 H/s de poder total.',
    metric: 'power',
    target: 100,
    rewardConfig: { type: 'coins', amountUnits: 100_000_000 }, // 100 coins
    enabled: true,
    version: 1,
  },
  'a_power_1k': {
    category: 'mining',
    title: '1.000 H/s',
    description: 'Alcance 1.000 H/s de poder total.',
    metric: 'power',
    target: 1_000,
    rewardConfig: { type: 'coins', amountUnits: 400_000_000 }, // 400 coins
    enabled: true,
    version: 1,
  },
  'a_machines_1': {
    category: 'collection',
    title: 'Primeira Máquina',
    description: 'Possua 1 máquina.',
    metric: 'machines',
    target: 1,
    rewardConfig: { type: 'coins', amountUnits: 100_000_000 }, // 100 coins
    enabled: true,
    version: 1,
  },
  'a_machines_5': {
    category: 'collection',
    title: '5 Máquinas',
    description: 'Possua 5 máquinas.',
    metric: 'machines',
    target: 5,
    rewardConfig: { type: 'coins', amountUnits: 500_000_000 }, // 500 coins
    enabled: true,
    version: 1,
  },
  'a_claims_10': {
    category: 'missions',
    title: 'Caçador de Recompensas',
    description: 'Resgate 10 recompensas.',
    metric: 'claims',
    target: 10,
    rewardConfig: { type: 'coins', amountUnits: 250_000_000 }, // 250 coins
    enabled: true,
    version: 1,
  },
};

const GAMES: Record<string, Record<string, unknown>> = {
  'tap-blitz': {
    name: 'Tap Blitz',
    enabled: true,
    configuration: {
      maxExpectedScore: 1_000,
      powerBaseReward: 250,
      powerCapPerSession: 250,
    },
  },
  'reflex-rush': {
    name: 'Reflex Rush',
    enabled: true,
    configuration: {
      maxExpectedScore: 2_000,
      powerBaseReward: 400,
      powerCapPerSession: 400,
    },
  },
  // NOVA SWARM — shooter espacial 2D (FÁCIL, 60s, 3 vidas, ondas crescentes).
  // Fórmula de poder: linear_cap
  //   power = floor(min(score / maxExpectedScore, 1) × powerCapPerSessionBaseUnits)
  // powerCapPerSessionBaseUnits = 100_000 units = 100 H/s (powerBasePerHs = 1_000).
  // Fácil = mais pontos (pointsPerKill 150); médios/duros futuros usarão menos.
  //
  // v2: countdown, mergulhos programados, tiros inimigos, power-ups
  // (escudo/tiro duplo/moeda) e paridade comportamental com a referência.
  'nova-swarm': {
    name: 'NOVA SWARM',
    difficulty: 'easy',
    enabled: true,
    version: 2,
    configuration: NOVA_SWARM_V2_CONFIGURATION,
  },
  // NEON HOPPER — plataforma 2D side-scroll (MÉDIO, 45s, 3 vidas). Score
  // OFICIAL = f(breakdown) recalculado no servidor (doc 05 §12/§51).
  'neon-hopper': {
    name: 'NEON HOPPER',
    difficulty: 'medium',
    enabled: true,
    version: 1,
    configuration: NEON_HOPPER_V1_CONFIGURATION,
  },
};

// Dados canônicos v1/v2/v3 de config/payouts + helpers PUROS de merge
// (unit-testáveis) vivem em core/payoutsUpgrade.ts — fonte ÚNICA usada pelo
// seed e pelos testes de upgrade idempotente.
import { buildPayoutsV4Doc } from './core/payoutsUpgrade';

async function createIfMissing(
  db: ReturnType<typeof initAdmin>['db'],
  docPath: string,
  data: Record<string, unknown>,
): Promise<'created' | 'exists'> {
  const ref = db.doc(docPath);
  const snap = await ref.get();
  if (snap.exists) return 'exists';
  await ref.set(data);
  return 'created';
}

/**
 * Upgrade IDEMPOTENTE da config do NOVA SWARM para v2: se o doc existir com
 * version < 2, faz MERGE dos campos novos na configuration existente (nunca
 * remove campos v1 — economia preservada). Rodar novamente = no-op.
 */
async function upgradeNovaSwarmToV2(
  db: ReturnType<typeof initAdmin>['db'],
): Promise<'upgraded' | 'current' | 'created'> {
  const ref = db.doc('games/nova-swarm');
  const snap = await ref.get();
  if (!snap.exists) {
    await ref.set(GAMES['nova-swarm']);
    return 'created';
  }
  const data = snap.data() ?? {};
  const version = typeof data.version === 'number' ? data.version : 1;
  if (version >= 2) return 'current';
  const existingCfg = (data.configuration ?? {}) as Record<string, unknown>;
  await ref.set(
    {
      version: 2,
      configuration: { ...existingCfg, ...NOVA_SWARM_V2_CONFIGURATION },
    },
    { merge: true },
  );
  return 'upgraded';
}

/**
 * Garante config/economy.machineSlots (sala de máquinas da HOME). MERGE:
 * só grava o campo se ele AINDA NÃO EXISTIR no doc (nunca destrói).
 */
async function ensureMachineSlots(
  db: ReturnType<typeof initAdmin>['db'],
): Promise<'set' | 'exists'> {
  const ref = db.doc('config/economy');
  const snap = await ref.get();
  if (snap.exists && snap.get('machineSlots') !== undefined) return 'exists';
  await ref.set({ machineSlots: 10 }, { merge: true });
  return 'set';
}

/**
 * Upgrade IDEMPOTENTE do catálogo de máquinas para v2
 * (config/catalog/machines/{id}): doc ausente => cria; version < 2 => MERGE
 * dos campos v2 (nunca remove); version >= 2 => no-op. Rodar novamente = no-op.
 */
async function upgradeMachinesToV2(
  db: ReturnType<typeof initAdmin>['db'],
): Promise<'created' | 'upgraded' | 'current'> {
  let created = 0;
  let upgraded = 0;
  let current = 0;
  for (const [id, v2] of Object.entries(MACHINES_V2)) {
    const ref = db.doc(`config/catalog/machines/${id}`);
    const snap = await ref.get();
    if (!snap.exists) {
      await ref.set(v2);
      created += 1;
      continue;
    }
    const version = typeof snap.get('version') === 'number' ? Number(snap.get('version')) : 1;
    if (version >= 2) {
      current += 1;
      continue;
    }
    await ref.set(v2, { merge: true });
    upgraded += 1;
  }
  if (created > 0) return 'created';
  if (upgraded > 0) return 'upgraded';
  return 'current';
}

/**
 * Upgrade IDEMPOTENTE de config/payouts para o SCHEMA CANÔNICO v4 (12.9):
 * doc ausente ⇒ cria já em v4; version < 4 OU assets em forma legada ⇒
 * normaliza (array→mapa, ids UPPER, aliases de campo) e persiste com MERGE
 * seguro. LTC enabled:true, litoshiPerCoin:100, minWithdrawCoins:20,
 * feeCoins:2; BTC/DOGE/USDT enabled:false. Rodar novamente = no-op.
 */
/**
 * Upgrade IDEMPOTENTE da economia para BLOCK_REWARD = 5 COIN (12.23):
 * doc ausente => tratado pelo createIfMissing (já nasce em v2);
 * blockRewardUnits != 5.000.000 OU economicRuleVersion < 2 => MERGE apenas
 * dos campos {blockRewardUnits, economicRuleVersion = atual+1} (nunca toca
 * em residueUnits/lastFinalizedPeriodKey/limits — resíduo e recuperação
 * preservados). Rodar novamente = no-op. Transações antigas mantêm o
 * ruleVersion com que foram gravadas (doc 05 §44).
 */
async function upgradeEconomyBlockRewardV2(
  db: ReturnType<typeof initAdmin>['db'],
): Promise<'upgraded' | 'current'> {
  const ref = db.doc('config/economy');
  const snap = await ref.get();
  if (!snap.exists) return 'current'; // createIfMissing grava ECONOMY já em v2
  const data = snap.data() ?? {};
  const version = typeof data.economicRuleVersion === 'number'
    ? Number(data.economicRuleVersion)
    : 1;
  const reward = Number(data.blockRewardUnits);
  if (reward === 5_000_000 && version >= 2) return 'current';
  await ref.set(
    {
      blockRewardUnits: 5_000_000,
      economicRuleVersion: version + 1,
      updatedAt: new Date(),
    },
    { merge: true },
  );
  return 'upgraded';
}

/**
 * Upgrade IDEMPOTENTE das trilhas da TEMPORADA 01 para os valores OFICIAIS
 * (v2): doc ausente => tratado pelo createIfMissing (já nasce em v2);
 * version >= 2 E nenhuma recompensa zerada => no-op; caso contrário
 * (valores 0 OU version < 2) => MERGE de tracks + version+1. Nunca remove
 * startAt/endAt/xpConfig/levelXp. Rodar novamente = no-op.
 */
async function upgradeSeasonTracksV2(
  db: ReturnType<typeof initAdmin>['db'],
): Promise<'upgraded' | 'current'> {
  const ref = db.doc('seasons/season-01');
  const snap = await ref.get();
  if (!snap.exists) return 'current'; // createIfMissing grava já em v2
  const data = (snap.data() ?? {}) as Record<string, unknown>;
  const version = typeof data.version === 'number' ? Number(data.version) : 1;
  const tracks = (data.tracks ?? {}) as Record<string, unknown>;
  const hasZero = [tracks['free'], tracks['premium']].some((track) =>
    Array.isArray(track)
      ? track.some(
          (entry) =>
            Number(
              ((entry as Record<string, unknown> | null)?.reward as
                | Record<string, unknown>
                | null)?.amountUnits ?? 0,
            ) === 0
        )
      : true,
  );
  if (version >= 2 && !hasZero) return 'current';
  await ref.set(
    {
      tracks: {
        free: seasonTrack(SEASON_FREE_COINS),
        premium: seasonTrack(SEASON_PREMIUM_COINS),
      },
      version: Math.max(version, 2),
    },
    { merge: true },
  );
  return 'upgraded';
}

async function upgradePayoutsToV4(
  db: ReturnType<typeof initAdmin>['db'],
): Promise<'created' | 'upgraded' | 'current'> {
  const ref = db.doc('config/payouts');
  const snap = await ref.get();
  if (!snap.exists) {
    await ref.set(buildPayoutsV4Doc(null));
    return 'created';
  }
  const data = (snap.data() ?? {}) as Record<string, unknown>;
  const version = typeof data.version === 'number' ? Number(data.version) : 1;
  const legacyShape = !data.assets || Array.isArray(data.assets);
  if (version >= 4 && !legacyShape) return 'current';
  await ref.set(buildPayoutsV4Doc(data), { merge: true });
  return legacyShape || version < 4 ? 'upgraded' : 'current';
}

async function main(): Promise<void> {
  if (process.env.NODE_ENV === 'production') {
    throw new Error('SEED_BLOCKED_IN_PRODUCTION');
  }
  const { db, projectId } = initAdmin();
  console.log(`[seed] start project=${projectId} (somente docs ausentes)`);

  console.log(`[seed] config/economy: ${await createIfMissing(db, 'config/economy', ECONOMY)}`);
  console.log(`[seed] config/economy.machineSlots: ${await ensureMachineSlots(db)}`);
  console.log(`[seed] config/economy.blockReward=5COIN (v2): ${await upgradeEconomyBlockRewardV2(db)}`);
  console.log(`[seed] config/catalog/machines (v2): ${await upgradeMachinesToV2(db)}`);
  for (const [id, data] of Object.entries(MACHINES)) {
    console.log(`[seed] config/catalog/machines/${id}: ${await createIfMissing(db, `config/catalog/machines/${id}`, data)}`);
  }
  for (const [id, data] of Object.entries(GAMES)) {
    if (id === 'nova-swarm') continue; // tratado abaixo com upgrade idempotente
    console.log(`[seed] games/${id}: ${await createIfMissing(db, `games/${id}`, data)}`);
  }
  console.log(`[seed] games/nova-swarm (v2): ${await upgradeNovaSwarmToV2(db)}`);
  for (const [id, data] of Object.entries(MISSIONS)) {
    console.log(`[seed] missions/${id}: ${await createIfMissing(db, `missions/${id}`, data)}`);
  }
  for (const [id, data] of Object.entries(ACHIEVEMENTS)) {
    console.log(`[seed] achievements/${id}: ${await createIfMissing(db, `achievements/${id}`, data)}`);
  }
  for (const [id, data] of Object.entries(LEAGUES)) {
    console.log(`[seed] leagues/${id}: ${await createIfMissing(db, `leagues/${id}`, data)}`);
  }
  console.log(`[seed] config/payouts (v4): ${await upgradePayoutsToV4(db)}`);
  console.log(`[seed] config/ads (v1): ${await createIfMissing(db, 'config/ads', ADS_V1)}`);
  console.log(`[seed] seasons/season-01: ${await createIfMissing(db, 'seasons/season-01', seasonDoc())}`);
  console.log(`[seed] seasons/season-01 tracks (v2): ${await upgradeSeasonTracksV2(db)}`);
  for (const [id, data] of Object.entries(SEASON_MISSIONS)) {
    console.log(`[seed] missions/${id} (season): ${await createIfMissing(db, `missions/${id}`, data)}`);
  }
  console.log('[seed] done');
}

main().catch((err) => {
  console.error(`[seed] fatal=${String(err?.message ?? err).slice(0, 300)}`);
  process.exitCode = 1;
});
