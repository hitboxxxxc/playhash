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
  console.log('[seed] done');
}

main().catch((err) => {
  console.error(`[seed] fatal=${String(err?.message ?? err).slice(0, 300)}`);
  process.exitCode = 1;
});
