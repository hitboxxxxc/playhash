/**
 * Seed DEV — cria config/economy, config/catalog/machines/* e games/*
 * SOMENTE se não existirem. Nunca sobrescreve dados existentes.
 * Bloqueado em produção (NODE_ENV=production).
 *
 * NOTA: caminhos de DOCUMENTO no Firestore precisam de nº PAR de segmentos;
 * por isso o catálogo vive em config/catalog/machines/{id} (4 segmentos).
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

async function main(): Promise<void> {
  if (process.env.NODE_ENV === 'production') {
    throw new Error('SEED_BLOCKED_IN_PRODUCTION');
  }
  const { db, projectId } = initAdmin();
  console.log(`[seed] start project=${projectId} (somente docs ausentes)`);

  console.log(`[seed] config/economy: ${await createIfMissing(db, 'config/economy', ECONOMY)}`);
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
