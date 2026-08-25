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

const ECONOMY = {
  blockRewardUnits: 1_000_000, // 1 coin por bloco (coinPrecision = 6 casas)
  blockIntervalMs: 300_000, // 5 minutos
  coinPrecision: 1_000_000,
  powerBasePerHs: 1_000,
  residueUnits: 0,
  economicRuleVersion: 1,
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
    version: 2,
  },
  'rig-volt': {
    name: 'RIG VOLT',
    rarity: 'common',
    powerUnits: 30, // +30 H/s
    priceUnits: 1_100_000_000, // 1.100 coins
    maxPerUser: 4,
    currencyId: 'coins',
    enabled: true,
    version: 2,
  },
  'rig-pulse': {
    name: 'RIG PULSE',
    rarity: 'rare',
    powerUnits: 80, // +80 H/s
    priceUnits: 2_600_000_000, // 2.600 coins
    maxPerUser: 3,
    currencyId: 'coins',
    enabled: true,
    version: 2,
  },
  'rig-quantum': {
    name: 'RIG QUANTUM',
    rarity: 'epic',
    powerUnits: 200, // +200 H/s
    priceUnits: 6_000_000_000, // 6.000 coins
    maxPerUser: 2,
    currencyId: 'coins',
    enabled: true,
    version: 2,
  },
  'rig-nova': {
    name: 'RIG NOVA',
    rarity: 'legendary',
    powerUnits: 500, // +500 H/s
    priceUnits: 15_000_000_000, // 15.000 coins
    maxPerUser: 1,
    currencyId: 'coins',
    enabled: true,
    version: 2,
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
function seasonTrack(baseCoins: number, stepCoins: number): Record<string, unknown>[] {
  return Array.from({ length: 20 }, (_, i) => ({
    level: i + 1,
    reward: {
      type: 'coins',
      amountUnits: (baseCoins + stepCoins * i) * 1_000_000,
    },
  }));
}

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
      free: seasonTrack(100, 50),
      premium: seasonTrack(500, 150),
    },
    version: 1,
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
};

/**
 * Config de PAGAMENTOS/SAQUES v1 — config/payouts (create-if-absent).
 * Autoridade do runner (processWithdrawals); cliente lê SOMENTE para exibir
 * mínimos/taxas (rótulo "valores definidos pelo servidor").
 *  - assets[]: ativos habilitados p/ saque; unidades em UNITS de coin
 *    (coinPrecision = 1_000_000 ⇒ minWithdrawUnits 20_000_000 = 20 coins;
 *    feeUnits 2_000_000 = 2 coins). receivedUnits = amount − fee.
 *  - antifraude: cooldownHours desde o último saque não-failed, maxPerDay,
 *    minAccountAgeHours e requireFinishedGames (elegibilidade).
 */
const PAYOUTS_V1: Record<string, unknown> = {
  assets: [
    { id: 'BTC', network: 'Bitcoin', enabled: true, minWithdrawUnits: 20_000_000, feeUnits: 2_000_000 },
    { id: 'LTC', network: 'Litecoin', enabled: true, minWithdrawUnits: 20_000_000, feeUnits: 2_000_000 },
    { id: 'DOGE', network: 'Dogecoin', enabled: true, minWithdrawUnits: 20_000_000, feeUnits: 2_000_000 },
    { id: 'USDT', network: 'TRC20', enabled: true, minWithdrawUnits: 20_000_000, feeUnits: 2_000_000 },
  ],
  cooldownHours: 24,
  maxPerDay: 3,
  minAccountAgeHours: 24,
  requireFinishedGames: 1,
  coinPrecision: 1_000_000,
  version: 1,
};

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

async function main(): Promise<void> {
  if (process.env.NODE_ENV === 'production') {
    throw new Error('SEED_BLOCKED_IN_PRODUCTION');
  }
  const { db, projectId } = initAdmin();
  console.log(`[seed] start project=${projectId} (somente docs ausentes)`);

  console.log(`[seed] config/economy: ${await createIfMissing(db, 'config/economy', ECONOMY)}`);
  console.log(`[seed] config/economy.machineSlots: ${await ensureMachineSlots(db)}`);
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
  console.log(`[seed] config/payouts (v1): ${await createIfMissing(db, 'config/payouts', PAYOUTS_V1)}`);
  console.log(`[seed] config/ads (v1): ${await createIfMissing(db, 'config/ads', ADS_V1)}`);
  console.log(`[seed] seasons/season-01: ${await createIfMissing(db, 'seasons/season-01', seasonDoc())}`);
  for (const [id, data] of Object.entries(SEASON_MISSIONS)) {
    console.log(`[seed] missions/${id} (season): ${await createIfMissing(db, `missions/${id}`, data)}`);
  }
  console.log('[seed] done');
}

main().catch((err) => {
  console.error(`[seed] fatal=${String(err?.message ?? err).slice(0, 300)}`);
  process.exitCode = 1;
});
